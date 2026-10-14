--[[
	NOVA UI 1.0 — biblioteca de interface para Roblox (Luau)
	Coloque como ModuleScript e use com require() a partir de um LocalScript.

	API principal
		local Window = NovaUI.new({Title, Subtitle, Width, Height, Theme, Parent, Name,
			ToggleKey, Persistence, OnClose, DisplayOrder})
		local Tab = Window:AddTab("Nome") | Window:AddTab({Name, Icon, Description})
		Tab:AddToggle / AddButton / AddTextbox / AddDropdown / AddSlider / AddLabel / AddSeparator
		Window:Notify / Minimize / Restore / ToggleMinimize / Show / Hide / SetTitle /
		       SetSubtitle / SelectTab / GetTab / SaveConfig / LoadConfig / Destroy
	Todo elemento (exceto Label/Separator) possui: Get, Set(valor, silencioso), SetDisabled,
	SetName, SetDescription, SetVisible, Destroy.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local NovaUI = {}
NovaUI.Version = "1.0"

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local TOP_H = 56 -- altura da barra superior
local SIDEBAR_W = 142 -- largura da barra lateral
local MIN_SCALE = 0.7 -- menor escala automática (telas pequenas)

local DefaultTheme = {
	Background = Color3.fromRGB(7, 13, 28),
	Sidebar = Color3.fromRGB(9, 17, 36),
	Panel = Color3.fromRGB(13, 24, 48),
	PanelHover = Color3.fromRGB(18, 33, 66),
	Control = Color3.fromRGB(9, 18, 40),
	Stroke = Color3.fromRGB(28, 48, 92),
	Accent = Color3.fromRGB(28, 121, 255),
	AccentDark = Color3.fromRGB(16, 74, 176),
	AccentLight = Color3.fromRGB(96, 165, 255),
	Text = Color3.fromRGB(245, 248, 255),
	SubText = Color3.fromRGB(139, 158, 198),
	Off = Color3.fromRGB(38, 52, 84),
	Success = Color3.fromRGB(46, 204, 113),
	Warning = Color3.fromRGB(255, 184, 46),
	Error = Color3.fromRGB(255, 82, 82),
}

----------------------------------------------------------------------
-- Funções auxiliares
----------------------------------------------------------------------

local clamp = math.clamp

local function create(className, props, children)
	local inst = Instance.new(className)
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function padding(parent, top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		Parent = parent,
	})
end

local function tween(inst, props, duration, style, direction)
	local info = TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

local function sanitize(text)
	return (tostring(text):gsub("[^%w_]", ""))
end

local function toHex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function richTitle(title, accent)
	local safe = title:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	local head, last = safe:match("^(.*)%s(%S+)$")
	if head then
		return string.format('%s <font color="%s">%s</font>', head, toHex(accent), last)
	end
	return safe
end

local function countDecimals(number)
	local text = string.format("%.6f", number):gsub("0+$", "")
	local decimals = text:match("%.(%d*)$")
	return decimals and #decimals or 0
end

local function buildTheme(custom)
	local theme = {}
	for key, value in pairs(DefaultTheme) do
		theme[key] = value
	end
	if type(custom) == "table" then
		for key, value in pairs(custom) do
			if DefaultTheme[key] ~= nil and typeof(value) == "Color3" then
				theme[key] = value
			else
				warn("[NovaUI] Cor de tema inválida ignorada: " .. tostring(key))
			end
		end
	end
	return theme
end

local function prep(cfg, method)
	if type(cfg) == "string" then
		cfg = { Name = cfg }
	end
	if type(cfg) ~= "table" then
		error(("[NovaUI] %s espera uma tabela de configuração."):format(method), 3)
	end
	local copy = table.clone(cfg)
	copy.Name = tostring(copy.Name or "Sem nome")
	return copy
end

local function alive(window)
	if window._destroyed then
		error("[NovaUI] A janela já foi destruída.", 3)
	end
end

local function safeCall(window, label, fn, ...)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[NovaUI] Erro no callback '%s': %s"):format(tostring(label), tostring(err)))
		if window and not window._destroyed then
			window:Notify({ Title = "Erro no callback", Content = tostring(label), Type = "Error" })
		end
	end
end

local function makeIcon(parent, icon, color, textSize)
	icon = tostring(icon or "")
	if icon:sub(1, 6) == "rbxass" then
		local image = create("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = icon,
			ImageColor3 = color,
			Parent = parent,
		})
		return function(c) image.ImageColor3 = c end
	end
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = icon,
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = textSize or 15,
		Parent = parent,
	})
	return function(c) label.TextColor3 = c end
end

local function resolveParent(custom)
	if typeof(custom) == "Instance" then
		return custom
	end
	local player = Players.LocalPlayer
	if player then
		local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
		if playerGui then
			return playerGui
		end
	end
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok then
		return coreGui
	end
	return nil
end

-- Persistência: só existe se o ambiente oferecer writefile/readfile/isfile.
local function detectFileSystem()
	local ok, env = pcall(getfenv)
	if not ok or type(env) ~= "table" then
		return nil
	end
	local writeFn, readFn, isFileFn = env.writefile, env.readfile, env.isfile
	if type(writeFn) == "function" and type(readFn) == "function" and type(isFileFn) == "function" then
		return {
			writefile = writeFn,
			readfile = readFn,
			isfile = isFileFn,
			isfolder = type(env.isfolder) == "function" and env.isfolder or nil,
			makefolder = type(env.makefolder) == "function" and env.makefolder or nil,
		}
	end
	return nil
end

----------------------------------------------------------------------
-- Janela
----------------------------------------------------------------------

function Window:_connect(signal, fn)
	local connection = signal:Connect(fn)
	table.insert(self._connections, connection)
	return connection
end

function Window:_nextId()
	self._ids += 1
	return self._ids
end

function Window:_register(flag, element)
	if self.Flags[flag] then
		warn("[NovaUI] Flag duplicada, a anterior foi substituída: " .. tostring(flag))
	end
	self.Flags[flag] = element
end

function Window:_initial(cfg, default, validate)
	if cfg.Flag and self._persist then
		local saved = self._saved[cfg.Flag]
		if saved ~= nil and validate(saved) then
			return saved, true
		end
	end
	return default, false
