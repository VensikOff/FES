-- NPC Controller v4.6 - ONE LocalScript
-- Put it in: StarterPlayer > StarterPlayerScripts (LocalScript). For your own game in Studio.

local P, RS, UIS = game:GetService("Players"), game:GetService("RunService"), game:GetService("UserInputService")
local player = P.LocalPlayer
local function bad(...) warn("[NPC]", ...) end
local function log(...) print("[NPC]", ...) end
if not RS:IsClient() then bad("This must be a LocalScript, not a Script.") return end
local pgui = player:WaitForChild("PlayerGui", 10)
if not pgui then bad("PlayerGui not found") return end

---------------------------------------------------------------- state
local DEF_INT, DEF_SPIN = 2, 300
local npcs, nextId, selected, primary, anchorSel = {}, 0, {}, nil, nil
local controlling, possessMode, possessed, homeChar, saved = nil, true, false, nil, nil
local keepClose, dbgMarkers = true, true
local moveMode, addMode, autoScan, interval, lastScan, espAll, spinSpeed = false, false, true, DEF_INT, 0, false, DEF_SPIN
local ignored = setmetatable({}, { __mode = "k" })
local order, features = 0, {}
local refresh, setStatus, speedBox, jumpBox
local function nxt() order += 1 return order end
local function fmt(n) return tostring(math.floor(n * 100 + 0.5) / 100) end

local controls
task.spawn(function()
	local ok, r = pcall(function()
		local ps = player:WaitForChild("PlayerScripts", 10)
		return require(ps:WaitForChild("PlayerModule", 10)):GetControls()
	end)
	if ok and r then controls = r else bad("PlayerModule not found, using fallback WASD:", r) end
end)
local function moveVec()
	if controls then
		local ok, v = pcall(function() return controls:GetMoveVector() end)
		if ok and typeof(v) == "Vector3" then return v end
	end
	local x, z = 0, 0
	if UIS:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
	if UIS:IsKeyDown(Enum.KeyCode.S) then z += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	local v = Vector3.new(x, 0, z)
	return v.Magnitude > 1 and v.Unit or v
end
-- while controlling, "my character" = my REAL character
local function myChar() return homeChar or player.Character end
local function myRoot() local c = myChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function myHum() local c = myChar() return c and c:FindFirstChildOfClass("Humanoid") end

---------------------------------------------------------------- tiny UI toolkit
local C = {
	bg = Color3.fromRGB(28, 28, 33), pn = Color3.fromRGB(40, 40, 47), btn = Color3.fromRGB(62, 62, 70),
	on = Color3.fromRGB(40, 150, 70), sel = Color3.fromRGB(50, 100, 190), red = Color3.fromRGB(170, 60, 60),
}
local function T(class, parent, props)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel, o.BackgroundColor3 = 0, C.btn end
	if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
		o.TextColor3, o.Font, o.TextSize = Color3.new(1, 1, 1), Enum.Font.Gotham, 12
	end
	if o:IsA("TextLabel") then o.BackgroundTransparency = 1 end
	if o:IsA("ScrollingFrame") then
		o.BackgroundTransparency, o.ScrollBarThickness, o.AutomaticCanvasSize, o.CanvasSize = 1, 4, Enum.AutomaticSize.Y, UDim2.new()
	end
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function lay(parent, props)
	props.SortOrder = Enum.SortOrder.LayoutOrder
	return T("UIListLayout", parent, props)
end

local old = pgui:FindFirstChild("NPCController")
if old then old:Destroy() end
local gui = T("ScreenGui", pgui, { Name = "NPCController", ResetOnSpawn = false, DisplayOrder = 999, IgnoreGuiInset = true })

