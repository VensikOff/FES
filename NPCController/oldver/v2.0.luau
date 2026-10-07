-- NPC Controller v2 — ОДИН LocalScript
-- Положить в: StarterPlayer > StarterPlayerScripts (тип: LocalScript)

local TAG = "[NPC] "
local function log(...) print(TAG, ...) end
local function bad(...) warn(TAG, ...) end

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

if not RunService:IsClient() then
	bad("ОШИБКА: это должен быть LocalScript в StarterPlayerScripts, а не обычный Script.")
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
	bad("ОШИБКА: PlayerGui не появился за 10 секунд")
	return
end
log("Скрипт v2 запущен")

---------------------------------------------------------------- Управление игрока (WASD / геймпад / мобильный)
local controls = nil
task.spawn(function()
	local ok, res = pcall(function()
		local ps = player:WaitForChild("PlayerScripts", 10)
		local pm = ps and ps:WaitForChild("PlayerModule", 10)
		return pm and require(pm):GetControls()
	end)
	if ok and res then
		controls = res
		log("Стандартное управление найдено (WASD, геймпад, мобильный джойстик)")
	else
		bad("PlayerModule недоступен, использую запасное управление на WASD:", res)
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

---------------------------------------------------------------- Состояние
local npcs = {}            -- [model] = d
local sel = nil            -- выбранный бот (таблица d)
local controlling = nil    -- бот, которым играем
local clickToMove = false
local espAll = false
local keepClose = true     -- держать моего персонажа рядом с NPC (чтобы не пропал network ownership)
local sprinting = false
local savedStats = nil
local warnedNoRoot = setmetatable({}, { __mode = "k" })

local function myChar() return player.Character end
local function myRoot() local c = player.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function myHum() local c = player.Character return c and c:FindFirstChildOfClass("Humanoid") end

---------------------------------------------------------------- UI
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
	Size = UDim2.new(0, 640, 0, 420), Position = UDim2.new(0, 20, 0.5, -210),
	BackgroundColor3 = Color3.fromRGB(24, 24, 28), BorderSizePixel = 0,
}, gui)
corner(main, 10)

-- заголовок (за него можно таскать окно)
local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(34, 34, 40),
	BorderSizePixel = 0, Active = true,
}, main)
corner(titleBar, 10)
new("TextLabel", {
	Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 12, 0, 0), BackgroundTransparency = 1,
	TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "NPC Controller v2   ·   P: меню   ·   X: выйти из контроля",
}, titleBar)

-- левая панель: боты
local left = new("Frame", {
	Size = UDim2.new(0, 210, 1, -48), Position = UDim2.new(0, 8, 0, 40),
	BackgroundColor3 = Color3.fromRGB(32, 32, 37), BorderSizePixel = 0,
}, main)
corner(left)
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(180, 180, 190),
	Font = Enum.Font.GothamBold, TextSize = 12, Text = "БОТЫ",
}, left)
local list = new("ScrollingFrame", {
	Size = UDim2.new(1, -8, 1, -32), Position = UDim2.new(0, 4, 0, 28), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, left)
new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.Name }, list)

