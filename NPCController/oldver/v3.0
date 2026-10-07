-- NPC Controller v3 - ONE LocalScript
-- Put it in: StarterPlayer > StarterPlayerScripts (type: LocalScript)
-- Made for your own game in Roblox Studio.

local TAG = "[NPC] "
local function log(...) print(TAG, ...) end
local function bad(...) warn(TAG, ...) end

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

if not RunService:IsClient() then
	bad("ERROR: this must be a LocalScript in StarterPlayerScripts, not a normal Script.")
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	bad("ERROR: PlayerGui did not appear within 10 seconds")
	return
end
log("Script v3 started")

---------------------------------------------------------------- Settings / state
local DEFAULT_INTERVAL = 2   -- seconds between auto-scans
local DEFAULT_SPIN = 300     -- degrees per second

local npcs = {}              -- [model] = d
local nextId = 0
local selected = {}          -- [d] = true
local primary = nil          -- main selected NPC (used for info / control)
local anchorSel = nil        -- anchor for Shift range select

local controlling = nil      -- NPC we are playing as
local possessMode = true     -- true: swap Player.Character, false: direct Humanoid:Move
local possessed = false      -- are we currently using the character swap?
local homeChar = nil         -- my real character while controlling
local savedStats = nil
local keepClose = true
local sprinting = false

local clickToMove = false
local clickAdd = false
local autoScan = true
local scanInterval = DEFAULT_INTERVAL
local lastScan = 0
local espAll = false
local spinSpeed = DEFAULT_SPIN

local ignored = setmetatable({}, { __mode = "k" })       -- models the user removed by hand
local warnedNoRoot = setmetatable({}, { __mode = "k" })

local orderCounter = 0
local function nextOrder() orderCounter += 1 return orderCounter end

local refreshUI            -- defined later
local speedBox, jumpBox    -- value text boxes, defined later

---------------------------------------------------------------- Player controls (WASD / gamepad / mobile)
local controls = nil
task.spawn(function()
	local ok, res = pcall(function()
		local ps = player:WaitForChild("PlayerScripts", 10)
		local pm = ps and ps:WaitForChild("PlayerModule", 10)
		return pm and require(pm):GetControls()
	end)
	if ok and res then
		controls = res
		log("Default player controls found")
	else
		bad("PlayerModule not available, using fallback WASD input:", res)
	end
end)

local function getMoveVector()
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

-- while controlling, "my character" always means my REAL character
local function myChar() return homeChar or player.Character end
local function myRoot() local c = myChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function myHum() local c = myChar() return c and c:FindFirstChildOfClass("Humanoid") end

---------------------------------------------------------------- UI helpers
local GRAY = Color3.fromRGB(58, 58, 64)
local GREEN = Color3.fromRGB(40, 150, 70)
local BLUE = Color3.fromRGB(50, 100, 190)
local RED = Color3.fromRGB(170, 60, 60)
local ROWC = Color3.fromRGB(40, 40, 46)
local WHITE = Color3.new(1, 1, 1)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end
local function fmt(n) return tostring(math.floor(n * 100 + 0.5) / 100) end

local old = playerGui:FindFirstChild("NPCController")
if old then old:Destroy() end

local gui = new("ScreenGui", { Name = "NPCController", ResetOnSpawn = false, DisplayOrder = 999, IgnoreGuiInset = true }, playerGui)

local toggleBtn = new("TextButton", {
	Size = UDim2.new(0, 90, 0, 28), Position = UDim2.new(0, 10, 0, 44),
	BackgroundColor3 = Color3.fromRGB(40, 40, 46), TextColor3 = WHITE,
	Font = Enum.Font.GothamBold, TextSize = 13, Text = "NPC (P)", BorderSizePixel = 0,
}, gui)
corner(toggleBtn)

local main = new("Frame", {
	Size = UDim2.new(0, 700, 0, 500), Position = UDim2.new(0, 20, 0.5, -250),
	BackgroundColor3 = Color3.fromRGB(24, 24, 28), BorderSizePixel = 0,
}, gui)
corner(main, 10)

local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(34, 34, 40), BorderSizePixel = 0, Active = true,
}, main)
corner(titleBar, 10)
new("TextLabel", {
	Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 12, 0, 0), BackgroundTransparency = 1,
	TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "NPC Controller v3   |   P: menu   |   X: stop controlling",
}, titleBar)

-- LEFT panel: NPC list + scan controls
local left = new("Frame", {
	Size = UDim2.new(0, 250, 1, -48), Position = UDim2.new(0, 8, 0, 40),
	BackgroundColor3 = Color3.fromRGB(32, 32, 37), BorderSizePixel = 0,
}, main)
corner(left)
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(180, 180, 190),
	Font = Enum.Font.GothamBold, TextSize = 12, Text = "NPC LIST",
}, left)

local list = new("ScrollingFrame", {
	Size = UDim2.new(1, -8, 1, -142), Position = UDim2.new(0, 4, 0, 138), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, left)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)

new("TextLabel", {
	Size = UDim2.new(1, -12, 0, 44), Position = UDim2.new(0, 6, 0, 88), BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(150, 150, 160), Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Click = select / deselect  |  Ctrl, Shift = multi-select\nBox next to Auto-scan = seconds between scans\nClick to add = click an NPC in the world",
}, left)