local toggle = T("TextButton", gui, { Size = UDim2.new(0, 84, 0, 28), Position = UDim2.new(0, 10, 0, 44), Text = "NPC Menu", Font = Enum.Font.GothamBold })
local main = T("Frame", gui, { Size = UDim2.new(0, 700, 0, 480), Position = UDim2.new(0, 20, 0.5, -240), BackgroundColor3 = C.bg })
local title = T("TextLabel", main, {
	Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 0, BackgroundColor3 = C.pn, Active = true,
	Text = "  NPC Controller v4.6   (drag title to move, drag corner to resize)", TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold, TextSize = 13,
})
local grip = T("TextButton", main, { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -22, 1, -22), Text = "//", ZIndex = 10 })
local hide = T("TextButton", main, { Size = UDim2.new(0, 54, 0, 22), Position = UDim2.new(1, -60, 0, 4), Text = "Hide", Font = Enum.Font.GothamBold, ZIndex = 10 })
hide.MouseButton1Click:Connect(function() main.Visible = false end)
local left = T("Frame", main, { Position = UDim2.new(0, 6, 0, 36), Size = UDim2.new(0, 230, 1, -42), BackgroundColor3 = C.pn })
local right = T("Frame", main, { Position = UDim2.new(0, 242, 0, 36), Size = UDim2.new(1, -248, 1, -42), BackgroundColor3 = C.pn })
local list = T("ScrollingFrame", left, { Position = UDim2.new(0, 2, 0, 66), Size = UDim2.new(1, -4, 1, -68) })
lay(list, { Padding = UDim.new(0, 3) })
local info = T("TextLabel", right, { Position = UDim2.new(0, 6, 0, 2), Size = UDim2.new(1, -12, 0, 34), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.GothamBold, TextSize = 13 })
local scroll = T("ScrollingFrame", right, { Position = UDim2.new(0, 4, 0, 38), Size = UDim2.new(1, -8, 1, -72) })
lay(scroll, { Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Center })
local status = T("TextLabel", right, { Position = UDim2.new(0, 6, 1, -32), Size = UDim2.new(1, -34, 0, 30), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 200) })
setStatus = function(t) status.Text = t end
local hud = T("TextButton", gui, { Size = UDim2.new(0, 560, 0, 28), Position = UDim2.new(0.5, -280, 0, 8), BackgroundTransparency = 0.25,
	BackgroundColor3 = C.bg, TextColor3 = Color3.fromRGB(120, 255, 140), Font = Enum.Font.GothamBold, Visible = false })

-- one shared drag system (window move, resize, menu button move, slider)
local active
local function makeDrag(h, start, move)
	h.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			active = { p0 = i.Position, data = start(), move = move }
			move(Vector3.zero, active.data, i.Position)
		end
	end)
end
UIS.InputChanged:Connect(function(i)
	if active and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		active.move(i.Position - active.p0, active.data, i.Position)
	end
end)
UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then active = nil end
end)
local function moveTo(frame, dl, p0)
	frame.Position = UDim2.new(p0.X.Scale, p0.X.Offset + dl.X, p0.Y.Scale, p0.Y.Offset + dl.Y)
end
makeDrag(title, function() return main.Position end, function(dl, p0) moveTo(main, dl, p0) end)
makeDrag(grip, function() return main.AbsoluteSize end, function(dl, s0)
	main.Size = UDim2.new(0, math.max(540, s0.X + dl.X), 0, math.max(360, s0.Y + dl.Y))
end)
local tgMoved = false
makeDrag(toggle, function() tgMoved = false return toggle.Position end, function(dl, p0)
	if dl.Magnitude > 4 then tgMoved = true end
	if tgMoved then moveTo(toggle, dl, p0) end
end)
toggle.MouseButton1Click:Connect(function() if not tgMoved then main.Visible = not main.Visible end end)

