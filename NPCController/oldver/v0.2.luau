local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local npcs = {}        -- [model] = {hum, root, frozen, row, ctrlBtn, freezeBtn, info}
local selected = nil   -- currently controlled NPC model
local following = false

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "NPCController"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 110, 0, 32)
toggleBtn.Position = UDim2.new(0, 10, 0.5, -16)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
toggleBtn.TextColor3 = Color3.new(1, 1, 1)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.Text = "NPCs (P)"
toggleBtn.Parent = gui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 290, 0, 340)
main.Position = UDim2.new(0, 10, 0.5, 24)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Text = "NPC Controller"
title.Parent = main

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -16, 1, -120)
list.Position = UDim2.new(0, 8, 0, 34)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 40)
status.Position = UDim2.new(0, 8, 1, -82)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.Text = "Press Control on an NPC, then click the ground to move it."
status.Parent = main

local function makeButton(text, size, pos, color, parent)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Text = text
	b.BorderSizePixel = 0
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local followBtn = makeButton("Follow me (F)", UDim2.new(0.5, -12, 0, 30), UDim2.new(0, 8, 1, -38), Color3.fromRGB(50, 90, 160), main)
local stopBtn = makeButton("Stop (G)", UDim2.new(0.5, -12, 0, 30), UDim2.new(0.5, 4, 1, -38), Color3.fromRGB(160, 60, 60), main)

toggleBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)

---------------------------------------------------------------- NPC logic
local function isNPC(model)
	return model:IsA("Model")
		and model:FindFirstChildOfClass("Humanoid") ~= nil
		and model:FindFirstChild("HumanoidRootPart") ~= nil
		and Players:GetPlayerFromCharacter(model) == nil
end

local function setFrozen(model, state)
	local d = npcs[model]
	if not d then return end
	d.frozen = state
	if state then
		d.origSpeed = d.hum.WalkSpeed
		d.origJump = d.hum.JumpPower
		d.hum.WalkSpeed = 0
		d.hum.JumpPower = 0
		d.hum.JumpHeight = 0
		d.hum:MoveTo(d.root.Position)
		if selected == model then following = false end
	else
		d.hum.WalkSpeed = d.origSpeed or 16
		d.hum.JumpPower = d.origJump or 50
		d.hum.JumpHeight = 7.2
	end
end

local function refreshVisuals()
	for model, d in pairs(npcs) do
		d.ctrlBtn.BackgroundColor3 = (selected == model) and Color3.fromRGB(40, 150, 70) or Color3.fromRGB(60, 60, 60)
		d.ctrlBtn.Text = (selected == model) and "Controlling" or "Control"
		d.freezeBtn.BackgroundColor3 = d.frozen and Color3.fromRGB(70, 140, 200) or Color3.fromRGB(60, 60, 60)
		d.freezeBtn.Text = d.frozen and "Unfreeze" or "Freeze"
	end
end

local function addNPC(model)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 62)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	row.BorderSizePixel = 0
	row.Parent = list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -10, 0, 22)
	info.Position = UDim2.new(0, 8, 0, 2)
	info.BackgroundTransparency = 1
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextColor3 = Color3.new(1, 1, 1)
	info.Font = Enum.Font.Gotham
	info.TextSize = 13
	info.Parent = row

	local ctrl = makeButton("Control", UDim2.new(0.5, -10, 0, 28), UDim2.new(0, 6, 0, 28), Color3.fromRGB(60, 60, 60), row)
	local frz = makeButton("Freeze", UDim2.new(0.5, -10, 0, 28), UDim2.new(0.5, 4, 0, 28), Color3.fromRGB(60, 60, 60), row)

	npcs[model] = {
		hum = model:FindFirstChildOfClass("Humanoid"),
		root = model.HumanoidRootPart,
		frozen = false,
		row = row, info = info, ctrlBtn = ctrl, freezeBtn = frz,
	}

	ctrl.MouseButton1Click:Connect(function()
		if selected == model then
			selected = nil
			following = false
		else
			selected = model
			following = false
			if npcs[model].frozen then setFrozen(model, false) end
		end
		refreshVisuals()
	end)

	frz.MouseButton1Click:Connect(function()
		setFrozen(model, not npcs[model].frozen)
		refreshVisuals()
	end)
end

local function removeNPC(model)
	local d = npcs[model]
	if d then
		d.row:Destroy()
		npcs[model] = nil
		if selected == model then selected = nil following = false end
	end
end

-- Scan for NPCs every 2 seconds
local function scan()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local model = inst.Parent
			if model and not npcs[model] and isNPC(model) then
				addNPC(model)
			end
		end
	end
	for model in pairs(npcs) do
		if not model:IsDescendantOf(workspace) then
			removeNPC(model)
		end
	end
	refreshVisuals()
end

task.spawn(function()
	while true do
		scan()
		task.wait(2)
	end
end)

-- Update distance text + range warning
task.spawn(function()
	while true do
		local char = player.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		for model, d in pairs(npcs) do
			local dist = myRoot and math.floor((d.root.Position - myRoot.Position).Magnitude) or 0
			local far = dist > 100
			d.info.Text = model.Name .. "  (" .. dist .. " studs)" .. (far and "  ⚠ too far" or "")
			d.info.TextColor3 = far and Color3.fromRGB(255, 170, 80) or Color3.new(1, 1, 1)
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------- Controls
local function getSelected()
	local d = selected and npcs[selected]
	if d and not d.frozen then return d end
end

local function startFollow()
	if getSelected() then following = true end
end

local function stopNPC()
	following = false
	local d = getSelected()
	if d then d.hum:MoveTo(d.root.Position) end
end

followBtn.MouseButton1Click:Connect(startFollow)
stopBtn.MouseButton1Click:Connect(stopNPC)

UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.P then
		main.Visible = not main.Visible
	elseif input.KeyCode == Enum.KeyCode.F then
		startFollow()
	elseif input.KeyCode == Enum.KeyCode.G then
		stopNPC()
	elseif input.KeyCode == Enum.KeyCode.H then
		local d = getSelected()
		if d then d.hum.Jump = true end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local d = getSelected()
		if d and mouse.Hit then
			following = false
			d.hum:MoveTo(mouse.Hit.Position)
		end
	end
end)

local timer = 0
RunService.Heartbeat:Connect(function(dt)
	if not following then return end
	timer += dt
	if timer < 0.25 then return end
	timer = 0

	local d = getSelected()
	local char = player.Character
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	if d and myRoot then
		d.hum:MoveTo(myRoot.Position)
	end
end)