end

function Window:_markDirty()
	if not self._persist then
		return
	end
	self._dirty = true
	if self._saveQueued then
		return
	end
	self._saveQueued = true
	task.delay(0.6, function()
		self._saveQueued = false
		if not self._destroyed and self._dirty then
			self:SaveConfig()
		end
	end)
end

function Window:SaveConfig()
	if not self._persist then
		return false, "Persistência indisponível neste ambiente"
	end
	local data = {}
	for flag, element in pairs(self.Flags) do
		local ok, value = pcall(function()
			return element:Get()
		end)
		if ok and value ~= nil then
			data[flag] = value
		end
	end
	local ok, err = pcall(function()
		local fs = self._fs
		if fs.isfolder and fs.makefolder and not fs.isfolder(self._folder) then
			fs.makefolder(self._folder)
		end
		fs.writefile(self._file, HttpService:JSONEncode(data))
	end)
	if ok then
		self._dirty = false
		return true
	end
	warn("[NovaUI] Falha ao salvar configuração: " .. tostring(err))
	return false, tostring(err)
end

function Window:LoadConfig()
	if not self._persist then
		return false, "Persistência indisponível neste ambiente"
	end
	local ok, data = pcall(function()
		if self._fs.isfile(self._file) then
			return HttpService:JSONDecode(self._fs.readfile(self._file))
		end
		return nil
	end)
	if not ok or type(data) ~= "table" then
		return false, "Arquivo não encontrado ou inválido"
	end
	self._saved = data
	for flag, element in pairs(self.Flags) do
		if data[flag] ~= nil then
			pcall(function()
				element:Set(data[flag])
			end)
		end
	end
	return true
end

function Window:_closeDropdown()
	local open = self._openDropdown
	if open then
		self._openDropdown = nil
		open.close()
	end
end

function Window:_updateLayout()
	if self._destroyed then
		return
	end
	local screen = self.Gui.AbsoluteSize
	if screen.X < 10 or screen.Y < 10 then
		return
	end
	local fit = math.min((screen.X - 16) / self._width, (screen.Y - 16) / self._height)
	local scale = clamp(fit, MIN_SCALE, 1)
	self._scale.Scale = scale
	self._notifScale.Scale = scale
	self._effW = math.max(300, math.min(self._width, math.floor((screen.X - 16) / scale)))
	self._effH = math.max(200, math.min(self._height, math.floor((screen.Y - 16) / scale)))
	if self._sizeTween then
		self._sizeTween:Cancel()
		self._sizeTween = nil
	end
	self._root.Size = UDim2.fromOffset(self._effW, self._minimized and TOP_H or self._effH)
	if self._dragged then
		local center = self._root.AbsolutePosition + self._root.AbsoluteSize / 2
		self._root.Position = UDim2.fromOffset(clamp(center.X, 40, screen.X - 40), clamp(center.Y, 28, screen.Y - 28))
	end
	self:_closeDropdown()
end

function Window:_refreshTitle()
	self._titleLabel.Text = richTitle(self._title, self.Theme.Accent)
	local hasSub = self._subtitle ~= ""
	self._subLabel.Text = self._subtitle
	self._subLabel.Visible = hasSub
	self._titleLabel.Position = UDim2.fromOffset(52, hasSub and 9 or 17)
end

function Window:SetTitle(title)
	alive(self)
	self._title = tostring(title)
	self:_refreshTitle()
end

function Window:SetSubtitle(subtitle)
	alive(self)
	self._subtitle = tostring(subtitle or "")
	self:_refreshTitle()
end

function Window:_applySearch()
	local query = string.lower(self._search.Text)
	query = query:gsub("^%s+", ""):gsub("%s+$", "")
	local visibleCount = 0
	for _, tab in ipairs(self._tabs) do
		local match = query == "" or string.find(string.lower(tab.Name), query, 1, true) ~= nil
		tab.Button.Visible = match
		if match then
			visibleCount += 1
		end
	end
	self._noResults.Visible = #self._tabs > 0 and visibleCount == 0
end

function Window:GetTab(name)
	for _, tab in ipairs(self._tabs) do
		if string.lower(tab.Name) == string.lower(tostring(name)) then
			return tab
		end
	end
	return nil
end

function Window:SelectTab(target)
	alive(self)
	local tab = target
	if type(target) == "string" then
		tab = self:GetTab(target)
	elseif type(target) == "number" then
		tab = self._tabs[target]
	end
	if type(tab) ~= "table" or not table.find(self._tabs, tab) then
		warn("[NovaUI] SelectTab: aba não encontrada.")
		return
	end
	self:_closeDropdown()
	for _, other in ipairs(self._tabs) do
		local selected = other == tab
		other.Page.Visible = selected
		other._setSelected(selected)
	end
	self._current = tab
	self._headerTitle.Text = tab.Name
	self._headerDesc.Text = tab.Description
	for _, child in ipairs(self._headerIconBox:GetChildren()) do
		child:Destroy()
	end
	makeIcon(self._headerIconBox, tab.Icon, self.Theme.AccentLight, 16)
end

function Window:Minimize()
	alive(self)
	if self._minimized then
		return
	end
	self._minimized = true
	self:_closeDropdown()
	self._minText.Text = "+"
	local tw = tween(self._root, { Size = UDim2.fromOffset(self._effW, TOP_H) }, 0.22)
	self._sizeTween = tw
	tw.Completed:Connect(function()
		if self._minimized and not self._destroyed and self._sizeTween == tw then
			self._body.Visible = false
		end
	end)
end

function Window:Restore()
	alive(self)
	if not self._minimized then
		return
	end
	self._minimized = false
	self._minText.Text = "–"
	self._body.Visible = true
	self._sizeTween = tween(self._root, { Size = UDim2.fromOffset(self._effW, self._effH) }, 0.22)
end

function Window:ToggleMinimize()
	if self._minimized then
		self:Restore()
	else
		self:Minimize()
	end
end

function Window:IsMinimized()
	return self._minimized
end

function Window:Show()
	alive(self)
	self._root.Visible = true
end

function Window:Hide()
	alive(self)
	self:_closeDropdown()
	self._root.Visible = false
