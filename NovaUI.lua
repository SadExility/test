--[[
    NOVA UI - biblioteca de interface para Roblox (Luau)
    Versao 1.0.0

    - Janela arrastavel, minimizavel, com abas, pesquisa e rodape.
    - Botao flutuante independente (camada propria) para abrir/ocultar a janela.
    - Componentes: Section, Toggle, Button, Textbox, Dropdown, Slider, Label, Separator.
    - Tema e transparencia totalmente configuraveis, com atualizacao dinamica.
    - Logo e icone do botao flutuante por URL (requer funcoes do ambiente, veja README).
    - Notificacoes, tooltips, persistencia opcional (se writefile/readfile existirem).

    Este arquivo so retorna a tabela publica (NovaUI). Nenhum codigo de exemplo aqui.
    Nao ha coleta de dados, nao ha execucao de texto digitado e nenhum codigo extra
    e baixado: a unica requisicao HTTP possivel e a de IMAGENS que voce configurar.
]]

local NovaUI = {}
NovaUI.__index = NovaUI
NovaUI.Version = "1.0.0"

--------------------------------------------------------------------------------
-- Servicos e constantes
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local HEADER_HEIGHT = 46
local FOOTER_HEIGHT = 20

local FONT = Enum.Font.Gotham
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local DEFAULT_THEME = {
	Background = Color3.fromRGB(12, 15, 24),
	Header = Color3.fromRGB(15, 19, 31),
	Sidebar = Color3.fromRGB(19, 24, 37),
	Component = Color3.fromRGB(25, 32, 48),
	Accent = Color3.fromRGB(70, 145, 255),
	Button = Color3.fromRGB(70, 145, 255),
	ButtonText = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(240, 244, 255),
	MutedText = Color3.fromRGB(145, 157, 180),
	Border = Color3.fromRGB(43, 53, 74),
	ToggleOn = Color3.fromRGB(70, 145, 255),
	ToggleOff = Color3.fromRGB(52, 62, 84),
	FloatingButton = Color3.fromRGB(70, 145, 255),
	FloatingText = Color3.fromRGB(255, 255, 255),
	Success = Color3.fromRGB(64, 201, 120),
	Warning = Color3.fromRGB(245, 178, 60),
	Error = Color3.fromRGB(240, 84, 84),
}

local DEFAULT_TRANSPARENCY = {
	Window = 0,
	Sidebar = 0,
	Header = 0,
	Components = 0,
	Buttons = 0,
	FloatingButton = 0,
	Borders = 0.2,
	Dropdown = 0,
	Notifications = 0.05,
}

-- Tabelas de metodos (preenchidas mais abaixo)
local HostMethods = {}
local TabMethods = {}
local SectionMethods = {}
local TabMT = { __index = TabMethods }
local SectionMT = { __index = SectionMethods }

--------------------------------------------------------------------------------
-- Utilitarios
--------------------------------------------------------------------------------
local function warnf(fmt, ...)
	warn("[NovaUI] " .. string.format(fmt, ...))
end

local function isColor(value)
	return typeof(value) == "Color3"
end

local function clampNumber(value, lo, hi, default)
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, lo, hi)
end

local function merge(base, override)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	if type(override) == "table" then
		for k, v in pairs(override) do
			out[k] = v
		end
	end
	return out
end

local function copy(tbl)
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = v
	end
	return out
end