-- правая панель: фичи
local right = new("Frame", {
	Size = UDim2.new(1, -234, 1, -48), Position = UDim2.new(0, 226, 0, 40),
	BackgroundColor3 = Color3.fromRGB(32, 32, 37), BorderSizePixel = 0,
}, main)
corner(right)
local info = new("TextLabel", {
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0, 4), BackgroundTransparency = 1,
	TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 13, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Выбери бота слева",
}, right)
local grid = new("ScrollingFrame", {
	Size = UDim2.new(1, -12, 1, -82), Position = UDim2.new(0, 6, 0, 46), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, right)
new("UIGridLayout", {
	CellSize = UDim2.new(0.5, -4, 0, 34), CellPadding = UDim2.new(0, 6, 0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)
local status = new("TextLabel", {
	Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 1, -32), BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(190, 190, 200), Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "Ищу NPC...",
}, right)
local function setStatus(t) status.Text = t end

-- плашка сверху экрана, когда играешь за NPC
local hud = new("TextLabel", {
	Size = UDim2.new(0, 620, 0, 30), Position = UDim2.new(0.5, -310, 0, 8),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24), BackgroundTransparency = 0.25,
	TextColor3 = Color3.fromRGB(120, 255, 140), Font = Enum.Font.GothamBold, TextSize = 13,
	Text = "", Visible = false, BorderSizePixel = 0,
}, gui)
corner(hud, 8)

-- перетаскивание окна
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
log("UI построен")

---------------------------------------------------------------- Логика NPC
local refreshUI -- объявлено заранее, определим ниже

local function findRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
end

local function applyStats(d)
	if d.frozen then
		d.hum.WalkSpeed = 0
		d.hum.JumpPower = 0
		d.hum.JumpHeight = 0
	else
		local mult = (controlling == d and sprinting) and 1.7 or 1
		d.hum.WalkSpeed = d.speed * mult
		d.hum.JumpPower = d.jumpPower
		d.hum.JumpHeight = d.jumpHeight
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
	log(state and "Заморожен:" or "Разморожен:", d.model.Name)
end

local function setMyTransparency(v)
	local c = myChar()
	if not c then return end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") then p.LocalTransparencyModifier = v end
	end
end

local function stopControl(reason)
	local d = controlling
	if not d then return end
	controlling = nil
	pcall(function() d.hum:Move(Vector3.zero, true) end)
	d.moving = false
	local r = myRoot()
	if r then r.Anchored = false end
	local h = myHum()
	if h then
		if savedStats then
			h.WalkSpeed, h.JumpPower, h.JumpHeight = savedStats.ws, savedStats.jp, savedStats.jh
		end
		workspace.CurrentCamera.CameraSubject = h
	end
	savedStats = nil
	setMyTransparency(0)
	pcall(applyStats, d)
	hud.Visible = false
	main.Visible = true
	log("Контроль снят:", d.model.Name, reason or "")
end

local function startControl(d)
	if controlling == d then return end
	if controlling then stopControl("переключение") end
	local h = myHum()
	if not h then
		bad("У твоего персонажа нет Humanoid — камера не переключится. Подожди, пока он появится.")
		return
	end
	if d.hum.Health <= 0 then
		bad("NPC", d.model.Name, "мёртв (Health = 0), управлять нечем.")
		return
	end
	controlling = d
	d.following, d.target, d.moving = false, nil, false
	if d.frozen then setFrozen(d, false) end

	savedStats = { ws = h.WalkSpeed, jp = h.JumpPower, jh = h.JumpHeight }
	h.WalkSpeed, h.JumpPower, h.JumpHeight = 0, 0, 0 -- мой персонаж стоит, ходит только NPC

	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = d.hum

	hud.Text = "Контроль: " .. d.model.Name .. "   |   WASD ходить · Пробел прыжок · Shift бег · C сесть · X выйти · P меню"
	hud.Visible = true
	main.Visible = false

	if d.root.Anchored then
		bad("NPC", d.model.Name, ": корневая часть Anchored — он не будет двигаться. Сними Anchored.")
	end
	log("Играешь за:", d.model:GetFullName())
end

local function removeNPC(model)
	local d = npcs[model]
	if not d then return end
	if controlling == d then stopControl("NPC удалён из игры") end
	if sel == d then sel = nil end
	d.row:Destroy()
	npcs[model] = nil
	log("NPC удалён из списка:", model.Name)
end

local function addNPC(model, hum, root)
	local row = new("TextButton", {
		Name = model.Name, Size = UDim2.new(1, -6, 0, 38), BackgroundColor3 = ROWC, TextColor3 = WHITE,
		Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		Text = model.Name, BorderSizePixel = 0,
	}, list)
	corner(row)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, row)

	local d = {
		model = model, hum = hum, root = root, row = row,
		frozen = false, following = false, spinning = false, moving = false,
		moveTime = 0, dist = 0, warnedStuck = false,
		speed = hum.WalkSpeed, jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight,
		spawnCF = root.CFrame,
	}

	d.hl = new("Highlight", {
		Name = "NPCCtrlHL", Adornee = model, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillTransparency = 0.55, OutlineTransparency = 0, Enabled = false,
	}, model)
	d.tag = new("BillboardGui", {
		Name = "NPCCtrlTag", Adornee = root, AlwaysOnTop = true, Size = UDim2.new(0, 190, 0, 30),
		StudsOffset = Vector3.new(0, 3.8, 0), Enabled = false,
	}, root)
	d.tagLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, TextColor3 = WHITE,
		TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBold, TextSize = 14, Text = model.Name,
	}, d.tag)

	npcs[model] = d

	row.MouseButton1Click:Connect(function()
		sel = d
		setStatus("Выбран: " .. model.Name)
		refreshUI()
	end)

	if root.Anchored then
		bad("NPC", model.Name, ": корневая часть Anchored — он не сможет двигаться. Сними Anchored.")
	end
	if hum.Health <= 0 then
		bad("NPC", model.Name, ": Health = 0, он мёртв.")
	end
	log("Добавлен NPC:", model:GetFullName())