end

function Window:Notify(opts)
	if self._destroyed then
		return
	end
	if type(opts) == "string" then
		opts = { Content = opts }
	end
	opts = type(opts) == "table" and opts or {}
	local T = self.Theme
	local colors = { Success = T.Success, Warning = T.Warning, Error = T.Error, Info = T.Accent }
	local color = colors[opts.Type or "Info"] or T.Accent
	local duration = clamp(tonumber(opts.Duration) or 4, 1, 30)

	local card = create("CanvasGroup", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Panel,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		LayoutOrder = self:_nextId(),
		Parent = self._notifHolder,
	})
	corner(card, 10)
	stroke(card, color, 1.5, 0.2)
	local inner = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = card,
	})
	padding(inner, 8, 12, 9, 12)
	create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
	create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = tostring(opts.Title or (opts.Type or "Info")),
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = inner,
	})
	if opts.Content and tostring(opts.Content) ~= "" then
		create("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = tostring(opts.Content),
			TextColor3 = T.Text,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = inner,
		})
	end
	tween(card, { GroupTransparency = 0 }, 0.2)

	local dismissed = false
	local function dismiss()
		if dismissed or not card.Parent then
			return
		end
		dismissed = true
		local tw = tween(card, { GroupTransparency = 1 }, 0.2)
		tw.Completed:Connect(function()
			card:Destroy()
		end)
	end
	inner.Activated:Connect(dismiss)
	task.delay(duration, dismiss)
end

function Window:Destroy()
	if self._destroyed then
		return
	end
	if self._persist and self._dirty then
		self:SaveConfig()
	end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._connections)
	if self._sizeTween then
		self._sizeTween:Cancel()
	end
	self._openDropdown = nil
	self.Gui:Destroy()
	table.clear(self.Flags)
	table.clear(self._tabs)
	if type(self._onClose) == "function" then
		task.spawn(function()
			local ok, err = pcall(self._onClose)
			if not ok then
				warn("[NovaUI] Erro em OnClose: " .. tostring(err))
			end
		end)
	end
end

----------------------------------------------------------------------
-- Abas
----------------------------------------------------------------------

function Window:AddTab(config)
	alive(self)
	if type(config) == "string" then
		config = { Name = config }
	end
	if type(config) ~= "table" or type(config.Name) ~= "string" or config.Name == "" then
		error("[NovaUI] AddTab: 'Name' deve ser um texto não vazio.", 2)
	end
	local T = self.Theme
	local id = self:_nextId()

	local tab = setmetatable({
		Window = self,
		Name = config.Name,
		Description = tostring(config.Description or ""),
		Icon = tostring(config.Icon or string.upper(config.Name:sub(1, 1))),
		Elements = {},
		_order = 0,
	}, Tab)

	local button = create("TextButton", {
		Name = "Tab_" .. id .. "_" .. sanitize(config.Name),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = T.AccentDark,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = id,
		Parent = self._tabList,
	})
	corner(button, 9)
	local indicator = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = T.AccentLight,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	})
	corner(indicator, 2)
	local iconHolder = create("Frame", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Parent = button,
	})
	local setIconColor = makeIcon(iconHolder, tab.Icon, T.SubText, 14)
	local nameLabel = create("TextLabel", {
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -44, 1, 0),
		BackgroundTransparency = 1,
		Text = config.Name,
		TextColor3 = T.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})

	local page = create("ScrollingFrame", {
		Name = "Page_" .. id .. "_" .. sanitize(config.Name),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.Accent,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = self._pages,
	})
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	padding(page, 4, 12, 12, 10)
	self:_connect(page:GetPropertyChangedSignal("CanvasPosition"), function()
		self:_closeDropdown()
	end)

	tab.Button = button
	tab.Page = page
	tab._setSelected = function(selected)
		tween(button, { BackgroundTransparency = selected and 0.05 or 1 }, 0.15)
		tween(indicator, { BackgroundTransparency = selected and 0 or 1 }, 0.15)
		tween(nameLabel, { TextColor3 = selected and T.Text or T.SubText }, 0.15)
		setIconColor(selected and T.AccentLight or T.SubText)
		tab._selected = selected
	end

	self:_connect(button.Activated, function()
		self:SelectTab(tab)
	end)
	self:_connect(button.MouseEnter, function()
		if not tab._selected then
			tween(button, { BackgroundColor3 = T.PanelHover, BackgroundTransparency = 0.4 }, 0.12)
		end
	end)
	self:_connect(button.MouseLeave, function()
		if not tab._selected then
			tween(button, { BackgroundTransparency = 1 }, 0.12)
		end
		button.BackgroundColor3 = T.AccentDark
	end)

	table.insert(self._tabs, tab)
	self:_applySearch()
	if #self._tabs == 1 then
		self:SelectTab(tab)
	end
	return tab
end

function Tab:Select()
	self.Window:SelectTab(self)
end

function Tab:Destroy()
	local window = self.Window
	if window._destroyed then
		return
	end
	for _, element in ipairs(table.clone(self.Elements)) do
		element:Destroy()
	end
	local index = table.find(window._tabs, self)
	if index then
		table.remove(window._tabs, index)
	end
	self.Button:Destroy()
	self.Page:Destroy()
	if window._current == self then
		window._current = nil
		if window._tabs[1] then
			window:SelectTab(window._tabs[1])
		else
			window._headerTitle.Text = ""
			window._headerDesc.Text = ""
		end
	end
	window:_applySearch()
end

----------------------------------------------------------------------
-- Componentes
----------------------------------------------------------------------