local function create(class, props, children)
	local inst = Instance.new(class)
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function tween(inst, props, duration, style, direction)
	if inst == nil then
		return nil
	end
	if inst.Parent == nil then
		for k, v in pairs(props) do
			pcall(function()
				inst[k] = v
			end)
		end
		return nil
	end
	local t = TweenService:Create(
		inst,
		TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function safeCall(callback, ...)
	if type(callback) ~= "function" then
		return
	end
	local ok, err = pcall(callback, ...)
	if not ok then
		warnf("Erro dentro de um callback: %s", tostring(err))
	end
end

local function envFunc(name)
	local ok, fn = pcall(function()
		return getfenv()[name]
	end)
	if ok and type(fn) == "function" then
		return fn
	end
	return nil
end

local function countDecimals(n)
	local str = string.format("%.6f", n)
	str = (str:gsub("0+$", ""))
	local dot = str:find("%.")
	if dot then
		return #str - dot
	end
	return 0
end

-- Gerenciador simples de conexoes/instancias
local function newMaid()
	return { items = {} }
end

local function maidGive(maid, item)
	table.insert(maid.items, item)
	return item
end

local function maidClean(maid)
	local items = maid.items
	maid.items = {}
	for _, item in ipairs(items) do
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			item:Destroy()
		elseif kind == "function" then
			pcall(item)
		end
	end
end

--------------------------------------------------------------------------------
-- Imagens remotas
-- Uma URL web NAO pode ser atribuida direto a ImageLabel.Image. O caminho aqui e:
--   baixar os bytes -> writefile -> getcustomasset -> usar o "rbxasset://..." gerado.
-- Isso so existe em alguns ambientes (executores). Em Studio/jogos normais, use
-- "rbxassetid://ID" (ou apenas o numero do ID).
--------------------------------------------------------------------------------
local imageCache = {}

local function hashString(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 4294967296
	end
	return string.format("%08x", h)
end

local function httpGet(url)
	local ok, data = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(data) == "string" then
		return data
	end
	local ok2, data2 = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if ok2 and type(data2) == "string" then
		return data2
	end
	error("falha na requisicao HTTP (" .. tostring(ok and "resposta invalida" or data) .. ")", 0)
end

local function looksLikeImage(data)
	if #data < 12 then
		return false
	end
	local b1, b2, b3, b4 = string.byte(data, 1, 4)
	if b1 == 137 and b2 == 80 and b3 == 78 and b4 == 71 then
		return true -- PNG
	end
	if b1 == 255 and b2 == 216 then
		return true -- JPEG
	end
	if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then
		return true
	end
	return false
end

-- callback(asset, isLocalAsset) recebe uma string utilizavel em .Image, ou nil em caso de falha.
-- isLocalAsset = true quando o asset veio de um arquivo gravado em disco (writefile + getcustomasset):
-- esses carregam na hora, e a propriedade IsLoaded nem sempre fica true para eles em executores,
-- entao loadInto nao deve esperar por IsLoaded nesse caso (ver comentario abaixo).
local function resolveImage(source, callback)
	if type(source) ~= "string" or source == "" then
		callback(nil, false)
		return
	end
	if
		source:match("^rbxassetid://")
		or source:match("^rbxasset://")
		or source:match("^rbxthumb://")
		or source:match("^https?://www%.roblox%.com/asset")
	then
		callback(source, false)
		return
	end
	if source:match("^%d+$") then
		callback("rbxassetid://" .. source, false)
		return
	end
	if not source:match("^https?://") then
		warnf("Imagem ignorada (formato invalido): %s", source)
		callback(nil, false)
		return
	end
	if imageCache[source] then
		callback(imageCache[source], true)
		return
	end
	task.spawn(function()
		local writeFile = envFunc("writefile")
		local getAsset = envFunc("getcustomasset") or envFunc("getsynasset")
		if not (writeFile and getAsset) then
			warnf("Imagem por URL indisponivel neste ambiente (faltam writefile/getcustomasset). Usando alternativa.")
			callback(nil, false)
			return
		end
		local makeFolder = envFunc("makefolder")
		local isFile = envFunc("isfile")
		local clean = (source:gsub("[%?#].*$", ""))
		local ext = (clean:match("%.(%w+)$") or "png"):lower()
		if ext ~= "png" and ext ~= "jpg" and ext ~= "jpeg" and ext ~= "webp" then
			ext = "png"
		end
		local path = "NovaUI/img_" .. hashString(source) .. "." .. ext
		local ok, asset = pcall(function()
			if makeFolder then
				pcall(makeFolder, "NovaUI")
			end
			local exists = isFile and isFile(path)
			if not exists then
				local data = httpGet(source)
				if not looksLikeImage(data) then
					error("o conteudo recebido nao e uma imagem PNG/JPEG/WEBP", 0)
				end
				writeFile(path, data)
			end
			return getAsset(path)
		end)
		if ok and type(asset) == "string" and asset ~= "" then
			imageCache[source] = asset
			callback(asset, true)
		else
			warnf("Nao foi possivel carregar a imagem '%s': %s", source, tostring(asset))
			callback(nil, false)
		end
	end)
end

-- Carrega a imagem dentro de um ImageLabel e confirma que carregou de verdade.
local function loadInto(imageLabel, source, onSuccess, onFail)
	resolveImage(source, function(asset, isLocalAsset)
		if imageLabel.Parent == nil then
			return
		end
		if not asset then
			if onFail then
				onFail()
			end
			return
		end
		imageLabel.Image = asset
		if isLocalAsset then
			-- Asset local (gravado via writefile + getcustomasset): carrega instantaneamente
			-- do disco. Em varios executores a propriedade IsLoaded nunca fica "true" para
			-- esse tipo de asset, entao esperar por ela so faria a imagem (ja valida, ja
			-- atribuida) ser escondida de novo pelo onFail apos o timeout. Confirma direto.
			if onSuccess then
				onSuccess()
			end
			return
		end
		local started = os.clock()
		task.spawn(function()
			while imageLabel.Parent ~= nil and not imageLabel.IsLoaded and os.clock() - started < 8 do
				task.wait(0.1)
			end
			if imageLabel.Parent == nil then
				return
			end
			if imageLabel.IsLoaded then
				if onSuccess then
					onSuccess()
				end
			elseif onFail then
				onFail()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Montagem de ScreenGui
--------------------------------------------------------------------------------
local function mountGui(gui)
	local candidates = {}
	local getHui = envFunc("gethui")
	local isExecutor = getHui ~= nil or envFunc("getcustomasset") ~= nil
	if getHui then
		local ok, ui = pcall(getHui)
		if ok and typeof(ui) == "Instance" then
			table.insert(candidates, ui)
		end
	end
	if isExecutor then
		local okCore, core = pcall(function()
			return game:GetService("CoreGui")
		end)
		if okCore then
			table.insert(candidates, core)
		end
	end
	if LocalPlayer then
		local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
		if playerGui then
			table.insert(candidates, playerGui)
		end
	end
	for _, parent in ipairs(candidates) do
		local ok = pcall(function()
			gui.Parent = parent
		end)
		if ok and gui.Parent == parent then
			return true
		end
	end
	error("[NovaUI] Nao foi possivel anexar a interface (sem gethui, CoreGui ou PlayerGui disponiveis).", 0)
end

--------------------------------------------------------------------------------
-- Arraste unificado (mouse + toque)
--------------------------------------------------------------------------------
local function trackDrag(store, startInput, onMove, onEnd)
	local isTouch = startInput.UserInputType == Enum.UserInputType.Touch
	local conns = {}
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		store[conns] = nil
		if onEnd then
			onEnd()
		end
	end
	conns[1] = UserInputService.InputChanged:Connect(function(input)
		if isTouch then
			if input == startInput then
				onMove(input.Position)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			onMove(input.Position)
		end
	end)
	conns[2] = UserInputService.InputEnded:Connect(function(input)
		if isTouch then
			if input == startInput then
				finish()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			finish()
		end
	end)
	store[conns] = true
end

local function dropDrags(store)
	for conns in pairs(store) do
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
	for k in pairs(store) do
		store[k] = nil
	end
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

--------------------------------------------------------------------------------
-- Tema: registro de elementos e atualizacao dinamica
--------------------------------------------------------------------------------
function NovaUI:_fn(inst, fn)
	fn()
	table.insert(self.themed, { inst = inst, apply = fn })
end

function NovaUI:_bg(inst, colorKey, transKey)
	self:_fn(inst, function()
		if colorKey then
			inst.BackgroundColor3 = self.theme[colorKey]
		end
		if transKey then
			inst.BackgroundTransparency = self.transparency[transKey]
		end
	end)
end

function NovaUI:_color(inst, prop, colorKey)
	self:_fn(inst, function()
		inst[prop] = self.theme[colorKey]
	end)
end

function NovaUI:_stroke(stroke, colorKey)
	self:_fn(stroke, function()
		stroke.Color = self.theme[colorKey]
		stroke.Transparency = self.transparency.Borders
	end)
end

function NovaUI:_applyTheme()
	local alive = {}
	for _, entry in ipairs(self.themed) do
		if entry.inst.Parent ~= nil then
			local ok, err = pcall(entry.apply)
			if not ok then
				warnf("Erro ao aplicar tema: %s", tostring(err))
			end
			table.insert(alive, entry)
		end
	end
	self.themed = alive
end

function NovaUI:_set(inst, props, animate, duration)
	if animate and inst.Parent ~= nil then
		tween(inst, props, duration or 0.15)
	else
		for k, v in pairs(props) do
			inst[k] = v
		end
	end
end

function NovaUI:_viewport()
	local size = Vector2.new(0, 0)
	if self.layerGui and self.layerGui.Parent then
		size = self.layerGui.AbsoluteSize
	end
	if size.X < 2 or size.Y < 2 then
		local cam = workspace.CurrentCamera
		size = cam and cam.ViewportSize or Vector2.new(1024, 576)
	end
	return size
end

function NovaUI:_newLabel(parent, text, size, colorKey, font)
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = tostring(text),
		Font = font or FONT_MEDIUM,
		TextSize = size or 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	self:_color(label, "TextColor3", colorKey or "Text")
	return label
end

function NovaUI:_newRow(host, height, clickable)
	local props = {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BorderSizePixel = 0,
		LayoutOrder = host:_nextOrder(),
	}
	if clickable then
		props.Text = ""
		props.AutoButtonColor = false
	end
	local row = create(clickable and "TextButton" or "Frame", props)
	corner(row, 6)
	local stroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = row,
	})
	self:_bg(row, "Component", "Components")
	self:_stroke(stroke, "Border")
	local hover = create("Frame", {
		Name = "Hover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(hover, 6)
	if clickable then
		row.MouseEnter:Connect(function()
			tween(hover, { BackgroundTransparency = 0.94 }, 0.1)
		end)
		row.MouseLeave:Connect(function()
			tween(hover, { BackgroundTransparency = 1 }, 0.1)
		end)
	end
	return row
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------
function NovaUI:_hideTooltip()
	if self.tooltip then
		self.tooltip.Visible = false
	end
end

function NovaUI:_moveTooltip()
	if not self.tooltip or not self.tooltipSize then
		return
	end
	local vp = self:_viewport()
	local s = self.baseScale
	local mouse = UserInputService:GetMouseLocation()
	local w = self.tooltipSize.X * s
	local h = self.tooltipSize.Y * s
	local x = math.clamp(mouse.X + 14, 4, math.max(4, vp.X - w - 4))
	local y = mouse.Y + 18
	if y + h > vp.Y - 4 then
		y = math.max(4, mouse.Y - h - 8)
	end
	self.tooltip.Position = UDim2.fromOffset(x, y)
end

function NovaUI:_showTooltip(text)
	if not self.tooltip then
		return
	end
	local bounds = TextService:GetTextSize(text, 12, FONT, Vector2.new(220, 1000))
	self.tooltipSize = Vector2.new(bounds.X + 18, bounds.Y + 12)
	self.tooltip.Text = text
	self.tooltip.Size = UDim2.fromOffset(self.tooltipSize.X, self.tooltipSize.Y)
	self:_moveTooltip()
	self.tooltip.Visible = true
end

function NovaUI:_tooltip(obj, getter)
	local token = 0
	obj.MouseEnter:Connect(function()
		if not UserInputService.MouseEnabled then
			return
		end
		local text = getter()
		if type(text) ~= "string" or text == "" then
			return
		end
		token = token + 1
		local mine = token
		task.delay(0.45, function()
			if mine ~= token or not self.mainAlive or not self.visible or self.minimized then
				return
			end
			self:_showTooltip(text)
		end)
	end)
	obj.MouseMoved:Connect(function()
		if self.tooltip and self.tooltip.Visible then
			self:_moveTooltip()
		end
	end)
	obj.MouseLeave:Connect(function()
		token = token + 1
		self:_hideTooltip()
	end)
end

function NovaUI:_closeOverlays()
	if self.activeClose then
		local fn = self.activeClose
		self.activeClose = nil
		fn()
	end
	self:_hideTooltip()
end

--------------------------------------------------------------------------------
-- Pecas visuais reutilizaveis
--------------------------------------------------------------------------------
local function buildSwitch(win, parent, style, rightPad)
	rightPad = rightPad or 10
	if style == "Checkbox" then
		local box = create("Frame", {
			Name = "Checkbox",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -rightPad, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			BorderSizePixel = 0,
			Parent = parent,
		})
		corner(box, 4)
		local mark = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = box,
		})
		corner(mark, 2)
		return function(state, enabled, animate)
			local t = win.theme
			win:_set(box, {
				BackgroundColor3 = state and t.ToggleOn or t.ToggleOff,
				BackgroundTransparency = enabled and 0 or 0.5,
			}, animate)
			win:_set(mark, {
				BackgroundTransparency = state and (enabled and 0 or 0.5) or 1,
			}, animate)
		end
	end
	local track = create("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -rightPad, 0.5, 0),
		Size = UDim2.fromOffset(38, 20),
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(track, 10)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(knob, 7)
	return function(state, enabled, animate)
		local t = win.theme
		win:_set(track, {
			BackgroundColor3 = state and t.ToggleOn or t.ToggleOff,
			BackgroundTransparency = enabled and 0 or 0.5,
		}, animate)
		win:_set(knob, {
			Position = state and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundTransparency = enabled and 0 or 0.4,
		}, animate)
	end
end

local function buildChevron(win, parent)
	local holder = create("Frame", {
		Name = "Chevron",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local specs = { { x = 3.5, rot = 45 }, { x = 8.5, rot = -45 } }
	for _, spec in ipairs(specs) do
		local bar = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(spec.x, 5),
			Size = UDim2.fromOffset(7, 2),
			Rotation = spec.rot,
			BorderSizePixel = 0,
			Parent = holder,
		})
		win:_bg(bar, "MutedText")
	end
	return holder
end

--------------------------------------------------------------------------------
-- Construcao: camada persistente (notificacoes + botao flutuante)
--------------------------------------------------------------------------------
function NovaUI:_buildLayer(floatCfg)
	local layerGui = create("ScreenGui", {
		Name = "NovaUI_Layer",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
		IgnoreGuiInset = true,
	})
	mountGui(layerGui)
	self.layerGui = layerGui
	maidGive(self.layerMaid, layerGui)

	-- Notificacoes
	local holder = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, 260, 1, -24),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = layerGui,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		Parent = holder,
	})
	self.notifScale = create("UIScale", { Parent = holder })
	self.notifHolder = holder

	-- Botao flutuante
	local size = clampNumber(tonumber(floatCfg.Size), 28, 96, 48)
	local radius = clampNumber(tonumber(floatCfg.CornerRadius), 0, size / 2, math.floor(size * 0.28))
	local container = create("Frame", {
		Name = "FloatingButton",
		AnchorPoint = typeof(floatCfg.AnchorPoint) == "Vector2" and floatCfg.AnchorPoint or Vector2.new(0, 0.5),
		Position = typeof(floatCfg.Position) == "UDim2" and floatCfg.Position or UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 80,
		Visible = floatCfg.Enabled ~= false,
		Parent = layerGui,
	})
	self.floatContainer = container
	self.floatScale = create("UIScale", { Parent = container })

	if floatCfg.Shadow ~= false then
		local shadow = create("Frame", {
			Name = "Shadow",
			Position = UDim2.new(0, -4, 0, -4),
			Size = UDim2.new(1, 8, 1, 8),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			Parent = container,
		})
		corner(shadow, radius + 4)
	end

	local body = create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Active = true,
		Parent = container,
	})
	corner(body, radius)
	local stroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = body,
	})
	self:_bg(body, "FloatingButton", "FloatingButton")
	self:_fn(stroke, function()
		stroke.Color = self.theme.Border
		stroke.Transparency = math.clamp(self.transparency.Borders + 0.2, 0, 1)
	end)

	local iconText = tostring(floatCfg.Text or "N")
	local icon = create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = iconText,
		Font = FONT_BOLD,
		TextSize = math.floor(size * 0.42),
		Parent = body,
	})
	self:_color(icon, "TextColor3", "FloatingText")

	local image = create("ImageLabel", {
		Name = "Image",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		Parent = body,
	})
	if floatCfg.Image ~= nil and floatCfg.Image ~= "" then
		loadInto(image, floatCfg.Image, function()
			image.Visible = true
			icon.Visible = false
		end, function()
			image.Visible = false
			icon.Visible = true
		end)
	end

	local draggable = floatCfg.Draggable ~= false
	body.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		local startPos = input.Position
		local startUDim = container.Position
		local moved = false
		tween(self.floatScale, { Scale = 0.92 }, 0.08)
		trackDrag(self.layerDrags, input, function(pos)
			local dx = pos.X - startPos.X
			local dy = pos.Y - startPos.Y
			if not moved and draggable and (math.abs(dx) > 6 or math.abs(dy) > 6) then
				moved = true
			end
			if moved then
				self:_placeFloat(UDim2.new(startUDim.X.Scale, startUDim.X.Offset + dx, startUDim.Y.Scale, startUDim.Y.Offset + dy))
			end
		end, function()
			tween(self.floatScale, { Scale = 1 }, 0.12)
			if not moved then
				self:Toggle()
			end
		end)
	end)

	maidGive(
		self.layerMaid,
		layerGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_onViewport()
		end)
	)
	if typeof(self.toggleKey) == "EnumItem" then
		maidGive(
			self.layerMaid,
			UserInputService.InputBegan:Connect(function(input, processed)
				if not processed and input.KeyCode == self.toggleKey then
					self:Toggle()
				end
			end)
		)
	end