---------------------------------------------------------------- selection helpers
local function selCount() local n = 0 for _ in pairs(selected) do n += 1 end return n end
local function targets()
	local t = {}
	for d in pairs(selected) do
		if npcs[d.model] == d and d.hum.Parent then t[#t + 1] = d end
	end
	table.sort(t, function(a, b) return a.id < b.id end)
	return t
end
local function need()
	local t = targets()
	if #t == 0 then bad("Select an NPC in the list first.") setStatus("Select an NPC in the list first.") end
	return t
end
local function getPrimary()
	if not (primary and selected[primary]) then primary = targets()[1] end
	return primary
end
local function any(prop) for d in pairs(selected) do if d[prop] then return true end end return false end
local function toggleProp(prop, fn)
	local t = need()
	if #t == 0 then return end
	local s = not any(prop)
	for _, d in ipairs(t) do fn(d, s) end
end

---------------------------------------------------------------- NPC logic
local function applyStats(d)
	local h = d.hum
	if d.frozen then h.WalkSpeed, h.JumpPower, h.JumpHeight = 0, 0, 0 return end
	h.WalkSpeed = d.speed
	if d.jumpEdited then
		h.UseJumpPower, h.JumpPower = true, d.jumpPower
	else
		h.UseJumpPower, h.JumpPower, h.JumpHeight = d.o.useJP, d.o.jp, d.o.jh
	end
end
local function setFrozen(d, s)
	d.frozen = s
	if s then d.following, d.target = false, nil d.hum:MoveTo(d.root.Position) end
	applyStats(d)
end
local function standUp(d) if d.hum.Sit then d.hum.Sit = false end end
local function setAlpha(v)
	local c = myChar()
	if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then p.LocalTransparencyModifier = v end end end
end

local function stopControl(reason, charChanged)
	local d = controlling
	if not d then return end
	controlling = nil
	pcall(function() d.hum:Move(Vector3.zero, true) end)
	d.moving = false
	local r = myRoot()
	if r then r.Anchored = false end
	if possessed then
		possessed = false
		if not charChanged then
			if homeChar and homeChar.Parent then
				local ok, e = pcall(function() player.Character = homeChar end)
				if not ok then bad("Could not give your character back:", e) end
			else
				bad("Your original character is gone - wait for the server to respawn you.")
			end
		end
	end
	local h = myHum()
	if h then
		if saved then h.WalkSpeed, h.JumpPower, h.JumpHeight = saved[1], saved[2], saved[3] end
		workspace.CurrentCamera.CameraSubject = h
	end
	saved = nil
	setAlpha(0)
	homeChar = nil
	pcall(applyStats, d)
	hud.Visible, main.Visible = false, true
	log("Stopped controlling", d.model.Name, reason or "")
end

local function startControl(d)
	if controlling == d then return end
	if controlling then stopControl("switch") end
	if d.hum.Health <= 0 then bad(d.model.Name, "is dead.") return end
	local c = player.Character
	local ch = c and c:FindFirstChildOfClass("Humanoid")
	if not ch then bad("Your character has no Humanoid yet.") return end
	homeChar, controlling = c, d
	d.following, d.target, d.moving = false, nil, false
	if d.frozen then setFrozen(d, false) end
	possessed = false
	if possessMode then
		local ok, e = pcall(function() player.Character = d.model end)
		if ok and player.Character == d.model then
			possessed = true
		else
			bad("Possess mode failed (" .. tostring(e) .. "), using Direct mode.")
			pcall(function() player.Character = homeChar end)
		end
	end
	if not possessed then
		saved = { ch.WalkSpeed, ch.JumpPower, ch.JumpHeight }
		ch.WalkSpeed, ch.JumpPower, ch.JumpHeight = 0, 0, 0
	end
	local cam = workspace.CurrentCamera
	cam.CameraType, cam.CameraSubject = Enum.CameraType.Custom, d.hum
	hud.Text = "Controlling " .. d.model.Name .. (possessed and " [Possess]" or " [Direct]") .. "  -  click here to stop"
	hud.Visible, main.Visible = true, false
	if d.root.Anchored then bad(d.model.Name, ": root part is Anchored - it will not move.") end
	log("Controlling", d.model:GetFullName(), possessed and "(Possess)" or "(Direct)")
end

local function removeNPC(d, byUser)
	if npcs[d.model] ~= d then return end
	if controlling == d then stopControl("NPC removed") end
	if byUser then ignored[d.model] = true end
	selected[d] = nil
	if primary == d then primary = nil end
	if anchorSel == d then anchorSel = nil end
	d.frozen, d.following, d.spinning, d.aiOff, d.target, d.speed, d.jumpEdited = false, false, false, false, nil, d.o.speed, false
	pcall(applyStats, d)
	pcall(function() d.hl:Destroy() end) pcall(function() d.mk:Destroy() end)
	d.row:Destroy()
	npcs[d.model] = nil
	log("Removed:", d.model.Name)
end

local function onRowClick(d)
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
	if shift and anchorSel and npcs[anchorSel.model] == anchorSel then
		if not ctrl then table.clear(selected) end
		local lo, hi = math.min(anchorSel.id, d.id), math.max(anchorSel.id, d.id)
		for _, o in pairs(npcs) do if o.id >= lo and o.id <= hi then selected[o] = true end end
		primary = d
	elseif ctrl then
		selected[d] = (not selected[d]) or nil
		primary = selected[d] and d or nil
		anchorSel = d
	else
		local wasOnly = selCount() == 1 and selected[d]
		table.clear(selected)
		if not wasOnly then selected[d], primary = true, d end
		anchorSel = d
	end
	setStatus(selCount() .. " NPC(s) selected.")
	refresh()
end

local function findRoot(m)
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
end

local function addNPC(model, hum, root)
	nextId += 1
	local d = {
		id = nextId, model = model, hum = hum, root = root, dist = 0, speed = hum.WalkSpeed, jumpPower = hum.JumpPower,
		spawnCF = root.CFrame, o = { speed = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight, useJP = hum.UseJumpPower },
	}
	d.row = T("Frame", list, { Size = UDim2.new(1, -6, 0, 28), BackgroundTransparency = 1, LayoutOrder = d.id })
	d.btn = T("TextButton", d.row, { Size = UDim2.new(1, -30, 1, 0), BackgroundColor3 = C.bg, Text = model.Name, TextXAlignment = Enum.TextXAlignment.Left })
	T("UIPadding", d.btn, { PaddingLeft = UDim.new(0, 20) })
	d.dot = T("Frame", d.row, { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 6, 0.5, -5) })
	T("TextButton", d.row, { Size = UDim2.new(0, 28, 1, 0), Position = UDim2.new(1, -28, 0, 0), BackgroundColor3 = C.red, Text = "X", Font = Enum.Font.GothamBold })
		.MouseButton1Click:Connect(function() removeNPC(d, true) refresh() end)
	d.btn.MouseButton1Click:Connect(function() onRowClick(d) end)
	d.hl = T("Highlight", model, { Adornee = model, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, FillTransparency = 0.55, Enabled = false })
	d.mk = T("BillboardGui", root, { Adornee = root, AlwaysOnTop = true, Size = UDim2.new(0, 14, 0, 14), StudsOffset = Vector3.new(0, 3.6, 0), Enabled = dbgMarkers })
	d.mkDot = T("Frame", d.mk, { Size = UDim2.new(1, 0, 1, 0) })
	T("UICorner", d.mkDot, { CornerRadius = UDim.new(1, 0) })
	npcs[model], ignored[model] = d, nil
	if root.Anchored then bad(model.Name, ": root part is Anchored - it will not move. Unanchor it.") end
	if hum.Health <= 0 then bad(model.Name, ": Health = 0, it is dead.") end
	log("Added:", model:GetFullName())
	return d