local function createRow(tab, height, cfg, defaultIcon, titleWidth)
	local window = tab.Window
	local T = window.Theme
	local id = window:_nextId()
	tab._order += 1

	local row = create("Frame", {
		Name = "Row_" .. id .. "_" .. sanitize(cfg.Name),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = T.Panel,
		BorderSizePixel = 0,
		LayoutOrder = tab._order,
		Parent = tab.Page,
	})
	corner(row, 10)
	stroke(row, T.Stroke, 1)

	local iconBox = create("Frame", {
		Name = "IconBox",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = T.Control,
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(iconBox, 9)
	stroke(iconBox, T.Stroke, 1)
	makeIcon(iconBox, cfg.Icon or defaultIcon, T.AccentLight, 15)

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Text = cfg.Name,
		TextColor3 = T.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local desc = create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Text = tostring(cfg.Description or ""),
		TextColor3 = T.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local dim = create("Frame", {
		Name = "DisabledOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ZIndex = 20,
		Parent = row,
	})
	corner(dim, 10)

	local parts = { Row = row, Title = title, Desc = desc, Dim = dim }
	function parts.Relayout()
		local hasDesc = desc.Text ~= ""
		desc.Visible = hasDesc
		local block = hasDesc and 32 or 17
		local top = math.floor((height - block) / 2)
		title.Position = UDim2.new(0, 58, 0, top)
		title.Size = UDim2.new(titleWidth.Scale, titleWidth.Offset, 0, 17)
		desc.Position = UDim2.new(0, 58, 0, top + 17)
		desc.Size = UDim2.new(titleWidth.Scale, titleWidth.Offset, 0, 14)
	end
	parts.Relayout()

	window:_connect(row.MouseEnter, function()
		tween(row, { BackgroundColor3 = T.PanelHover }, 0.12)
	end)
	window:_connect(row.MouseLeave, function()
		tween(row, { BackgroundColor3 = T.Panel }, 0.12)
	end)
	return row, parts
end

local function attachCommon(tab, el, parts, cfg)
	local window = tab.Window
	el.Row = parts.Row
	el.Tab = tab
	el.Flag = cfg.Flag
	el.Disabled = false

	function el:SetDisabled(state)
		self.Disabled = state == true
		parts.Dim.Visible = self.Disabled
		if self.Disabled and self._onDisabled then
			self._onDisabled()
		end
	end
	function el:SetName(text)
		parts.Title.Text = tostring(text)
	end
	function el:SetDescription(text)
		parts.Desc.Text = tostring(text or "")
		parts.Relayout()
	end
	function el:SetVisible(state)
		parts.Row.Visible = state ~= false
	end
	function el:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		if self._cleanup then
			pcall(self._cleanup)
		end
		if self.Flag and window.Flags[self.Flag] == self then
			window.Flags[self.Flag] = nil
		end
		local index = table.find(tab.Elements, self)
		if index then
			table.remove(tab.Elements, index)
		end
		parts.Row:Destroy()
	end

	table.insert(tab.Elements, el)
	if cfg.Flag then
		window:_register(cfg.Flag, el)
	end
	if cfg.Disabled then
		el:SetDisabled(true)
	end
end

-- Toggle ---------------------------------------------------------------

function Tab:AddToggle(cfg)
	cfg = prep(cfg, "AddToggle")
	local window = self.Window
	local T = window.Theme
	local row, parts = createRow(self, 52, cfg, "◐", UDim.new(1, -(58 + 42 + 28)))
	local el = { Type = "Toggle" }

	local value, loaded = window:_initial(cfg, cfg.Default == true, function(v)
		return type(v) == "boolean"
	end)

	local hit = create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	local switch = create("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(42, 22),
		BackgroundColor3 = T.Off,
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(switch, 11)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = switch,
	})
	corner(knob, 8)

	local function render(animate)
		local goal = {
			position = value and UDim2.new(0, 23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			color = value and T.Accent or T.Off,
		}
		if animate then
			tween(knob, { Position = goal.position }, 0.15)
			tween(switch, { BackgroundColor3 = goal.color }, 0.15)
		else
			knob.Position = goal.position
			switch.BackgroundColor3 = goal.color
		end
	end
	render(false)

	function el:Get()
		return value
	end
	function el:Set(newValue, silent)
		newValue = newValue == true
		if newValue == value then
			return
		end
		value = newValue
		render(true)
		if not silent then
			safeCall(window, cfg.Name, cfg.Callback, value)
			window:_markDirty()
		end
	end

	window:_connect(hit.Activated, function()
		if not el.Disabled then
			el:Set(not value)
		end
	end)

	attachCommon(self, el, parts, cfg)
	if loaded then
		safeCall(window, cfg.Name, cfg.Callback, value)
	end
	return el
end

-- Botão ----------------------------------------------------------------

function Tab:AddButton(cfg)
	cfg = prep(cfg, "AddButton")
	local window = self.Window
	local T = window.Theme
	local row, parts = createRow(self, 52, cfg, "▶", UDim.new(1, -(58 + 140 + 28)))
	local el = { Type = "Button" }
	local cooldown = clamp(tonumber(cfg.Cooldown) or 0.2, 0, 10)
	local busy = false

	local button = create("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(140, 32),
		BackgroundColor3 = T.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = tostring(cfg.ButtonText or "Executar") .. "  →",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		Parent = row,
	})
	corner(button, 8)
	create("UIGradient", {
		Color = ColorSequence.new(T.AccentLight, T.Accent),
		Rotation = 90,
		Transparency = NumberSequence.new(0.25, 0),
		Parent = button,
	})
	local pressScale = create("UIScale", { Parent = button })

	window:_connect(button.MouseEnter, function()
		tween(button, { BackgroundColor3 = T.AccentLight }, 0.12)
	end)
	window:_connect(button.MouseLeave, function()
		tween(button, { BackgroundColor3 = T.Accent }, 0.12)
		tween(pressScale, { Scale = 1 }, 0.1)
	end)
	window:_connect(button.MouseButton1Down, function()
		tween(pressScale, { Scale = 0.95 }, 0.08)
	end)
	window:_connect(button.MouseButton1Up, function()
		tween(pressScale, { Scale = 1 }, 0.1)
	end)

	function el:Fire()
		if el.Disabled or busy then
			return
		end
		busy = true
		safeCall(window, cfg.Name, cfg.Callback)
		task.delay(cooldown, function()
			busy = false
		end)
	end
	function el:Get()
		return nil
	end
	function el:Set(text)
		button.Text = tostring(text) .. "  →"
	end
	function el:SetText(text)
		el:Set(text)
	end

	window:_connect(button.Activated, function()
		el:Fire()
	end)

	attachCommon(self, el, parts, cfg)
	return el
end

-- Textbox --------------------------------------------------------------

function Tab:AddTextbox(cfg)
	cfg = prep(cfg, "AddTextbox")
	local window = self.Window
	local T = window.Theme
	local row, parts = createRow(self, 52, cfg, "T", UDim.new(0.53, -62))
	local el = { Type = "Textbox" }

	local initial, loaded = window:_initial(cfg, tostring(cfg.Default or ""), function(v)
		return type(v) == "string"
	end)

	local box = create("TextBox", {
		Name = "Input",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.43, 0, 0, 30),
		BackgroundColor3 = T.Control,
		BorderSizePixel = 0,
		Text = initial,
		PlaceholderText = tostring(cfg.Placeholder or "Digite aqui..."),
		PlaceholderColor3 = T.SubText,
		TextColor3 = T.Text,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		Parent = row,
	})
	padding(box, 0, 8, 0, 10)
	corner(box, 8)
	local boxStroke = stroke(box, T.Stroke, 1)

	window:_connect(box.Focused, function()
		tween(boxStroke, { Color = T.Accent }, 0.12)
	end)
	if cfg.Numeric then
		window:_connect(box:GetPropertyChangedSignal("Text"), function()
			local cleaned = box.Text:gsub("[^%d%.%-]", "")
			if cleaned ~= box.Text then
				box.Text = cleaned
			end
		end)
	end
	window:_connect(box.FocusLost, function(enterPressed)
		tween(boxStroke, { Color = T.Stroke }, 0.12)
		if el.Disabled then
			return
		end
		if cfg.OnEnterOnly and not enterPressed then
			return
		end
		safeCall(window, cfg.Name, cfg.Callback, box.Text)
		window:_markDirty()
	end)

	function el:Get()
		return box.Text
	end
	function el:Set(text, silent)
		box.Text = tostring(text)
		if not silent then
			safeCall(window, cfg.Name, cfg.Callback, box.Text)
			window:_markDirty()
		end
	end
	el._onDisabled = function()
		box:ReleaseFocus()
	end

	attachCommon(self, el, parts, cfg)
	if loaded then
		safeCall(window, cfg.Name, cfg.Callback, box.Text)
	end
	return el