end

function NovaUI:_placeFloat(pos)
	local c = self.floatContainer
	if not c or c.Parent == nil then
		return
	end
	local vp = self:_viewport()
	local sz = c.Size.X.Offset
	local a = c.AnchorPoint
	local ax = pos.X.Scale * vp.X + pos.X.Offset - a.X * sz
	local ay = pos.Y.Scale * vp.Y + pos.Y.Offset - a.Y * sz
	local nx = math.clamp(ax, 4, math.max(4, vp.X - sz - 4))
	local ny = math.clamp(ay, 4, math.max(4, vp.Y - sz - 4))
	c.Position = UDim2.new(pos.X.Scale, pos.X.Offset + (nx - ax), pos.Y.Scale, pos.Y.Offset + (ny - ay))
end

function NovaUI:_pulseFloat()
	if not self.floatScale or self.floatScale.Parent == nil then
		return
	end
	self.floatScale.Scale = 0.86
	tween(self.floatScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

--------------------------------------------------------------------------------
-- Escala, posicao e tamanho (responsivo)
--------------------------------------------------------------------------------
function NovaUI:_moveRootTo(cx, ty)
	if not self.mainAlive then
		return
	end
	local vp = self:_viewport()
	local s = self.baseScale
	local wPx = self.width * s
	local hPx = (self.minimized and HEADER_HEIGHT or self.height) * s
	cx = math.clamp(cx, math.min(wPx / 2, vp.X / 2), math.max(vp.X - wPx / 2, vp.X / 2))
	ty = math.clamp(ty, 0, math.max(0, vp.Y - hPx))
	self.root.Position = UDim2.fromOffset(cx, ty)
	self.posX = cx / vp.X
	self.posY = ty / vp.Y
end

function NovaUI:_applyPosition()
	if not self.mainAlive then
		return
	end
	local vp = self:_viewport()
	if self.posY == nil then
		self.posY = math.max(0, (vp.Y - self.height * self.baseScale) / 2) / vp.Y
	end
	self:_moveRootTo(self.posX * vp.X, self.posY * vp.Y)
end

function NovaUI:_updateScale()
	local vp = self:_viewport()
	local s = math.min(1, (vp.X - 16) / self.width, (vp.Y - 16) / self.height)
	s = math.clamp(s, 0.5, 1)
	self.baseScale = s
	if self.notifScale then
		self.notifScale.Scale = math.max(s, 0.7)
	end
	if self.mainAlive then
		if self.visible then
			self.rootScale.Scale = s
		end
		self.dropScale.Scale = s
		self.tooltipScale.Scale = s
		self:_applyPosition()
	end
end

function NovaUI:_onViewport()
	if self.destroyed then
		return
	end
	self:_closeOverlays()
	self:_updateScale()
	self:_placeFloat(self.floatContainer.Position)
end

function NovaUI:_layoutFixed()
	self.body.Size = UDim2.new(1, 0, 0, self.height - HEADER_HEIGHT - FOOTER_HEIGHT)
	self.footer.Position = UDim2.new(0, 0, 0, self.height - FOOTER_HEIGHT)
end

function NovaUI:SetSize(width, height)
	if not self.mainAlive then
		return false
	end
	self.width = clampNumber(tonumber(width), self.minWidth, self.maxWidth, self.width)
	self.height = clampNumber(tonumber(height), self.minHeight, self.maxHeight, self.height)
	self.root.Size = UDim2.fromOffset(self.width, self.minimized and HEADER_HEIGHT or self.height)
	self:_layoutFixed()
	self:_updateScale()
	return true
end

--------------------------------------------------------------------------------
-- Construcao: janela principal
--------------------------------------------------------------------------------
function NovaUI:_buildMain(config)
	local isTouch = self.isTouch
	local mainGui = create("ScreenGui", {
		Name = "NovaUI_Main",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 900,
		IgnoreGuiInset = true,
	})
	mountGui(mainGui)
	self.mainGui = mainGui
	maidGive(self.maid, mainGui)

	local root = create("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(self.width, self.height),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Visible = self.visible,
		Parent = mainGui,
	})
	self.root = root
	self.rootScale = create("UIScale", { Parent = root })
	create("UISizeConstraint", {
		MinSize = Vector2.new(self.minWidth, HEADER_HEIGHT),
		MaxSize = Vector2.new(self.maxWidth, self.maxHeight),
		Parent = root,
	})

	-- Sombras suaves (camadas)
	local shadowSpecs = {
		{ grow = 12, y = 3, transparency = 0.82, radius = 16 },
		{ grow = 26, y = 7, transparency = 0.92, radius = 24 },
	}
	for _, spec in ipairs(shadowSpecs) do
		local shadow = create("Frame", {
			Name = "Shadow",
			Position = UDim2.new(0, -spec.grow / 2, 0, -spec.grow / 2 + spec.y),
			Size = UDim2.new(1, spec.grow, 1, spec.grow),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = spec.transparency,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = root,
		})
		corner(shadow, spec.radius)
	end

	local main = create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		ZIndex = 1,
		Parent = root,
	})
	corner(main, 10)
	local mainStroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = main,
	})
	self:_bg(main, "Background", "Window")
	self:_stroke(mainStroke, "Border")

	-- Cabecalho
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 3,
		Parent = main,
	})
	corner(header, 10)
	self:_bg(header, "Header", "Header")
	local headerFill = create("Frame", {
		Name = "HeaderFill",
		Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 12),
		BorderSizePixel = 0,
		Parent = header,
	})
	self:_bg(headerFill, "Header", "Header")
	self.headerFill = headerFill
	local headerLine = create("Frame", {
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		Parent = header,
	})
	self:_bg(headerLine, "Border")
	local headerDivider = create("Frame", {
		Position = UDim2.new(0, self.sidebarWidth - 1, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BorderSizePixel = 0,
		Parent = header,
	})
	self:_bg(headerDivider, "Border")

	-- Logo
	local logoCfg = merge({ Enabled = true, Size = 30, CornerRadius = 8 }, config.Logo)
	local logoSize = math.floor(clampNumber(tonumber(logoCfg.Size), 16, HEADER_HEIGHT - 8, 30))
	local logoRadius = clampNumber(tonumber(logoCfg.CornerRadius), 0, logoSize / 2, 8)
	local logoHolder = create("Frame", {
		Name = "Logo",
		Position = UDim2.fromOffset(12, math.floor((HEADER_HEIGHT - logoSize) / 2)),
		Size = UDim2.fromOffset(logoSize, logoSize),
		BorderSizePixel = 0,
		Parent = header,
	})
	corner(logoHolder, logoRadius)
	self:_bg(logoHolder, "Accent")
	local logoInitial = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = math.floor(logoSize * 0.5),
		Text = string.upper(string.sub(tostring(logoCfg.Text or self.title), 1, 1)),
		Parent = logoHolder,
	})
	self:_color(logoInitial, "TextColor3", "ButtonText")
	local logoImage = create("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		Parent = logoHolder,
	})
	corner(logoImage, logoRadius)
	self.logoInitial = logoInitial
	if logoCfg.Enabled ~= false and logoCfg.Image ~= nil and logoCfg.Image ~= "" then
		loadInto(logoImage, logoCfg.Image, function()
			logoImage.Visible = true
			logoInitial.Visible = false
			logoHolder.BackgroundTransparency = 1
		end, function()
			logoImage.Visible = false
			logoInitial.Visible = true
		end)
	end

	-- Titulo / subtitulo
	local titleX = 12 + logoSize + 10
	local titleWidth = math.max(40, self.sidebarWidth - titleX - 6)
	local titleLabel = create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(titleX, 5),
		Size = UDim2.fromOffset(titleWidth, 20),
		BackgroundTransparency = 1,
		Text = self.title,
		Font = FONT_BOLD,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	self:_color(titleLabel, "TextColor3", "Text")
	local subtitleLabel = create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(titleX, 26),
		Size = UDim2.fromOffset(titleWidth, 16),
		BackgroundTransparency = 1,
		Text = self.subtitle,
		Font = FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	self:_color(subtitleLabel, "TextColor3", "MutedText")
	self.titleLabel = titleLabel
	self.subtitleLabel = subtitleLabel
	self.layoutTitle = function()
		if subtitleLabel.Text == "" then
			titleLabel.Position = UDim2.fromOffset(titleX, 13)
		else
			titleLabel.Position = UDim2.fromOffset(titleX, 5)
		end
	end
	self.layoutTitle()

	-- Nome da aba atual (area de conteudo)
	local tabNameLabel = create("TextLabel", {
		Name = "CurrentTab",
		Position = UDim2.fromOffset(self.sidebarWidth + 14, 0),
		Size = UDim2.new(1, -(self.sidebarWidth + 14 + 84), 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Font = FONT_MEDIUM,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	self:_color(tabNameLabel, "TextColor3", "MutedText")
	self.tabNameLabel = tabNameLabel

	-- Botoes de controle da janela
	local btnSize = isTouch and 34 or 28
	local function headerButton(offsetFromRight)
		local b = create("TextButton", {
			Size = UDim2.fromOffset(btnSize, btnSize),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -offsetFromRight, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Parent = header,
		})
		corner(b, 6)
		b.MouseEnter:Connect(function()
			b.BackgroundColor3 = self.theme.Component
			tween(b, { BackgroundTransparency = 0 }, 0.1)
		end)
		b.MouseLeave:Connect(function()
			tween(b, { BackgroundTransparency = 1 }, 0.1)
		end)
		return b
	end
	local closeBtn = headerButton(8)
	local minBtn = headerButton(8 + btnSize + 4)

	local function iconHolder(parent)
		return create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			Parent = parent,
		})
	end
	local closeIcon = iconHolder(closeBtn)
	for _, rot in ipairs({ 45, -45 }) do
		local bar = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 2),
			Rotation = rot,
			BorderSizePixel = 0,
			Parent = closeIcon,
		})
		self:_bg(bar, "MutedText")
	end
	local minIcon = iconHolder(minBtn)
	local minBar = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 2),
		BorderSizePixel = 0,
		Parent = minIcon,
	})
	self:_bg(minBar, "MutedText")
	local minSquare = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = minIcon,
	})
	local minSquareStroke = create("UIStroke", {
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = minSquare,
	})
	self:_fn(minSquareStroke, function()
		minSquareStroke.Color = self.theme.MutedText
	end)
	self.minBar = minBar
	self.minSquare = minSquare

	minBtn.Activated:Connect(function()
		if self.minimized then
			self:Restore()
		else
			self:Minimize()
		end
	end)
	closeBtn.Activated:Connect(function()
		if self.closeAction == "Hide" then
			self:Hide()
		else
			self:_closeMain()
		end
	end)

	-- Arrastar a janela pelo cabecalho
	header.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		self:_closeOverlays()
		local startPos = input.Position
		local startCx = self.root.Position.X.Offset
		local startTy = self.root.Position.Y.Offset
		trackDrag(self.activeDrags, input, function(pos)
			self:_moveRootTo(startCx + (pos.X - startPos.X), startTy + (pos.Y - startPos.Y))
		end)
	end)

	-- Corpo
	local body = create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 0, self.height - HEADER_HEIGHT - FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		Parent = main,
	})
	self.body = body

	local sidebar = create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, self.sidebarWidth, 1, 0),
		BorderSizePixel = 0,
		Parent = body,
	})
	self:_bg(sidebar, "Sidebar", "Sidebar")
	local sideLine = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BorderSizePixel = 0,
		Parent = sidebar,
	})
	self:_bg(sideLine, "Border")

	local searchH = isTouch and 34 or 28
	local searchHolder = create("Frame", {
		Name = "Search",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -17, 0, searchH),
		BorderSizePixel = 0,
		Parent = sidebar,
	})
	corner(searchHolder, 6)
	local searchStroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = searchHolder,
	})
	self:_bg(searchHolder, "Component", "Components")
	self:_stroke(searchStroke, "Border")
	local searchBox = create("TextBox", {
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -18, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Pesquisar...",
		ClearTextOnFocus = false,
		Font = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		Parent = searchHolder,
	})
	self:_color(searchBox, "TextColor3", "Text")
	self:_color(searchBox, "PlaceholderColor3", "MutedText")
	self.searchBox = searchBox
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:_filterTabs(searchBox.Text)
	end)

	local listTop = searchH + 16
	local tabList = create("ScrollingFrame", {
		Name = "TabList",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.new(1, -1, 1, -listTop),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = sidebar,
	})
	self:_color(tabList, "ScrollBarImageColor3", "Accent")
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = tabList,
	})
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 8),
		Parent = tabList,
	})
	self.tabList = tabList

	local noResults = create("TextLabel", {
		Name = "NoResults",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "Nenhuma aba encontrada",
		Font = FONT,
		TextSize = 12,
		Visible = false,
		LayoutOrder = 1000000,
		Parent = tabList,
	})
	self:_color(noResults, "TextColor3", "MutedText")
	self.noResults = noResults

	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(self.sidebarWidth, 0),
		Size = UDim2.new(1, -self.sidebarWidth, 1, 0),
		BackgroundTransparency = 1,
		Parent = body,
	})
	self.content = content

	-- Rodape
	local footer = create("Frame", {
		Name = "Footer",
		Position = UDim2.new(0, 0, 0, self.height - FOOTER_HEIGHT),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = main,
	})
	corner(footer, 10)
	self:_bg(footer, "Header", "Header")
	local footerFill = create("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		BorderSizePixel = 0,
		Parent = footer,
	})
	self:_bg(footerFill, "Header", "Header")
	local footerLabel = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = self.footerText,
		Font = FONT,
		TextSize = 11,
		Parent = footer,
	})
	self:_color(footerLabel, "TextColor3", "MutedText")
	self.footer = footer
	self.footerLabel = footerLabel

	-- Camadas de sobreposicao (dropdown, tooltip) - acima de tudo na janela
	local blocker = create("TextButton", {
		Name = "Blocker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 90,
		Parent = mainGui,
	})
	blocker.Activated:Connect(function()
		self:_closeOverlays()
	end)
	self.blocker = blocker

	local dropList = create("ScrollingFrame", {
		Name = "DropList",
		Visible = false,
		ZIndex = 100,
		BorderSizePixel = 0,
		Active = true,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = mainGui,
	})
	corner(dropList, 8)
	local dropStroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = dropList,
	})
	self:_bg(dropList, "Component", "Dropdown")
	self:_stroke(dropStroke, "Border")
	self:_color(dropList, "ScrollBarImageColor3", "Accent")
	create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = dropList,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = dropList,
	})
	self.dropScale = create("UIScale", { Parent = dropList })
	self.dropList = dropList

	local tooltip = create("TextLabel", {
		Name = "Tooltip",
		Visible = false,
		ZIndex = 110,
		BorderSizePixel = 0,
		Font = FONT,
		TextSize = 12,
		TextWrapped = true,
		Text = "",
		Parent = mainGui,
	})
	corner(tooltip, 6)
	local tipStroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = tooltip,
	})
	self:_bg(tooltip, "Component", "Dropdown")
	self:_color(tooltip, "TextColor3", "Text")
	self:_stroke(tipStroke, "Border")
	self.tooltipScale = create("UIScale", { Parent = tooltip })
	self.tooltip = tooltip