-- RIGHT panel: info + collapsible sections
local right = new("Frame", {
	Size = UDim2.new(1, -274, 1, -48), Position = UDim2.new(0, 266, 0, 40),
	BackgroundColor3 = Color3.fromRGB(32, 32, 37), BorderSizePixel = 0,
}, main)
corner(right)
local info = new("TextLabel", {
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0, 4), BackgroundTransparency = 1,
	TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 13, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "No NPC selected - click one in the list",
}, right)
local scroll = new("ScrollingFrame", {
	Size = UDim2.new(1, -12, 1, -82), Position = UDim2.new(0, 6, 0, 46), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, right)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, scroll)
local status = new("TextLabel", {
	Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 1, -32), BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(190, 190, 200), Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "Looking for NPCs...",
}, right)
local function setStatus(t) status.Text = t end

-- HUD while controlling
local hud = new("TextLabel", {
	Size = UDim2.new(0, 640, 0, 30), Position = UDim2.new(0.5, -320, 0, 8),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24), BackgroundTransparency = 0.25,
	TextColor3 = Color3.fromRGB(120, 255, 140), Font = Enum.Font.GothamBold, TextSize = 13,
	Text = "", Visible = false, BorderSizePixel = 0,
}, gui)
corner(hud, 8)

-- drag the window by its title bar
do
	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, main.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end
toggleBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)

---------------------------------------------------------------- Selection helpers
local function selCount() local n = 0 for _ in pairs(selected) do n += 1 end return n end
local function clearSel() for k in pairs(selected) do selected[k] = nil end end

local function getPrimary()
	if primary and selected[primary] and npcs[primary.model] == primary then return primary end
	local best
	for d in pairs(selected) do
		if not best or d.id < best.id then best = d end
	end
	primary = best
	return best
end

local function getTargets()
	local t = {}
	for d in pairs(selected) do
		if npcs[d.model] == d and d.hum.Parent then table.insert(t, d) end
	end
	table.sort(t, function(a, b) return a.id < b.id end)
	return t
end

local function needTargets()
	local t = getTargets()
	if #t == 0 then
		bad("Select at least one NPC in the list first.")
		setStatus("Select at least one NPC in the list first.")
	end
	return t
end

local function anyTarget(prop)
	for d in pairs(selected) do
		if d[prop] then return true end
	end
	return false
end

local function toggleOnTargets(prop, apply)
	local ts = needTargets()
	if #ts == 0 then return end
	local newState = not anyTarget(prop)
	for _, d in ipairs(ts) do apply(d, newState) end
end

---------------------------------------------------------------- NPC logic
local function findRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
end

local function applyStats(d)
	local h = d.hum
	if d.frozen then
		h.WalkSpeed = 0
		h.JumpPower = 0
		h.JumpHeight = 0
		return
	end
	local mult = (controlling == d and sprinting) and 1.7 or 1
	h.WalkSpeed = d.speed * mult
	if d.jumpEdited then
		h.UseJumpPower = true
		h.JumpPower = d.jumpPower
	else
		h.UseJumpPower = d.origUseJP
		h.JumpPower = d.origJumpPower
		h.JumpHeight = d.origJumpHeight
	end
end

local function setFrozen(d, state)
	d.frozen = state
	if state then
		d.following = false
		d.target = nil
		d.hum:MoveTo(d.root.Position)
	end
	applyStats(d)
	log(state and "Frozen:" or "Unfrozen:", d.model.Name)
end

local function standUp(d)
	if d.hum.Sit then d.hum.Sit = false end
end

local function setMyTransparency(v)
	local c = myChar()
	if not c then return end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") then p.LocalTransparencyModifier = v end
	end
end

local function hudText()
	return "Controlling: " .. (controlling and controlling.model.Name or "?")
		.. (possessed and "  [Possess]" or "  [Direct]")
		.. "  |  WASD move, Space jump, Shift sprint, C sit, X stop, P menu"
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
				local ok, err = pcall(function() player.Character = homeChar end)
				if not ok then bad("Could not give your character back:", err) end
			else
				bad("Your original character no longer exists - wait for the server to respawn you.")
			end
		end
	end

	local h = myHum()
	if h then
		if savedStats then
			h.WalkSpeed, h.JumpPower, h.JumpHeight = savedStats.ws, savedStats.jp, savedStats.jh
		end
		workspace.CurrentCamera.CameraSubject = h
	end
	savedStats = nil
	setMyTransparency(0)
	homeChar = nil
	pcall(applyStats, d)

	hud.Visible = false
	main.Visible = true
	log("Stopped controlling:", d.model.Name, reason or "")
end