end

-- Dropdown -------------------------------------------------------------

function Tab:AddDropdown(cfg)
	cfg = prep(cfg, "AddDropdown")
	local window = self.Window
	local T = window.Theme
	local row, parts = createRow(self, 52, cfg, "▼", UDim.new(0.53, -62))
	local el = { Type = "Dropdown" }
	local placeholder = tostring(cfg.Placeholder or "Selecionar...")

	local options = {}
	local function setOptionList(list)
		table.clear(options)
		if type(list) == "table" then
			for _, option in ipairs(list) do
				table.insert(options, tostring(option))
			end
		else
			warn("[NovaUI] Dropdown '" .. cfg.Name .. "': 'Options' deve ser uma lista.")
		end
	end
	setOptionList(cfg.Options)

	local selected = nil
	local initial, loaded = window:_initial(cfg, cfg.Default ~= nil and tostring(cfg.Default) or nil, function(v)
		return type(v) == "string" and table.find(options, v) ~= nil
	end)
	if initial ~= nil and table.find(options, initial) then
		selected = initial
	end

	local button = create("TextButton", {
		Name = "Selector",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.43, 0, 0, 30),
		BackgroundColor3 = T.Control,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	corner(button, 8)
	local btnStroke = stroke(button, T.Stroke, 1)
	local valueLabel = create("TextLabel", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -30, 1, 0),
		BackgroundTransparency = 1,
		Text = selected or placeholder,
		TextColor3 = selected and T.Text or T.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})
	local arrow = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Text = "▼",
		TextColor3 = T.SubText,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		Parent = button,
	})

	-- Lista fica no Overlay (fora da janela) para nunca ser cortada.
	local list = create("Frame", {
		Name = "DropdownList",
		BackgroundColor3 = T.Panel,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ClipsDescendants = true,
		Parent = window._overlay,
	})
	corner(list, 8)
	stroke(list, T.Accent, 1, 0.4)
	local listScale = create("UIScale", { Parent = list })
	local scroller = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.Accent,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = list,
	})
	create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller })
	padding(scroller, 4, 4, 4, 4)

	local isOpen = false
	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		list.Visible = false
		window._overlay.Visible = false
		tween(arrow, { Rotation = 0 }, 0.12)
		tween(btnStroke, { Color = T.Stroke }, 0.12)
	end

	local function setSelected(option, silent)
		if option ~= nil then
			option = tostring(option)
			if not table.find(options, option) then
				warn("[NovaUI] Dropdown '" .. cfg.Name .. "': opção inexistente '" .. option .. "'.")
				return
			end
		end
		local changed = option ~= selected
		selected = option
		valueLabel.Text = selected or placeholder
		valueLabel.TextColor3 = selected and T.Text or T.SubText
		if changed and not silent then
			safeCall(window, cfg.Name, cfg.Callback, selected)
			window:_markDirty()
		end
	end

	local function build()
		for _, child in ipairs(scroller:GetChildren()) do
			if child:IsA("TextButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		if #options == 0 then
			create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				Text = "Sem opções",
				TextColor3 = T.SubText,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				Parent = scroller,
			})
			return
		end
		for index, option in ipairs(options) do
			local item = create("TextButton", {
				Name = "Option_" .. index,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = T.AccentDark,
				BackgroundTransparency = option == selected and 0 or 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				Parent = scroller,
			})
			corner(item, 6)
			create("TextLabel", {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -16, 1, 0),
				BackgroundTransparency = 1,
				Text = option,
				TextColor3 = option == selected and T.Text or T.SubText,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = item,
			})
			item.MouseEnter:Connect(function()
				if option ~= selected then
					tween(item, { BackgroundTransparency = 0.6 }, 0.1)
				end
			end)
			item.MouseLeave:Connect(function()
				if option ~= selected then
					tween(item, { BackgroundTransparency = 1 }, 0.1)
				end
			end)
			item.Activated:Connect(function()
				window:_closeDropdown()
				setSelected(option)
			end)
		end
	end
	build()

	local function open()
		if el.Disabled or isOpen then
			return
		end
		window:_closeDropdown()
		build() -- atualiza destaque da seleção
		local scale = window._scale.Scale
		local screen = window.Gui.AbsoluteSize
		local pos, size = button.AbsolutePosition, button.AbsoluteSize
		local count = math.max(#options, 1)
		local wantedPx = math.min(count * 30 + 8, 170) * scale
		local below = screen.Y - (pos.Y + size.Y) - 8
		local above = pos.Y - 8
		local heightPx, y
		if wantedPx <= below or below >= above then
			heightPx = math.min(wantedPx, math.max(below, 40))
			y = pos.Y + size.Y + 4
		else
			heightPx = math.min(wantedPx, math.max(above, 40))
			y = pos.Y - heightPx - 4
		end
		local x = clamp(pos.X, 4, math.max(4, screen.X - size.X - 4))
		listScale.Scale = scale
		list.Position = UDim2.fromOffset(x, y)
		list.Size = UDim2.fromOffset(size.X / scale, 0)
		list.Visible = true
		window._overlay.Visible = true
		isOpen = true
		window._openDropdown = { owner = el, close = close }
		tween(list, { Size = UDim2.fromOffset(size.X / scale, heightPx / scale) }, 0.14)
		tween(arrow, { Rotation = 180 }, 0.12)
		tween(btnStroke, { Color = T.Accent }, 0.12)
	end

	window:_connect(button.Activated, function()
		if isOpen then
			window:_closeDropdown()
		else
			open()
		end
	end)

	function el:Get()
		return selected
	end
	function el:Set(option, silent)
		setSelected(option, silent)
	end
	function el:Refresh(newOptions, keepSelection)
		setOptionList(newOptions)
		if selected and not (keepSelection and table.find(options, selected)) then
			selected = nil
			valueLabel.Text = placeholder
			valueLabel.TextColor3 = T.SubText
		end
		build()
	end
	el._cleanup = function()
		if window._openDropdown and window._openDropdown.owner == el then
			window:_closeDropdown()
		end
		list:Destroy()
	end

	attachCommon(self, el, parts, cfg)
	if loaded then
		safeCall(window, cfg.Name, cfg.Callback, selected)
	end
	return el
end

-- Slider ---------------------------------------------------------------

function Tab:AddSlider(cfg)
	cfg = prep(cfg, "AddSlider")
	local window = self.Window
	local T = window.Theme
	local row, parts = createRow(self, 62, cfg, "↔", UDim.new(0.53, -62))
	local el = { Type = "Slider" }
	local page = self.Page

	local min = tonumber(cfg.Min) or 0
	local max = tonumber(cfg.Max) or 100
	if min > max then
		min, max = max, min
	end
	local decimals = tonumber(cfg.Decimals)
	local increment = tonumber(cfg.Increment)
	if not increment or increment <= 0 then
		increment = decimals and 10 ^ (-decimals) or 1
	end
	decimals = clamp(math.floor(decimals or countDecimals(increment)), 0, 6)

	local function snap(v)
		v = clamp(v, min, max)
		if max == min then
			return min
		end
		local steps = math.floor((v - min) / increment + 0.5)
		v = clamp(min + steps * increment, min, max)
		local factor = 10 ^ decimals
		return math.floor(v * factor + 0.5) / factor
	end

	local initial, loaded = window:_initial(cfg, tonumber(cfg.Default) or min, function(v)
		return type(v) == "number"
	end)
	local value = snap(initial)

	local area = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0.43, 0, 0, 46),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local valueBox = create("TextBox", {
		Name = "Value",
		Size = UDim2.fromOffset(60, 22),
		BackgroundColor3 = T.Control,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = T.Text,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		Parent = area,
	})
	corner(valueBox, 6)
	stroke(valueBox, T.Stroke, 1)
	local hit = create("TextButton", {
		Name = "Hit",
		Position = UDim2.new(0, 0, 1, -22),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = area,
	})
	local track = create("Frame", {
		Position = UDim2.new(0, 7, 0.5, -3),
		Size = UDim2.new(1, -14, 0, 6),
		BackgroundColor3 = T.Off,
		BorderSizePixel = 0,
		Parent = hit,
	})
	corner(track, 3)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(fill, 3)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(knob, 8)

	local function render()
		local ratio = (max == min) and 0 or (value - min) / (max - min)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
		valueBox.Text = string.format("%." .. decimals .. "f", value)
	end
	render()

	function el:Get()
		return value
	end
	function el:Set(newValue, silent)
		local number = tonumber(newValue)
		if not number then
			warn("[NovaUI] Slider '" .. cfg.Name .. "': valor inválido.")
			return
		end
		number = snap(number)
		local changed = number ~= value
		value = number
		render()
		if changed and not silent then
			safeCall(window, cfg.Name, cfg.Callback, value)
			window:_markDirty()
		end
	end

	local dragging, source, endConnection = false, nil, nil
	local function fromInput(position)
		if max == min then
			return
		end
		local ratio = clamp((position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		el:Set(min + ratio * (max - min))
	end
	local function stopDrag()
		dragging, source = false, nil
		if endConnection then
			endConnection:Disconnect()
			endConnection = nil
		end
		if page.Parent then
			page.ScrollingEnabled = true
		end
	end

	window:_connect(hit.InputBegan, function(input)
		if el.Disabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, source = true, input
			page.ScrollingEnabled = false
			fromInput(input.Position)
			if endConnection then
				endConnection:Disconnect()
			end
			endConnection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					stopDrag()
				end
			end)
		end
	end)
	window:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input == source or input.UserInputType == Enum.UserInputType.MouseMovement) then
			fromInput(input.Position)
		end
	end)
	window:_connect(valueBox.FocusLost, function()
		local typed = tonumber(valueBox.Text)
		if typed and not el.Disabled then
			el:Set(typed)
		end
		render()
	end)
	el._cleanup = stopDrag

	attachCommon(self, el, parts, cfg)
	if loaded then
		safeCall(window, cfg.Name, cfg.Callback, value)
	end
	return el
