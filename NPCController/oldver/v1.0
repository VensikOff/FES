local TAG = "[NPC] "
local function log(...) print(TAG, ...) end
local function bad(...) warn(TAG, ...) end

log("Скрипт запущен")

local RunService = game:GetService("RunService")
if not RunService:IsClient() then
	bad("ОШИБКА: скрипт работает на сервере! Нужен LocalScript, а не Script. Положите его в StarterPlayer > StarterPlayerScripts")
	return
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	bad("ОШИБКА: LocalPlayer не найден")
	return
end

local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	bad("ОШИБКА: PlayerGui не появился за 10 секунд")
	return
end
log("PlayerGui найден")

local mouse = player:GetMouse()

local npcs = {}
local selected = nil
local following = false

---------------------------------------------------------------- UI
local ok, err = pcall(function()
	local old = playerGui:FindFirstChild("NPCController")
	if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "NPCController"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
gui.Parent = playerGui
log("ScreenGui создан, родитель:", tostring(gui.Parent))

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
status.Text = "Ищу NPC..."
status.Parent = main

local function setStatus(text)
	status.Text = text
end

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

toggleBtn.MouseButton1Click:Connect(function()
	main.Visible = not main.Visible
	log("Панель", main.Visible and "открыта" or "скрыта")
end)

log("UI построен")

---------------------------------------------------------------- NPC logic
local function findRoot(model)
	return model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("UpperTorso")
end

local function setFrozen(model, state)
	local d = npcs[model]
	if not d then
		bad("setFrozen: NPC", model.Name, "не найден в списке")
		return
	end
	d.frozen = state
	if state then
		d.origSpeed = d.hum.WalkSpeed
		d.origJump = d.hum.JumpPower
		d.hum.WalkSpeed = 0
		d.hum.JumpPower = 0
		d.hum.JumpHeight = 0
		d.hum:MoveTo(d.root.Position)
		if selected == model then following = false end
		log("Заморожен:", model.Name)
	else
		d.hum.WalkSpeed = d.origSpeed or 16
		d.hum.JumpPower = d.origJump or 50
		d.hum.JumpHeight = 7.2
		log("Разморожен:", model.Name)
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

local function addNPC(model, hum, root)
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
	info.Text = model.Name
	info.Parent = row

	local ctrl = makeButton("Control", UDim2.new(0.5, -10, 0, 28), UDim2.new(0, 6, 0, 28), Color3.fromRGB(60, 60, 60), row)
	local frz = makeButton("Freeze", UDim2.new(0.5, -10, 0, 28), UDim2.new(0.5, 4, 0, 28), Color3.fromRGB(60, 60, 60), row)

	npcs[model] = {
		hum = hum, root = root, frozen = false,
		row = row, info = info, ctrlBtn = ctrl, freezeBtn = frz,
	}

	-- предупреждения о проблемах конкретного NPC
	if root.Anchored then
		bad("NPC", model.Name, ": корневая часть Anchored — он не сможет двигаться. Сними Anchored.")
	end
	if hum.Health <= 0 then
		bad("NPC", model.Name, ": Health = 0, он мёртв.")
	end

	ctrl.MouseButton1Click:Connect(function()
		if selected == model then
			selected = nil
			following = false
			log("Управление снято с", model.Name)
		else
			selected = model
			following = false
			if npcs[model].frozen then setFrozen(model, false) end
			log("Управляешь NPC:", model.Name)
			setStatus("Управляешь: " .. model.Name .. ". Кликни по земле.")
		end
		refreshVisuals()
	end)

	frz.MouseButton1Click:Connect(function()
		setFrozen(model, not npcs[model].frozen)
		refreshVisuals()
	end)

	log("Добавлен NPC:", model:GetFullName())
end

local function removeNPC(model)
	local d = npcs[model]
	if d then
		d.row:Destroy()
		npcs[model] = nil
		if selected == model then selected = nil following = false end
		log("NPC удалён из списка:", model.Name)
	end
end

local lastCount = -1
local function scan()
	local foundHumanoids, skipped = 0, 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local model = inst.Parent
			if model and model:IsA("Model") then
				foundHumanoids += 1
				if not npcs[model] then
					if Players:GetPlayerFromCharacter(model) then
						-- это игрок, пропускаем молча
					else
						local root = findRoot(model)
						if root then
							addNPC(model, inst, root)
						else
							skipped += 1
							bad("Пропущен", model:GetFullName(), ": нет HumanoidRootPart / PrimaryPart / Torso")
						end
					end
				end
			end
		end
	end

	for model in pairs(npcs) do
		if not model:IsDescendantOf(workspace) then
			removeNPC(model)
		end
	end

	local count = 0
	for _ in pairs(npcs) do count += 1 end

	if count ~= lastCount then
		lastCount = count
		log("Сканирование: Humanoid в workspace =", foundHumanoids, "| NPC в списке =", count, "| пропущено =", skipped)
		if count == 0 then
			bad("NPC не найдены! Проверь: 1) в workspace есть Model с Humanoid; 2) это не персонаж игрока; 3) у модели есть HumanoidRootPart.")
			setStatus("NPC не найдены. Смотри консоль (F9).")
		else
			setStatus("Нажми Control у NPC, затем кликни по земле.")
		end
	end
	refreshVisuals()
end

task.spawn(function()
	while true do
		local okScan, errScan = pcall(scan)
		if not okScan then
			bad("Ошибка при сканировании:", errScan)
		end
		task.wait(2)
	end
end)

task.spawn(function()
	while true do
		local char = player.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		for model, d in pairs(npcs) do
			if d.root and d.root.Parent then
				local dist = myRoot and math.floor((d.root.Position - myRoot.Position).Magnitude) or 0
				local far = dist > 100
				d.info.Text = model.Name .. "  (" .. dist .. " studs)" .. (far and "  ⚠ далеко" or "")
				d.info.TextColor3 = far and Color3.fromRGB(255, 170, 80) or Color3.new(1, 1, 1)
			end
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------- Controls
local function getSelected(reason)
	if not selected then
		bad("Нет выбранного NPC — сначала нажми Control у нужного NPC." .. (reason and (" (действие: " .. reason .. ")") or ""))
		return nil
	end
	local d = npcs[selected]
	if not d then
		bad("Выбранный NPC пропал из списка.")
		return nil
	end
	if d.frozen then
		bad("NPC", selected.Name, "заморожен — разморозь его кнопкой Unfreeze.")
		return nil
	end
	return d
end

local function startFollow()
	if getSelected("follow") then
		following = true
		log("Следование включено")
	end
end

local function stopNPC()
	following = false
	local d = getSelected("stop")
	if d then
		d.hum:MoveTo(d.root.Position)
		log("NPC остановлен")
	end
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
		local d = getSelected("jump")
		if d then
			d.hum.Jump = true
			log("Прыжок")
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not selected then return end -- обычные клики без выбора не спамят
		local d = getSelected("move")
		if d then
			if mouse.Hit then
				following = false
				d.hum:MoveTo(mouse.Hit.Position)
				log("MoveTo:", tostring(mouse.Hit.Position))
			else
				bad("mouse.Hit = nil — кликни по поверхности, а не по небу.")
			end
		end
	end
end)

local timer = 0
local warnedRange = false
RunService.Heartbeat:Connect(function(dt)
	if not following then return end
	timer += dt
	if timer < 0.25 then return end
	timer = 0

	local d = getSelected("follow-update")
	local char = player.Character
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not d then following = false return end
	if not myRoot then
		bad("У твоего персонажа нет HumanoidRootPart")
		return
	end
	local dist = (d.root.Position - myRoot.Position).Magnitude
	if dist > 100 and not warnedRange then
		warnedRange = true
		bad("NPC дальше 100 studs — возможно, у тебя нет network ownership, и он не будет слушаться.")
	elseif dist <= 100 then
		warnedRange = false
	end
	d.hum:MoveTo(myRoot.Position)
end)

log("Готово. Нажми P, чтобы открыть/закрыть панель.")
