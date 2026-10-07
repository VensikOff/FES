-- NPC Controller FE v8.2
-- Idea: Vensik | Made by Claude AI

local P, RS, UIS = game:GetService("Players"), game:GetService("RunService"), game:GetService("UserInputService")
local PFS = game:GetService("PathfindingService")
local player = P.LocalPlayer
local function bad(...) warn("[NPC]", ...) end
local function log(...) print("[NPC]", ...) end
if not RS:IsClient() then bad("This must be a LocalScript, not a Script.") return end
local pgui = player:WaitForChild("PlayerGui", 10)
if not pgui then bad("PlayerGui not found") return end

---------------------------------------------------------------- settings (no limits - any number works, 0 rate = off)
local S = {
	aiRate = 60,        -- anti-AI: MoveTo(own position) per second
	jitRate = 60,       -- jitter steps per second
	jitAmp = 0.01,      -- jitter size, studs
	jitter = true,      -- jitter on NPCs whose AI is held down
	aiSpam = false,     -- anti-AI MoveTo spam
	autoBan = false,    -- automatically ban NPCs whose body is anchored to the map
	tryAll = false,     -- Try on non-owned NPCs: apply anyway, then check and roll back if it did not work
	tryWait = 1.5,      -- seconds to wait before that check
	freezeMode = "hard",-- "soft" / "hard" / "full"
	hideDepth = 5,      -- Keep my char near: my body hides this deep under the NPC
	pocketDepth = 5,    -- Pocket: NPCs float this deep under me
	orbitRadius = 8,    -- Orbit: distance from me, studs
	orbitSpeed = 90,    -- Orbit: degrees per second
	claimHeight = 5,    -- Claim ownership: I hover this high above the NPC
	interval = 2,       -- auto-scan, seconds
	spin = 300,         -- spin speed, degrees per second
}
local DEF = table.clone(S)
local NEXT = { soft = "hard", hard = "full", full = "soft" }

---------------------------------------------------------------- state
local npcs, nextId, selected, primary, anchorSel = {}, 0, {}, nil, nil
local allSel, applyNew, allState, allFns, allVals = false, false, {}, {}, {} -- "All NPCs" + "Apply to new NPCs"
local controlling, possessed, homeChar, saved, spectating, claim = nil, false, nil, nil, nil, nil
local keepClose, moveMode, addMode, autoScan, lastScan = true, false, false, false, 0
local ignored, banned = setmetatable({}, { __mode = "k" }), {}
local collideSaved, homeCF, bodyMoved, hiddenNow = nil, nil, false, false
local order, features, fields = 0, {}, {}
local refresh, setStatus, rebuildBans, setCarry, closeAll, endClaim, settingsBox, claimBtn, applyRow, verifyTry
local alive, conns = true, {}
local function track(c) conns[#conns + 1] = c return c end
local function nxt() order += 1 return order end
local function fmt(n) return tostring(math.floor(n * 1000 + 0.5) / 1000) end
local function byId(a, b) return a.id < b.id end
-- is the NPC's BODY stuck to something anchored? IsGrounded only looks at parts joined to the root,
-- so an anchored item that just lies inside the model (not welded to the body) does not count
local function grounded(root)
	local ok, g = pcall(root.IsGrounded, root)
	return ok and g or false
end

local controls
task.spawn(function()
	local ok, r = pcall(function()
		return require(player:WaitForChild("PlayerScripts", 10):WaitForChild("PlayerModule", 10)):GetControls()
	end)
	if ok and r then controls = r else bad("PlayerModule not found - controlling NPCs will not work:", r) end
end)
local function moveVec()
	if not controls then return Vector3.zero end
	local ok, v = pcall(controls.GetMoveVector, controls)
	return (ok and typeof(v) == "Vector3") and v or Vector3.zero
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
local toggle = T("TextButton", gui, { Size = UDim2.new(0, 84, 0, 28), Position = UDim2.new(0, 10, 0.5, -14), Text = "NPC Menu", Font = Enum.Font.GothamBold })
local main = T("Frame", gui, { Size = UDim2.new(0, 700, 0, 480), Position = UDim2.new(0, 20, 0.5, -240), BackgroundColor3 = C.bg })
local title = T("TextLabel", main, {
	Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 0, BackgroundColor3 = C.pn, Active = true,
	Text = "  NPC Controller FE v8.2 By Vensik", TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextSize = 13,
})
local grip = T("TextButton", main, { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -22, 1, -22), Text = "//", ZIndex = 10 })
-- top right: "-" = minimize (open again with the NPC Menu button), "X" = close the script and undo everything
T("TextButton", main, { Size = UDim2.new(0, 26, 0, 22), Position = UDim2.new(1, -60, 0, 4), Text = "-", TextSize = 18, Font = Enum.Font.GothamBold, ZIndex = 10 })
	.MouseButton1Click:Connect(function() main.Visible = false end)
T("TextButton", main, { Size = UDim2.new(0, 26, 0, 22), Position = UDim2.new(1, -30, 0, 4), Text = "X", BackgroundColor3 = C.red, Font = Enum.Font.GothamBold, ZIndex = 10 })
	.MouseButton1Click:Connect(function() closeAll() end)
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

-- one shared drag system (window move, resize, menu button move)
local active
local function makeDrag(h, start, move)
	h.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			active = { p0 = i.Position, data = start(), move = move }
		end
	end)
end
track(UIS.InputChanged:Connect(function(i)
	if active and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		active.move(i.Position - active.p0, active.data)
	end
end))
track(UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then active = nil end
end))
local function shift(frame, dl, p0) frame.Position = UDim2.new(p0.X.Scale, p0.X.Offset + dl.X, p0.Y.Scale, p0.Y.Offset + dl.Y) end
makeDrag(title, function() return main.Position end, function(dl, p0) shift(main, dl, p0) end)
makeDrag(grip, function() return main.AbsoluteSize end, function(dl, s0)
	main.Size = UDim2.new(0, math.max(540, s0.X + dl.X), 0, math.max(360, s0.Y + dl.Y))
end)
local tgMoved = false
makeDrag(toggle, function() tgMoved = false return toggle.Position end, function(dl, p0)
	if dl.Magnitude > 4 then tgMoved = true end
	if tgMoved then shift(toggle, dl, p0) end
end)
toggle.MouseButton1Click:Connect(function() if not tgMoved then main.Visible = not main.Visible end end)

---------------------------------------------------------------- ownership
-- Checked EVERY frame. ReceiveAge = time since the server last sent this part's physics.
-- Exactly 0 every frame = nobody sends it = my client simulates it. A part owned by the server or
-- another player gets updates, so its ReceiveAge is above 0 at least now and then -> red.
-- 8 frames of exact 0 in a row are needed, so one lucky frame can't give a false green.
local OWN = { mine = Color3.fromRGB(60, 220, 90), other = Color3.fromRGB(230, 60, 60), none = Color3.fromRGB(255, 160, 40), unk = Color3.fromRGB(150, 150, 150) }
local OWNTXT = { mine = "you own it", other = "NOT yours", none = "cannot be controlled", unk = "owner unknown" }
local warnedAge = false
local function ownStep()
	for _, d in pairs(npcs) do
		if d.hum.Health <= 0 or d.anchored then
			d.own, d.zeroRun = "none", 0
		else
			local ok, age = pcall(function() return d.root.ReceiveAge end)
			if not ok or type(age) ~= "number" then
				if not warnedAge then warnedAge = true bad("BasePart.ReceiveAge is not readable - ownership will show gray.") end
				d.own = "unk"
			else
				d.zeroRun = age == 0 and d.zeroRun + 1 or 0
				d.own = d.zeroRun >= 8 and "mine" or "other"
			end
		end
	end