end

-- ownership debug: green = you simulate it, red = someone else does, orange = cannot be controlled, gray = unknown
local OWN = { mine = Color3.fromRGB(60, 220, 90), other = Color3.fromRGB(230, 60, 60), none = Color3.fromRGB(255, 160, 40), unk = Color3.fromRGB(150, 150, 150) }
local OWNTXT = { mine = "you own it", other = "NOT yours", none = "cannot be controlled", unk = "owner unknown" }
local warnedAge = false
local function ownerState(d)
	if d.hum.Health <= 0 or d.root.Anchored then return "none" end
	local ok, age = pcall(function() return d.root.ReceiveAge end)
	if not ok or type(age) ~= "number" then
		if not warnedAge then warnedAge = true bad("Ownership debug: BasePart.ReceiveAge is not readable, markers will be gray.") end
		return "unk"
	end
	return age < 0.1 and "mine" or "other"
end
local lastCount = -1
local function scan(manual)
	if manual then table.clear(ignored) end
	for _, h in ipairs(workspace:GetDescendants()) do
		if h:IsA("Humanoid") then
			local m = h.Parent
			if m and m:IsA("Model") and not npcs[m] and not ignored[m] and m ~= homeChar and not P:GetPlayerFromCharacter(m) then
				local root = findRoot(m)
				if root then addNPC(m, h, root) else ignored[m] = true bad("Skipped", m:GetFullName(), ": no HumanoidRootPart / PrimaryPart / Torso") end
			end
		end
	end
	local n = 0
	for _ in pairs(npcs) do n += 1 end
	if n ~= lastCount or manual then
		lastCount = n
		log("Scan: NPCs in list =", n)
		if n == 0 then bad("No NPCs found. Need a Model in workspace with a Humanoid + HumanoidRootPart (not a player).") end
		if manual then setStatus("Scan finished: " .. n .. " NPC(s).") end
	end
end

refresh = function()
	local prim = getPrimary()
	for _, d in pairs(npcs) do
		d.btn.Text = (controlling == d and " * " or "  ") .. d.model.Name .. "  |  " .. d.dist .. "m" .. (d.frozen and "  [frozen]" or "")
		d.btn.BackgroundColor3 = (controlling == d and C.on) or (selected[d] and C.sel) or C.bg
		d.own = ownerState(d)
		d.dot.BackgroundColor3, d.mkDot.BackgroundColor3, d.mk.Enabled = OWN[d.own], OWN[d.own], dbgMarkers
		local col = (controlling == d and Color3.fromRGB(60, 255, 90)) or (selected[d] and Color3.fromRGB(255, 220, 60)) or (espAll and Color3.fromRGB(80, 200, 255))
		d.hl.Enabled = col and true or false
		if col then d.hl.FillColor, d.hl.OutlineColor = col, col end
	end
	if prim and prim.hum.Parent then
		local n = selCount()
		info.Text = string.format("%s%s\nHP %d/%d  |  spd %s  |  %d studs  |  %s", prim.model.Name, n > 1 and ("  (+" .. (n - 1) .. " more)") or "",
			math.floor(prim.hum.Health), math.floor(prim.hum.MaxHealth), fmt(prim.speed), prim.dist, OWNTXT[prim.own or "unk"])
	else
		info.Text = "No NPC selected - click one in the list"
	end
	for _, f in ipairs(features) do
		local on = f[4] and f[4]() or false
		f[1].BackgroundColor3 = on and C.on or C.btn
		f[1].Text = (on and f[3]) or f[2]
	end
	if speedBox and not speedBox:IsFocused() then speedBox.Text = prim and fmt(prim.speed) or "" end
	if jumpBox and not jumpBox:IsFocused() then jumpBox.Text = prim and fmt(prim.jumpPower) or "" end