end

--------------------------------------------------------------------------------
-- Construtor
--------------------------------------------------------------------------------
function NovaUI.new(config)
	config = type(config) == "table" and config or {}
	local self = setmetatable({}, NovaUI)

	self.maid = newMaid()
	self.layerMaid = newMaid()
	self.themed = {}
	self.activeDrags = {}
	self.layerDrags = {}
	self.tabs = {}
	self.groups = {}
	self.flags = {}
	self.listOrder = 0
	self.notifCounter = 0
	self.notifQueue = {}
	self.animToken = 0
	self.minToken = 0
	self.baseScale = 1
	self.visible = config.Visible ~= false
	self.minimized = false
	self.mainAlive = true
	self.destroyed = false
	self.isTouch = UserInputService.TouchEnabled
	self.rowHeight = self.isTouch and 36 or 30
	self.tabHeight = self.isTouch and 38 or 32
	self.closeAction = config.CloseAction == "Hide" and "Hide" or "Destroy"
	self.onClose = config.OnClose
	self.toggleKey = config.ToggleKey

	self.title = tostring(config.Title or "NOVA UI")
	self.subtitle = tostring(config.Subtitle or "")
	self.footerText = tostring(config.Footer or "NOVA UI")

	-- Tema e transparencia (validados)
	self.theme = copy(DEFAULT_THEME)
	self.transparency = copy(DEFAULT_TRANSPARENCY)
	if type(config.Theme) == "table" then
		for k, v in pairs(config.Theme) do
			if DEFAULT_THEME[k] ~= nil and isColor(v) then
				self.theme[k] = v
			else
				warnf("Theme.%s ignorado (chave desconhecida ou valor nao e Color3).", tostring(k))
			end
		end
	end
	if type(config.Transparency) == "table" then
		for k, v in pairs(config.Transparency) do
			if DEFAULT_TRANSPARENCY[k] ~= nil and type(v) == "number" then
				self.transparency[k] = clampNumber(v, 0, 1, DEFAULT_TRANSPARENCY[k])
			else
				warnf("Transparency.%s ignorado (chave desconhecida ou valor nao numerico).", tostring(k))
			end
		end
	end

	-- Atalhos de configuracao do botao flutuante
	local floatCfg = merge({ Enabled = true }, config.FloatingButton)
	if isColor(floatCfg.BackgroundColor) then
		self.theme.FloatingButton = floatCfg.BackgroundColor
	end
	local iconColor = isColor(floatCfg.IconColor) and floatCfg.IconColor or (isColor(floatCfg.TextColor) and floatCfg.TextColor or nil)
	if iconColor then
		self.theme.FloatingText = iconColor
	end
	if type(floatCfg.BackgroundTransparency) == "number" then
		self.transparency.FloatingButton = clampNumber(floatCfg.BackgroundTransparency, 0, 1, 0)
	end
	self.floatCfg = floatCfg

	-- Dimensoes
	self.minWidth = clampNumber(tonumber(config.MinWidth), 300, 2000, 380)
	self.minHeight = clampNumber(tonumber(config.MinHeight), 160, 2000, 240)
	self.maxWidth = math.max(self.minWidth, clampNumber(tonumber(config.MaxWidth), 300, 3000, 1000))
	self.maxHeight = math.max(self.minHeight, clampNumber(tonumber(config.MaxHeight), 160, 3000, 800))
	self.width = clampNumber(tonumber(config.Width), self.minWidth, self.maxWidth, 590)
	self.height = clampNumber(tonumber(config.Height), self.minHeight, self.maxHeight, 390)
	self.sidebarWidth = math.floor(
		math.clamp(clampNumber(tonumber(config.SidebarWidth), 110, 400, 150), 110, math.floor(self.width * 0.45))
	)
	self.posX = 0.5
	self.posY = nil

	self:_buildLayer(floatCfg)
	self:_buildMain(config)
	self:_updateScale()
	if self.visible then
		self.rootScale.Scale = self.baseScale
	end
	return self