end
local function isMine(d) return d.own == "mine" or d.own == "unk" end
-- run fn on the NPCs I own, report the rest in ONE message
-- With "Try on non-owned" ON, non-owned NPCs get the action too, then verifyTry checks it and rolls back.
-- NPCs whose body is anchored to the map are always skipped - they cannot move for anyone.
local function forOwned(t, what, fn)
	local skipped, done = {}, {}
	for _, d in ipairs(t) do
		if isMine(d) then
			fn(d) done[d] = true
		elseif S.tryAll and not d.anchored and d.hum.Health > 0 then
			verifyTry(d, what, fn) done[d] = true
		else
			skipped[#skipped + 1] = d.model.Name
		end
	end
	if #skipped > 0 then
		local names = table.concat(skipped, ", ", 1, math.min(#skipped, 6)) .. (#skipped > 6 and (" +" .. (#skipped - 6) .. " more") or "")
		local msg = what .. " skipped - not yours: " .. names .. ". Try Claim ownership (Other)" .. (S.tryAll and "." or " or turn on 'Try on non-owned'.")
		bad(msg) setStatus(msg)
	end
	return done
end

---------------------------------------------------------------- selection helpers
local function selCount() local n = 0 for _ in pairs(selected) do n += 1 end return n end
local function targets()
	local t = {}
	if allSel then
		for _, d in pairs(npcs) do if d.hum.Parent then t[#t + 1] = d end end
		table.sort(t, byId)
		return t
	end
	for d in pairs(selected) do if npcs[d.model] == d and d.hum.Parent then t[#t + 1] = d end end
	table.sort(t, byId)
	return t
end
local function need()
	local t = targets()
	if #t == 0 then bad("Select an NPC in the list first.") setStatus("Select an NPC in the list first.") end
	return t
end
local function getPrimary()
	if allSel then return nil end
	if not (primary and selected[primary]) then primary = targets()[1] end
	return primary
end
local function any(prop) for _, d in ipairs(targets()) do if d[prop] then return true end end return false end
-- for things that only make sense on one NPC (Control, Spectate, Claim, Go To)
local function one()
	if allSel then bad("Pick one NPC for this, not 'All NPCs'.") setStatus("Pick one NPC for this, not 'All NPCs'.") return nil end
	local p = getPrimary()
	if not p then need() end
	return p
end
-- on/off feature for the selection. Turning ON needs ownership (if needOwn). With "All NPCs" selected
-- the choice is remembered, so "Apply to new NPCs" can give it to NPCs that appear later.
local EXCL = { frozen = { "pocket", "orbit" }, pocket = { "frozen", "orbit" }, orbit = { "frozen", "pocket" } }
local function toggleProp(prop, fn, what, needOwn)
	local t = need()
	if #t == 0 then return end
	local s = not any(prop)
	local done = {}
	if s and needOwn then done = forOwned(t, what, function(d) fn(d, true) end)
	else for _, d in ipairs(t) do fn(d, s) done[d] = true end end
	if allSel then
		allState[prop], allFns[prop] = s, fn
		if s then for _, o in ipairs(EXCL[prop] or {}) do allState[o] = false end end
		-- the ones that did not get it (not yours / anchored) stay "pending": Apply to new gives it to them
		-- as soon as they become yours, get unanchored, or respawn
		for _, d in pairs(npcs) do d.newDone = done[d] or false end
	end
end

---------------------------------------------------------------- NPC logic
-- "suppressed" = the NPC's own AI must be held down. Anti-AI spam and jitter run on them.
local function suppressed(d) return controlling == d or d.aiOff or d.frozen or d.pocket or d.orbit end

local function applyStats(d)
	local h = d.hum
	if d.frozen then h.WalkSpeed, h.JumpPower, h.JumpHeight = 0, 0, 0 return end
	h.WalkSpeed = d.speed
	if d.jumpEdited then h.UseJumpPower, h.JumpPower = true, d.jumpPower
	else h.UseJumpPower, h.JumpPower, h.JumpHeight = d.o.useJP, d.o.jp, d.o.jh end
end
local function standUp(d) if d.hum.Sit then d.hum.Sit = false end end
local function cancelPath(d) d.pathId = (d.pathId or 0) + 1 d.target = nil end
local function unJitter(d)
	if d.jitUp then pcall(function() d.root.CFrame -= Vector3.new(0, d.jitUp, 0) end) d.jitUp = nil end
end
local function setAlpha(v) -- local only: other players never see this
	local c = myChar()
	if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") or p:IsA("Decal") then p.LocalTransparencyModifier = v end end end
end
-- collisions off for a model (store = part -> original CanCollide), and back
local function noclip(model, store)
	if not model then return end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if store[p] == nil then store[p] = p.CanCollide end
			p.CanCollide = false
		end
	end
end
local function unclip(store) for p, v in pairs(store) do if p.Parent then p.CanCollide = v end end end

-- Freeze. soft = WalkSpeed 0 + anti-AI + jitter. hard = + AlignPosition/AlignOrientation (cannot be pushed).
-- full = hard + PlatformStand (the Humanoid stops walking at all, AI commands do nothing).
local function pinFrozen(d)
	if d.movers then d.movers[2].Position, d.movers[3].CFrame = d.frozenCF.Position, d.frozenCF end
end
local function setFrozen(d, s)
	if s and (d.pocket or d.orbit) then setCarry(d, nil) end
	d.frozen, d.lost = s, false
	for _, o in ipairs(d.movers or {}) do pcall(o.Destroy, o) end
	d.movers = nil
	if d.fullFrozen then pcall(function() d.hum.PlatformStand = false end) d.fullFrozen = nil end
	if s then
		d.following = false
		cancelPath(d)
		d.hum:MoveTo(d.root.Position)
		d.frozenCF = d.root.CFrame
		if S.freezeMode ~= "soft" then
			local a = T("Attachment", d.root, { Name = "NPCC_Freeze" })
			local ap = T("AlignPosition", d.root, { Name = "NPCC_Freeze", Mode = Enum.PositionAlignmentMode.OneAttachment,
				Attachment0 = a, Position = d.root.Position, RigidityEnabled = true })
			local ao = T("AlignOrientation", d.root, { Name = "NPCC_Freeze", Mode = Enum.OrientationAlignmentMode.OneAttachment,
				Attachment0 = a, CFrame = d.root.CFrame, RigidityEnabled = true })
			d.movers = { a, ap, ao }
			if S.freezeMode == "full" then d.hum.PlatformStand, d.fullFrozen = true, true end
		end
	end
	applyStats(d)
end

-- Carry: "pocket" = NPC floats right under me, "orbit" = NPC circles around me, nil = release.
-- I stay the closest player either way, so I keep its ownership.
setCarry = function(d, mode)
	local cur = d.pocket and "pocket" or d.orbit and "orbit" or nil
	if cur == mode then return end
	if mode then
		if d.frozen then setFrozen(d, false) end
		d.following, d.spinning = false, false
		cancelPath(d)
		d.coll = d.coll or {}
		d.pocket, d.orbit = mode == "pocket", mode == "orbit"
		d.hum.PlatformStand = true
	else
		d.pocket, d.orbit = false, false
		if d.coll then unclip(d.coll) d.coll = nil end
		pcall(function() d.hum.PlatformStand = false end)
		local mr = myRoot()
		if mr and d.root.Parent then -- drop it in front of me
			local pos = (mr.CFrame * CFrame.new(0, 0, -5)).Position
			d.root.CFrame = CFrame.lookAt(pos, Vector3.new(mr.Position.X, pos.Y, mr.Position.Z))
			d.root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

-- Try on non-owned: remember the NPC, apply the action, wait, and if the NPC still is not mine the effect
-- only exists on my screen -> undo it (the server keeps its own version anyway)
local function snapshot(d)
	return { frozen = d.frozen, pocket = d.pocket, orbit = d.orbit, aiOff = d.aiOff, spinning = d.spinning,
		following = d.following, speed = d.speed, jumpPower = d.jumpPower, jumpEdited = d.jumpEdited,
		health = d.hum.Health, sit = d.hum.Sit, cf = d.root.CFrame }
end
local function rollback(d, sn)
	if (d.pocket and not sn.pocket) or (d.orbit and not sn.orbit) then setCarry(d, nil) end
	if d.frozen and not sn.frozen then setFrozen(d, false) end
	d.aiOff, d.spinning, d.following = sn.aiOff, sn.spinning, sn.following
	d.speed, d.jumpPower, d.jumpEdited = sn.speed, sn.jumpPower, sn.jumpEdited
	cancelPath(d)
	unJitter(d)
	pcall(applyStats, d)
	pcall(function()
		if d.hum.Health <= 0 and sn.health > 0 then d.hum.Health = sn.health end
		d.hum.Sit = sn.sit
		d.root.CFrame = sn.cf
	end)
	d.newDone = false -- Apply to new can try again once it is really mine
end
verifyTry = function(d, what, fn)
	local sn = snapshot(d)
	fn(d)
	task.delay(S.tryWait, function()
		if not alive or npcs[d.model] ~= d then return end
		if isMine(d) then
			log(what, "on", d.model.Name, "worked - it is yours now.")
		else
			local ok = pcall(rollback, d, sn)
			bad(what, "on", d.model.Name, "did not work (still not yours) -", ok and "rolled back." or "rollback failed.")
			setStatus(what .. " on " .. d.model.Name .. " did not work - rolled back.")
		end
	end)
end

local function hudText()
	if controlling then
		hud.Text = "Controlling " .. controlling.model.Name .. (possessed and "" or " [direct]") .. "  -  click here to stop"
	elseif claim then
		hud.Text = "Claiming " .. claim.d.model.Name .. ": pick an action when its dot turns green  -  click here to cancel"
	elseif spectating then
		hud.Text = "Watching " .. spectating.model.Name .. "  -  click here to stop"
	end
	hud.Visible = (controlling or claim or spectating) and true or false
end
local function stopSpectate()
	if not spectating then return end
	spectating = nil
	local h = myHum()
	if h then workspace.CurrentCamera.CameraSubject = h end
	hudText()
end
-- Claim ownership: hover above the NPC (I become the closest player), then any action brings me back
endClaim = function()
	if not claim then return end
	local c = claim
	claim = nil
	local r = myRoot()
	if r then
		r.Anchored = false
		if c.home then r.CFrame, r.AssemblyLinearVelocity = c.home, Vector3.zero end
	end
	hudText()
end
local function startClaim(d)
	local r = myRoot()
	if not r then bad("Your character is not loaded.") return end
	claim = { d = d, home = r.CFrame, told = false }
	setStatus("Claiming " .. d.model.Name .. "... wait for a green dot, then pick an action.")
	hudText()
end

local function stopControl(reason, charChanged)
	local d = controlling
	if not d then return end
	controlling = nil
	pcall(function() d.hum:Move(Vector3.zero, true) end)
	d.moving = false
	local r = myRoot()
	if r then
		r.Anchored = false
		if bodyMoved and homeCF then r.CFrame, r.AssemblyLinearVelocity = homeCF, Vector3.zero end -- back to where I started
	end
	bodyMoved = false
	if collideSaved then unclip(collideSaved) collideSaved = nil end
	setAlpha(0)
	hiddenNow = false
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
	saved, homeChar = nil, nil
	pcall(applyStats, d)
	main.Visible = true
	hudText()
	log("Stopped controlling", d.model.Name, reason or "")
end

local function startControl(d)
	if controlling == d then return end
	if d.anchored then bad(d.model.Name, "is anchored to the map - it cannot move.") setStatus(d.model.Name .. " is anchored - it cannot move.") return end
	local trying = not isMine(d)
	if trying and not S.tryAll then
		bad(d.model.Name, "is not yours - controlling it would only move it on your screen. Try Claim ownership.")
		setStatus(d.model.Name .. " is not yours. Try Claim ownership (Other) or turn on 'Try on non-owned'.")
		return
	end
	if trying then -- check after a moment; stop if it still is not mine
		task.delay(S.tryWait, function()
			if alive and controlling == d and not isMine(d) then
				stopControl("not yours - the server rejected it")
				bad("Control of", d.model.Name, "did not work (still not yours) - stopped.")
				setStatus("Control of " .. d.model.Name .. " did not work - stopped.")
			end
		end)
	end
	if controlling then stopControl("switch") end
	if d.hum.Health <= 0 then bad(d.model.Name, "is dead.") return end
	local c = player.Character
	local ch = c and c:FindFirstChildOfClass("Humanoid")
	if not ch then bad("Your character has no Humanoid yet.") return end
	stopSpectate()
	if d.pocket or d.orbit then setCarry(d, nil) end
	if d.frozen then setFrozen(d, false) end
	homeChar, controlling = c, d
	local hr = c:FindFirstChild("HumanoidRootPart")
	homeCF, bodyMoved = hr and hr.CFrame, false
	d.following, d.moving = false, false
	cancelPath(d)
	-- Possess: swap my Character to the NPC, the default controls drive it. If that fails - drive it directly.
	local ok, e = pcall(function() player.Character = d.model end)
	possessed = ok and player.Character == d.model
	if not possessed then
		bad("Possess failed (" .. tostring(e) .. ") - driving the NPC directly instead.")
		pcall(function() player.Character = homeChar end)
		saved = { ch.WalkSpeed, ch.JumpPower, ch.JumpHeight }
		ch.WalkSpeed, ch.JumpPower, ch.JumpHeight = 0, 0, 0
	end
	local cam = workspace.CurrentCamera
	cam.CameraType, cam.CameraSubject = Enum.CameraType.Custom, d.hum
	main.Visible = false
	hudText()
	log("Controlling", d.model:GetFullName())
end

-- smart Click to Move: PathfindingService goes around walls; MoveTo is re-sent often so the AI cannot steal the NPC
local function walkPath(d, goal)
	cancelPath(d)
	local id = d.pathId
	d.target = goal
	standUp(d)
	task.spawn(function()
		local ok, e = pcall(function()
			local path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
			local okC = pcall(function() path:ComputeAsync(d.root.Position, goal) end)
			local wps
			if okC and path.Status == Enum.PathStatus.Success then
				wps = path:GetWaypoints()
			else
				bad(d.model.Name, ": no path found, walking straight.")
				wps = { { Position = goal, Action = Enum.PathWaypointAction.Walk } }
			end
			for _, wp in ipairs(wps) do
				if d.pathId ~= id or npcs[d.model] ~= d then return end
				if wp.Action == Enum.PathWaypointAction.Jump then d.hum.Jump = true end
				local t0 = os.clock()
				repeat
					if d.pathId ~= id then return end
					d.hum:MoveTo(wp.Position)
					task.wait(0.1)
					local f = wp.Position - d.root.Position
				until Vector3.new(f.X, 0, f.Z).Magnitude < 2.5 or os.clock() - t0 > 4
			end
			if d.pathId == id then d.target = nil d.hum:MoveTo(d.root.Position) end
		end)
		if not ok then bad("Path error:", e) end
	end)
end

local function removeNPC(d, byUser)
	if npcs[d.model] ~= d then return end
	if controlling == d then stopControl("NPC removed") end
	if spectating == d then stopSpectate() end
	if claim and claim.d == d then endClaim() end
	if byUser then ignored[d.model] = true end
	selected[d] = nil
	if primary == d then primary = nil end
	if anchorSel == d then anchorSel = nil end
	d.following, d.spinning, d.aiOff = false, false, false
	cancelPath(d)
	pcall(setCarry, d, nil)
	pcall(setFrozen, d, false)
	d.speed, d.jumpEdited = d.o.speed, false
	unJitter(d)
	pcall(applyStats, d)
	pcall(function() d.hl:Destroy() end)
	d.row:Destroy()
	npcs[d.model] = nil
	log("Removed:", d.model.Name)
end
local function banNPC(d)
	if npcs[d.model] ~= d then return end
	banned[d.model] = true
	removeNPC(d, false)
	setStatus("Banned " .. d.model.Name .. " - unban it in Settings.")
	rebuildBans()
end

local function onRowClick(d)
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local shiftKey = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
	allSel = false -- clicking a normal NPC leaves "All NPCs"
	if shiftKey and anchorSel and npcs[anchorSel.model] == anchorSel then
		if not ctrl then table.clear(selected) end
		local lo, hi = math.min(anchorSel.id, d.id), math.max(anchorSel.id, d.id)
		for _, o in pairs(npcs) do if o.id >= lo and o.id <= hi then selected[o] = true end end
		primary = d
	elseif ctrl then
		selected[d] = (not selected[d]) or nil
		primary, anchorSel = selected[d] and d or nil, d
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
		o = { speed = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight, useJP = hum.UseJumpPower },
		aiAcc = 0, jitAcc = 0, zeroRun = 0, own = "other", newDone = false, anchored = grounded(root),
	}
	d.row = T("Frame", list, { Size = UDim2.new(1, -6, 0, 28), BackgroundTransparency = 1, LayoutOrder = d.id })
	d.btn = T("TextButton", d.row, { Size = UDim2.new(1, -66, 1, 0), BackgroundColor3 = C.bg, Text = model.Name, TextXAlignment = Enum.TextXAlignment.Left })
	T("UIPadding", d.btn, { PaddingLeft = UDim.new(0, 20) })
	d.dot = T("Frame", d.row, { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 6, 0.5, -5) })
	-- X = remove from the list (comes back on the next scan), Ban = never comes back until unbanned
	T("TextButton", d.row, { Size = UDim2.new(0, 28, 1, 0), Position = UDim2.new(1, -64, 0, 0), Text = "X", Font = Enum.Font.GothamBold })
		.MouseButton1Click:Connect(function() removeNPC(d, true) refresh() end)
	T("TextButton", d.row, { Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(1, -34, 0, 0), BackgroundColor3 = C.red, Text = "Ban", Font = Enum.Font.GothamBold })
		.MouseButton1Click:Connect(function() banNPC(d) refresh() end)
	d.btn.MouseButton1Click:Connect(function() onRowClick(d) end)
	d.hl = T("Highlight", model, { Adornee = model, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, FillTransparency = 0.55, Enabled = false })
	npcs[model], ignored[model] = d, nil
	if hum.Health <= 0 then bad(model.Name, ": Health = 0, it is dead.") end
	log("Added:", model:GetFullName())
	return d
end

local lastCount = -1
local function scan(manual)
	if manual then table.clear(ignored) end
	for _, h in ipairs(workspace:GetDescendants()) do
		if h:IsA("Humanoid") then
			local m = h.Parent
			if m and m:IsA("Model") and not npcs[m] and not ignored[m] and not banned[m] and m ~= homeChar and not P:GetPlayerFromCharacter(m) then
				local root = findRoot(m)
				if root and S.autoBan and grounded(root) then
					banned[m] = true
					log("Auto-banned (anchored):", m.Name)
					rebuildBans()
				elseif root then
					addNPC(m, h, root)
				else
					ignored[m] = true
					bad("Skipped", m:GetFullName(), ": no HumanoidRootPart / PrimaryPart / Torso")
				end
			end
		end
	end
	local n = 0
	for _ in pairs(npcs) do n += 1 end
	if n ~= lastCount or manual then
		lastCount = n
		log("Scan: NPCs in list =", n)
		if manual then
			setStatus(n == 0 and "No NPCs found nearby (far ones may not be loaded if the game uses streaming)." or ("Scan finished: " .. n .. " NPC(s)."))
		end
	end
end

---------------------------------------------------------------- "All NPCs" entry (top of the list)
local allBtn = T("TextButton", list, { Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = C.bg, Text = "  All NPCs",
	TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, LayoutOrder = 0 })
allBtn.MouseButton1Click:Connect(function()
	allSel = not allSel
	table.clear(selected)
	primary = nil
	setStatus(allSel and "All NPCs selected - actions apply to everyone in the list." or "Selection cleared.")
	refresh()
end)

refresh = function()
	local prim = getPrimary()
	local n = 0
	for _, d in pairs(npcs) do
		n += 1
		local tag = (d.frozen and "  [frozen]" or "") .. (d.pocket and "  [pocket]" or "") .. (d.orbit and "  [orbit]" or "")
		d.btn.Text = (controlling == d and " * " or "  ") .. d.model.Name .. "  |  " .. d.dist .. "m" .. tag
		d.btn.BackgroundColor3 = (controlling == d and C.on) or (selected[d] and C.sel) or C.bg
		d.dot.BackgroundColor3 = OWN[d.own] or OWN.unk
		local col = (controlling == d and Color3.fromRGB(60, 255, 90)) or (d.esp and Color3.fromRGB(80, 200, 255))
			or (selected[d] and Color3.fromRGB(255, 220, 60))
		d.hl.Enabled = col and true or false
		if col then d.hl.FillColor, d.hl.OutlineColor = col, col end
	end
	allBtn.Text = "  All NPCs (" .. n .. ")"
	allBtn.BackgroundColor3 = allSel and C.sel or C.bg
	if applyRow then applyRow.Visible = allSel end -- "Apply to new NPCs" only matters for "All NPCs"
	if allSel then
		info.Text = "All NPCs (" .. n .. ")" .. (applyNew and "  |  new NPCs get the same" or "")
	elseif prim and prim.hum.Parent then
		local c = selCount()
		info.Text = string.format("%s%s\nHP %d/%d  |  spd %s  |  %d studs  |  %s", prim.model.Name, c > 1 and ("  (+" .. (c - 1) .. " more)") or "",
			math.floor(prim.hum.Health), math.floor(prim.hum.MaxHealth), fmt(prim.speed), prim.dist, OWNTXT[prim.own] or "")
	else
		info.Text = "No NPC selected - click one in the list"
	end
	for _, f in ipairs(features) do
		local on = f[4] and f[4]() or false
		f[1].BackgroundColor3 = on and C.on or C.btn
		f[1].Text = f[5] and f[5]() or (on and f[3]) or f[2]
	end
	for _, f in ipairs(fields) do
		if not f[1]:IsFocused() then
			local v = f[2]()
			f[1].Text = v and fmt(v) or ""
		end
	end
end

---------------------------------------------------------------- UI builders
-- text can be a function -> dynamic label (for multi-state buttons)
local function btn(parent, text, fn, isOn, onText)
	local labelFn
	if type(text) == "function" then labelFn, text = text, text() end
	local b = T("TextButton", parent, { Text = text, TextWrapped = true, Font = Enum.Font.GothamBold })
	b.MouseButton1Click:Connect(function()
		-- while claiming, any action button first brings me back home, then runs the action
		if claim and b ~= claimBtn and b:IsDescendantOf(scroll) and not (settingsBox and b:IsDescendantOf(settingsBox)) then endClaim() end
		local ok, e = pcall(fn)
		if not ok then bad("Error in '" .. text .. "':", e) end
		refresh()
	end)
	features[#features + 1] = { b, text, onText, isOn, labelFn }
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
	local bs = {}
	for i, s in ipairs(specs) do
		local b = btn(r, s[1], s[2], s[3], s[4])
		b.Size, b.LayoutOrder = UDim2.new(1 / #specs, -4 * (#specs - 1) / #specs, 1, 0), i
		bs[i] = b
	end
	return bs
end
-- number field: label + box + Reset. Any number is accepted, the box shows get() when not typing.
local function field(c, name, get, apply, reset)
	local r = T("Frame", c, { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nxt() })
	lay(r, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) })
	T("TextLabel", r, { Size = UDim2.new(0, 130, 1, 0), Text = name, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 })
	local box = T("TextBox", r, { Size = UDim2.new(1, -196, 1, 0), BackgroundColor3 = C.bg, ClearTextOnFocus = false, Text = "", LayoutOrder = 2 })
	local rb = T("TextButton", r, { Size = UDim2.new(0, 58, 1, 0), Text = "Reset", Font = Enum.Font.GothamBold, LayoutOrder = 3 })
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if not n then bad(name .. ": type a number.")
		else
			local ok, e = pcall(apply, n)
			if not ok then bad(name .. " error:", e) end
		end
		refresh()
	end)
	rb.MouseButton1Click:Connect(function()
		local ok, e = pcall(reset)
		if not ok then bad(name .. " reset error:", e) end
		refresh()
	end)
	fields[#fields + 1] = { box, get }
end
local function setting(c, name, key, unit, hook)
	field(c, name, function() return S[key] end, function(n)
		if hook then hook() end
		S[key] = n
		setStatus(name .. ": " .. fmt(n) .. " " .. unit)
	end, function()
		if hook then hook() end
		S[key] = DEF[key]
		setStatus(name .. " reset to " .. fmt(DEF[key]) .. " " .. unit)
	end)
end

---------------------------------------------------------------- left panel: scan controls
local top = T("Frame", left, { Position = UDim2.new(0, 4, 0, 4), Size = UDim2.new(1, -8, 0, 60), BackgroundTransparency = 1, ZIndex = 5 })
lay(top, { Padding = UDim.new(0, 4) })
row(top, {
	{ "Auto-scan: OFF", function()
		autoScan, lastScan = not autoScan, 0
		setStatus(autoScan and ("Auto-scan ON, every " .. fmt(S.interval) .. " s.") or "Auto-scan OFF.")
	end, function() return autoScan end, "Auto-scan: ON" },
	{ "Refresh", function() scan(true) end },
})
row(top, { { "Click to add: OFF", function()
	addMode = not addMode
	setStatus(addMode and "Click an NPC in the world to add it to the list." or "Click to add OFF.")
end, function() return addMode end, "Click to add: ON" } })

---------------------------------------------------------------- right panel
-- above all sections: what you do to "All NPCs" also happens to NPCs that appear later
applyRow = row(scroll, { { "Apply to new NPCs: OFF", function()
	applyNew = not applyNew
	setStatus(applyNew and "ON: what you apply with 'All NPCs' selected is also applied to NPCs that appear later (once they are yours)." or "Apply to new NPCs OFF.")
end, function() return applyNew end, "Apply to new NPCs: ON" } })[1].Parent
applyRow.Visible = false

local s1 = section("Control")
row(s1, { { "Control NPC", function()
	if controlling then stopControl("button") return end
	local p = one()
	if p then startControl(p) end
end, function() return controlling ~= nil end, "Controlling (stop)" } })
row(s1, {
	{ "Click to Move", function()
		moveMode = not moveMode
		setStatus(moveMode and "Click the ground: selected NPCs find a path there." or "Click to Move OFF.")
	end, function() return moveMode end, "Click to Move: ON" },
	{ "Follow me", function()
		toggleProp("following", function(d, s)
			if controlling == d then return end
			if s and (d.frozen or d.pocket or d.orbit) then return end
			cancelPath(d)
			d.following = s
			if s then standUp(d) end
		end, "Follow me", true)
	end, function() return any("following") end, "Following me" },
})

local s2 = section("Actions")
row(s2, {
	{ "Disable AI", function()
		toggleProp("aiOff", function(d, s) d.aiOff = s if s then d.following = false cancelPath(d) end end, "Disable AI", true)
	end, function() return any("aiOff") end, "AI disabled" },
	{ "Freeze", function()
		toggleProp("frozen", function(d, s) if controlling ~= d then setFrozen(d, s) end end, "Freeze", true)
	end, function() return any("frozen") end, "Unfreeze" },
})
row(s2, {
	{ "Pocket", function()
		toggleProp("pocket", function(d, s)
			if controlling == d then return end
			if s then setCarry(d, "pocket") elseif d.pocket then setCarry(d, nil) end
		end, "Pocket", true)
	end, function() return any("pocket") end, "In pocket (release)" },
	{ "Spectate", function()
		if spectating then stopSpectate() return end
		if controlling then bad("Stop controlling first.") return end
		local p = one()
		if not p then return end
		spectating = p
		workspace.CurrentCamera.CameraSubject = p.hum
		hudText()
	end, function() return spectating ~= nil end, "Watching (stop)" },
})
row(s2, { { "Kill", function()
	forOwned(need(), "Kill", function(d) -- both ways, to be sure: Health = 0 and the Dead state
		pcall(function() d.hum.Health = 0 end)
		pcall(function() d.hum:ChangeState(Enum.HumanoidStateType.Dead) end)
		log("Killed:", d.model.Name)
	end)
end } })

local s3 = section("Values")
field(s3, "WalkSpeed", function() local p = getPrimary() return p and p.speed end, function(n)
	forOwned(need(), "WalkSpeed", function(d) d.speed = n applyStats(d) end)
	if allSel then allVals.speed = n end
end, function()
	for _, d in ipairs(targets()) do d.speed = d.o.speed applyStats(d) end
	if allSel then allVals.speed = nil end
end)
field(s3, "JumpPower", function() local p = getPrimary() return p and p.jumpPower end, function(n)
	forOwned(need(), "JumpPower", function(d) d.jumpPower, d.jumpEdited = n, true applyStats(d) end)
	if allSel then allVals.jump = n end
end, function()
	for _, d in ipairs(targets()) do d.jumpPower, d.jumpEdited = d.o.jp, false applyStats(d) end
	if allSel then allVals.jump = nil end
end)

local s4 = section("Teleport")
row(s4, {
	{ "Go To", function()
		local p, mr = one(), myRoot()
		if not p then return end
		if controlling then bad("Stop controlling first.") return end
		if mr then mr.CFrame = p.root.CFrame * CFrame.new(0, 3, 6) end
	end },
	{ "Bring", function()
		local mr = myRoot()
		if not mr then return end
		local t = {}
		for _, d in ipairs(need()) do if not (d.pocket or d.orbit) then t[#t + 1] = d end end
		local i = 0
		forOwned(t, "Bring", function(d)
			i += 1
			local a = (i - 1) * 2 * math.pi / #t
			local off = #t == 1 and Vector3.new(0, 3, -5) or Vector3.new(math.sin(a) * 6, 3, -math.cos(a) * 6)
			local pos = (mr.CFrame * CFrame.new(off)).Position
			d.root.CFrame = CFrame.lookAt(pos, Vector3.new(mr.Position.X, pos.Y, mr.Position.Z))
			d.root.AssemblyLinearVelocity, d.jitUp = Vector3.zero, nil
			if d.frozen then d.frozenCF = d.root.CFrame pinFrozen(d) end -- frozen NPC stays frozen at the new spot
		end)
	end },
})
row(s4, { { "Void", function()
	-- below workspace.FallenPartsDestroyHeight the engine destroys parts -> the NPC dies / gets removed
	local y = workspace.FallenPartsDestroyHeight - 25
	local t = {}
	for _, d in ipairs(need()) do if controlling ~= d then t[#t + 1] = d end end
	forOwned(t, "Void", function(d)
		setCarry(d, nil)
		setFrozen(d, false)
		d.aiOff, d.following, d.spinning = false, false, false
		cancelPath(d)
		local p = d.root.Position
		d.root.CFrame, d.root.AssemblyLinearVelocity, d.jitUp = CFrame.new(p.X, y, p.Z), Vector3.zero, nil
		log("Sent to the void:", d.model.Name)
	end)
end } })

local s5 = section("Other")
claimBtn = row(s5, { { "Claim ownership", function()
	if claim then endClaim() setStatus("Claim cancelled.") return end
	if controlling then bad("Stop controlling first.") return end
	local p = one()
	if not p then return end
	if isMine(p) then setStatus(p.model.Name .. " is already yours.") return end
	startClaim(p)
end, function() return claim ~= nil end, "Claiming... (cancel)" } })[1]
row(s5, {
	{ "Sit / Stand", function()
		local t, sit = need(), false
		for _, d in ipairs(t) do if d.hum.Sit then sit = true end end
		forOwned(t, "Sit", function(d) d.hum.Sit = not sit end)
	end, function() for _, d in ipairs(targets()) do if d.hum.Sit then return true end end return false end, "Sitting (stand)" },
	{ "Jump", function()
		local t = {}
		for _, d in ipairs(need()) do if not (d.frozen or d.pocket or d.orbit) then t[#t + 1] = d end end
		forOwned(t, "Jump", function(d) standUp(d) d.hum.Jump = true end)
	end },
})
row(s5, { { "Spin", function()
	toggleProp("spinning", function(d, s) d.spinning = s end, "Spin", true)
end, function() return any("spinning") end, "Spinning (stop)" } })
setting(s5, "Spin speed (deg/s)", "spin", "deg/s")
row(s5, { { "Orbit (Omega Flowey)", function()
	toggleProp("orbit", function(d, s)
		if controlling == d then return end
		if s then setCarry(d, "orbit") elseif d.orbit then setCarry(d, nil) end
	end, "Orbit", true)
end, function() return any("orbit") end, "Orbiting (release)" } })
setting(s5, "Orbit radius (studs)", "orbitRadius", "studs")
setting(s5, "Orbit speed (deg/s)", "orbitSpeed", "deg/s")
row(s5, { { "Highlight", function()
	toggleProp("esp", function(d, s) d.esp = s end, "Highlight", false)
end, function() return any("esp") end, "Highlighted (off)" } })

-- Settings: always the last (bottom) section
local s6 = section("Settings")
settingsBox = s6
row(s6, {
	{ "Jitter: OFF", function()
		S.jitter = not S.jitter
		if not S.jitter then for _, d in pairs(npcs) do unJitter(d) end end
		setStatus(S.jitter and "Jitter ON for controlled / AI-disabled / frozen NPCs." or "Jitter OFF.")
	end, function() return S.jitter end, "Jitter: ON" },
	{ function() return "Freeze: " .. S.freezeMode:upper() end, function()
		S.freezeMode = NEXT[S.freezeMode]
		setStatus(({
			soft = "SOFT freeze: speed 0 + anti-AI + jitter. Can be pushed.",
			hard = "HARD freeze: + AlignPosition / AlignOrientation. Cannot be pushed.",
			full = "FULL freeze: hard + PlatformStand. AI commands do nothing.",
		})[S.freezeMode] .. " Applies to the next freeze.")
	end, function() return S.freezeMode ~= "soft" end },
})
row(s6, {
	{ "Keep my char near: OFF", function()
		keepClose = not keepClose
		setStatus(keepClose and "While controlling, my body hides under the NPC (keeps ownership)." or "My body stays where I left it - far NPCs may stop obeying.")
	end, function() return keepClose end, "Keep my char near: ON" },
	{ "Anti-AI spam: OFF", function()
		S.aiSpam = not S.aiSpam
		setStatus(S.aiSpam and "Anti-AI spam ON: MoveTo(own position) holds suppressed NPCs." or "Anti-AI spam OFF.")
	end, function() return S.aiSpam end, "Anti-AI spam: ON" },
})
row(s6, { { "Try on non-owned: OFF", function()
	S.tryAll = not S.tryAll
	setStatus(S.tryAll and "Try on non-owned ON: actions also run on red NPCs, then get rolled back if they did not work." or "Try on non-owned OFF: red NPCs are skipped.")
end, function() return S.tryAll end, "Try on non-owned: ON" } })
row(s6, { { "Auto-ban anchored: OFF", function()
	S.autoBan = not S.autoBan
	if S.autoBan then
		local n = 0
		for _, d in pairs(npcs) do if d.anchored then banNPC(d) n += 1 end end
		setStatus("Auto-ban anchored ON" .. (n > 0 and (": banned " .. n .. " NPC(s) now.") or "."))
	else
		setStatus("Auto-ban anchored OFF.")
	end
end, function() return S.autoBan end, "Auto-ban anchored: ON" } })
setting(s6, "Anti-AI rate (per sec)", "aiRate", "/s")
setting(s6, "Jitter rate (per sec)", "jitRate", "/s")
setting(s6, "Jitter size (studs)", "jitAmp", "studs", function() for _, d in pairs(npcs) do unJitter(d) end end)
setting(s6, "Hide depth (studs)", "hideDepth", "studs")
setting(s6, "Pocket depth (studs)", "pocketDepth", "studs")
setting(s6, "Claim height (studs)", "claimHeight", "studs")
setting(s6, "Try check after (sec)", "tryWait", "s")
setting(s6, "Auto-scan every (sec)", "interval", "s")
row(s6, {
	{ "Ban selected", function() for _, d in ipairs(need()) do banNPC(d) end end },
	{ "Unban all", function()
		local n = 0
		for m in pairs(banned) do banned[m] = nil n += 1 end
		rebuildBans()
		pcall(scan, false)
		setStatus("Unbanned " .. n .. " NPC(s).")
	end },
})
local banTitle = T("TextLabel", s6, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = nxt(), Text = "Banned NPCs: 0",
	TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold })
local banBox = T("Frame", s6, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nxt() })
lay(banBox, { Padding = UDim.new(0, 3) })
rebuildBans = function()
	for _, ch in ipairs(banBox:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	local ms = {}
	for m in pairs(banned) do ms[#ms + 1] = m end
	table.sort(ms, function(a, b) return a.Name < b.Name end)
	banTitle.Text = "Banned NPCs: " .. #ms
	for i, m in ipairs(ms) do
		local r = T("Frame", banBox, { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = i })
		T("TextLabel", r, { Size = UDim2.new(1, -70, 1, 0), Text = "  " .. m.Name, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 0, BackgroundColor3 = C.pn })
		T("TextButton", r, { Size = UDim2.new(0, 64, 1, 0), Position = UDim2.new(1, -64, 0, 0), Text = "Unban", Font = Enum.Font.GothamBold })
			.MouseButton1Click:Connect(function()
				banned[m] = nil
				rebuildBans()
				pcall(scan, false) -- back in the list right away
				setStatus("Unbanned " .. m.Name .. ".")
				refresh()
			end)
	end
end
rebuildBans()
T("TextLabel", s6, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = nxt(), RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(170, 170, 180),
	Text = "Dot next to an NPC name: <font color='#3cdc5a'>green</font> = you own it (commands work), "
		.. "<font color='#e63c3c'>red</font> = the server or another player owns it, "
		.. "<font color='#ffa028'>orange</font> = its body is anchored to the map or it is dead (cannot move), gray = unknown." })
T("TextLabel", s6, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nxt(), Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(150, 150, 165), Text = "Idea: Vensik  |  Made by Claude AI" })

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
	if banned[m] then bad("Click to add:", m.Name, "is banned - unban it in Settings.") setStatus(m.Name .. " is banned - unban it in Settings.") return true end
	local d = npcs[m]
	if not d then
		local root = findRoot(m)
		if not root then bad("Click to add:", m:GetFullName(), "has no root part.") return true end
		d = addNPC(m, m:FindFirstChildOfClass("Humanoid"), root)
	end
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	if not ctrl then allSel = false table.clear(selected) end
	selected[d], primary, anchorSel = true, d, d
	setStatus("Added / selected: " .. m.Name)
	return true
end
local function doMove()
	local t = {}
	for _, d in ipairs(targets()) do if not (d.frozen or d.pocket or d.orbit or controlling == d) then t[#t + 1] = d end end
	if #t == 0 then bad("Click to Move: no movable NPC selected (frozen / pocket / orbit / controlled ones are skipped).") return end
	local ig = { myChar() }
	for _, d in ipairs(t) do ig[#ig + 1] = d.model end
	local res = ray(ig)
	if not res then bad("Click missed (sky?). Click on the ground.") return end
	local i = 0
	forOwned(t, "Click to Move", function(d)
		i += 1
		local a, p = (i - 1) * 2 * math.pi / #t, res.Position
		if #t > 1 then p += Vector3.new(math.cos(a) * 3, 0, math.sin(a) * 3) end
		d.following = false
		walkPath(d, p)
	end)
end

---------------------------------------------------------------- input
hud.MouseButton1Click:Connect(function()
	if controlling then stopControl("HUD button") elseif claim then endClaim() else stopSpectate() end
	refresh()
end)
track(UIS.InputBegan:Connect(function(input, gp)
	if gp or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
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
end))
track(UIS.JumpRequest:Connect(function() -- direct mode only: in Possess the default controls already jump the NPC
	local d = controlling
	if d and not possessed then standUp(d) d.hum.Jump = true end
end))
track(player.CharacterAdded:Connect(function(c)
	if controlling and c ~= controlling.model and c ~= homeChar then
		homeChar = nil
		stopControl("your character respawned", true)
		refresh()
	end
	if claim then claim = nil hudText() end
end))

---------------------------------------------------------------- physics steps (right before physics)
-- Anti-AI spam: a suppressed NPC that stands still keeps getting "walk to where you are".
local function antiAI(dt)
	if not S.aiSpam then return end
	for _, s in pairs(npcs) do
		if s.root.Parent and suppressed(s) and not (s.pocket or s.orbit) and not s.target and not s.following and not (controlling == s and s.moving) then
			s.aiAcc += dt
			if s.aiAcc >= 1 / S.aiRate then s.aiAcc = 0 s.hum:MoveTo(s.root.Position) end
		end
	end
end
-- Jitter: alternate +size / -size on Y, the NPC ends where it was. Keeps it from falling asleep.
local function jitter(dt)
	for _, d in pairs(npcs) do
		local r = d.root
		if r.Parent then
			if S.jitter and suppressed(d) and not (d.pocket or d.orbit) and not d.anchored and d.hum.Health > 0 then
				d.jitAcc += dt
				if d.jitAcc >= 1 / S.jitRate then
					d.jitAcc = 0
					if d.jitUp then r.CFrame -= Vector3.new(0, d.jitUp, 0) d.jitUp = nil
					else r.CFrame += Vector3.new(0, S.jitAmp, 0) d.jitUp = S.jitAmp end
				end
			elseif d.jitUp then
				unJitter(d)
			end
		end
	end
end
-- Keep my char near: my real body sits under the controlled NPC, anchored, no collisions.
local function bodyStep()
	local d, mr = controlling, myRoot()
	if d and mr and d.root.Parent then
		mr.Anchored = keepClose
		if keepClose then
			mr.CFrame = d.root.CFrame * CFrame.new(0, -S.hideDepth, 0)
			bodyMoved = true
			collideSaved = collideSaved or {}
			noclip(myChar(), collideSaved)
			return
		elseif bodyMoved and homeCF then -- Keep near turned off while controlling: put my body back
			mr.CFrame, mr.AssemblyLinearVelocity, bodyMoved = homeCF, Vector3.zero, false
		end
	end
	if collideSaved then unclip(collideSaved) collideSaved = nil end
end
-- Pocket (under me, a small ring if there are several) and Orbit (circle around me): no collisions, no velocity.
local function carryStep()
	local mr = myRoot()
	if not mr then return end
	local pk, ob = {}, {}
	for _, d in pairs(npcs) do
		if d.root.Parent then
			if d.pocket then pk[#pk + 1] = d elseif d.orbit then ob[#ob + 1] = d end
		end
	end
	table.sort(pk, byId)
	table.sort(ob, byId)
	local function hold(d, cf)
		noclip(d.model, d.coll)
		d.root.CFrame = cf
		d.root.AssemblyLinearVelocity, d.root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	end
	for i, d in ipairs(pk) do
		local a = (i - 1) * 2 * math.pi / #pk
		local off = #pk == 1 and Vector3.zero or Vector3.new(math.cos(a) * 2.5, 0, math.sin(a) * 2.5)
		hold(d, CFrame.new(mr.Position + Vector3.new(0, -S.pocketDepth, 0) + off))
	end
	local base = os.clock() * math.rad(S.orbitSpeed)
	for i, d in ipairs(ob) do
		local a = base + (i - 1) * 2 * math.pi / #ob
		local pos = mr.Position + Vector3.new(math.cos(a) * S.orbitRadius, 0, math.sin(a) * S.orbitRadius)
		hold(d, CFrame.lookAt(pos, Vector3.new(mr.Position.X, pos.Y, mr.Position.Z)))
	end
end
-- Claim: hover above the NPC so I am the closest player
local function claimStep()
	if not claim then return end
	local d, r = claim.d, myRoot()
	if not r or npcs[d.model] ~= d or not d.root.Parent then endClaim() return end
	r.Anchored = true
	r.CFrame = CFrame.new(d.root.Position + Vector3.new(0, S.claimHeight, 0)) * r.CFrame.Rotation
end
local warned = {}
local function safe(name, f, ...)
	local ok, e = pcall(f, ...)
	if not ok and not warned[name] then warned[name] = true bad(name .. " error:", e) end
end
local function physicsStep(dt)
	safe("Jitter", jitter, dt)
	safe("Keep-near", bodyStep)
	safe("Carry", carryStep)
	safe("Claim", claimStep)
end
local okPS, preSim = pcall(function() return RS.PreSimulation end)
if okPS and preSim then track(preSim:Connect(physicsStep)) else track(RS.Stepped:Connect(function(_, dt) physicsStep(dt) end)) end

---------------------------------------------------------------- per-frame: ownership, spin, anti-AI, driving the controlled NPC
track(RS.RenderStepped:Connect(function(dt)
	safe("Ownership", ownStep)
	for _, s in pairs(npcs) do
		if s.root.Parent and s.spinning and not s.frozen and not (s.pocket or s.orbit) then
			s.root.CFrame *= CFrame.Angles(0, math.rad(S.spin) * dt, 0)
		end
	end
	safe("Anti-AI", antiAI, dt)
	local d = controlling
	if not d then return end
	if not d.hum.Parent or d.hum.Health <= 0 then
		bad(d.model.Name, "died or disappeared - stopped controlling.")
		stopControl("NPC unavailable") refresh()
		return
	end
	local v = moveVec()
	if v.Magnitude > 0.05 then
		if not d.moving then d.moving, d.moveTime, d.warned = true, 0, false end
		standUp(d)
		d.hum:Move(v, true) -- every frame, also in Possess: beats the server AI while walking
		d.moveTime += dt
		if d.moveTime > 1.5 and not d.warned and d.root.AssemblyLinearVelocity.Magnitude < 0.5 then
			d.warned = true
			bad("The NPC is not moving. Possible reasons: lost network ownership, Anchored parts, a server script controls it, or a wall.")
		end
	elseif d.moving then
		d.moving = false
		d.hum:Move(Vector3.zero, true)
	end
end))

---------------------------------------------------------------- background: list, followers, watchdog, claim, apply to new
local function tick()
	local mr = myRoot()
	local followers = {}
	for m, d in pairs(npcs) do
		if not m:IsDescendantOf(workspace) then
			removeNPC(d, false)
		elseif d.root.Parent then
			d.dist = mr and math.floor((d.root.Position - mr.Position).Magnitude) or 0
			d.anchored = grounded(d.root)
			if d.anchored and S.autoBan and controlling ~= d then banNPC(d) end
			if d.following and controlling ~= d then followers[#followers + 1] = d end
			-- watchdog: a frozen NPC that lost ownership is put back to its spot as soon as ownership returns
			if d.frozen then
				if d.own == "other" then
					if not d.lost then d.lost = true bad(d.model.Name, ": lost ownership while frozen.") end
				elseif d.own == "mine" and d.lost then
					d.lost = false
					d.root.CFrame, d.root.AssemblyLinearVelocity, d.jitUp = d.frozenCF, Vector3.zero, nil
					pinFrozen(d)
					log("Ownership back:", d.model.Name, "- returned to its frozen spot.")
				end
			end
			-- apply to new NPCs: what was applied to "All NPCs" (needs ownership, except Highlight)
			if applyNew and not d.newDone then
				if allState.esp and not d.esp then d.esp = true end
				if isMine(d) and not d.anchored and controlling ~= d then
					for prop, val in pairs(allState) do
						if val and not d[prop] and allFns[prop] then pcall(allFns[prop], d, true) end
					end
					if allVals.speed then d.speed = allVals.speed end
					if allVals.jump then d.jumpPower, d.jumpEdited = allVals.jump, true end
					pcall(applyStats, d)
					d.newDone = true
				end
			end
		end
	end
	if mr then -- followers stand slightly to the side and behind me
		table.sort(followers, byId)
		for i, d in ipairs(followers) do
			local slot = i - 1
			local side, ring = (slot % 2 == 0) and 1 or -1, math.floor(slot / 2)
			local goal = (mr.CFrame * CFrame.new(side * (3.5 + ring * 2.5), 0, 3 + ring * 2)).Position
			local f = Vector3.new(goal.X - d.root.Position.X, 0, goal.Z - d.root.Position.Z)
			d.hum:MoveTo(f.Magnitude > 2.2 and goal or d.root.Position)
		end
	end
	if claim and not claim.told and isMine(claim.d) then
		claim.told = true
		setStatus(claim.d.model.Name .. " is yours now! Pick an action - you will be sent back.")
		log("Ownership claimed:", claim.d.model.Name)
	end
	-- I am invisible (to myself) only while my body hides under the controlled NPC
	local wantHidden = controlling ~= nil and keepClose
	if wantHidden then setAlpha(1) elseif hiddenNow then setAlpha(0) end
	hiddenNow = wantHidden
	if spectating and npcs[spectating.model] ~= spectating then stopSpectate() end
	local gone = false
	for m in pairs(banned) do if not m:IsDescendantOf(workspace) then banned[m] = nil gone = true end end
	if gone then rebuildBans() end
	refresh()
end

closeAll = function()
	if not alive then return end
	alive = false
	pcall(endClaim)
	pcall(stopControl, "closing")
	pcall(stopSpectate)
	for _, d in pairs(npcs) do pcall(removeNPC, d, false) end -- unfreeze, release pocket / orbit, reset speed, remove highlights
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	if collideSaved then unclip(collideSaved) collideSaved = nil end
	pcall(setAlpha, 0)
	local r = myRoot()
	if r then r.Anchored = false end
	gui:Destroy()
	log("Closed - everything was restored.")
end

task.spawn(function()
	while alive do
		task.wait(0.1)
		if autoScan and os.clock() - lastScan >= S.interval then
			lastScan = os.clock()
			safe("Scan", scan, false)
		end
	end
end)
task.spawn(function()
	while alive do
		local ok, e = pcall(tick)
		if not ok then bad("Update error:", e) end
		task.wait(0.25)
	end
end)

setStatus("Click = select / deselect, Ctrl / Shift = multi-select, 'All NPCs' = everyone.")
log("Ready. Use the 'NPC Menu' button to open / close the menu (you can drag it).")