end

-- Label ----------------------------------------------------------------

function Tab:AddLabel(cfg)
	cfg = prep(cfg, "AddLabel")
	local window = self.Window
	local T = window.Theme
	self._order += 1
	local frame = create("Frame", {
		Name = "Label_" .. window:_nextId() .. "_" .. sanitize(cfg.Name),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
		Parent = self.Page,
	})
	padding(frame, 2, 4, 2, 4)
	create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
	local nameLabel = create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = cfg.Name,
		TextColor3 = T.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local textLabel = create("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = tostring(cfg.Text or cfg.Description or ""),
		Visible = (cfg.Text or cfg.Description) ~= nil,
		TextColor3 = T.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	local el = { Type = "Label", Row = frame, Tab = self }
	function el:SetName(text)
		nameLabel.Text = tostring(text)
	end
	function el:SetText(text)
		textLabel.Text = tostring(text or "")
		textLabel.Visible = textLabel.Text ~= ""
	end
	function el:Get()
		return nameLabel.Text
	end
	function el:SetVisible(state)
		frame.Visible = state ~= false
	end
	function el:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		local index = table.find(self.Tab.Elements, self)
		if index then
			table.remove(self.Tab.Elements, index)
		end
		frame:Destroy()
	end
	table.insert(self.Elements, el)
	return el
end

-- Separador ------------------------------------------------------------

function Tab:AddSeparator(cfg)
	if cfg ~= nil and type(cfg) ~= "table" and type(cfg) ~= "string" then
		error("[NovaUI] AddSeparator espera texto ou tabela.", 2)
	end
	local text = type(cfg) == "string" and cfg or (type(cfg) == "table" and cfg.Name) or nil
	local window = self.Window
	local T = window.Theme
	self._order += 1
	local frame = create("Frame", {
		Name = "Separator_" .. window:_nextId(),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
		Parent = self.Page,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = T.Stroke,
		BorderSizePixel = 0,
		Parent = frame,
	})
	if text then
		create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = T.Background,
			BorderSizePixel = 0,
			Text = "  " .. tostring(text) .. "  ",
			TextColor3 = T.SubText,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			Parent = frame,
		})
	end
	local el = { Type = "Separator", Row = frame, Tab = self }
	function el:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		local index = table.find(self.Tab.Elements, self)
		if index then
			table.remove(self.Tab.Elements, index)
		end
		frame:Destroy()
	end
	table.insert(self.Elements, el)
	return el