local function startControl(d)
	if controlling == d then return end
	if controlling then stopControl("switching") end

	if d.hum.Health <= 0 then
		bad("NPC", d.model.Name, "is dead (Health = 0), nothing to control.")
		return
	end
	local c = player.Character
	local ch = c and c:FindFirstChildOfClass("Humanoid")
	if not ch then
		bad("Your character has no Humanoid yet - wait until it spawns.")
		return
	end

	homeChar = c
	controlling = d
	d.following, d.target, d.moving = false, nil, false
	if d.frozen then setFrozen(d, false) end

	possessed = false
	if possessMode then
		local ok, err = pcall(function() player.Character = d.model end)
		if ok and player.Character == d.model then
			possessed = true
		else
			bad("Possess mode failed (" .. tostring(err) .. "), falling back to Direct mode.")
			pcall(function() player.Character = homeChar end)
		end
	end

	if not possessed then
		savedStats = { ws = ch.WalkSpeed, jp = ch.JumpPower, jh = ch.JumpHeight }
		ch.WalkSpeed, ch.JumpPower, ch.JumpHeight = 0, 0, 0 -- my real character stays still
	end

	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = d.hum

	hud.Text = hudText()
	hud.Visible = true
	main.Visible = false

	if d.root.Anchored then
		bad("NPC", d.model.Name, ": root part is Anchored - it will not move. Unanchor it.")
	end
	log("Controlling:", d.model:GetFullName(), possessed and "(Possess mode)" or "(Direct mode)")
end

local function releaseNPC(d)
	d.frozen, d.following, d.spinning, d.aiOff = false, false, false, false
	d.target = nil
	d.speed = d.origSpeed
	d.jumpEdited = false
	d.jumpPower = d.origJumpPower
	pcall(applyStats, d)
	pcall(function() d.hl:Destroy() end)
	pcall(function() d.tag:Destroy() end)
end

local function removeNPC(d, byUser)
	if npcs[d.model] ~= d then return end
	if controlling == d then stopControl("NPC removed") end
	if byUser then ignored[d.model] = true end
	selected[d] = nil
	if primary == d then primary = nil end
	if anchorSel == d then anchorSel = nil end
	releaseNPC(d)
	d.row:Destroy()
	npcs[d.model] = nil
	log("Removed from list:", d.model.Name)
end

local function onRowClick(d)
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)

	if shift and anchorSel and npcs[anchorSel.model] == anchorSel then
		if not ctrl then clearSel() end
		local lo, hi = math.min(anchorSel.id, d.id), math.max(anchorSel.id, d.id)
		for _, o in pairs(npcs) do
			if o.id >= lo and o.id <= hi then selected[o] = true end
		end
		primary = d
	elseif ctrl then
		if selected[d] then
			selected[d] = nil
			if primary == d then primary = nil end
		else
			selected[d] = true
			primary = d
		end
		anchorSel = d
	else
		if selCount() == 1 and selected[d] then
			clearSel()
			primary = nil
		else
			clearSel()
			selected[d] = true
			primary = d
		end
		anchorSel = d
	end
	local n = selCount()
	setStatus(n == 0 and "Selection cleared." or (n .. " NPC(s) selected."))
	refreshUI()
end

local function addNPC(model, hum, root)
	nextId += 1
	local d = {
		id = nextId, model = model, hum = hum, root = root,
		frozen = false, following = false, spinning = false, aiOff = false,
		moving = false, moveTime = 0, dist = 0, warnedStuck = false, target = nil,
		speed = hum.WalkSpeed, origSpeed = hum.WalkSpeed,
		jumpPower = hum.JumpPower, origJumpPower = hum.JumpPower,
		origJumpHeight = hum.JumpHeight, origUseJP = hum.UseJumpPower, jumpEdited = false,
		spawnCF = root.CFrame,
	}

	-- list row: [ name button ][ X ]
	local row = new("Frame", { Name = model.Name, Size = UDim2.new(1, -6, 0, 34), BackgroundTransparency = 1, LayoutOrder = d.id }, list)
	local btn = new("TextButton", {
		Size = UDim2.new(1, -34, 1, 0), BackgroundColor3 = ROWC, TextColor3 = WHITE, Font = Enum.Font.Gotham,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Text = model.Name, BorderSizePixel = 0,
	}, row)
	corner(btn)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, btn)
	local x = new("TextButton", {
		Size = UDim2.new(0, 30, 1, 0), Position = UDim2.new(1, -30, 0, 0), BackgroundColor3 = RED, TextColor3 = WHITE,
		Font = Enum.Font.GothamBold, TextSize = 13, Text = "X", BorderSizePixel = 0,
	}, row)
	corner(x)
	d.row, d.btn = row, btn
	btn.MouseButton1Click:Connect(function() onRowClick(d) end)
	x.MouseButton1Click:Connect(function()
		removeNPC(d, true)
		refreshUI()
	end)

	-- highlight through walls + name tag (only you see them)
	d.hl = new("Highlight", {
		Name = "NPCCtrlHL", Adornee = model, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillTransparency = 0.55, OutlineTransparency = 0, Enabled = false,
	}, model)
	d.tag = new("BillboardGui", {
		Name = "NPCCtrlTag", Adornee = root, AlwaysOnTop = true, Size = UDim2.new(0, 200, 0, 30),
		StudsOffset = Vector3.new(0, 3.8, 0), Enabled = false,
	}, root)
	d.tagLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, TextColor3 = WHITE,
		TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBold, TextSize = 14, Text = model.Name,
	}, d.tag)

	npcs[model] = d
	ignored[model] = nil

	if root.Anchored then
		bad("NPC", model.Name, ": root part is Anchored - it will not be able to move. Unanchor it.")
	end
	if hum.Health <= 0 then
		bad("NPC", model.Name, ": Health = 0, it is dead.")
	end
	log("Added NPC:", model:GetFullName())
	return d