end

local lastCount = -1
local function scan()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local model = inst.Parent
			if model and model:IsA("Model") and not npcs[model] and not Players:GetPlayerFromCharacter(model) then
				local root = findRoot(model)
				if root then
					addNPC(model, inst, root)
				elseif not warnedNoRoot[model] then
					warnedNoRoot[model] = true
					bad("Пропущен", model:GetFullName(), ": нет HumanoidRootPart / PrimaryPart / Torso")
				end
			end
		end
	end
	for model in pairs(npcs) do
		if not model:IsDescendantOf(workspace) then removeNPC(model) end
	end
	local count = 0
	for _ in pairs(npcs) do count += 1 end
	if count ~= lastCount then
		lastCount = count
		log("Сканирование: NPC в списке =", count)
		if count == 0 then
			bad("NPC не найдены! Нужна Model в workspace с Humanoid и HumanoidRootPart (и это не персонаж игрока).")
			setStatus("NPC не найдены. Смотри консоль (F9).")
		end
	end
end

---------------------------------------------------------------- Обновление UI и подсветки
local function updateESP()
	for _, d in pairs(npcs) do
		local mode
		if controlling == d then mode = Color3.fromRGB(60, 255, 90)
		elseif sel == d then mode = Color3.fromRGB(255, 220, 60)
		elseif espAll then mode = Color3.fromRGB(80, 200, 255) end
		if mode then
			d.hl.FillColor = mode
			d.hl.OutlineColor = mode
			d.tagLabel.TextColor3 = mode
		end
		d.hl.Enabled = mode ~= nil
		d.tag.Enabled = mode ~= nil
	end
end

local features = {}

refreshUI = function()
	for _, d in pairs(npcs) do
		local t = d.model.Name .. "  ·  " .. d.dist .. "m"
		if controlling == d then t = "● " .. t end
		if d.frozen then t = t .. "  [заморожен]" end
		d.row.Text = t
		d.row.BackgroundColor3 = (controlling == d and GREEN) or (sel == d and BLUE) or ROWC
	end
	if sel and sel.hum.Parent then
		info.Text = string.format("%s\nHP %d/%d  ·  скорость %d  ·  %d studs",
			sel.model.Name, math.floor(sel.hum.Health), math.floor(sel.hum.MaxHealth), math.floor(sel.speed), sel.dist)
	else
		info.Text = "Выбери бота слева"
	end
	for _, f in ipairs(features) do
		local on = f.isOn and f.isOn() or false
		f.btn.BackgroundColor3 = on and GREEN or GRAY
		f.btn.Text = (on and f.onText) or f.text
	end
	updateESP()
end

---------------------------------------------------------------- Действия и кнопки
local function needSel()
	if not sel or not sel.hum.Parent then
		bad("Сначала выбери бота в списке слева.")
		setStatus("Сначала выбери бота в списке слева.")
		return nil
	end
	return sel
end

local function standUp(d)
	if d.hum.Sit then d.hum.Sit = false end
end

local function feature(text, fn, isOn, onText)
	local b = new("TextButton", {
		BackgroundColor3 = GRAY, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 12,
		Text = text, BorderSizePixel = 0, TextWrapped = true, LayoutOrder = #features + 1,
	}, grid)
	corner(b)
	b.MouseButton1Click:Connect(function()
		local ok, err = pcall(fn)
		if not ok then bad("Ошибка в кнопке '" .. text .. "':", err) end
		refreshUI()
	end)
	table.insert(features, { btn = b, text = text, onText = onText, isOn = isOn })
end

feature("Контроль (как игрок)", function()
	local d = needSel() if not d then return end
	if controlling == d then stopControl() else startControl(d) end
end, function() return sel ~= nil and controlling == sel end, "Контроль: ВКЛ (X)")