end

----------------------------------------------------------------------
-- Construtor
----------------------------------------------------------------------

function NovaUI.new(config)
	config = type(config) == "table" and config or {}
	local parent = resolveParent(config.Parent)
	if not parent then
		error("[NovaUI] Não foi possível encontrar um local para a interface (PlayerGui).", 2)
	end

	local self = setmetatable({}, Window)
	self._connections = {}
	self._tabs = {}
	self._ids = 0
	self._destroyed = false
	self._minimized = false
	self._dragged = false
	self._dirty = false
	self._saved = {}
	self._persist = false
	self.Flags = {}
	self.Theme = buildTheme(config.Theme)
	local T = self.Theme

	self._title = tostring(config.Title or "NOVA UI")
	self._subtitle = config.Subtitle ~= nil and tostring(config.Subtitle) or ""
	self._width = clamp(tonumber(config.Width) or 590, 360, 900)
	self._height = clamp(tonumber(config.Height) or 390, 240, 700)
	self._effW, self._effH = self._width, self._height
	self._onClose = config.OnClose

	-- Persistência (somente se o ambiente suportar)
	local persistence = config.Persistence
	if persistence == true then
		persistence = {}
	end
	if type(persistence) == "table" and persistence.Enabled ~= false then
		local fs = detectFileSystem()
		if fs then
			self._fs = fs
			self._persist = true
			self._folder = tostring(persistence.Folder or "NovaUI")
			self._file = self._folder .. "/" .. tostring(persistence.FileName or "config") .. ".json"
			local ok, data = pcall(function()
				if fs.isfile(self._file) then
					return HttpService:JSONDecode(fs.readfile(self._file))
				end
				return nil
			end)
			if ok and type(data) == "table" then
				self._saved = data
			end
		else
			warn("[NovaUI] Persistência solicitada, mas este ambiente não oferece writefile/readfile. Os valores NÃO serão salvos.")
		end
	end
	self.PersistenceEnabled = self._persist

	-- ScreenGui
	local guiName = tostring(config.Name or "NovaUI")
	local old = parent:FindFirstChild(guiName)
	if old and old:IsA("ScreenGui") then
		old:Destroy()
	end
	local gui = create("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = tonumber(config.DisplayOrder) or 100,
	})
	self.Gui = gui

	-- Janela (root) + sombras
	local root = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(self._width, self._height),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	self._root = root
	self._scale = create("UIScale", { Parent = root })
	for _, layer in ipairs({ { 34, 0.9 }, { 18, 0.82 }, { 6, 0.7 } }) do
		local shadow = create("Frame", {
			Name = "Shadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 4),
			Size = UDim2.new(1, layer[1], 1, layer[1]),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = layer[2],
			BorderSizePixel = 0,
			Parent = root,
		})
		corner(shadow, 14 + layer[1] / 2)
	end

	local main = create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	})
	corner(main, 14)
	stroke(main, T.Accent, 1, 0.55)

	local sidebarBg = create("Frame", {
		Name = "SidebarBackground",
		Size = UDim2.new(0, SIDEBAR_W, 1, 0),
		BackgroundColor3 = T.Sidebar,
		BorderSizePixel = 0,
		Parent = main,
	})
	create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(SIDEBAR_W, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = T.Stroke,
		BorderSizePixel = 0,
		Parent = main,
	})

	-- Barra superior
	local topbar = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, TOP_H),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = main,
	})
	local dragArea = create("TextButton", {
		Name = "DragArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = topbar,
	})
	local logo = create("Frame", {
		Name = "Logo",
		Position = UDim2.fromOffset(14, 13),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = T.Accent,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = topbar,
	})
	corner(logo, 8)
	create("UIGradient", { Color = ColorSequence.new(T.AccentLight, T.AccentDark), Rotation = 45, Parent = logo })
	create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "N",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		ZIndex = 3,
		Parent = logo,
	})
	self._titleLabel = create("TextLabel", {
		Name = "Title",
		Size = UDim2.fromOffset(SIDEBAR_W - 58, 20),
		BackgroundTransparency = 1,
		RichText = true,
		Text = "",
		TextColor3 = T.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = topbar,
	})
	self._subLabel = create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(52, 29),
		Size = UDim2.fromOffset(SIDEBAR_W - 58, 14),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = T.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = topbar,
	})
	self:_refreshTitle()

	-- Cabeçalho da aba atual
	self._headerIconBox = create("Frame", {
		Name = "HeaderIcon",
		Position = UDim2.fromOffset(SIDEBAR_W + 14, 11),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = T.Panel,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = topbar,
	})
	corner(self._headerIconBox, 9)
	stroke(self._headerIconBox, T.Stroke, 1)
	self._headerTitle = create("TextLabel", {
		Position = UDim2.fromOffset(SIDEBAR_W + 58, 9),
		Size = UDim2.new(1, -(SIDEBAR_W + 58 + 84), 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = T.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = topbar,
	})
	self._headerDesc = create("TextLabel", {
		Position = UDim2.fromOffset(SIDEBAR_W + 58, 29),
		Size = UDim2.new(1, -(SIDEBAR_W + 58 + 84), 0, 14),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = T.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = topbar,
	})

	-- Botões minimizar / fechar
	local function topButton(text, offsetX, hoverColor)
		local button = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, offsetX, 0, 14),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = T.Panel,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = T.SubText,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			ZIndex = 3,
			Parent = topbar,
		})
		corner(button, 8)
		self:_connect(button.MouseEnter, function()
			tween(button, { BackgroundColor3 = hoverColor, TextColor3 = T.Text }, 0.12)
		end)
		self:_connect(button.MouseLeave, function()
			tween(button, { BackgroundColor3 = T.Panel, TextColor3 = T.SubText }, 0.12)
		end)
		return button
	end
	local minButton = topButton("–", -42, T.PanelHover)
	local closeButton = topButton("×", -10, T.Error)
	self._minText = minButton
	self:_connect(minButton.Activated, function()
		self:ToggleMinimize()
	end)
	self:_connect(closeButton.Activated, function()
		self:Destroy()
	end)

	-- Corpo
	self._body = create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, TOP_H),
		Size = UDim2.new(1, 0, 1, -TOP_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = main,
	})
	local side = create("Frame", {
		Name = "Side",
		Size = UDim2.new(0, SIDEBAR_W, 1, 0),
		BackgroundTransparency = 1,
		Parent = self._body,
	})
	local searchFrame = create("Frame", {
		Name = "Search",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.fromOffset(SIDEBAR_W - 20, 32),
		BackgroundColor3 = T.Control,
		BorderSizePixel = 0,
		Parent = side,
	})
	corner(searchFrame, 16)
	local searchStroke = stroke(searchFrame, T.Stroke, 1)
	local glass = create("Frame", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(11, 11),
		BackgroundTransparency = 1,
		Parent = searchFrame,
	})
	corner(glass, 6)
	stroke(glass, T.SubText, 1.5)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(24, 21),
		Size = UDim2.fromOffset(6, 2),
		Rotation = 45,
		BackgroundColor3 = T.SubText,
		BorderSizePixel = 0,
		Parent = searchFrame,
	})
	self._search = create("TextBox", {
		Name = "SearchBox",
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -38, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Pesquisar...",
		PlaceholderColor3 = T.SubText,
		TextColor3 = T.Text,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		Parent = searchFrame,
	})
	self:_connect(self._search:GetPropertyChangedSignal("Text"), function()
		self:_applySearch()
	end)
	self:_connect(self._search.Focused, function()
		tween(searchStroke, { Color = T.Accent }, 0.12)
	end)
	self:_connect(self._search.FocusLost, function()
		tween(searchStroke, { Color = T.Stroke }, 0.12)
	end)

	self._tabList = create("ScrollingFrame", {
		Name = "TabList",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = side,
	})
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self._tabList })
	padding(self._tabList, 2, 8, 6, 8)
	self._noResults = create("TextLabel", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "Nenhuma aba encontrada",
		TextColor3 = T.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		Visible = false,
		Parent = side,
	})

	self._pages = create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(SIDEBAR_W + 1, 0),
		Size = UDim2.new(1, -(SIDEBAR_W + 1), 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = self._body,
	})

	-- Overlay (dropdowns) e notificações
	self._overlay = create("TextButton", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 100,
		Parent = gui,
	})
	self:_connect(self._overlay.Activated, function()
		self:_closeDropdown()
	end)
	self._notifHolder = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, 270, 1, -24),
		BackgroundTransparency = 1,
		ZIndex = 200,
		Parent = gui,
	})
	self._notifScale = create("UIScale", { Parent = self._notifHolder })
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = self._notifHolder,
	})

	-- Arrastar (mouse e toque)
	local dragging, dragSource, dragStart, dragCenter = false, nil, Vector2.zero, Vector2.zero
	self:_connect(dragArea.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragSource = true, input
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			dragCenter = root.AbsolutePosition + root.AbsoluteSize / 2
			self:_closeDropdown()
			local connection
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging, dragSource = false, nil
					connection:Disconnect()
				end
			end)
		end
	end)
	self:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input == dragSource or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local screen = gui.AbsoluteSize
			local center = dragCenter + (Vector2.new(input.Position.X, input.Position.Y) - dragStart)
			root.Position = UDim2.fromOffset(clamp(center.X, 40, screen.X - 40), clamp(center.Y, 28, screen.Y - 28))
			self._dragged = true
		end
	end)

	-- Tecla para mostrar/ocultar (PC)
	local toggleKey = config.ToggleKey
	if toggleKey == nil then
		toggleKey = Enum.KeyCode.RightControl
	end
	if typeof(toggleKey) == "EnumItem" then
		self:_connect(UserInputService.InputBegan, function(input, processed)
			if not processed and input.KeyCode == toggleKey then
				if root.Visible then
					self:Hide()
				else
					self:Show()
				end
			end
		end)
	end

	-- Responsividade (usa o tamanho do ScreenGui, sem depender de CurrentCamera)
	self:_connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:_updateLayout()
	end)

	gui.Parent = parent
	self:_updateLayout()
	return self
end

NovaUI.CreateWindow = NovaUI.new

return NovaUI