end

--------------------------------------------------------------------------------
-- Visibilidade, minimizar, fechar
--------------------------------------------------------------------------------
function NovaUI:Show()
	if not self.mainAlive then
		return false
	end
	self.visible = true
	self.animToken = self.animToken + 1
	self.root.Visible = true
	self.rootScale.Scale = self.baseScale * 0.92
	tween(self.rootScale, { Scale = self.baseScale }, 0.16)
	self:_applyPosition()
	return true
end

function NovaUI:Hide()
	if not self.mainAlive or not self.visible then
		return false
	end
	self.visible = false
	self.animToken = self.animToken + 1
	local token = self.animToken
	self:_closeOverlays()
	tween(self.rootScale, { Scale = self.baseScale * 0.92 }, 0.12)
	task.delay(0.13, function()
		if self.mainAlive and token == self.animToken and not self.visible then
			self.root.Visible = false
			self.rootScale.Scale = self.baseScale
		end
	end)
	return true
end

function NovaUI:Toggle()
	if self.destroyed then
		return
	end
	self:_pulseFloat()
	if not self.mainAlive then
		safeCall(self.floatCfg.OnClickWhenClosed)
		return
	end
	if self.visible then
		self:Hide()
	else
		self:Show()
	end
end

function NovaUI:IsVisible()
	return self.mainAlive and self.visible
end

function NovaUI:IsMinimized()
	return self.mainAlive and self.minimized
end

function NovaUI:IsDestroyed()
	return self.destroyed
end

function NovaUI:IsClosed()
	return not self.mainAlive
end

function NovaUI:_updateMinIcon()
	self.minBar.Visible = not self.minimized
	self.minSquare.Visible = self.minimized
end

function NovaUI:Minimize()
	if not self.mainAlive or self.minimized then
		return false
	end
	self:_closeOverlays()
	self.minimized = true
	self.minToken = self.minToken + 1
	local token = self.minToken
	self:_updateMinIcon()
	tween(self.root, { Size = UDim2.fromOffset(self.width, HEADER_HEIGHT) }, 0.2)
	task.delay(0.21, function()
		if self.mainAlive and self.minimized and token == self.minToken then
			self.body.Visible = false
			self.footer.Visible = false
			self.headerFill.Visible = false
		end
	end)
	self:_applyPosition()
	return true
end

function NovaUI:Restore()
	if not self.mainAlive or not self.minimized then
		return false
	end
	self.minimized = false
	self.minToken = self.minToken + 1
	self.body.Visible = true
	self.footer.Visible = true
	self.headerFill.Visible = true
	self:_updateMinIcon()
	tween(self.root, { Size = UDim2.fromOffset(self.width, self.height) }, 0.2)
	self:_applyPosition()
	return true
end

-- Fecha somente a janela principal (o botao flutuante continua existindo)
function NovaUI:_closeMain()
	if not self.mainAlive then
		return
	end
	self.mainAlive = false
	self.activeClose = nil
	dropDrags(self.activeDrags)
	maidClean(self.maid)
	self.tabs = {}
	self.groups = {}
	self.currentTab = nil
	self.root, self.mainGui, self.body, self.footer = nil, nil, nil, nil
	self.dropList, self.tooltip, self.blocker = nil, nil, nil
	if self.onClose then
		safeCall(self.onClose)
	end
end

function NovaUI:Destroy()
	if self.destroyed then
		return
	end
	self:_closeMain()
	self.destroyed = true
	dropDrags(self.layerDrags)
	maidClean(self.layerMaid)
	self.themed = {}
	self.flags = {}
	self.floatContainer = nil
	self.floatScale = nil
	self.notifHolder = nil
end

function NovaUI:SetFloatingButtonVisible(visible)
	if self.floatContainer and self.floatContainer.Parent then
		self.floatContainer.Visible = visible ~= false
	end
end

--------------------------------------------------------------------------------
-- Tema / transparencia / textos
--------------------------------------------------------------------------------
function NovaUI:SetTheme(newTheme)
	if self.destroyed or type(newTheme) ~= "table" then
		return false
	end
	self:_closeOverlays()
	for k, v in pairs(newTheme) do
		if DEFAULT_THEME[k] ~= nil and isColor(v) then
			self.theme[k] = v
		else
			warnf("SetTheme: '%s' ignorado (chave desconhecida ou valor nao e Color3).", tostring(k))
		end
	end
	self:_applyTheme()
	return true
end

function NovaUI:GetTheme()
	return copy(self.theme)
end

function NovaUI:SetTransparency(values)
	if self.destroyed or type(values) ~= "table" then
		return false
	end
	for k, v in pairs(values) do
		if DEFAULT_TRANSPARENCY[k] ~= nil and type(v) == "number" then
			self.transparency[k] = clampNumber(v, 0, 1, DEFAULT_TRANSPARENCY[k])
		else
			warnf("SetTransparency: '%s' ignorado (chave desconhecida ou valor nao numerico).", tostring(k))
		end
	end
	self:_applyTheme()
	return true
end

function NovaUI:GetTransparency()
	return copy(self.transparency)
end

function NovaUI:SetTitle(text)
	self.title = tostring(text)
	if self.mainAlive then
		self.titleLabel.Text = self.title
	end
end

function NovaUI:SetSubtitle(text)
	self.subtitle = tostring(text)
	if self.mainAlive then
		self.subtitleLabel.Text = self.subtitle
		self.layoutTitle()
	end
end

function NovaUI:SetFooter(text)
	self.footerText = tostring(text)
	if self.mainAlive then
		self.footerLabel.Text = self.footerText
	end
end

--------------------------------------------------------------------------------
-- Notificacoes
--------------------------------------------------------------------------------
function NovaUI:Notify(opts)
	if self.destroyed or not self.notifHolder then
		return nil
	end
	if type(opts) == "string" then
		opts = { Content = opts }
	end
	if type(opts) ~= "table" then
		return nil
	end
	local kind = string.lower(tostring(opts.Type or "info"))
	local colorKey = "Accent"
	if kind == "success" then
		colorKey = "Success"
	elseif kind == "warning" then
		colorKey = "Warning"
	elseif kind == "error" then
		colorKey = "Error"
	end
	local duration = clampNumber(tonumber(opts.Duration), 1, 30, 4)

	self.notifCounter = self.notifCounter + 1
	local wrapper = create("Frame", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self.notifCounter,
		Parent = self.notifHolder,
	})
	local card = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 290, 0, 0),
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Parent = wrapper,
	})
	corner(card, 8)
	local stroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = card,
	})
	local inner = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	})
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = inner,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = inner,
	})
	local titleText = opts.Title ~= nil and tostring(opts.Title) or ""
	local title = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = titleText,
		Font = FONT_BOLD,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = titleText ~= "",
		LayoutOrder = 1,
		Parent = inner,
	})
	local contentText = opts.Content ~= nil and tostring(opts.Content) or ""
	local contentLabel = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = contentText,
		Font = FONT,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = contentText ~= "",
		LayoutOrder = 2,
		Parent = inner,
	})
	self:_fn(card, function()
		card.BackgroundColor3 = self.theme.Component
		card.BackgroundTransparency = self.transparency.Notifications
		stroke.Color = self.theme[colorKey]
		stroke.Transparency = 0.2
		title.TextColor3 = self.theme[colorKey]
		contentLabel.TextColor3 = self.theme.Text
	end)

	local entry = { done = false }
	local function dismiss()
		if entry.done then
			return
		end
		entry.done = true
		tween(card, { Position = UDim2.new(0, 290, 0, 0) }, 0.2)
		task.delay(0.22, function()
			if wrapper.Parent ~= nil then
				wrapper:Destroy()
			end
		end)
	end
	entry.fn = dismiss
	card.Activated:Connect(dismiss)
	tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.25, Enum.EasingStyle.Back)
	task.delay(duration, dismiss)

	table.insert(self.notifQueue, entry)
	local active = {}
	for _, e in ipairs(self.notifQueue) do
		if not e.done then
			table.insert(active, e)
		end
	end
	self.notifQueue = active
	while #self.notifQueue > 5 do
		local oldest = table.remove(self.notifQueue, 1)
		oldest.fn()
	end
	return { Dismiss = dismiss }
end