end

local lastCount = -1
local function scan(manual)
	if manual then
		for k in pairs(ignored) do ignored[k] = nil end
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local model = inst.Parent
			if model and model:IsA("Model") and not npcs[model] and not ignored[model]
				and model ~= homeChar and not Players:GetPlayerFromCharacter(model) then
				local root = findRoot(model)
				if root then
					addNPC(model, inst, root)
				elseif not warnedNoRoot[model] then
					warnedNoRoot[model] = true
					bad("Skipped", model:GetFullName(), ": no HumanoidRootPart / PrimaryPart / Torso")
				end
			end
		end
	end
	local count = 0
	for _ in pairs(npcs) do count += 1 end
	if count ~= lastCount or manual then
		lastCount = count
		log("Scan finished: NPCs in list =", count)
		if count == 0 then
			bad("No NPCs found! You need a Model in workspace with a Humanoid and HumanoidRootPart (and it must not be a player).")
			setStatus("No NPCs found. Check the console (F9).")
		elseif manual then
			setStatus("Scan finished: " .. count .. " NPC(s) in the list.")
		end
	end
end

---------------------------------------------------------------- UI refresh + ESP
local function updateESP()
	for _, d in pairs(npcs) do
		local color
		if controlling == d then color = Color3.fromRGB(60, 255, 90)
		elseif selected[d] then color = Color3.fromRGB(255, 220, 60)
		elseif espAll then color = Color3.fromRGB(80, 200, 255) end
		if color then
			d.hl.FillColor = color
			d.hl.OutlineColor = color
			d.tagLabel.TextColor3 = color
		end
		d.hl.Enabled = color ~= nil
		d.tag.Enabled = color ~= nil
	end
end

local features = {}

refreshUI = function()
	local prim = getPrimary()
	for _, d in pairs(npcs) do
		local t = d.model.Name .. "  |  " .. d.dist .. "m"
		if controlling == d then t = "* " .. t end
		if d.frozen then t = t .. "  [frozen]" end
		d.btn.Text = t
		d.btn.BackgroundColor3 = (controlling == d and GREEN) or (selected[d] and BLUE) or ROWC
	end

	if prim and prim.hum.Parent then
		local n = selCount()
		info.Text = string.format("%s%s\nHP %d/%d  |  speed %s  |  %d studs",
			prim.model.Name, n > 1 and ("   (+" .. (n - 1) .. " more selected)") or "",
			math.floor(prim.hum.Health), math.floor(prim.hum.MaxHealth), fmt(prim.speed), prim.dist)
	else
		info.Text = "No NPC selected - click one in the list"
	end

	for _, f in ipairs(features) do
		local on = f.isOn and f.isOn() or false
		f.btn.BackgroundColor3 = on and GREEN or GRAY
		f.btn.Text = (on and f.onText) or f.text
	end

	if speedBox and not speedBox:IsFocused() then speedBox.Text = prim and fmt(prim.speed) or "" end
	if jumpBox and not jumpBox:IsFocused() then jumpBox.Text = prim and fmt(prim.jumpPower) or "" end

	updateESP()
end

---------------------------------------------------------------- UI builders (features, sections, sliders)
local function makeFeature(parent, text, fn, isOn, onText)
	local b = new("TextButton", {
		BackgroundColor3 = GRAY, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 12,
		Text = text, BorderSizePixel = 0, TextWrapped = true,
	}, parent)
	corner(b)
	b.MouseButton1Click:Connect(function()
		local ok, err = pcall(fn)
		if not ok then bad("Error in button '" .. text .. "':", err) end
		refreshUI()
	end)
	table.insert(features, { btn = b, text = text, onText = onText, isOn = isOn })
	return b
end

local function section(title)
	local box = new("Frame", {
		Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(38, 38, 44), BorderSizePixel = 0, LayoutOrder = nextOrder(),
	}, scroll)
	corner(box)
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, box)
	new("UIPadding", { PaddingBottom = UDim.new(0, 6) }, box)
	local header = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromRGB(52, 52, 62), TextColor3 = WHITE,
		Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "[-]  " .. title, BorderSizePixel = 0, LayoutOrder = 0,
	}, box)
	corner(header)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, header)
	local content = new("Frame", {
		Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1,
	}, box)
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	header.MouseButton1Click:Connect(function()
		content.Visible = not content.Visible
		header.Text = (content.Visible and "[-]  " or "[+]  ") .. title
	end)
	return content
end

local function row(content, specs)
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, r)
	local n = #specs
	for i, s in ipairs(specs) do
		local b = makeFeature(r, s[1], s[2], s[3], s[4])
		b.Size = UDim2.new(1 / n, -(5 * (n - 1)) / n, 1, 0)
		b.LayoutOrder = i
	end
end