feature("Click to Move", function()
	clickToMove = not clickToMove
	setStatus(clickToMove and "Click to Move: кликай по земле, выбранный бот пойдёт туда." or "Click to Move выключен.")
end, function() return clickToMove end, "Click to Move: ВКЛ")

feature("Сесть / встать", function()
	local d = needSel() if not d then return end
	d.hum.Sit = not d.hum.Sit
end, function() return sel ~= nil and sel.hum.Sit end, "Сидит (встать)")

feature("Заморозить", function()
	local d = needSel() if not d then return end
	setFrozen(d, not d.frozen)
end, function() return sel ~= nil and sel.frozen end, "Разморозить")

feature("Прыжок", function()
	local d = needSel() if not d then return end
	if d.frozen then bad("NPC заморожен — прыгнуть не сможет.") return end
	standUp(d)
	d.hum.Jump = true
end)

feature("Следовать за мной", function()
	local d = needSel() if not d then return end
	if controlling == d then bad("Ты и так управляешь этим NPC.") return end
	if d.frozen then bad("NPC заморожен — разморозь его.") return end
	d.following = not d.following
	d.target = nil
	standUp(d)
end, function() return sel ~= nil and sel.following end, "Следует за мной")

feature("Стоп", function()
	local d = needSel() if not d then return end
	d.following, d.target = false, nil
	d.hum:MoveTo(d.root.Position)
end)

feature("Скорость  −", function()
	local d = needSel() if not d then return end
	d.speed = math.max(2, d.speed - 4)
	applyStats(d)
	setStatus("Скорость: " .. d.speed)
end)

feature("Скорость  +", function()
	local d = needSel() if not d then return end
	d.speed = math.min(120, d.speed + 4)
	applyStats(d)
	setStatus("Скорость: " .. d.speed)
end)

feature("NPC → ко мне", function()
	local d = needSel() if not d then return end
	local mr = myRoot()
	if not mr then bad("У тебя нет HumanoidRootPart.") return end
	d.root.CFrame = mr.CFrame * CFrame.new(0, 3, -5)
end)

feature("Я → к NPC", function()
	local d = needSel() if not d then return end
	local mr = myRoot()
	if not mr then bad("У тебя нет HumanoidRootPart.") return end
	mr.CFrame = d.root.CFrame * CFrame.new(0, 3, 6)
end)

feature("Вернуть на место", function()
	local d = needSel() if not d then return end
	d.root.CFrame = d.spawnCF
	d.target = nil
end)

feature("Смотреть на меня", function()
	local d = needSel() if not d then return end
	local mr = myRoot()
	if not mr then bad("У тебя нет HumanoidRootPart.") return end
	d.root.CFrame = CFrame.lookAt(d.root.Position, Vector3.new(mr.Position.X, d.root.Position.Y, mr.Position.Z))
end)

feature("Крутить", function()
	local d = needSel() if not d then return end
	d.spinning = not d.spinning
end, function() return sel ~= nil and sel.spinning end, "Крутится (стоп)")

feature("Подсветка всех (ESP)", function()
	espAll = not espAll
end, function() return espAll end, "Подсветка всех: ВКЛ")

feature("Мой перс рядом", function()
	keepClose = not keepClose
	setStatus(keepClose
		and "Мой персонаж держится рядом с NPC — сетевой контроль не пропадёт."
		or "Мой персонаж остаётся где стоял. Если уйдёшь далеко — NPC перестанет слушаться.")
end, function() return keepClose end, "Мой перс рядом: ВКЛ")

feature("Заморозить всех", function()
	for _, d in pairs(npcs) do setFrozen(d, true) end
end)

feature("Разморозить всех", function()
	for _, d in pairs(npcs) do setFrozen(d, false) end
end)

---------------------------------------------------------------- Click to Move
local function clickMove(d)
	if d.frozen then bad("NPC", d.model.Name, "заморожен — разморозь его.") return end
	local cam = workspace.CurrentCamera
	local pos = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { d.model, player.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not res then
		bad("Клик мимо: луч ничего не задел (небо?). Кликни по земле.")
		return
	end
	d.following = false
	standUp(d)
	d.target = res.Position
	d.hum:MoveTo(res.Position)
	log("MoveTo:", d.model.Name, tostring(res.Position))

	local m = new("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2), Material = Enum.Material.Neon, Color = Color3.fromRGB(60, 255, 90),
		Position = res.Position + Vector3.new(0, 0.6, 0),
	}, workspace)
	Debris:AddItem(m, 1.5)