--------------------------------------------------------------------------------
-- Persistencia opcional (somente se readfile/writefile existirem)
--------------------------------------------------------------------------------
function NovaUI:SaveConfig(name)
	local writeFile = envFunc("writefile")
	if not writeFile then
		return false, "writefile indisponivel neste ambiente"
	end
	local data = {}
	for flag, comp in pairs(self.flags) do
		data[flag] = comp:Get()
	end
	local okEnc, encoded = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not okEnc then
		return false, tostring(encoded)
	end
	local makeFolder = envFunc("makefolder")
	if makeFolder then
		pcall(makeFolder, "NovaUI")
		pcall(makeFolder, "NovaUI/configs")
	end
	local okWrite, err = pcall(writeFile, "NovaUI/configs/" .. tostring(name or "default") .. ".json", encoded)
	if not okWrite then
		return false, tostring(err)
	end
	return true
end

function NovaUI:LoadConfig(name)
	local readFile = envFunc("readfile")
	local isFile = envFunc("isfile")
	if not readFile then
		return false, "readfile indisponivel neste ambiente"
	end
	local path = "NovaUI/configs/" .. tostring(name or "default") .. ".json"
	if isFile and not isFile(path) then
		return false, "arquivo nao encontrado"
	end
	local okRead, raw = pcall(readFile, path)
	if not okRead then
		return false, tostring(raw)
	end
	local okDec, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not okDec or type(data) ~= "table" then
		return false, "JSON invalido"
	end
	for flag, value in pairs(data) do
		local comp = self.flags[flag]
		if comp then
			pcall(function()
				comp:Set(value)
			end)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Abas, grupos e pesquisa
--------------------------------------------------------------------------------
function NovaUI:_filterTabs(query)
	query = string.lower(tostring(query or ""))
	local anyVisible = false
	for _, tab in ipairs(self.tabs) do
		local match = query == "" or string.find(string.lower(tab.name), query, 1, true) ~= nil
		tab._button.Visible = match
		if match then
			anyVisible = true
		end
	end
	for _, group in ipairs(self.groups) do
		group.Visible = query == ""
	end
	self.noResults.Visible = (not anyVisible) and #self.tabs > 0
end

function NovaUI:AddTabGroup(title)
	if not self.mainAlive then
		error("[NovaUI] A janela principal ja foi fechada.", 2)
	end
	self.listOrder = self.listOrder + 1
	local label = create("TextLabel", {
		Name = "Group",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = tostring(title or ""),
		Font = FONT_BOLD,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = self.listOrder,
		Parent = self.tabList,
	})
	create("UIPadding", { PaddingLeft = UDim.new(0, 4), Parent = label })
	self:_color(label, "TextColor3", "MutedText")
	table.insert(self.groups, label)
	return label
end

function NovaUI:AddTab(name, options)
	if not self.mainAlive then
		error("[NovaUI] A janela principal ja foi fechada.", 2)
	end
	options = type(options) == "table" and options or {}
	name = tostring(name or "Aba")

	local tab = setmetatable({ _win = self, name = name, order = 0 }, TabMT)
	self.listOrder = self.listOrder + 1

	local button = create("TextButton", {
		Name = "Tab_" .. name,
		Size = UDim2.new(1, 0, 0, self.tabHeight),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = self.listOrder,
		Parent = self.tabList,
	})
	corner(button, 6)
	local indicator = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(3, 16),
		BorderSizePixel = 0,
		Visible = false,
		Parent = button,
	})
	corner(indicator, 2)

	local textX = 12
	local iconObj
	if options.Icon ~= nil and tostring(options.Icon) ~= "" then
		local iconStr = tostring(options.Icon)
		if iconStr:match("^rbxassetid://") or iconStr:match("^%d+$") then
			iconObj = create("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				Image = iconStr:match("^%d+$") and ("rbxassetid://" .. iconStr) or iconStr,
				Parent = button,
			})
		else
			iconObj = create("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(18, 18),
				BackgroundTransparency = 1,
				Text = iconStr,
				Font = FONT_BOLD,
				TextSize = 14,
				Parent = button,
			})
		end
		textX = 36
	end
	local text = create("TextLabel", {
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -(textX + 6), 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = FONT_MEDIUM,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})

	local hovered = false
	local function refresh(animate)
		local t = self.theme
		local selected = self.currentTab == tab
		self:_set(button, {
			BackgroundColor3 = t.Component,
			BackgroundTransparency = selected and self.transparency.Components or (hovered and 0.6 or 1),
		}, animate, 0.12)
		indicator.BackgroundColor3 = t.Accent
		indicator.Visible = selected
		self:_set(text, { TextColor3 = selected and t.Text or t.MutedText }, animate, 0.12)
		if iconObj then
			if iconObj:IsA("TextLabel") then
				iconObj.TextColor3 = selected and t.Accent or t.MutedText
			else
				iconObj.ImageColor3 = selected and t.Accent or t.MutedText
			end
		end
	end
	self:_fn(button, function()
		refresh(false)
	end)
	button.MouseEnter:Connect(function()
		hovered = true
		refresh(true)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		refresh(true)
	end)
	button.Activated:Connect(function()
		tab:Select()
	end)

	local page = create("ScrollingFrame", {
		Name = "Page_" .. name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = self.isTouch and 5 or 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = self.content,
	})
	self:_color(page, "ScrollBarImageColor3", "Accent")
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = page,
	})
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = page,
	})
	page:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if self.activeClose then
			self:_closeOverlays()
		end
	end)

	tab._button = button
	tab._text = text
	tab._page = page
	tab._container = page
	tab._refresh = refresh

	table.insert(self.tabs, tab)
	if self.searchBox and self.searchBox.Text ~= "" then
		self:_filterTabs(self.searchBox.Text)
	end
	if not self.currentTab then
		tab:Select()
	else
		refresh(false)
	end
	return tab
end

function NovaUI:SelectTab(target)
	if not self.mainAlive then
		return false
	end
	if type(target) == "table" and target._page then
		target:Select()
		return true
	end
	for _, tab in ipairs(self.tabs) do
		if tab.name == target then
			tab:Select()
			return true
		end
	end
	return false
end

function NovaUI:GetTab(name)
	for _, tab in ipairs(self.tabs) do
		if tab.name == name then
			return tab
		end
	end
	return nil
end

function TabMethods:Select()
	local win = self._win
	if not win.mainAlive or win.currentTab == self then
		return
	end
	win:_closeOverlays()
	local previous = win.currentTab
	win.currentTab = self
	if previous then
		previous._page.Visible = false
	end
	self._page.Visible = true
	win.tabNameLabel.Text = self.name
	for _, tab in ipairs(win.tabs) do
		tab._refresh(true)
	end
end

function TabMethods:SetName(newName)
	self.name = tostring(newName)
	self._text.Text = self.name
	if self._win.currentTab == self then
		self._win.tabNameLabel.Text = self.name
	end
end

function TabMethods:GetName()
	return self.name
end

--------------------------------------------------------------------------------
-- Componentes (compartilhados por Tab e Section)
--------------------------------------------------------------------------------
function HostMethods:_nextOrder()
	self.order = self.order + 1
	return self.order
end

local function normalizeCfg(cfg, defaultName)
	if type(cfg) == "string" then
		return { Name = cfg }
	end
	if type(cfg) ~= "table" then
		return { Name = defaultName }
	end
	return cfg
end