local function valueRow(content, labelText, onApply, onReset)
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, content)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
	}, r)
	new("TextLabel", {
		Size = UDim2.new(0, 86, 1, 0), BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.Gotham,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Text = labelText, LayoutOrder = 1,
	}, r)
	local box = new("TextBox", {
		Size = UDim2.new(1, -170, 1, 0), BackgroundColor3 = Color3.fromRGB(28, 28, 32), TextColor3 = WHITE,
		Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false, Text = "", BorderSizePixel = 0, LayoutOrder = 2,
	}, r)
	corner(box)
	local reset = new("TextButton", {
		Size = UDim2.new(0, 70, 1, 0), BackgroundColor3 = GRAY, TextColor3 = WHITE, Font = Enum.Font.GothamBold,
		TextSize = 12, Text = "Reset", BorderSizePixel = 0, LayoutOrder = 3,
	}, r)
	corner(reset)
	box.FocusLost:Connect(function()
		local ok, err = pcall(onApply, box.Text)
		if not ok then bad("Error applying value:", err) end
		refreshUI()
	end)
	reset.MouseButton1Click:Connect(function()
		local ok, err = pcall(onReset)
		if not ok then bad("Error resetting value:", err) end
		refreshUI()
	end)
	return box
end

local function makeSlider(content, labelText, minV, maxV, defaultV, onChange)
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, content)
	new("TextLabel", {
		Size = UDim2.new(0, 86, 1, 0), BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.Gotham,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Text = labelText,
	}, frame)
	local hit = new("TextButton", {
		Size = UDim2.new(1, -204, 1, 0), Position = UDim2.new(0, 90, 0, 0), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false,
	}, frame)
	local track = new("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0.5, -3),
		BackgroundColor3 = Color3.fromRGB(70, 70, 78), BorderSizePixel = 0,
	}, hit)
	corner(track, 3)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, track)
	corner(fill, 3)
	local knob = new("Frame", {
		Size = UDim2.new(0, 14, 0, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0,
	}, hit)
	corner(knob, 7)
	local valueLabel = new("TextLabel", {
		Size = UDim2.new(0, 46, 1, 0), Position = UDim2.new(1, -110, 0, 0), BackgroundTransparency = 1,
		TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 12, Text = "",
	}, frame)
	local reset = new("TextButton", {
		Size = UDim2.new(0, 60, 0, 26), Position = UDim2.new(1, -60, 0, 2), BackgroundColor3 = GRAY, TextColor3 = WHITE,
		Font = Enum.Font.GothamBold, TextSize = 12, Text = "Reset", BorderSizePixel = 0,
	}, frame)
	corner(reset)

	local value = defaultV
	local function render()
		local rel = (value - minV) / (maxV - minV)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, -7, 0.5, -7)
		valueLabel.Text = tostring(math.floor(value + 0.5))
	end
	local function setValue(v)
		value = math.clamp(v, minV, maxV)
		render()
		onChange(value)
	end
	render()

	local dragging = false
	local function fromX(x)
		local aw = hit.AbsoluteSize.X
		if aw <= 0 then return end
		setValue(minV + math.clamp((x - hit.AbsolutePosition.X) / aw, 0, 1) * (maxV - minV))
	end
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(i.Position.X)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			fromX(i.Position.X)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	reset.MouseButton1Click:Connect(function() setValue(defaultV) end)
end

---------------------------------------------------------------- LEFT panel controls (scan / refresh / click to add)
local autoBtn = makeFeature(left, "Auto-scan: OFF", function()
	autoScan = not autoScan
	lastScan = 0
	setStatus(autoScan and ("Auto-scan ON, every " .. fmt(scanInterval) .. " s.") or "Auto-scan OFF.")
end, function() return autoScan end, "Auto-scan: ON")
autoBtn.Size = UDim2.new(0, 104, 0, 28)
autoBtn.Position = UDim2.new(0, 6, 0, 24)

local intervalBox = new("TextBox", {
	Size = UDim2.new(0, 50, 0, 28), Position = UDim2.new(0, 114, 0, 24), BackgroundColor3 = Color3.fromRGB(28, 28, 32),
	TextColor3 = WHITE, Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
	Text = tostring(DEFAULT_INTERVAL), PlaceholderText = "sec", BorderSizePixel = 0,
}, left)
corner(intervalBox)
intervalBox.FocusLost:Connect(function()
	local n = tonumber(intervalBox.Text)
	if not n or n < 0.2 or n > 120 then
		bad("Scan interval must be a number from 0.2 to 120 seconds. Keeping", scanInterval)
		intervalBox.Text = fmt(scanInterval)
		return
	end
	scanInterval = n
	intervalBox.Text = fmt(n)
	setStatus("Scan interval set to " .. fmt(n) .. " s.")
end)

local intervalReset = new("TextButton", {
	Size = UDim2.new(0, 66, 0, 28), Position = UDim2.new(0, 168, 0, 24), BackgroundColor3 = GRAY, TextColor3 = WHITE,
	Font = Enum.Font.GothamBold, TextSize = 12, Text = "Reset", BorderSizePixel = 0,
}, left)
corner(intervalReset)
intervalReset.MouseButton1Click:Connect(function()
	scanInterval = DEFAULT_INTERVAL
	intervalBox.Text = tostring(DEFAULT_INTERVAL)
	setStatus("Scan interval reset to " .. DEFAULT_INTERVAL .. " s.")
end)

local refreshBtn = makeFeature(left, "Refresh (scan once)", function()
	scan(true)
end)
refreshBtn.Size = UDim2.new(0, 112, 0, 28)
refreshBtn.Position = UDim2.new(0, 6, 0, 56)