end

---------------------------------------------------------------- Ввод
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.P then
		main.Visible = not main.Visible
	elseif kc == Enum.KeyCode.X then
		if controlling then stopControl("клавиша X") refreshUI() end
	elseif kc == Enum.KeyCode.C then
		if controlling then controlling.hum.Sit = not controlling.hum.Sit refreshUI() end
	elseif kc == Enum.KeyCode.LeftShift then
		sprinting = true
		if controlling then applyStats(controlling) end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if clickToMove then
			if not sel then
				bad("Click to Move включён, но бот не выбран. Выбери бота слева.")
			else
				local ok, err = pcall(clickMove, sel)
				if not ok then bad("Ошибка Click to Move:", err) end
			end
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
	local d = controlling
	if d and not d.frozen then
		standUp(d)
		d.hum.Jump = true
	end
end)

player.CharacterAdded:Connect(function()
	if controlling then
		stopControl("твой персонаж возродился")
		refreshUI()
	end
end)

---------------------------------------------------------------- Главный цикл кадра: ходьба как у игрока
RunService.RenderStepped:Connect(function(dt)
	for _, s in pairs(npcs) do
		if s.spinning and not s.frozen and s.root.Parent then
			s.root.CFrame *= CFrame.Angles(0, math.rad(300) * dt, 0)
		end
	end

	local d = controlling
	if not d then return end
	if not d.hum.Parent or d.hum.Health <= 0 then
		bad("NPC", d.model.Name, "умер или пропал — контроль снят.")
		stopControl("NPC недоступен")
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
			if d.frozen then bad("NPC заморожен — разморозь его, чтобы ходить.") end
		end
		standUp(d)
		d.following = false
		d.target = nil
		d.hum:Move(v, true)
		d.moveTime += dt
		if d.moveTime > 1.5 and not d.warnedStuck and not d.frozen and d.root.AssemblyLinearVelocity.Magnitude < 0.5 then
			d.warnedStuck = true
			bad("NPC не двигается. Возможные причины: нет network ownership (подойди ближе / включи 'Мой перс рядом'), "
				.. "детали Anchored, сервер управляет NPC, или он упёрся в стену.")
		end
	elseif d.moving then
		d.moving = false
		d.hum:Move(Vector3.zero, true)
	end
end)

---------------------------------------------------------------- Фоновые циклы
local warnedFar = false
local function tick()
	local mr = myRoot()
	for _, d in pairs(npcs) do
		if d.root.Parent then
			d.dist = mr and math.floor((d.root.Position - mr.Position).Magnitude) or 0
			d.tagLabel.Text = string.format("%s  [%d m]  HP %d", d.model.Name, d.dist, math.floor(d.hum.Health))

			if d.target and not d.frozen then
				local flat = Vector3.new(d.target.X - d.root.Position.X, 0, d.target.Z - d.root.Position.Z)
				if flat.Magnitude < 3 then
					d.target = nil
				else
					d.hum:MoveTo(d.target) -- MoveTo сам отменяется через 8 сек, обновляем
				end
			end

			if d.following and not d.frozen and mr then
				if d.dist > 7 then d.hum:MoveTo(mr.Position) else d.hum:MoveTo(d.root.Position) end
			end
		end
	end

	if controlling then
		setMyTransparency(1)
		if not keepClose and controlling.dist > 100 then
			if not warnedFar then
				warnedFar = true
				bad("NPC дальше 100 studs — возможно, пропал network ownership. Включи 'Мой перс рядом'.")
			end
		else
			warnedFar = false
		end
	end
	refreshUI()
end

task.spawn(function()
	while true do
		local ok, err = pcall(scan)
		if not ok then bad("Ошибка сканирования:", err) end
		task.wait(2)
	end
end)

task.spawn(function()
	while true do
		local ok, err = pcall(tick)
		if not ok then bad("Ошибка обновления:", err) end
		task.wait(0.25)
	end
end)

log("Готово. P — открыть/закрыть меню.")