-- Section ---------------------------------------------------------------------
function HostMethods:AddSection(cfg)
	cfg = normalizeCfg(cfg, "Secao")
	local win = self._win
	local name = tostring(cfg.Name or "Secao")

	local card = create("Frame", {
		Name = "Section",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = self:_nextOrder(),
	})
	corner(card, 8)
	local stroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = card,
	})
	win:_bg(card, "Sidebar", "Components")
	win:_stroke(stroke, "Border")
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = card,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = card,
	})

	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Parent = card,
	})
	local title = create("TextLabel", {
		Size = UDim2.new(1, -56, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = FONT_BOLD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	win:_color(title, "TextColor3", "Text")

	local section = setmetatable({
		_win = win,
		_container = card,
		_page = self._page,
		_title = title,
		order = 0,
		name = name,
	}, SectionMT)

	if type(cfg.Toggle) == "table" then
		local tcfg = cfg.Toggle
		local state = tcfg.Default == true
		local update = buildSwitch(win, header, tcfg.Style, 2)
		local function refresh(animate)
			update(state, true, animate)
		end
		win:_fn(header, function()
			refresh(false)
		end)
		local hit = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 56, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = header,
		})
		local api = {}
		function api:Set(value, silent)
			value = value == true
			if value == state then
				return
			end
			state = value
			refresh(true)
			if not silent then
				safeCall(tcfg.Callback, state)
			end
		end
		function api:Get()
			return state
		end
		hit.Activated:Connect(function()
			api:Set(not state)
		end)
		if tcfg.Flag then
			win.flags[tcfg.Flag] = api
		end
		section.HeaderToggle = api
	end

	card.Parent = self._container
	return section
end

function SectionMethods:SetName(newName)
	self.name = tostring(newName)
	self._title.Text = self.name
end

function SectionMethods:Destroy()
	self._container:Destroy()
end

-- Toggle ----------------------------------------------------------------------
function HostMethods:AddToggle(cfg)
	cfg = normalizeCfg(cfg, "Toggle")
	local win = self._win
	local name = tostring(cfg.Name or "Toggle")
	local state = cfg.Default == true
	local enabled = cfg.Disabled ~= true
	local callback = cfg.Callback
	local tip = cfg.Tooltip

	local row = win:_newRow(self, win.rowHeight, true)
	local label = win:_newLabel(row, name, 13, "Text")
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(1, -64, 1, 0)
	local update = buildSwitch(win, row, cfg.Style, 10)

	local function refresh(animate)
		update(state, enabled, animate)
		label.TextTransparency = enabled and 0 or 0.55
	end
	win:_fn(row, function()
		refresh(false)
	end)

	local api = {}
	function api:Set(value, silent)
		value = value == true
		if value == state then
			return
		end
		state = value
		refresh(true)
		if not silent then
			safeCall(callback, state)
		end
	end
	function api:Get()
		return state
	end
	function api:SetEnabled(value)
		enabled = value ~= false
		refresh(false)
	end
	function api:IsEnabled()
		return enabled
	end
	function api:SetText(text)
		name = tostring(text)
		label.Text = name
	end
	function api:SetTooltip(text)
		tip = text
	end
	function api:SetVisible(value)
		row.Visible = value ~= false
	end
	function api:Destroy()
		row:Destroy()
	end

	row.Activated:Connect(function()
		if enabled then
			api:Set(not state)
		end
	end)
	win:_tooltip(row, function()
		return tip
	end)
	if cfg.Flag then
		win.flags[cfg.Flag] = api
	end
	row.Parent = self._container
	return api
end

-- Button ----------------------------------------------------------------------
function HostMethods:AddButton(cfg)
	cfg = normalizeCfg(cfg, "Botao")
	local win = self._win
	local name = tostring(cfg.Name or "Botao")
	local enabled = cfg.Disabled ~= true
	local callback = cfg.Callback
	local cooldown = clampNumber(tonumber(cfg.Cooldown), 0, 5, 0.2)
	local tip = cfg.Tooltip

	local btn = create("TextButton", {
		Name = "Button",
		Size = UDim2.new(1, 0, 0, win.rowHeight),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = FONT_MEDIUM,
		TextSize = 13,
		Text = name,
		LayoutOrder = self:_nextOrder(),
	})
	corner(btn, 6)

	local hovered, pressed = false, false
	local function refresh(animate)
		local t = win.theme
		local base = t.Button
		local color = base
		if enabled then
			if pressed then
				color = base:Lerp(Color3.new(0, 0, 0), 0.25)
			elseif hovered then
				color = base:Lerp(Color3.new(1, 1, 1), 0.12)
			end
		end
		local alpha = win.transparency.Buttons
		win:_set(btn, {
			BackgroundColor3 = color,
			BackgroundTransparency = enabled and alpha or math.clamp(alpha + 0.45, 0, 1),
			TextColor3 = t.ButtonText,
			TextTransparency = enabled and 0 or 0.5,
		}, animate, 0.1)
	end
	win:_fn(btn, function()
		refresh(false)
	end)
	btn.MouseEnter:Connect(function()
		hovered = true
		refresh(true)
	end)
	btn.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		refresh(true)
	end)
	btn.MouseButton1Down:Connect(function()
		pressed = true
		refresh(true)
	end)
	btn.MouseButton1Up:Connect(function()
		pressed = false
		refresh(true)
	end)

	local lastClick = 0
	local api = {}
	local function fire()
		if not enabled then
			return false
		end
		local now = os.clock()
		if now - lastClick < cooldown then
			return false
		end
		lastClick = now
		safeCall(callback)
		return true
	end
	btn.Activated:Connect(fire)

	function api:Fire()
		return fire()
	end
	function api:SetText(text)
		name = tostring(text)
		btn.Text = name
	end
	function api:GetText()
		return name
	end
	function api:SetEnabled(value)
		enabled = value ~= false
		refresh(false)
	end
	function api:IsEnabled()
		return enabled
	end
	function api:SetTooltip(text)
		tip = text
	end
	function api:SetVisible(value)
		btn.Visible = value ~= false
	end
	function api:Destroy()
		btn:Destroy()
	end

	win:_tooltip(btn, function()
		return tip
	end)
	btn.Parent = self._container
	return api
end

-- Textbox ---------------------------------------------------------------------
function HostMethods:AddTextbox(cfg)
	cfg = normalizeCfg(cfg, "Texto")
	local win = self._win
	local name = tostring(cfg.Name or "Texto")
	local enabled = cfg.Disabled ~= true
	local callback = cfg.Callback
	local tip = cfg.Tooltip
	local maxLength = tonumber(cfg.MaxLength)

	local row = win:_newRow(self, win.rowHeight + 4, false)
	local label = win:_newLabel(row, name, 13, "Text")
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(0.4, -10, 1, 0)

	local box = create("TextBox", {
		Name = "Input",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.6, -14, 0, win.rowHeight - 4),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Text = cfg.Default ~= nil and tostring(cfg.Default) or "",
		PlaceholderText = tostring(cfg.Placeholder or ""),
		Font = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		Parent = row,
	})
	corner(box, 5)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = box,
	})
	local boxStroke = create("UIStroke", {
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = box,
	})

	local focused = false
	local function refresh(animate)
		local t = win.theme
		box.BackgroundColor3 = t.Background
		box.BackgroundTransparency = win.transparency.Components
		box.TextColor3 = t.Text
		box.PlaceholderColor3 = t.MutedText
		box.TextEditable = enabled
		box.TextTransparency = enabled and 0 or 0.5
		label.TextTransparency = enabled and 0 or 0.55
		boxStroke.Transparency = win.transparency.Borders
		win:_set(boxStroke, { Color = focused and t.Accent or t.Border }, animate, 0.12)
	end
	win:_fn(row, function()
		refresh(false)
	end)

	box.Focused:Connect(function()
		focused = true
		refresh(true)
	end)
	box.FocusLost:Connect(function(enterPressed)
		focused = false
		if maxLength and #box.Text > maxLength then
			box.Text = string.sub(box.Text, 1, maxLength)
		end
		refresh(true)
		safeCall(callback, box.Text, enterPressed)
	end)

	local api = {}
	function api:Set(text, silent)
		text = tostring(text == nil and "" or text)
		if maxLength and #text > maxLength then
			text = string.sub(text, 1, maxLength)
		end
		box.Text = text
		if not silent then
			safeCall(callback, text, false)
		end
	end
	function api:Get()
		return box.Text
	end
	function api:SetPlaceholder(text)
		box.PlaceholderText = tostring(text)
	end
	function api:SetText(text)
		name = tostring(text)
		label.Text = name
	end
	function api:SetEnabled(value)
		enabled = value ~= false
		refresh(false)
	end
	function api:IsEnabled()
		return enabled
	end
	function api:SetTooltip(text)
		tip = text
	end
	function api:SetVisible(value)
		row.Visible = value ~= false
	end
	function api:Destroy()
		row:Destroy()
	end

	win:_tooltip(row, function()
		return tip
	end)
	if cfg.Flag then
		win.flags[cfg.Flag] = api
	end
	row.Parent = self._container
	return api
end

-- Dropdown --------------------------------------------------------------------
local function cleanOptions(list)
	local out = {}
	if type(list) == "table" then
		for _, v in ipairs(list) do
			table.insert(out, tostring(v))
		end
	end
	return out
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