local addBtn = makeFeature(left, "Click to add: OFF", function()
	clickAdd = not clickAdd
	setStatus(clickAdd and "Click to add ON: click an NPC in the world to add it to the list." or "Click to add OFF.")
end, function() return clickAdd end, "Click to add: ON")
addBtn.Size = UDim2.new(0, 116, 0, 28)
addBtn.Position = UDim2.new(0, 122, 0, 56)

---------------------------------------------------------------- Features / sections
-- ===== Control =====
local sCtl = section("Control")
row(sCtl, {
	{ "Control NPC", function()
		if controlling then stopControl("button") return end
		local ts = needTargets()
		if #ts == 0 then return end
		local p = getPrimary()
		if #ts > 1 then bad("Several NPCs selected - controlling only:", p.model.Name) end
		startControl(p)
	end, function() return controlling ~= nil end, "Controlling (X to stop)" },
	{ "Mode: Direct", function()
		possessMode = not possessMode
		setStatus(possessMode
			and "Mode: Possess - your Character is swapped to the NPC, so normal player scripts (fly, etc.) work on it."
			or "Mode: Direct - the script moves the NPC Humanoid itself.")
		if controlling then
			local d = controlling
			stopControl("mode change")
			startControl(d)
		end
	end, function() return possessMode end, "Mode: Possess" },
})
row(sCtl, {
	{ "Click to Move", function()
		clickToMove = not clickToMove
		setStatus(clickToMove and "Click to Move ON: click the ground, selected NPCs walk there." or "Click to Move OFF.")
	end, function() return clickToMove end, "Click to Move: ON" },
	{ "Follow me", function()
		toggleOnTargets("following", function(d, state)
			if controlling == d then bad("Cannot follow while you control", d.model.Name) return end
			if d.frozen then bad(d.model.Name, "is frozen - unfreeze it first.") return end
			d.following = state
			d.target = nil
			if state then standUp(d) end
		end)
	end, function() return anyTarget("following") end, "Following me" },
})
row(sCtl, {
	{ "Keep my char near", function()
		keepClose = not keepClose
		setStatus(keepClose
			and "My character stays next to the NPC while controlling, so you keep network ownership."
			or "My character stays where it is. If you are far away, the NPC may stop obeying.")
	end, function() return keepClose end, "Keep my char near: ON" },
	{ "Stop moving", function()
		for _, d in ipairs(needTargets()) do
			d.following, d.target = false, nil
			d.hum:MoveTo(d.root.Position)
		end
	end },
})

-- ===== Actions =====
local sAct = section("Actions")
row(sAct, {
	{ "Disable AI", function()
		toggleOnTargets("aiOff", function(d, state)
			d.aiOff = state
			if state then d.following, d.target = false, nil end
			log("AI override", state and "ON" or "OFF", "for", d.model.Name)
		end)
	end, function() return anyTarget("aiOff") end, "AI disabled" },
	{ "Freeze", function()
		toggleOnTargets("frozen", setFrozen)
	end, function() return anyTarget("frozen") end, "Unfreeze" },
})

-- ===== Values =====
local sVal = section("Values")
speedBox = valueRow(sVal, "WalkSpeed", function(text)
	local n = tonumber(text)
	if not n or n < 0 or n > 500 then bad("WalkSpeed must be a number from 0 to 500.") return end
	local ts = getTargets()
	if #ts == 0 then bad("Select an NPC first.") return end
	for _, d in ipairs(ts) do
		d.speed = n
		applyStats(d)
	end
end, function()
	for _, d in ipairs(getTargets()) do
		d.speed = d.origSpeed
		applyStats(d)
	end
end)
jumpBox = valueRow(sVal, "JumpPower", function(text)
	local n = tonumber(text)
	if not n or n < 0 or n > 1000 then bad("JumpPower must be a number from 0 to 1000.") return end
	local ts = getTargets()
	if #ts == 0 then bad("Select an NPC first.") return end
	for _, d in ipairs(ts) do
		d.jumpPower = n
		d.jumpEdited = true
		applyStats(d)
	end
end, function()
	for _, d in ipairs(getTargets()) do
		d.jumpEdited = false
		d.jumpPower = d.origJumpPower
		applyStats(d)
	end
end)

-- ===== Teleport =====
local sTp = section("Teleport")
row(sTp, {
	{ "Me -> NPC", function()
		local p = getPrimary()
		if not p then bad("Select an NPC first.") return end
		if controlling then bad("Stop controlling first (your character is parked next to the NPC).") return end
		local mr = myRoot()
		if not mr then bad("You have no HumanoidRootPart.") return end
		mr.CFrame = p.root.CFrame * CFrame.new(0, 3, 6)
	end },
	{ "NPC -> me", function()
		local ts = needTargets()
		if #ts == 0 then return end
		local mr = myRoot()
		if not mr then bad("You have no HumanoidRootPart.") return end
		local n = #ts
		for i, d in ipairs(ts) do
			local pos
			if n == 1 then
				pos = (mr.CFrame * CFrame.new(0, 3, -5)).Position
			else
				local a = (i - 1) * (2 * math.pi / n)
				pos = (mr.CFrame * CFrame.new(math.sin(a) * 6, 3, -math.cos(a) * 6)).Position
			end
			d.root.CFrame = CFrame.lookAt(pos, Vector3.new(mr.Position.X, pos.Y, mr.Position.Z))
			d.root.AssemblyLinearVelocity = Vector3.zero
		end
	end },
})
row(sTp, {
	{ "Return to spawn point", function()
		for _, d in ipairs(needTargets()) do
			d.root.CFrame = d.spawnCF
			d.root.AssemblyLinearVelocity = Vector3.zero
			d.target = nil
		end
	end },
})