end

---------------------------------------------------------------- UI builders
local function btn(parent, text, fn, isOn, onText)
	local b = T("TextButton", parent, { Text = text, TextWrapped = true, Font = Enum.Font.GothamBold })
	b.MouseButton1Click:Connect(function()
		local ok, e = pcall(fn)
		if not ok then bad("Error in '" .. text .. "':", e) end
		refresh()
	end)
	features[#features + 1] = { b, text, onText, isOn }
	return b
end

local function section(name)
	local box = T("Frame", scroll, { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.bg, LayoutOrder = nxt() })
	lay(box, { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center })
	T("UIPadding", box, { PaddingBottom = UDim.new(0, 4) })
	local h = T("TextButton", box, { Size = UDim2.new(1, 0, 0, 26), Text = "[-] " .. name, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0 })
	local c = T("Frame", box, { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 })
	lay(c, { Padding = UDim.new(0, 4) })
	h.MouseButton1Click:Connect(function()
		c.Visible = not c.Visible
		h.Text = (c.Visible and "[-] " or "[+] ") .. name
	end)
	return c
end

local function row(c, specs)
	local r = T("Frame", c, { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nxt() })
	lay(r, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) })
	local n = #specs
	for i, s in ipairs(specs) do
		local b = btn(r, s[1], s[2], s[3], s[4])
		b.Size, b.LayoutOrder = UDim2.new(1 / n, -4 * (n - 1) / n, 1, 0), i
	end
end

local function valueRow(c, name, onApply, onReset)
	local r = T("Frame", c, { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nxt() })
	lay(r, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) })
	T("TextLabel", r, { Size = UDim2.new(0, 80, 1, 0), Text = name, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 })
	local box = T("TextBox", r, { Size = UDim2.new(1, -146, 1, 0), BackgroundColor3 = C.bg, ClearTextOnFocus = false, Text = "", LayoutOrder = 2 })
	local rb = T("TextButton", r, { Size = UDim2.new(0, 58, 1, 0), Text = "Reset", Font = Enum.Font.GothamBold, LayoutOrder = 3 })
	box.FocusLost:Connect(function()
		local ok, e = pcall(onApply, tonumber(box.Text))
		if not ok then bad("Value error:", e) end
		refresh()
	end)
	rb.MouseButton1Click:Connect(function() pcall(onReset) refresh() end)
	return box
end