function HostMethods:AddDropdown(cfg)
	cfg = normalizeCfg(cfg, "Opcoes")
	local win = self._win
	local name = tostring(cfg.Name or "Opcoes")
	local enabled = cfg.Disabled ~= true
	local callback = cfg.Callback
	local tip = cfg.Tooltip
	local options = cleanOptions(cfg.Options)
	local selected = nil
	if cfg.Default ~= nil and indexOf(options, tostring(cfg.Default)) then
		selected = tostring(cfg.Default)
	end
	local isOpen = false
	local itemH = math.max(28, win.rowHeight - 2)

	local row = win:_newRow(self, win.rowHeight, true)
	local label = win:_newLabel(row, name, 13, "Text")
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(0.45, -10, 1, 0)
	local valueLabel = create("TextLabel", {
		Position = UDim2.new(0.45, 0, 0, 0),
		Size = UDim2.new(0.55, -34, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_MEDIUM,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = row,
	})
	local chevron = buildChevron(win, row)

	local function refresh()
		local t = win.theme
		label.TextTransparency = enabled and 0 or 0.55
		valueLabel.TextTransparency = enabled and 0 or 0.55
		if selected then
			valueLabel.Text = selected
			valueLabel.TextColor3 = t.Accent
		else
			valueLabel.Text = tostring(cfg.Placeholder or "Selecionar...")
			valueLabel.TextColor3 = t.MutedText
		end
	end
	win:_fn(row, refresh)

	local api = {}

	local function closeList()
		if not isOpen then
			return
		end
		isOpen = false
		if win.mainAlive and win.dropList then
			win.dropList.Visible = false
			win.blocker.Visible = false
		end
		tween(chevron, { Rotation = 0 }, 0.15)
		if win.activeClose == closeList then
			win.activeClose = nil
		end
	end

	local function buildOptions()
		for _, child in ipairs(win.dropList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local t = win.theme
		for i, opt in ipairs(options) do
			local isSel = opt == selected
			local ob = create("TextButton", {
				Name = "Option",
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, itemH),
				BackgroundColor3 = t.Accent,
				BackgroundTransparency = isSel and 0.82 or 1,
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Text = opt,
				Font = isSel and FONT_BOLD or FONT_MEDIUM,
				TextSize = 13,
				TextColor3 = isSel and t.Accent or t.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = win.dropList,
			})
			corner(ob, 5)
			create("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 8),
				Parent = ob,
			})
			ob.MouseEnter:Connect(function()
				if not isSel then
					ob.BackgroundTransparency = 0.9
				end
			end)
			ob.MouseLeave:Connect(function()
				if not isSel then
					ob.BackgroundTransparency = 1
				end
			end)
			ob.Activated:Connect(function()
				closeList()
				api:Set(opt)
			end)
		end
	end

	local function openList()
		if not enabled or #options == 0 or not win.mainAlive then
			return
		end
		win:_closeOverlays()
		buildOptions()
		local s = win.baseScale
		local vp = win:_viewport()
		local abs = row.AbsolutePosition
		local absSize = row.AbsoluteSize
		local contentH = (#options * itemH + (#options - 1) * 2 + 8)
		local desiredPx = math.min(contentH, itemH * 6 + 18) * s
		local widthPx = math.min(vp.X - 8, math.max(absSize.X * 0.55, 150 * s))
		local xPx = math.clamp(abs.X + absSize.X - widthPx - 2 * s, 4, math.max(4, vp.X - widthPx - 4))
		local gap = 4 * s
		local below = vp.Y - (abs.Y + absSize.Y + gap) - 6
		local above = abs.Y - gap - 6
		local yPx, hPx
		if desiredPx <= below then
			yPx, hPx = abs.Y + absSize.Y + gap, desiredPx
		elseif desiredPx <= above then
			yPx, hPx = abs.Y - gap - desiredPx, desiredPx
		elseif below >= above then
			hPx = math.max(below, 40 * s)
			yPx = abs.Y + absSize.Y + gap
		else
			hPx = math.max(above, 40 * s)
			yPx = abs.Y - gap - hPx
		end
		yPx = math.clamp(yPx, 4, math.max(4, vp.Y - hPx - 4))
		win.dropList.Position = UDim2.fromOffset(xPx, yPx)
		win.dropList.Size = UDim2.fromOffset(widthPx / s, hPx / s)
		win.dropList.CanvasPosition = Vector2.new(0, 0)
		win.dropList.Visible = true
		win.blocker.Visible = true
		isOpen = true
		win.activeClose = closeList
		tween(chevron, { Rotation = 180 }, 0.15)
	end

	row.Activated:Connect(function()
		if isOpen then
			win:_closeOverlays()
		else
			openList()
		end
	end)

	function api:Set(option, silent)
		if option == nil then
			selected = nil
			refresh()
			return
		end
		option = tostring(option)
		if not indexOf(options, option) then
			warnf("Dropdown '%s': a opcao '%s' nao existe na lista.", name, option)
			return
		end
		local changed = option ~= selected
		selected = option
		refresh()
		if changed and not silent then
			safeCall(callback, selected)
		end
	end
	function api:Get()
		return selected
	end
	function api:SetOptions(list, keepSelection)
		options = cleanOptions(list)
		if keepSelection == false or (selected ~= nil and not indexOf(options, selected)) then
			selected = nil
		end
		if isOpen then
			closeList()
		end
		refresh()
	end
	function api:GetOptions()
		return cleanOptions(options)
	end
	function api:SetText(text)
		name = tostring(text)
		label.Text = name
	end
	function api:SetEnabled(value)
		enabled = value ~= false
		if not enabled then
			closeList()
		end
		refresh()
	end
	function api:IsEnabled()
		return enabled
	end
	function api:SetTooltip(text)
		tip = text
	end
	function api:SetVisible(value)
		row.Visible = value ~= false
	end
	function api:Destroy()
		closeList()
		row:Destroy()
	end

	win:_tooltip(row, function()
		return tip
	end)
	if cfg.Flag then
		win.flags[cfg.Flag] = api
	end
	row.Parent = self._container
	return api
end

-- Slider ----------------------------------------------------------------------
function HostMethods:AddSlider(cfg)
	cfg = normalizeCfg(cfg, "Slider")
	local win = self._win
	local name = tostring(cfg.Name or "Slider")
	local enabled = cfg.Disabled ~= true
	local callback = cfg.Callback
	local tip = cfg.Tooltip
	local suffix = cfg.Suffix ~= nil and tostring(cfg.Suffix) or ""

	local min = tonumber(cfg.Min) or 0
	local max = tonumber(cfg.Max) or 100
	if min > max then
		warnf("Slider '%s': Min maior que Max; valores invertidos.", name)
		min, max = max, min
	elseif min == max then
		warnf("Slider '%s': Min igual a Max; Max ajustado para Min + 1.", name)
		max = min + 1
	end
	local increment = tonumber(cfg.Increment)
	if increment ~= nil and increment <= 0 then
		increment = nil
	end
	local decimals = tonumber(cfg.Decimals)
	if decimals == nil then
		decimals = increment and countDecimals(increment) or 0
	end
	decimals = math.clamp(math.floor(decimals), 0, 6)
	local mult = 10 ^ decimals

	local function snap(v)
		v = math.clamp(v, min, max)
		if increment then
			v = min + math.floor((v - min) / increment + 0.5) * increment
		end
		v = math.clamp(v, min, max)
		return math.floor(v * mult + 0.5) / mult
	end

	local value = snap(tonumber(cfg.Default) or min)

	local height = win.rowHeight + 14
	local row = win:_newRow(self, height, false)
	local label = win:_newLabel(row, name, 13, "Text")
	label.Position = UDim2.fromOffset(10, 5)
	label.Size = UDim2.new(0.6, -10, 0, 16)
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 5),
		Size = UDim2.new(0.4, -10, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_MEDIUM,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = row,
	})

	local hit = create("TextButton", {
		Name = "Hit",
		Position = UDim2.new(0, 10, 0, height - 24),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	local bar = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 6),
		BorderSizePixel = 0,
		Parent = hit,
	})
	corner(bar, 3)
	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0,
		Parent = bar,
	})
	corner(fill, 3)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = bar,
	})
	corner(knob, 7)

	local function formatValue(v)
		return string.format("%." .. decimals .. "f", v) .. suffix
	end
	local function refresh()
		local t = win.theme
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = formatValue(value)
		bar.BackgroundColor3 = t.ToggleOff
		fill.BackgroundColor3 = t.Accent
		valueLabel.TextColor3 = t.MutedText
		local dim = enabled and 0 or 0.55
		label.TextTransparency = dim
		valueLabel.TextTransparency = dim
		bar.BackgroundTransparency = enabled and 0 or 0.5
		fill.BackgroundTransparency = enabled and 0 or 0.5
		knob.BackgroundTransparency = enabled and 0 or 0.4
	end
	win:_fn(row, refresh)

	local api = {}
	local function setValue(v, silent)
		v = snap(v)
		if v == value then
			return
		end
		value = v
		refresh()
		if not silent then
			safeCall(callback, value)
		end
	end

	local function updateFromX(x)
		local width = bar.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
		setValue(min + (max - min) * alpha)
	end

	hit.InputBegan:Connect(function(input)
		if not enabled or not isPress(input) then
			return
		end
		win:_closeOverlays()
		local page = self._page
		local previousScroll = page and page.ScrollingEnabled
		if page then
			page.ScrollingEnabled = false
		end
		updateFromX(input.Position.X)
		trackDrag(win.activeDrags, input, function(pos)
			updateFromX(pos.X)
		end, function()
			if page and page.Parent ~= nil and previousScroll ~= nil then
				page.ScrollingEnabled = previousScroll
			end
		end)
	end)

	function api:Set(v, silent)
		v = tonumber(v)
		if v == nil then
			warnf("Slider '%s': valor invalido em Set.", name)
			return
		end
		setValue(v, silent)
	end
	function api:Get()
		return value
	end
	function api:SetRange(newMin, newMax)
		newMin, newMax = tonumber(newMin), tonumber(newMax)
		if newMin == nil or newMax == nil then
			warnf("Slider '%s': intervalo invalido em SetRange.", name)
			return
		end
		if newMin > newMax then
			newMin, newMax = newMax, newMin
		elseif newMin == newMax then
			newMax = newMin + 1
		end
		min, max = newMin, newMax
		value = snap(value)
		refresh()
	end
	function api:SetText(text)
		name = tostring(text)
		label.Text = name
	end
	function api:SetEnabled(v)
		enabled = v ~= false
		refresh()
	end
	function api:IsEnabled()
		return enabled
	end
	function api:SetTooltip(text)
		tip = text
	end
	function api:SetVisible(v)
		row.Visible = v ~= false
	end
	function api:Destroy()
		row:Destroy()
	end

	win:_tooltip(row, function()
		return tip
	end)
	if cfg.Flag then
		win.flags[cfg.Flag] = api
	end
	row.Parent = self._container
	return api
end

-- Label -----------------------------------------------------------------------
function HostMethods:AddLabel(cfg)
	cfg = normalizeCfg(cfg, "Label")
	local win = self._win
	local name = tostring(cfg.Name or "")
	local desc = cfg.Description ~= nil and tostring(cfg.Description) or ""

	local holder = create("Frame", {
		Name = "Label",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self:_nextOrder(),
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = holder,
	})
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 2),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
		Parent = holder,
	})
	local title = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = name,
		Font = FONT_MEDIUM,
		TextSize = math.floor(clampNumber(tonumber(cfg.Size), 10, 24, 13)),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 1,
		Parent = holder,
	})
	win:_color(title, "TextColor3", cfg.Muted and "MutedText" or "Text")
	local descLabel = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = desc,
		Font = FONT,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = desc ~= "",
		LayoutOrder = 2,
		Parent = holder,
	})
	win:_color(descLabel, "TextColor3", "MutedText")

	local api = {}
	function api:Set(text)
		name = tostring(text)
		title.Text = name
	end
	function api:Get()
		return name
	end
	function api:SetText(text)
		api:Set(text)
	end
	function api:SetDescription(text)
		desc = tostring(text or "")
		descLabel.Text = desc
		descLabel.Visible = desc ~= ""
	end
	function api:SetVisible(v)
		holder.Visible = v ~= false
	end
	function api:Destroy()
		holder:Destroy()
	end

	holder.Parent = self._container
	return api
end

-- Separator -------------------------------------------------------------------
function HostMethods:AddSeparator(cfg)
	cfg = normalizeCfg(cfg, "")
	local win = self._win
	local name = cfg.Name ~= nil and tostring(cfg.Name) or ""
	local holder = create("Frame", {
		Name = "Separator",
		Size = UDim2.new(1, 0, 0, name ~= "" and 22 or 8),
		BackgroundTransparency = 1,
		LayoutOrder = self:_nextOrder(),
	})
	if name ~= "" then
		local label = create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = name,
			Font = FONT_BOLD,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = holder,
		})
		win:_color(label, "TextColor3", "MutedText")
	end
	local line = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = name ~= "" and UDim2.new(0, 0, 0, 19) or UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		Parent = holder,
	})
	win:_bg(line, "Border")

	local api = {}
	function api:SetVisible(v)
		holder.Visible = v ~= false
	end
	function api:Destroy()
		holder:Destroy()
	end
	holder.Parent = self._container
	return api
end

-- Copia os metodos de componentes para Tab e Section
for k, v in pairs(HostMethods) do
	TabMethods[k] = v
	SectionMethods[k] = v
end

return NovaUI