-- ===== Other =====
local sOth = section("Other")
row(sOth, {
	{ "Sit / Stand", function()
		local ts = needTargets()
		if #ts == 0 then return end
		local anySit = false
		for _, d in ipairs(ts) do if d.hum.Sit then anySit = true end end
		for _, d in ipairs(ts) do d.hum.Sit = not anySit end
	end, function()
		for d in pairs(selected) do if d.hum.Sit then return true end end
		return false
	end, "Sitting (stand up)" },
	{ "Jump", function()
		for _, d in ipairs(needTargets()) do
			if d.frozen then
				bad(d.model.Name, "is frozen - it cannot jump.")
			else
				standUp(d)
				d.hum.Jump = true
			end
		end
	end },
})
row(sOth, {
	{ "Spin", function()
		toggleOnTargets("spinning", function(d, state) d.spinning = state end)
	end, function() return anyTarget("spinning") end, "Spinning (stop)" },
	{ "Look at me", function()
		local mr = myRoot()
		if not mr then bad("You have no HumanoidRootPart.") return end
		for _, d in ipairs(needTargets()) do
			d.root.CFrame = CFrame.lookAt(d.root.Position, Vector3.new(mr.Position.X, d.root.Position.Y, mr.Position.Z))
		end
	end },
})
makeSlider(sOth, "Spin speed", 0, 1440, DEFAULT_SPIN, function(v) spinSpeed = v end)
row(sOth, {
	{ "Highlight all NPCs", function()
		espAll = not espAll
	end, function() return espAll end, "Highlight all: ON" },
})

log("UI built")

---------------------------------------------------------------- Mouse in the world (Click to add / Click to Move)
local function raycastMouse(ignore)
	local cam = workspace.CurrentCamera
	local pos = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
end

local function modelFromPart(part)
	local inst = part
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then return inst end
		inst = inst.Parent
	end
	return nil
end