local function slider(c, name, lo, hi, def, onChange)
	local f = T("Frame", c, { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nxt() })
	T("TextLabel", f, { Size = UDim2.new(0, 80, 1, 0), Text = name, TextXAlignment = Enum.TextXAlignment.Left })
	local hit = T("TextButton", f, { Size = UDim2.new(1, -190, 1, 0), Position = UDim2.new(0, 84, 0, 0), Text = "", AutoButtonColor = false, BackgroundTransparency = 1 })
	local track = T("Frame", hit, { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0.5, -4), BackgroundColor3 = C.bg })
	local fill = T("Frame", track, { Size = UDim2.new(), BackgroundColor3 = C.on })
	local val = T("TextLabel", f, { Size = UDim2.new(0, 44, 1, 0), Position = UDim2.new(1, -102, 0, 0) })
	local rb = T("TextButton", f, { Size = UDim2.new(0, 54, 0, 24), Position = UDim2.new(1, -54, 0, 2), Text = "Reset", Font = Enum.Font.GothamBold })
	local function set(v)
		v = math.clamp(v, lo, hi)
		fill.Size = UDim2.new((v - lo) / (hi - lo), 0, 1, 0)
		val.Text = tostring(math.floor(v + 0.5))
		onChange(v)
	end
	set(def)
	makeDrag(hit, function() end, function(_, _, pos)
		set(lo + math.clamp((pos.X - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1) * (hi - lo))
	end)
	rb.MouseButton1Click:Connect(function() set(def) end)
end

---------------------------------------------------------------- left panel: scan controls
local ab = btn(left, "Auto-scan: OFF", function()
	autoScan, lastScan = not autoScan, 0
	setStatus(autoScan and ("Auto-scan ON, every " .. fmt(interval) .. " s.") or "Auto-scan OFF.")
end, function() return autoScan end, "Auto-scan: ON")
ab.Size, ab.Position = UDim2.new(0, 100, 0, 26), UDim2.new(0, 4, 0, 4)

local ib = T("TextBox", left, { Size = UDim2.new(0, 50, 0, 26), Position = UDim2.new(0, 108, 0, 4), BackgroundColor3 = C.bg,
	ClearTextOnFocus = false, Text = tostring(DEF_INT), PlaceholderText = "sec" })
ib.FocusLost:Connect(function()
	local n = tonumber(ib.Text)
	if not n or n < 0.2 or n > 120 then bad("Scan interval must be 0.2 - 120 seconds. Keeping", interval) ib.Text = fmt(interval) return end
	interval, ib.Text = n, fmt(n)
	setStatus("Scan interval: " .. fmt(n) .. " s.")
end)
local ir = T("TextButton", left, { Size = UDim2.new(0, 64, 0, 26), Position = UDim2.new(0, 162, 0, 4), Text = "Reset", Font = Enum.Font.GothamBold })
ir.MouseButton1Click:Connect(function() interval, ib.Text = DEF_INT, tostring(DEF_INT) setStatus("Scan interval reset to " .. DEF_INT .. " s.") end)

local rf = btn(left, "Refresh (scan once)", function() scan(true) end)
rf.Size, rf.Position = UDim2.new(0, 108, 0, 26), UDim2.new(0, 4, 0, 34)
local ad = btn(left, "Click to add: OFF", function()
	addMode = not addMode
	setStatus(addMode and "Click an NPC in the world to add it to the list." or "Click to add OFF.")
end, function() return addMode end, "Click to add: ON")
ad.Size, ad.Position = UDim2.new(0, 110, 0, 26), UDim2.new(0, 116, 0, 34)

---------------------------------------------------------------- right panel: sections
local s1 = section("Control")
row(s1, {
	{ "Control NPC", function()
		if controlling then stopControl("button") return end
		local t = need()
		if #t == 0 then return end
		if #t > 1 then bad("Several selected - controlling only", getPrimary().model.Name) end
		startControl(getPrimary())
	end, function() return controlling ~= nil end, "Controlling (stop)" },
	{ "Mode: Direct", function()
		possessMode = not possessMode
		setStatus(possessMode and "Possess: your Character is swapped to the NPC (player scripts like fly work on it)." or "Direct: the script moves the NPC Humanoid itself.")
		if controlling then local d = controlling stopControl("mode change") startControl(d) end
	end, function() return possessMode end, "Mode: Possess" },
})
row(s1, {
	{ "Click to Move", function()
		moveMode = not moveMode
		setStatus(moveMode and "Click the ground: selected NPCs walk there." or "Click to Move OFF.")
	end, function() return moveMode end, "Click to Move: ON" },
	{ "Follow me", function()
		toggleProp("following", function(d, s)
			if controlling == d then bad("Can't follow while you control", d.model.Name) return end
			if d.frozen then bad(d.model.Name, "is frozen.") return end
			d.following, d.target = s, nil
			if s then standUp(d) end
		end)
	end, function() return any("following") end, "Following me" },
})
row(s1, {
	{ "Keep my char near", function()
		keepClose = not keepClose
		setStatus(keepClose and "My character stays next to the NPC (keeps network ownership)." or "My character stays put - far NPCs may stop obeying.")
	end, function() return keepClose end, "Keep my char near: ON" },
	{ "Stop moving", function()
		for _, d in ipairs(need()) do d.following, d.target = false, nil d.hum:MoveTo(d.root.Position) end
	end },
})

local s2 = section("Actions")
row(s2, {
	{ "Disable AI", function()
		toggleProp("aiOff", function(d, s) d.aiOff = s if s then d.following, d.target = false, nil end end)
	end, function() return any("aiOff") end, "AI disabled" },
	{ "Freeze", function() toggleProp("frozen", setFrozen) end, function() return any("frozen") end, "Unfreeze" },
})

local s3 = section("Values")
speedBox = valueRow(s3, "WalkSpeed", function(n)
	if not n or n < 0 or n > 500 then bad("WalkSpeed must be 0 - 500.") return end
	for _, d in ipairs(need()) do d.speed = n applyStats(d) end
end, function()
	for _, d in ipairs(targets()) do d.speed = d.o.speed applyStats(d) end
end)
jumpBox = valueRow(s3, "JumpPower", function(n)
	if not n or n < 0 or n > 1000 then bad("JumpPower must be 0 - 1000.") return end
	for _, d in ipairs(need()) do d.jumpPower, d.jumpEdited = n, true applyStats(d) end
end, function()
	for _, d in ipairs(targets()) do d.jumpPower, d.jumpEdited = d.o.jp, false applyStats(d) end
end)

local s4 = section("Teleport")
row(s4, {
	{ "Me -> NPC", function()
		local p, mr = getPrimary(), myRoot()
		if not p then bad("Select an NPC first.") return end
		if controlling then bad("Stop controlling first.") return end
		if mr then mr.CFrame = p.root.CFrame * CFrame.new(0, 3, 6) end
	end },
	{ "NPC -> me", function()
		local t, mr = need(), myRoot()
		if #t == 0 or not mr then return end
		for i, d in ipairs(t) do
			local a = (i - 1) * 2 * math.pi / #t
			local off = #t == 1 and Vector3.new(0, 3, -5) or Vector3.new(math.sin(a) * 6, 3, -math.cos(a) * 6)
			local pos = (mr.CFrame * CFrame.new(off)).Position
			d.root.CFrame = CFrame.lookAt(pos, Vector3.new(mr.Position.X, pos.Y, mr.Position.Z))
			d.root.AssemblyLinearVelocity = Vector3.zero
		end
	end },
})
row(s4, { { "Return to spawn point", function()
	for _, d in ipairs(need()) do d.root.CFrame, d.target = d.spawnCF, nil d.root.AssemblyLinearVelocity = Vector3.zero end
end } })

local s5 = section("Other")
row(s5, {
	{ "Sit / Stand", function()
		local t = need()
		local sit = false
		for _, d in ipairs(t) do if d.hum.Sit then sit = true end end
		for _, d in ipairs(t) do d.hum.Sit = not sit end
	end, function() for d in pairs(selected) do if d.hum.Sit then return true end end return false end, "Sitting (stand)" },
	{ "Jump", function()
		for _, d in ipairs(need()) do
			if d.frozen then bad(d.model.Name, "is frozen.") else standUp(d) d.hum.Jump = true end
		end
	end },
})
row(s5, {
	{ "Spin", function() toggleProp("spinning", function(d, s) d.spinning = s end) end, function() return any("spinning") end, "Spinning (stop)" },
	{ "Look at me", function()
		local mr = myRoot()
		if mr then for _, d in ipairs(need()) do
			d.root.CFrame = CFrame.lookAt(d.root.Position, Vector3.new(mr.Position.X, d.root.Position.Y, mr.Position.Z))
		end end
	end },
})
slider(s5, "Spin speed", 0, 1440, DEF_SPIN, function(v) spinSpeed = v end)
row(s5, { { "Highlight all NPCs", function() espAll = not espAll end, function() return espAll end, "Highlight all: ON" } })

local s6 = section("Debug")
row(s6, { { "Ownership markers", function() dbgMarkers = not dbgMarkers end, function() return dbgMarkers end, "Ownership markers: ON" } })
T("TextLabel", s6, { Size = UDim2.new(1, 0, 0, 60), LayoutOrder = nxt(), RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "<font color='#3cdc5a'>Green</font> = you own it (commands work)\n<font color='#e63c3c'>Red</font> = server / another player owns it\n<font color='#ffa028'>Orange</font> = cannot be controlled (anchored / dead)\n<font color='#969696'>Gray</font> = unknown" })

---------------------------------------------------------------- mouse in the world
local function ray(ignore)
	local pos = UIS:GetMouseLocation()
	local r = workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
	local pr = RaycastParams.new()
	pr.FilterType, pr.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignore
	return workspace:Raycast(r.Origin, r.Direction * 1000, pr)
end

local function tryAdd() -- true if the click hit a humanoid model
	local res = ray({ myChar() })
	if not res then bad("Click to add: nothing was hit.") return false end
	local m = res.Instance
	while m and m ~= workspace and not (m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")) do m = m.Parent end
	if not m or m == workspace then return false end
	if m == homeChar or P:GetPlayerFromCharacter(m) then bad("Click to add: that is a player, not an NPC.") return true end
	local d = npcs[m]
	if not d then
		local root, hum = findRoot(m), m:FindFirstChildOfClass("Humanoid")
		if not root then bad("Click to add:", m:GetFullName(), "has no root part.") return true end
		d = addNPC(m, hum, root)
	end
	if not (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then table.clear(selected) end
	selected[d], primary, anchorSel = true, d, d
	setStatus("Added / selected: " .. m.Name)
	return true
end

local function doMove()
	local t = targets()
	if #t == 0 then bad("Click to Move is ON but no NPC is selected.") return end
	local ig = { myChar() }
	for _, d in ipairs(t) do ig[#ig + 1] = d.model end
	local res = ray(ig)
	if not res then bad("Click missed (sky?). Click on the ground.") return end
	for i, d in ipairs(t) do
		if d.frozen then
			bad(d.model.Name, "is frozen.")
		else
			local a, p = (i - 1) * 2 * math.pi / #t, res.Position
			if #t > 1 then p += Vector3.new(math.cos(a) * 3, 0, math.sin(a) * 3) end
			d.following, d.target = false, p
			standUp(d)
			d.hum:MoveTo(p)
		end
	end
end

---------------------------------------------------------------- input (no hotkeys - only mouse clicks in the world)
hud.MouseButton1Click:Connect(function() stopControl("HUD button") refresh() end)
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local handled = false
		if addMode then
			local ok, r = pcall(tryAdd)
			if ok then handled = r else bad("Click to add error:", r) end
			refresh()
		end
		if moveMode and not handled then
			local ok, e = pcall(doMove)
			if not ok then bad("Click to Move error:", e) end
		end
	end
end)
UIS.JumpRequest:Connect(function()
	local d = controlling -- Possess mode: default controls already jump the NPC
	if d and not possessed and not d.frozen then standUp(d) d.hum.Jump = true end
end)
player.CharacterAdded:Connect(function(c)
	if controlling and c ~= controlling.model and c ~= homeChar then
		homeChar = nil
		stopControl("your character respawned", true)
		refresh()
	end
end)

---------------------------------------------------------------- per-frame + background loops
RS.RenderStepped:Connect(function(dt)
	for _, s in pairs(npcs) do
		if s.root.Parent then
			if s.spinning and not s.frozen then s.root.CFrame *= CFrame.Angles(0, math.rad(spinSpeed) * dt, 0) end
			if s.aiOff and not s.frozen and not s.target and not s.following and controlling ~= s then s.hum:MoveTo(s.root.Position) end
		end
	end
	local d = controlling
	if not d then return end
	if not d.hum.Parent or d.hum.Health <= 0 then
		bad(d.model.Name, "died or disappeared - stopped controlling.")
		stopControl("NPC unavailable") refresh()
		return
	end
	local mr = myRoot()
	if mr then
		mr.Anchored = keepClose
		if keepClose then mr.CFrame = d.root.CFrame * CFrame.new(0, 0, 10) end
	end
	local v = moveVec()
	if v.Magnitude > 0.05 then
		if not d.moving then
			d.moving, d.moveTime, d.warned = true, 0, false
			if d.frozen then bad(d.model.Name, "is frozen - unfreeze it to walk.") end
		end
		standUp(d)
		d.following, d.target = false, nil
		if not possessed then d.hum:Move(v, true) end
		d.moveTime += dt
		if d.moveTime > 1.5 and not d.warned and not d.frozen and d.root.AssemblyLinearVelocity.Magnitude < 0.5 then
			d.warned = true
			bad("The NPC is not moving. Possible reasons: no network ownership (turn on 'Keep my char near'), Anchored parts, a server script controls it, or a wall.")
		end
	else
		if d.moving then
			d.moving = false
			if not possessed then d.hum:Move(Vector3.zero, true) end
		end
		if not d.target then d.hum:MoveTo(d.root.Position) end -- AI is off while controlling
	end
end)

local function tick()
	local mr = myRoot()
	local followers = {}
	for m, d in pairs(npcs) do
		if not m:IsDescendantOf(workspace) then
			removeNPC(d, false)
		elseif d.root.Parent then
			d.dist = mr and math.floor((d.root.Position - mr.Position).Magnitude) or 0
			if d.target and not d.frozen then
				local f = Vector3.new(d.target.X - d.root.Position.X, 0, d.target.Z - d.root.Position.Z)
				if f.Magnitude < 3 then d.target = nil else d.hum:MoveTo(d.target) end
			end
			if d.following and not d.frozen and controlling ~= d then followers[#followers + 1] = d end
		end
	end
	if mr then -- followers stand slightly to the side and behind me, not in a line behind my back
		table.sort(followers, function(a, b) return a.id < b.id end)
		for i, d in ipairs(followers) do
			local slot = i - 1
			local side, ring = (slot % 2 == 0) and 1 or -1, math.floor(slot / 2)
			local goal = (mr.CFrame * CFrame.new(side * (3.5 + ring * 2.5), 0, 3 + ring * 2)).Position
			local f = Vector3.new(goal.X - d.root.Position.X, 0, goal.Z - d.root.Position.Z)
			d.hum:MoveTo(f.Magnitude > 2.2 and goal or d.root.Position)
		end
	end
	if controlling then setAlpha(1) end
	refresh()
end

task.spawn(function()
	while true do
		task.wait(0.1)
		if autoScan and os.clock() - lastScan >= interval then
			lastScan = os.clock()
			local ok, e = pcall(scan, false)
			if not ok then bad("Scan error:", e) end
		end
	end
end)
task.spawn(function()
	while true do
		local ok, e = pcall(tick)
		if not ok then bad("Update error:", e) end
		task.wait(0.25)
	end
end)

setStatus("Click = select / deselect, Ctrl / Shift = multi-select.")
log("Ready. Use the 'NPC Menu' button to open / close the menu (you can drag it).")
