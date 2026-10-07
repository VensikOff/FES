local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Your NPC: a Model named "NPC" in Workspace with a Humanoid
local npc = workspace:WaitForChild("NPC")
local humanoid = npc:WaitForChild("Humanoid")
local npcRoot = npc:WaitForChild("HumanoidRootPart")

local following = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Click = walk to that spot
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if mouse.Hit then
			following = false
			humanoid:MoveTo(mouse.Hit.Position)
		end

	-- F = follow me
	elseif input.KeyCode == Enum.KeyCode.F then
		following = true

	-- G = stop
	elseif input.KeyCode == Enum.KeyCode.G then
		following = false
		humanoid:MoveTo(npcRoot.Position)

	-- Space = jump (uses H so it doesn't clash with your own jump)
	elseif input.KeyCode == Enum.KeyCode.H then
		humanoid.Jump = true
	end
end)

-- Keeps updating the follow target
local timer = 0
RunService.Heartbeat:Connect(function(dt)
	if not following then return end

	timer += dt
	if timer < 0.25 then return end
	timer = 0

	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	if myRoot then
		humanoid:MoveTo(myRoot.Position)
	end
end)