-- returns true if the click hit a humanoid model (handled)
local function tryClickAdd()
	local res = raycastMouse({ myChar() })
	if not res then
		bad("Click to add: the click did not hit anything.")
		return false
	end
	local model = modelFromPart(res.Instance)
	if not model then return false end
	if model == homeChar or Players:GetPlayerFromCharacter(model) then
		bad("Click to add: that is a player's character, not an NPC.")
		return true
	end
	local d = npcs[model]
	if not d then
		local root = findRoot(model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not root or not hum then
			bad("Click to add:", model:GetFullName(), "has no Humanoid / root part.")
			return true
		end
		d = addNPC(model, hum, root)
	end
	if not (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then clearSel() end
	selected[d] = true
	primary = d
	anchorSel = d
	setStatus("Added / selected: " .. model.Name)
	return true
end

local function clickMove()
	local ts = getTargets()
	if #ts == 0 then
		bad("Click to Move is ON but no NPC is selected. Select one in the list.")
		return
	end
	local ignore = { myChar() }
	for _, d in ipairs(ts) do table.insert(ignore, d.model) end
	local res = raycastMouse(ignore)
	if not res then
		bad("Click missed: the ray did not hit anything (sky?). Click on the ground.")
		return
	end
	for i, d in ipairs(ts) do
		if d.frozen then
			bad(d.model.Name, "is frozen - unfreeze it first.")
		else
			local p = res.Position
			if #ts > 1 then
				local a = (i - 1) * (2 * math.pi / #ts)
				p = p + Vector3.new(math.cos(a) * 3, 0, math.sin(a) * 3)
			end
			d.following = false
			standUp(d)
			d.target = p
			d.hum:MoveTo(p)
		end
	end
	log("MoveTo:", tostring(res.Position))

	local m = new("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2), Material = Enum.Material.Neon, Color = Color3.fromRGB(60, 255, 90),
		Position = res.Position + Vector3.new(0, 0.6, 0),
	}, workspace)
	Debris:AddItem(m, 1.5)
end

---------------------------------------------------------------- Input
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.P then
		main.Visible = not main.Visible
	elseif kc == Enum.KeyCode.X then
		if controlling then
			stopControl("X key")
			refreshUI()
		end
	elseif kc == Enum.KeyCode.C then
		if controlling then
			controlling.hum.Sit = not controlling.hum.Sit
			refreshUI()
		end
	elseif kc == Enum.KeyCode.LeftShift then
		sprinting = true
		if controlling then applyStats(controlling) end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local handled = false
		if clickAdd then
			local ok, res = pcall(tryClickAdd)
			if not ok then bad("Click to add error:", res) else handled = res end
			refreshUI()
		end
		if not handled and clickToMove then
			local ok, err = pcall(clickMove)
			if not ok then bad("Click to Move error:", err) end
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		if controlling then applyStats(controlling) end
	end
end)

UIS.JumpRequest:Connect(function()
	-- in Possess mode the default player controls already make the NPC jump
	local d = controlling
	if d and not possessed and not d.frozen then
		standUp(d)
		d.hum.Jump = true
	end
end)

player.CharacterAdded:Connect(function(c)
	-- ignore our own character swaps; react only to a real respawn
	if controlling and c ~= controlling.model and c ~= homeChar then
		homeChar = nil
		stopControl("your character respawned", true)
		refreshUI()
	end
end)

---------------------------------------------------------------- Per-frame loop
RunService.RenderStepped:Connect(function(dt)
	for _, s in pairs(npcs) do
		if s.root.Parent then
			if s.spinning and not s.frozen then
				s.root.CFrame *= CFrame.Angles(0, math.rad(spinSpeed) * dt, 0)
			end
			-- "Disable AI": cancel any movement order that is not ours
			if s.aiOff and not s.frozen and not s.target and not s.following and controlling ~= s then
				s.hum:MoveTo(s.root.Position)
			end
		end
	end

	local d = controlling
	if not d then return end
	if not d.hum.Parent or d.hum.Health <= 0 then
		bad("NPC", d.model.Name, "died or disappeared - stopped controlling.")
		stopControl("NPC unavailable")
		refreshUI()
		return
	end

	local mr = myRoot()
	if mr then
		if keepClose then
			mr.Anchored = true
			mr.CFrame = d.root.CFrame * CFrame.new(0, 0, 10)
		else
			mr.Anchored = false
		end
	end

	local v = getMoveVector()
	if v.Magnitude > 0.05 then
		if not d.moving then
			d.moving = true
			d.moveTime = 0
			d.warnedStuck = false
			if d.frozen then bad("NPC is frozen - unfreeze it to walk.") end
		end
		standUp(d)
		d.following = false
		d.target = nil
		if not possessed then d.hum:Move(v, true) end
		d.moveTime += dt
		if d.moveTime > 1.5 and not d.warnedStuck and not d.frozen and d.root.AssemblyLinearVelocity.Magnitude < 0.5 then
			d.warnedStuck = true
			bad("The NPC is not moving. Possible reasons: no network ownership (turn on 'Keep my char near'), "
				.. "parts are Anchored, a server script controls it, or it is stuck on a wall.")
		end
	else
		if d.moving then
			d.moving = false
			if not possessed then d.hum:Move(Vector3.zero, true) end
		end
		-- AI is off while controlling: hold position unless we gave a click-to-move order
		if not d.target then d.hum:MoveTo(d.root.Position) end
	end
end)

---------------------------------------------------------------- Background loops
local warnedFar = false
local function tick()
	local mr = myRoot()

	for model, d in pairs(npcs) do
		if not model:IsDescendantOf(workspace) then
			removeNPC(d, false)
		elseif d.root.Parent then
			d.dist = mr and math.floor((d.root.Position - mr.Position).Magnitude) or 0
			d.tagLabel.Text = string.format("%s  [%d m]  HP %d", d.model.Name, d.dist, math.floor(d.hum.Health))

			-- keep click-to-move orders alive (MoveTo expires after ~8 s)
			if d.target and not d.frozen then
				local flat = Vector3.new(d.target.X - d.root.Position.X, 0, d.target.Z - d.root.Position.Z)
				if flat.Magnitude < 3 then d.target = nil else d.hum:MoveTo(d.target) end
			end
		end
	end

	-- followers walk slightly to the side and behind me, not in a straight line behind my back
	if mr then
		local followers = {}
		for _, d in pairs(npcs) do
			if d.following and not d.frozen and d.root.Parent and controlling ~= d then
				table.insert(followers, d)
			end
		end
		table.sort(followers, function(a, b) return a.id < b.id end)
		for i, d in ipairs(followers) do
			local slot = i - 1
			local side = (slot % 2 == 0) and 1 or -1
			local ring = math.floor(slot / 2)
			local goal = (mr.CFrame * CFrame.new(side * (3.5 + ring * 2.5), 0, 3 + ring * 2)).Position
			local flat = Vector3.new(goal.X - d.root.Position.X, 0, goal.Z - d.root.Position.Z)
			if flat.Magnitude > 2.2 then d.hum:MoveTo(goal) else d.hum:MoveTo(d.root.Position) end
		end
	end

	if controlling then
		setMyTransparency(1)
		if not keepClose and controlling.dist > 100 then
			if not warnedFar then
				warnedFar = true
				bad("The NPC is more than 100 studs away - network ownership may be lost. Turn on 'Keep my char near'.")
			end
		else
			warnedFar = false
		end
	end

	refreshUI()
end

task.spawn(function()
	while true do
		task.wait(0.1)
		if autoScan and os.clock() - lastScan >= scanInterval then
			lastScan = os.clock()
			local ok, err = pcall(scan, false)
			if not ok then bad("Scan error:", err) end
		end
	end
end)

task.spawn(function()
	while true do
		local ok, err = pcall(tick)
		if not ok then bad("Update error:", err) end
		task.wait(0.25)
	end
end)

log("Ready. Press P to open / close the menu.")
