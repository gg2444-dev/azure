--[[
	Azure v1.0 - dark/gold basketball hub UI
	Run it: paste into an executor, OR put it in a LocalScript under StarterPlayerScripts.

	Hook your game logic up through Azure.Changed:

	    local Hub = loadstring(readfile("Azure.lua"))()
	    Hub.Changed:Connect(function(id, value)
	        if id == "defense.autoBlock" then setAutoBlock(value) end -- your code
	    end)
]]

local Players          = game:GetService("Players")
local UIS              = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local GuiService       = game:GetService("GuiService")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local TeleportService  = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

-- ---------------------------------------------------------------- Signal ---
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ _h = {} }, Signal) end
function Signal:Connect(fn)
	self._h[fn] = true
	local c = {}
	function c:Disconnect() self._h[fn] = nil end
	return c
end
function Signal:Fire(...)
	for fn in pairs(self._h) do task.spawn(fn, ...) end
end

-- ----------------------------------------------------------------- Theme ---
local Theme = {
	Bg        = Color3.fromRGB(14, 14, 16),
	Sidebar   = Color3.fromRGB(11, 11, 13),
	Row       = Color3.fromRGB(25, 25, 29),
	RowStroke = Color3.fromRGB(44, 44, 52),
	Track     = Color3.fromRGB(38, 38, 44),
	Box       = Color3.fromRGB(27, 27, 32),
	Text      = Color3.fromRGB(237, 237, 240),
	Muted     = Color3.fromRGB(150, 150, 160),
	Dim       = Color3.fromRGB(107, 107, 115),
	Dark      = Color3.fromRGB(14, 14, 16),
	Danger    = Color3.fromRGB(235, 87, 87),
}
local AccentNames = {
	Gold   = Color3.fromRGB(245, 166, 35),
	Red    = Color3.fromRGB(235, 87, 87),
	Cyan   = Color3.fromRGB(60, 200, 225),
	Purple = Color3.fromRGB(160, 110, 255),
	Green  = Color3.fromRGB(80, 205, 130),
	White  = Color3.fromRGB(240, 240, 245),
}
local Accent = AccentNames.Gold
local AccentRefs = {}
local function registerAccent(obj, prop)
	AccentRefs[#AccentRefs + 1] = { obj, prop }
	pcall(function() obj[prop] = Accent end)
end
local function applyAccent(color)
	Accent = color
	for _, ref in ipairs(AccentRefs) do
		if ref[1].Parent then pcall(function() ref[1][ref[2]] = color end) end
	end
end

-- -------------------------------------------------------------- Helpers ---
local function New(className, props)
	local inst = Instance.new(className)
	local parent = nil
	for k, v in pairs(props) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	if parent then inst.Parent = parent end
	return inst
end
local function AddCorner(inst, radius)
	return New("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end
local function AddStroke(inst, color, transparency, thickness)
	return New("UIStroke", {
		Color = color, Transparency = transparency or 0,
		Thickness = thickness or 1, Parent = inst,
	})
end
local function MakeLabel(props)
	local l = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for k, v in pairs(props) do l[k] = v end
	return l
end
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
local function MouseX() return UIS:GetMouseLocation().X end
local function MousePos() return UIS:GetMouseLocation() end
local function IsPrimary(t)
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

-- -------------------------------------------------------- State / Config ---
local State, WidgetRefs = {}, {}
local CONFIG_NAME = "Azure_config.json"

local function fileAPI()
	return typeof(readfile) == "function" and typeof(writefile) == "function"
end
local function saveConfigFile()
	if not fileAPI() then return false end
	local ok = pcall(function()
		writefile(CONFIG_NAME, HttpService:JSONEncode({ state = State }))
	end)
	return ok
end
local function readConfigFile()
	if not fileAPI() then return nil end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_NAME))
	end)
	if ok and type(data) == "table" and type(data.state) == "table" then
		return data.state
	end
	return nil
end

local Hub = { Version = "1.1.0" }
Hub.Changed = Signal.new()

function Hub:Get(id) return State[id] end
function Hub:Set(id, value)
	State[id] = value
	for _, setter in ipairs(WidgetRefs[id] or {}) do
		task.spawn(setter, value)
	end
	Hub.Changed:Fire(id, value)
end
function Hub:IsEnabled() return State["hub.enabled"] ~= false end
function Hub:SaveConfig() return saveConfigFile() end

local function addSetter(id, fn)
	local list = WidgetRefs[id]
	if not list then list = {} WidgetRefs[id] = list end
	list[#list + 1] = fn
end

local function seed(id, default)
	if State[id] == nil then State[id] = DeepCopy(default) end
	return State[id]
end

local Pristine = nil -- snapshot of defaults, taken after the UI is built

local function pushAll(tbl)
	for id, value in pairs(tbl) do
		State[id] = DeepCopy(value)
		for _, setter in ipairs(WidgetRefs[id] or {}) do task.spawn(setter, value) end
		Hub.Changed:Fire(id, value)
	end
end

function Hub:LoadConfig()
	local data = readConfigFile()
	if not data then
		Hub:Notify(fileAPI() and "No config file found" or "File API unavailable")
		return false
	end
	pushAll(data)
	Hub:Notify("Config loaded")
	return true
end
function Hub:ResetConfig()
	if Pristine then pushAll(Pristine) end
	Hub:Notify("Defaults restored")
end
local gui, GlobalConns -- assigned below, referenced here by Destroy

function Hub:Destroy()
	for _, c in ipairs(GlobalConns or {}) do pcall(function() c:Disconnect() end) end
	if gui then gui:Destroy() end
end

-- --------------------------------------------------------------- Notify ---
local notifFolder
function Hub:Notify(text)
	if State["ui.notifications"] == false then return end
	if not notifFolder then return end
	while #notifFolder:GetChildren() > 4 do
		local oldest
		for _, c in ipairs(notifFolder:GetChildren()) do
			if not oldest or c.LayoutOrder < oldest.LayoutOrder then oldest = c end
		end
		if oldest then oldest:Destroy() else break end
	end
	local toast = New("Frame", {
		Size = UDim2.fromOffset(250, 34),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		LayoutOrder = math.floor(os.clock() * 100),
		Parent = notifFolder,
		ZIndex = 300,
	})
	AddCorner(toast, 6)
	AddStroke(toast, Theme.RowStroke, 0.2, 1)
	local lbl = MakeLabel({
		Text = "  " .. tostring(text),
		Size = UDim2.fromScale(1, 1),
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toast,
		ZIndex = 301,
	})
	toast.Position = UDim2.fromOffset(40, 0)
	toast.BackgroundTransparency = 1
	lbl.TextTransparency = 1
	local tween = TweenService:Create(toast, TweenInfo.new(0.22, Enum.EasingStyle.Quad),
		{ Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.05 })
	TweenService:Create(lbl, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
	tween:Play()
	task.delay(2.6, function()
		if not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.25), {
			Position = UDim2.fromOffset(40, 0), BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(lbl, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		task.wait(0.3)
		pcall(function() toast:Destroy() end)
	end)
end

-- ------------------------------------------- Global drag / capture plumbing ---
local dragUpdate, dragEnd = nil, nil
local function beginDrag(update, finish)
	dragUpdate, dragEnd = update, finish
end

local capturing = nil
local function beginCapture(onKey)
	capturing = function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Unknown then return end
			capturing = nil
			if input.KeyCode == Enum.KeyCode.Escape then onKey(nil)
			else onKey(input.KeyCode.Name) end
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.Unknown then return end
			capturing = nil
			onKey(input.KeyCode.Name) -- e.g. ButtonX, ButtonL3, DPadUp
		elseif input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3 then
			capturing = nil
			onKey(input.UserInputType.Name)
		end
	end
end

local popups = {}
local popupCloser
local function closePopups()
	for _, p in ipairs(popups) do p.Visible = false end
	if popupCloser then popupCloser.Visible = false end
end

GlobalConns = {}
local function trackConn(c)
	GlobalConns[#GlobalConns + 1] = c
	return c
end

trackConn(UIS.InputChanged:Connect(function(input)
	if dragUpdate and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		dragUpdate(input)
	end
end))
trackConn(UIS.InputEnded:Connect(function(input)
	if dragEnd and IsPrimary(input.UserInputType) then
		local finish = dragEnd
		dragUpdate, dragEnd = nil, nil
		finish(input)
	end
end))

-- ------------------------------------------------------------- GUI shell ---
local WINDOW_W, WINDOW_H, TITLE_H, SIDEBAR_W = 780, 500, 46, 152
local ROW_GAP, SECTION_GAP = 6, 12

pcall(function() -- remove any previous Azure UI (re-execute safety)
	local existing = game:GetService("CoreGui"):FindFirstChild("Azure")
	if existing then existing:Destroy() end
end)
pcall(function()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local existing = pg and pg:FindFirstChild("Azure")
	if existing then existing:Destroy() end
end)

gui = New("ScreenGui", {
	Name = "Azure",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999999,
})
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local window = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	Parent = gui,
})
AddCorner(window, 10)
local uiScale = New("UIScale", { Scale = 1, Parent = window })

New("Frame", { -- gold top edge
	Size = UDim2.new(1, 0, 0, 2),
	BackgroundColor3 = Accent,
	BorderSizePixel = 0,
	ZIndex = 5,
	Parent = window,
})
local topBar = window:FindFirstChildOfClass("Frame")
registerAccent(topBar, "BackgroundColor3")

local titleBar = New("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H),
	Position = UDim2.new(0, 0, 0, 2),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = window,
})

-- logo + title + DEV badge
local logo = New("Frame", {
	Size = UDim2.fromOffset(24, 24),
	Position = UDim2.new(0, 14, 0.5, -12),
	BackgroundColor3 = Accent,
	BorderSizePixel = 0,
	Parent = titleBar,
})
AddCorner(logo, 12)
registerAccent(logo, "BackgroundColor3")
MakeLabel({
	Text = "AZ", TextSize = 9, Font = Enum.Font.GothamBold,
	TextColor3 = Theme.Dark, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1), Parent = logo,
})
MakeLabel({
	Text = "Azure", TextSize = 17, Font = Enum.Font.GothamBold,
	Position = UDim2.new(0, 46, 0, 0), Size = UDim2.new(0, 100, 1, 0),
	Parent = titleBar,
})
local devBadge = New("Frame", {
	Position = UDim2.new(0, 146, 0.5, -9),
	Size = UDim2.fromOffset(40, 18),
	BackgroundTransparency = 1,
	Parent = titleBar,
})
AddCorner(devBadge, 4)
AddStroke(devBadge, Accent, 0.3, 1)
registerAccent(devBadge, "BorderColor3")
MakeLabel({
	Text = "DEV", TextSize = 9, Font = Enum.Font.GothamBold,
	TextColor3 = Accent, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1), Parent = devBadge,
})

-- window control buttons: [hide] [minimize] [destroy]
local titleButtons = {}
local function makeTitleButton(x, kind)
	local btn = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -x, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = titleBar,
		ZIndex = 6,
	})
	titleButtons[btn] = true
	if kind == "circle" then
		local ring = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Parent = btn, ZIndex = 7,
		})
		AddCorner(ring, 5)
		AddStroke(ring, Theme.Muted, 0.2, 1.5)
	elseif kind == "min" then
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.62),
			Size = UDim2.fromOffset(10, 2),
			BackgroundColor3 = Theme.Muted,
			BorderSizePixel = 0, Parent = btn, ZIndex = 7,
		})
	else
		MakeLabel({
			Text = "X", TextSize = 12, Font = Enum.Font.GothamBold,
			TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1), Parent = btn, ZIndex = 7,
		})
	end
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.85 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
	end)
	return btn
end
local btnHide = makeTitleButton(76, "circle")
local btnMin   = makeTitleButton(44, "min")
local btnKill  = makeTitleButton(12, "kill")

-- sidebar + page area
local body = New("Frame", {
	Position = UDim2.new(0, 0, 0, TITLE_H),
	Size = UDim2.new(1, 0, 1, -TITLE_H),
	BackgroundTransparency = 1,
	Parent = window,
})
local sidebar = New("Frame", {
	Size = UDim2.new(0, SIDEBAR_W, 1, 0),
	BackgroundColor3 = Theme.Sidebar,
	BorderSizePixel = 0,
	Parent = body,
})
New("Frame", { -- sidebar divider
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = Theme.RowStroke,
	BorderSizePixel = 0,
	Parent = sidebar,
})
local pagesFolder = New("Frame", {
	Position = UDim2.new(0, SIDEBAR_W, 0, 0),
	Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = body,
})

notifFolder = New("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(270, 240),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = gui,
	ZIndex = 300,
})
New("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = notifFolder,
})

popupCloser = New("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Visible = false,
	AutoButtonColor = false,
	Parent = gui,
	ZIndex = 70,
})
popupCloser.MouseButton1Click:Connect(closePopups)

-- ----------------------------------------------------------- Page / Sec ---
local Page, Section = {}, {}
Page.__index = Page
Section.__index = Section

function Section:_place(height)
	local y = self.cursor
	self.cursor = y + height + ROW_GAP
	local h = self.cursor - ROW_GAP + 12
	self.frame.Size = UDim2.new(1, 0, 0, h)
	self.column.cursor = self.originY + h + SECTION_GAP
	if self.page and self.page._updateCanvas then self.page:_updateCanvas() end
	return y
end

function Page:_updateCanvas()
	local maxH = 0
	for _, col in ipairs(self.cols) do
		if col.cursor > maxH then maxH = col.cursor end
	end
	self.scroll.CanvasSize = UDim2.new(0, 0, 0, maxH + 24)
end

function Page:Section(title, col)
	local column
	if self.dual and col ~= 1 and col ~= 2 then
		column = self.cols[1].cursor <= self.cols[2].cursor and self.cols[1] or self.cols[2]
	else
		column = self.cols[col or 1]
	end
	local originY = column.cursor
	local frame = New("Frame", {
		Position = UDim2.new(0, 0, 0, originY),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = column.frame,
	})
	MakeLabel({
		Text = string.upper(title),
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Theme.Dim,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = frame,
	})
	local sec = setmetatable({
		frame = frame, cursor = 22, column = column, originY = originY, page = self,
	}, Section)
	column.cursor = originY + 34 + SECTION_GAP
	self:_updateCanvas()
	return sec
end

function Section:Toggle(label, id, default)
	seed(id, default)
	local y = self:_place(24)
	local row = New("TextButton", {
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = self.frame,
	})
	local circle = New("Frame", {
		Position = UDim2.new(0, 0, 0.5, -7),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.Row,
		BorderSizePixel = 0,
		Parent = row,
	})
	AddCorner(circle, 7)
	local stroke = AddStroke(circle, Theme.RowStroke, 0, 1.5)
	local dot = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Theme.Dark,
		Visible = false,
		Parent = circle,
	})
	AddCorner(dot, 3)
	local lbl = MakeLabel({
		Text = label,
		Position = UDim2.new(0, 24, 0, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Parent = row,
	})
	local function visual(v)
		v = v == true
		circle.BackgroundColor3 = v and Accent or Theme.Row
		stroke.Color = v and Accent or Theme.RowStroke
		dot.Visible = v
		lbl.TextColor3 = Theme.Text
	end
	visual(State[id])
	addSetter(id, visual)
	row.MouseButton1Click:Connect(function()
		Hub:Set(id, not (State[id] == true))
	end)
	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundTransparency = 0.9 }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
	end)
	return row
end

function Section:Slider(label, id, minV, maxV, default, decimals)
	decimals = decimals or 0
	seed(id, default)
	local y = self:_place(44)
	local row = New("Frame", {
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = self.frame,
	})
	MakeLabel({ Text = label, Size = UDim2.new(1, -50, 0, 16), Parent = row })
	local val = MakeLabel({
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Muted,
		TextSize = 12,
		Position = UDim2.new(1, -46, 0, 0),
		Size = UDim2.new(0, 46, 0, 16),
		Parent = row,
	})
	local track = New("TextButton", {
		Position = UDim2.new(0, 0, 0, 32),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Theme.Track,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	AddCorner(track, 2)
	local fill = New("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	AddCorner(fill, 2)
	registerAccent(fill, "BackgroundColor3")
	local thumb = New("Frame", {
		Position = UDim2.new(0, 0, 0.5, -6),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Accent,
		BorderSizePixel = 0,
		Parent = track,
		ZIndex = 3,
	})
	AddCorner(thumb, 7)
	registerAccent(thumb, "BackgroundColor3")

	local function fmt(v)
		if decimals == 0 then return tostring(math.floor(v + 0.5)) end
		return string.format("%." .. decimals .. "f", v)
	end
	local function visual(v)
		v = math.clamp(tonumber(v) or minV, minV, maxV)
		local f = (v - minV) / (maxV - minV)
		fill.Size = UDim2.new(f, 0, 1, 0)
		thumb.Position = UDim2.new(f, -f * 12, 0.5, -6)
		val.Text = fmt(v)
	end
	visual(State[id])
	addSetter(id, visual)

	local dragging = false
	local function applyX(x)
		local w = track.AbsoluteSize.X
		if w <= 0 then return end
		local f = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
		local v = minV + f * (maxV - minV)
		local step = decimals == 0 and 1 or (10 ^ -decimals)
		v = math.floor(v / step + 0.5) * step
		v = math.clamp(v, minV, maxV)
		Hub:Set(id, math.floor(v * 1e6 + 0.5) / 1e6)
	end
	track.InputBegan:Connect(function(input)
		if not IsPrimary(input.UserInputType) then return end
		dragging = true
		applyX(MouseX())
		beginDrag(function(inp)
			if dragging then applyX(inp.Position.X) end
		end, function() dragging = false end)
	end)
	return row
end

function Section:Keybind(label, id, default)
	seed(id, default)
	local y = self:_place(26)
	local row = New("Frame", {
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = self.frame,
	})
	MakeLabel({ Text = label, Size = UDim2.new(1, -66, 1, 0), Parent = row })
	local box = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(58, 22),
		BackgroundColor3 = Theme.Box,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	AddCorner(box, 5)
	AddStroke(box, Theme.RowStroke, 0.3, 1)
	local txt = MakeLabel({
		TextSize = 11, Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), Parent = box,
	})
	local function visual(v) txt.Text = tostring(v or "?") end
	visual(State[id])
	addSetter(id, visual)
	box.MouseButton1Click:Connect(function()
		txt.Text = "..."
		beginCapture(function(name)
			if name then
				Hub:Set(id, name)
			else
				txt.Text = tostring(State[id] or "?")
			end
		end)
	end)
	return row
end

function Section:Dropdown(label, id, options, default, multi)
	local initial
	if multi then
		initial = {}
		for _, v in ipairs(default or {}) do initial[#initial + 1] = v end
	else
		initial = default
	end
	seed(id, initial)
	if multi and type(State[id]) ~= "table" then State[id] = {} end

	local y = self:_place(26)
	local row = New("Frame", {
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = self.frame,
	})
	MakeLabel({ Text = label, Size = UDim2.new(1, -132, 1, 0), Parent = row })
	local box = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(124, 24),
		BackgroundColor3 = Theme.Box,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	AddCorner(box, 6)
	AddStroke(box, Theme.RowStroke, 0.3, 1)
	local txt = MakeLabel({
		TextSize = 12,
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Parent = box,
	})
	MakeLabel({
		Text = "\u{25BE}", TextSize = 10, TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -18, 0, 0),
		Size = UDim2.new(0, 12, 1, 0),
		Parent = box,
	})

	local popup, optButtons = nil, {}
	local function visual(v)
		if multi then
			local n = type(v) == "table" and #v or 0
			txt.Text = n > 0 and (n .. " selected") or "None"
			for _, ref in ipairs(optButtons) do
				local sel = false
				for _, s in ipairs(State[id] or {}) do if s == ref.name then sel = true end end
				ref.check.TextTransparency = sel and 0 or 1
			end
		else
			txt.Text = tostring(v or "None")
		end
	end

	local function close() closePopups() end
	local function open()
		closePopups()
		if not popup then
			local itemH = 24
			local h = math.min(#options * itemH + 8, 176)
			popup = New("ScrollingFrame", {
				AnchorPoint = Vector2.new(1, 0),
				Size = UDim2.fromOffset(math.max(box.AbsoluteSize.X + 16, 140), h),
				BackgroundColor3 = Theme.Row,
				BackgroundTransparency = 0.03,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = Accent,
				CanvasSize = UDim2.new(0, 0, 0, #options * itemH + 8),
				AutomaticCanvasSize = Enum.AutomaticSize.None,
				Visible = false,
				Parent = gui,
				ZIndex = 81,
			})
			AddCorner(popup, 6)
			AddStroke(popup, Theme.RowStroke, 0.1, 1)
			registerAccent(popup, "ScrollBarImageColor3")
			New("UIPadding", {
				PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
				Parent = popup,
			})
			popups[#popups + 1] = popup
			for i, option in ipairs(options) do
				local opt = New("TextButton", {
					Size = UDim2.new(1, 0, 0, itemH),
					BackgroundColor3 = Theme.Bg,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Selectable = true,
					Text = "",
					LayoutOrder = i,
					Parent = popup,
					ZIndex = 82,
				})
				AddCorner(opt, 4)
				MakeLabel({
					Text = "  " .. option, TextSize = 12,
					Size = UDim2.new(1, -24, 1, 0), Parent = opt, ZIndex = 83,
				})
				local check = MakeLabel({
					Text = "\u{2713}", TextSize = 11, Font = Enum.Font.GothamBold,
					TextColor3 = Accent, TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -20, 0, 0), Size = UDim2.new(0, 14, 1, 0),
					Parent = opt, ZIndex = 83,
				})
				registerAccent(check, "TextColor3")
				optButtons[#optButtons + 1] = { name = option, check = check }
				opt.MouseEnter:Connect(function()
					TweenService:Create(opt, TweenInfo.new(0.1), { BackgroundTransparency = 0.85 }):Play()
				end)
				opt.MouseLeave:Connect(function()
					TweenService:Create(opt, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
				end)
				opt.MouseButton1Click:Connect(function()
					if multi then
						local sel = {}
						for _, s in ipairs(State[id] or {}) do sel[#sel + 1] = s end
						local found = false
						for i2, s in ipairs(sel) do
							if s == option then table.remove(sel, i2) found = true break end
						end
						if not found then sel[#sel + 1] = option end
						Hub:Set(id, sel)
					else
						Hub:Set(id, option)
						close()
					end
				end)
			end
		end
		popup.AnchorPoint = Vector2.new(1, 0)
		popup.Position = UDim2.fromOffset(
			box.AbsolutePosition.X + box.AbsoluteSize.X,
			box.AbsolutePosition.Y + box.AbsoluteSize.Y + 4
		)
		popup.Visible = true
		popupCloser.Visible = true
	end
	visual(State[id])
	addSetter(id, visual)
	box.MouseButton1Click:Connect(function()
		if popup and popup.Visible then close() else open() end
	end)
	return row
end

function Section:Button(label, text, fn)
	local y = self:_place(28)
	local row = New("Frame", {
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = self.frame,
	})
	MakeLabel({ Text = label, Size = UDim2.new(1, -108, 1, 0), Parent = row })
	local btn = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(100, 24),
		BackgroundColor3 = Theme.Box,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Accent,
		Parent = row,
	})
	AddCorner(btn, 6)
	AddStroke(btn, Accent, 0.55, 1)
	registerAccent(btn, "TextColor3")
	registerAccent(btn, "BorderColor3")
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Accent
		btn.TextColor3 = Theme.Dark
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Theme.Box
		btn.TextColor3 = Accent
	end)
	btn.MouseButton1Click:Connect(function() task.spawn(fn) end)
	return row
end

function Section:Info(text)
	local y = self:_place(16)
	local lbl = MakeLabel({
		Text = text, TextSize = 11, TextColor3 = Theme.Dim,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = self.frame,
	})
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	return lbl
end

-- --------------------------------------------------------- Pages / Tabs ---
local Pages, TabButtons, currentPage = {}, {}, nil

function Hub:Page(name, dual)
	local scroll = New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Visible = false,
		Parent = pagesFolder,
	})
	registerAccent(scroll, "ScrollBarImageColor3")
	local page = setmetatable({ scroll = scroll, dual = dual, cols = {} }, Page)
	local PAD, GAP = 12, 16
	local innerW = (WINDOW_W - SIDEBAR_W) - PAD * 2
	local colW = dual and ((innerW - GAP) / 2) or innerW
	local count = dual and 2 or 1
	for i = 1, count do
		local col = New("Frame", {
			Position = UDim2.new(0, PAD + (i - 1) * (colW + GAP), 0, 8),
			Size = UDim2.new(0, colW, 0, 0),
			BackgroundTransparency = 1,
			Parent = scroll,
		})
		-- plain wrapper table: Roblox Instances reject custom fields like .cursor
		page.cols[i] = { frame = col, cursor = 0 }
	end
	Pages[name] = page
	return page
end

local function switchPage(name)
	closePopups()
	for n, p in pairs(Pages) do p.scroll.Visible = (n == name) end
	for n, btn in pairs(TabButtons) do
		local active = (n == name)
		btn.BackgroundColor3 = active and Color3.fromRGB(245, 245, 248) or Theme.Sidebar
		btn.BackgroundTransparency = active and 0 or 1
		btn.TextColor3 = active and Theme.Dark or Theme.Muted
		btn.Font = active and Enum.Font.GothamBold or Enum.Font.GothamMedium
	end
	currentPage = name
end
Hub.SwitchPage = switchPage

local tabOrder = {
	"Azure", "SHOOTING", "PLAYER", "DRIBBLING",
	"DEFENSE", "EXTRAS", "SETTINGS", "PRACTICAL BASKETBALL",
}
local function buildSidebar()
	local y = 12
	for i, name in ipairs(tabOrder) do
		if name == "PRACTICAL BASKETBALL" then y = y + 10 end
		local btn = New("TextButton", {
			Position = UDim2.new(0, 10, 0, y),
			Size = UDim2.new(1, -20, 0, 30),
			BackgroundColor3 = Theme.Sidebar,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "  " .. name,
			Font = Enum.Font.GothamMedium,
			TextColor3 = Theme.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = sidebar,
		})
		AddCorner(btn, 6)
		TabButtons[name] = btn
		btn.MouseButton1Click:Connect(function() switchPage(name) end)
		btn.MouseEnter:Connect(function()
			if currentPage == name then return end
			TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundTransparency = 0.88 }):Play()
		end)
		btn.MouseLeave:Connect(function()
			if currentPage == name then return end
			TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
		end)
		y = y + 34
	end
end

-- --------------------------------------------------------- Page content ---
local buildOk, buildErr = pcall(function()
buildSidebar()

local function envName()
	local ok, name = pcall(function()
		if typeof(identifyexecutor) == "function" then return identifyexecutor() end
		return nil
	end)
	if ok and name then return tostring(name) end
	if game:GetService("RunService"):IsStudio() then return "Roblox Studio" end
	return "Roblox"
end

local function rejoinServer()
	Hub:Notify("Rejoining...")
	TeleportService:Teleport(game.PlaceId, LocalPlayer)
end
local function serverHop()
	Hub:Notify("Finding a new server...")
	local ok, raw = pcall(function()
		return game:HttpGet("https://games.roblox.com/v1/games/"
			.. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
	end)
	if not ok or not raw then Hub:Notify("Server hop unavailable") return end
	local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok2 or not data or not data.data then Hub:Notify("Server hop failed") return end
	for _, s in ipairs(data.data) do
		if s.id and s.id ~= game.JobId and (s.playing or 0) < (s.maxPlayers or 0) then
			TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
			return
		end
	end
	Hub:Notify("No other server found")
end
local function resetCharacter()
	local c = LocalPlayer.Character
	if c then c:BreakJoints() end
	task.wait(0.2)
	pcall(function() LocalPlayer:LoadCharacter() end)
end
local function copyPlaceId()
	local ok = pcall(function()
		if typeof(setclipboard) == "function" then setclipboard(tostring(game.PlaceId)) end
	end)
	Hub:Notify(ok and ("PlaceId " .. game.PlaceId .. " copied") or ("PlaceId: " .. game.PlaceId))
end

-- Azure
do
	local p = Hub:Page("Azure", true)
	local l = p:Section("HUB", 1)
	l:Toggle("Enable Hub", "hub.enabled", true)
	l:Toggle("Notifications", "ui.notifications", true)
	l:Toggle("Watermark", "ui.watermark", false)
	l:Info("Hide with \u{25CB}, restore with the menu keybind.")
	l = p:Section("ABOUT", 2)
	l:Info("Azure v" .. Hub.Version)
	l:Info("Place: " .. game.PlaceId)
	l:Info("Running in: " .. envName())
	l:Info("Player: " .. LocalPlayer.Name)
end

-- SHOOTING
do
	local p = Hub:Page("SHOOTING", true)
	local l = p:Section("AUTO SHOOTING", 1)
	l:Toggle("Auto Shoot", "shoot.auto", false)
	l:Keybind("Shoot Key (Hold)", "shoot.key", "E")
	l:Toggle("Perfect Release / Auto Green", "shoot.perfect", true)
	l:Slider("Shot Range (studs)", "shoot.range", 10, 100, 60)
	l = p:Section("RELEASE", 2)
	l:Slider("Green Release %", "shoot.greenAt", 50, 100, 90)
	l:Slider("Release Delay (ms)", "shoot.delay", 0, 300, 0)
	l:Dropdown("Release Input", "shoot.device",
		{ "Auto", "Keyboard (E)", "Controller (Square)" }, "Auto")
	l:Info("Auto Green watches the shot meter and releases inside the green zone. It works on keyboard and on a PS5/Xbox controller. If it never fires, enable the Meter in the game's settings.")
	l:Info("Auto Shoot needs game internals - not active yet.")
end

-- PLAYER
do
	local p = Hub:Page("PLAYER", true)
	local l = p:Section("CHARACTER", 1)
	l:Slider("Walk Speed", "player.speed", 16, 100, 16)
	l:Toggle("Auto Sprint", "player.sprint", false)
	l:Slider("Sprint Speed", "player.sprintSpeed", 16, 120, 40)
	l:Slider("Jump Power", "player.jump", 50, 150, 50)
	l:Toggle("Infinite Stamina", "player.stamina", false)
	l:Toggle("No Fall Damage", "player.noFall", false)
	l:Info("Speed, Auto Sprint and Jump Power work on keyboard AND controller - they drive the Humanoid directly.")
	l = p:Section("CAMERA", 2)
	l:Slider("Field of View", "player.fov", 60, 120, 70)
	l:Toggle("Fullbright", "player.fullbright", false)
end

-- DRIBBLING
do
	local p = Hub:Page("DRIBBLING", true)
	local l = p:Section("AUTO DRIBBLE", 1)
	l:Toggle("Auto Dribble", "dribble.auto", false)
	l:Keybind("Dribble Key (Hold)", "dribble.key", "X")
	l:Slider("Crossover Speed (studs/sec)", "dribble.speed", 5, 60, 25)
	l:Toggle("Auto Spin Move", "dribble.spin", false)
	l = p:Section("GLIDES", 2)
	l:Dropdown("Glide For", "dribble.glideFor",
		{ "None", "On Ball", "Off Ball", "Everyone" }, "None")
	l:Slider("Glide Speed (studs/sec)", "dribble.glideSpeed", 1, 10, 3.8, 1)
	l:Slider("Glide Engage (studs)", "dribble.glideEngage", 0, 100, 48)
	l:Toggle("Auto Behind the Back", "dribble.behindBack", false)
end

-- DEFENSE
do
	local p = Hub:Page("DEFENSE", true)
	local l = p:Section("AUTO BLOCK", 1)
	l:Toggle("Auto Block", "defense.autoBlock", false)
	l:Keybind("Block Key (Hold)", "defense.blockKey", "G")
	l:Slider("MASTER Range (all)", "defense.masterRange", 1, 50, 18)
	l:Toggle("Opponents Only", "defense.opponentsOnly", false)
	l:Dropdown("Block These Shots", "defense.shots", {
		"Layup", "Dunk", "Jump Shot", "3 Pointer", "Fadeaway",
		"Alley-Oop", "Free Throw", "Floater", "Post Shot", "Tip Shot",
	}, {
		"Layup", "Dunk", "Jump Shot", "3 Pointer", "Fadeaway",
		"Alley-Oop", "Free Throw", "Floater", "Post Shot", "Tip Shot",
	}, true)
	l:Slider("Max Distance From Rim..", "defense.rimDist", 10, 100, 50)
	l = p:Section("AUTO REBOUND", 1)
	l:Toggle("Auto Rebound", "defense.autoRebound", false)
	l:Keybind("Rebound Key (Hold)", "defense.reboundKey", "R")
	l:Slider("Rebound Range (all)", "defense.reboundRange", 1, 50, 20)
	l:Toggle("Jump at Apex", "defense.apex", false)
	l = p:Section("DEFENSIVE GLIDES", 2)
	l:Dropdown("Glide For", "defense.glideFor",
		{ "None", "Teammates", "Opponents", "Everyone" }, "None")
	l:Slider("Block Speed (studs/sec)", "defense.blockSpeed", 1, 10, 3.8, 1)
	l:Slider("Block Engage (studs)", "defense.blockEngage", 0, 100, 48)
	l:Slider("Rebound Speed (studs/sec)", "defense.reboundSpeed", 1, 10, 3.8, 1)
	l:Slider("Rebound Engage (studs)", "defense.reboundEngage", 0, 100, 48)
	l:Toggle("Rebound: Glide to Ghost", "defense.ghostGlide", false)
end

-- EXTRAS
do
	local p = Hub:Page("EXTRAS", true)
	local l = p:Section("MISC", 1)
	l:Toggle("Anti-AFK", "extras.antiAfk", true)
	l:Toggle("Auto Save Config", "ui.autoSave", true)
	l:Toggle("FPS Boost", "extras.fps", false)
	l:Info("Auto save writes Azure_config.json when supported.")
	l = p:Section("TOOLS", 2)
	l:Button("Server", "Rejoin", rejoinServer)
	l:Button("Server", "Server Hop", serverHop)
	l:Button("Character", "Reset", resetCharacter)
	l:Button("Place ID", "Copy", copyPlaceId)
end

-- SETTINGS
do
	local p = Hub:Page("SETTINGS", true)
	local l = p:Section("INTERFACE", 1)
	l:Keybind("Menu Keybind", "ui.menuKey", "RightShift")
	l:Slider("UI Scale", "ui.scale", 0.8, 1.2, 1, 2)
	l:Dropdown("Accent Color", "ui.accent",
		{ "Gold", "Red", "Cyan", "Purple", "Green", "White" }, "Gold")
	l:Toggle("UI Animations", "ui.animations", true)
	l = p:Section("CONFIG", 2)
	l:Button("File", "Save", function()
		Hub:Notify(saveConfigFile() and "Config saved"
			or (fileAPI() and "Save failed" or "File API unavailable"))
	end)
	l:Button("File", "Load", function() Hub:LoadConfig() end)
	l:Button("File", "Reset", function() Hub:ResetConfig() end)
	l:Button("UI", "Destroy", function() Hub:Destroy() end)
	l:Info("\u{25CB} hide \u{2022} \u{2014} minimize \u{2022} X destroy")
end

-- PRACTICAL BASKETBALL (game tab - offsets)
do
	local p = Hub:Page("PRACTICAL BASKETBALL", true)
	local l = p:Section("AIM OFFSETS", 1)
	l:Toggle("Use Offsets", "offsets.enabled", false)
	l:Slider("Offset X (studs)", "offsets.x", -20, 20, 0)
	l:Slider("Offset Y (studs)", "offsets.y", -20, 20, 0)
	l:Slider("Offset Z (studs)", "offsets.z", -20, 20, 0)
	l = p:Section("BLOCK / REBOUND OFFSETS", 2)
	l:Slider("Block Offset Y (studs)", "offsets.blockY", -10, 10, 0)
	l:Slider("Rebound Offset Y (studs)", "offsets.reboundY", -10, 10, 0)
	l:Toggle("Auto Offset to Rim", "offsets.autoRim", false)
	l:Info("Offsets are applied to block/rebound/glide target positions.")
end
end)

if not buildOk then
	local msg = "content build error: " .. tostring(buildErr)
	print("[Azure] " .. msg)
	warn("[Azure] " .. msg)
	task.spawn(function() Hub:Notify(msg) end)
end

-- ------------------------------------------------- Window behaviour ---
local minimized = false

local function viewportSize()
	local cam = workspace.CurrentCamera
	return (cam and cam.ViewportSize) or Vector2.new(1280, 720)
end

titleBar.InputBegan:Connect(function(input)
	if not IsPrimary(input.UserInputType) then return end
	local target = input.Target
	if target and titleButtons[target] then return end
	closePopups()
	local vw, vh = viewportSize().X, viewportSize().Y
	local grabX = (0.5 * vw + window.Position.X.Offset) - MousePos().X
	local grabY = (0.5 * vh + window.Position.Y.Offset) - MousePos().Y
	beginDrag(function(inp)
		local offX = inp.Position.X + grabX - 0.5 * vw
		local offY = inp.Position.Y + grabY - 0.5 * vh
		local h = minimized and TITLE_H or WINDOW_H
		local halfW = WINDOW_W * uiScale.Scale / 2
		local halfH = h * uiScale.Scale / 2
		offX = math.clamp(offX, halfW - 0.5 * vw, vw - halfW - 0.5 * vw)
		offY = math.clamp(offY, halfH - 0.5 * vh, vh - halfH - 0.5 * vh)
		window.Position = UDim2.new(0.5, offX, 0.5, offY)
	end, function() end)
end)

local function setMinimized(m)
	if m == minimized then return end
	minimized = m
	closePopups()
	body.Visible = not m
	local scale = uiScale.Scale
	local top = (0.5 * viewportSize().Y + window.Position.Y.Offset) - (WINDOW_H * scale / 2)
	local newH = m and TITLE_H or WINDOW_H
	local targetY = (top + newH * scale / 2) - 0.5 * viewportSize().Y
	local targetSize = UDim2.new(1, 0, 0, newH)
	local targetPos = UDim2.new(0.5, window.Position.X.Offset, 0.5, targetY)
	if State["ui.animations"] == false then
		window.Size, window.Position = targetSize, targetPos
	else
		local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(window, info, { Size = targetSize }):Play()
		TweenService:Create(window, info, { Position = targetPos }):Play()
	end
end

btnHide.MouseButton1Click:Connect(function()
	closePopups()
	window.Visible = false
	Hub:Notify("UI hidden - press " .. tostring(State["ui.menuKey"]) .. " to restore")
end)
btnMin.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
btnKill.MouseButton1Click:Connect(function() Hub:Destroy() end)

trackConn(UIS.InputBegan:Connect(function(input)
	if capturing then capturing(input) return end
	if UIS:GetFocusedTextBox() then return end
	local key = State["ui.menuKey"]
	if not key then return end
	local matched = (input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode.Name == key)
		or (input.UserInputType.Name == key)
		or (input.UserInputType == Enum.UserInputType.Gamepad1
			and input.KeyCode == Enum.KeyCode.ButtonSelect) -- controller menu toggle
	if matched then
		closePopups()
		window.Visible = not window.Visible
		if window.Visible and State["ui.animations"] ~= false then
			uiScale.Scale = 0.94
			TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad),
				{ Scale = 1 }):Play()
		end
		-- controller focus: jump the selection cursor onto the sidebar
		pcall(function()
			if window.Visible and input.UserInputType == Enum.UserInputType.Gamepad1 then
				GuiService.SelectedObject = TabButtons["Azure"]
			elseif not window.Visible then
				GuiService.SelectedObject = nil
			end
		end)
	end
end))

-- ------------------------------------------------------------ Watermark ---
local watermark = New("TextLabel", {
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.fromOffset(10, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Theme.Row,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Theme.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	Parent = gui,
	ZIndex = 50,
})
AddCorner(watermark, 6)
AddStroke(watermark, Theme.RowStroke, 0.3, 1)
New("UIPadding", {
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	Parent = watermark,
})

local fps, frames, lastCheck = 0, 0, os.clock()
trackConn(RunService.Heartbeat:Connect(function()
	frames = frames + 1
	local now = os.clock()
	if now - lastCheck >= 1 then
		fps = math.floor(frames / (now - lastCheck))
		frames, lastCheck = 0, now
		if watermark.Visible then
			watermark.Text = "Azure  |  " .. LocalPlayer.Name .. "  |  " .. fps .. " FPS"
		end
	end
end))

-- -------------------------------------------------------------- Anti-AFK ---
local VirtualUser = game:GetService("VirtualUser")
trackConn(LocalPlayer.Idled:Connect(function()
	if State["extras.antiAfk"] == false then return end
	pcall(function()
		local cf = workspace.CurrentCamera and workspace.CurrentCamera.CFrame
		VirtualUser:Button2Down(Vector2.new(0, 0), cf)
		task.wait(0.1)
		VirtualUser:Button2Up(Vector2.new(0, 0), cf)
	end)
end))

-- ------------------------------------------------------ State listeners ---
local saveToken = 0
Hub.Changed:Connect(function(id, value)
	if id == "ui.accent" then
		applyAccent(AccentNames[value] or AccentNames.Gold)
	elseif id == "ui.scale" then
		uiScale.Scale = math.clamp(tonumber(value) or 1, 0.8, 1.2)
	elseif id == "ui.watermark" then
		watermark.Visible = value == true
	elseif id == "extras.fps" then
		pcall(function()
			if typeof(setfpscap) == "function" then setfpscap(value and 144 or 60) end
		end)
	elseif id == "player.sprint" then
		Hub:Notify(value == true
			and ("Auto Sprint ON - speed " .. tostring(State["player.sprintSpeed"]))
			or "Auto Sprint OFF")
	end
	if State["ui.autoSave"] == false then return end
	saveToken = saveToken + 1
	local mine = saveToken
	task.delay(1.5, function()
		if mine == saveToken then saveConfigFile() end
	end)
end)

-- ------------------------------------------------------- Gameplay engine ---
-- Real behavior for Practical Basketball. Everything here is input-agnostic:
-- it drives the Humanoid and reads the shot GUI, so it works the same on
-- keyboard/mouse and on a PS5/Xbox controller.

local function getHumanoid()
	local ok, hum = pcall(function()
		local char = LocalPlayer.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end)
	return ok and hum or nil
end

-- movement: walk speed + auto sprint + jump power, keep-alive style because
-- games often re-apply their own values on possession/respawn
task.spawn(function()
	while task.wait(0.25) do
		local hum = getHumanoid()
		if hum then
			local target = tonumber(State["player.speed"]) or 16
			if State["player.sprint"] == true then
				target = tonumber(State["player.sprintSpeed"]) or target
			end
			if target ~= 16 then
				pcall(function() hum.WalkSpeed = target end)
			end
			local jump = tonumber(State["player.jump"])
			if jump and jump ~= 50 then
				pcall(function()
					hum.UseJumpPower = true
					hum.JumpPower = jump
				end)
			end
		end
	end
end)

-- ----------------------------------------------------------- Auto green ---
-- The game meters every shot: hold the shoot button (E / Square / X), a meter
-- fills, release inside the green zone. Perfect Release tracks the meter GUI
-- and simulates the release at the configured fill percentage.

local SHOOT_INPUTS = {
	keyboard = {
		inputType = Enum.UserInputType.Keyboard,
		code = Enum.KeyCode.E, label = "E",
	},
	gamepad = {
		inputType = Enum.UserInputType.Gamepad1,
		code = Enum.KeyCode.ButtonX, label = "Square",
	},
}

local heldShoot, heldSince = nil, 0 -- what the player is physically holding
trackConn(UIS.InputBegan:Connect(function(input)
	for _, k in pairs(SHOOT_INPUTS) do
		if input.UserInputType == k.inputType and input.KeyCode == k.code then
			heldShoot, heldSince = k, os.clock()
		end
	end
end))
trackConn(UIS.InputEnded:Connect(function(input)
	for _, k in pairs(SHOOT_INPUTS) do
		if input.UserInputType == k.inputType and input.KeyCode == k.code
			and heldShoot == k then
			heldShoot = nil
		end
	end
end))

local VIM = game:GetService("VirtualInputManager")
local vimOk = VIM ~= nil and VIM.SendKeyEvent ~= nil

local function releaseShoot()
	local mode = State["shoot.device"] or "Auto"
	local k
	if mode == "Keyboard (E)" then k = SHOOT_INPUTS.keyboard
	elseif mode == "Controller (Square)" then k = SHOOT_INPUTS.gamepad
	else k = heldShoot or SHOOT_INPUTS.gamepad end
	local ok = pcall(function()
		VIM:SendKeyEvent(k.inputType, k.code, false, game)
	end)
	return ok, k
end

local METER_HINTS = {
	"meter", "shotbar", "shot_bar", "shootbar", "shoot_bar", "shotmeter",
	"shot_meter", "timingbar", "timing", "releasebar", "release_bar",
	"greenbar", "green_bar", "powerbar", "power_bar", "aimbar", "aim_bar",
	"shotui", "shot_ui", "shooting", "swing", "hotzone",
}
local function nameLooksLikeMeter(name)
	local n = string.lower(tostring(name))
	for _, hint in ipairs(METER_HINTS) do
		if string.find(n, hint, 1, true) then return true end
	end
	return false
end

local playerGui = nil
pcall(function()
	playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		or LocalPlayer:WaitForChild("PlayerGui", 5)
end)

local function collectMeters()
	local out = {}
	if not playerGui then return out end
	pcall(function()
		if not playerGui.Parent then -- PlayerGui can be rebuilt; reacquire
			playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		end
	end)
	pcall(function()
		for _, d in ipairs(playerGui:GetDescendants()) do
			local visible = false
			pcall(function() visible = d:IsA("GuiObject") and d.Visible end)
			if visible and nameLooksLikeMeter(d.Name) then
				out[#out + 1] = d
			end
		end
	end)
	-- meters are compact; a big panel named e.g. "Shooting" is likely the HUD
	table.sort(out, function(a, b)
		local function area(o)
			local ok, sz = pcall(function() return o.AbsoluteSize end)
			if ok and sz then return sz.X * sz.Y end
			return math.huge
		end
		return area(a) < area(b)
	end)
	return out
end

local meterScan = nil
local warnedNoMeter = false

task.spawn(function()
	while task.wait(1 / 30) do
		if State["shoot.perfect"] ~= true or not playerGui then
			meterScan = nil
		else
			local candidates = collectMeters()
			if #candidates == 0 then
				meterScan = nil
				if heldShoot and not warnedNoMeter
					and os.clock() - heldSince > 1.5 then
					warnedNoMeter = true
					Hub:Notify("Shot meter not found - enable the Meter "
						.. "in the game's settings for Auto Green")
				end
			else
				local cont = candidates[1]
				if not meterScan or meterScan.container ~= cont then
					-- new shot: snapshot every part of the meter
					meterScan = {
						container = cont, base = {}, maxDelta = {},
						released = false, startedAt = os.clock(),
					}
					pcall(function()
						for _, d in ipairs(cont:GetDescendants()) do
							if d:IsA("GuiObject") then
								meterScan.base[d] = d.AbsoluteSize
							end
						end
					end)
				else
					-- measure how much the bar has grown since the snapshot
					local progress = 0
					pcall(function()
						for obj, base in pairs(meterScan.base) do
							local sz = obj.AbsoluteSize
							local dx = math.abs(sz.X - base.X)
							local dy = math.abs(sz.Y - base.Y)
							local delta = math.max(dx, dy)
							local prevMax = meterScan.maxDelta[obj] or 0
							if delta > prevMax then
								meterScan.maxDelta[obj] = delta
							end
							local denom = meterScan.maxDelta[obj]
							if denom > 8 then -- real bar, not layout noise
								local ratio = math.clamp(
									delta / denom, 0, 1)
								if ratio > progress then progress = ratio end
							end
						end
					end)
					if progress < 0.15 then meterScan.released = false end
					local greenAt = (tonumber(State["shoot.greenAt"]) or 90) / 100
					if not meterScan.released and progress >= greenAt
						and os.clock() - meterScan.startedAt > 0.15 then
						meterScan.released = true
						local delay = (tonumber(State["shoot.delay"]) or 0) / 1000
						task.delay(delay, function()
							local ok, k = releaseShoot()
							if ok then
								Hub:Notify("Auto Green released (" .. k.label .. ")")
							else
								Hub:Notify("Auto Green could not release input"
									.. " - check VirtualInputManager support")
							end
						end)
					end
				end
			end
		end
	end
end)

if not vimOk then
	task.spawn(function()
		Hub:Notify("Input simulation unavailable - Auto Green release is disabled")
	end)
end

-- ------------------------------------------------------------- Startup ---
Pristine = DeepCopy(State)

local loaded = readConfigFile()
if loaded then pushAll(loaded) end

applyAccent(AccentNames[State["ui.accent"]] or AccentNames.Gold)
uiScale.Scale = math.clamp(tonumber(State["ui.scale"]) or 1, 0.8, 1.2)
watermark.Visible = State["ui.watermark"] == true

for _, page in pairs(Pages) do page:_updateCanvas() end

switchPage("Azure")

-- controller support: let the PS5/Xbox thumbstick + D-pad navigate the UI
pcall(function()
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiButton") then d.Selectable = true end
	end
end)

if State["ui.animations"] ~= false then
	uiScale.Scale = 0.94
	TweenService:Create(uiScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { Scale = math.clamp(tonumber(Pristine["ui.scale"]) or 1, 0.8, 1.2) }):Play()
end

pcall(function()
	_G.Azure = Hub
	if typeof(getgenv) == "function" then getgenv().Azure = Hub end
end)

print("[Azure] v" .. Hub.Version .. " loaded - "
	.. tostring(State["ui.menuKey"]) .. " toggles the UI")

do -- visible load banner: green = built, red = exact error
	local n = 0
	for _ in pairs(Pages) do n = n + 1 end
	local okBuild = (buildOk ~= false) and n == 8
	local banner = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 720, 0, 34),
		BackgroundColor3 = okBuild and Color3.fromRGB(30, 130, 70)
			or Color3.fromRGB(175, 40, 40),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = okBuild and 13 or 11,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = okBuild
			and ("[Azure] OK - " .. n .. "/8 pages built - "
				.. tostring(State["ui.menuKey"]) .. " toggles the menu")
			or ("[Azure] BUILD ERROR: " .. tostring(buildErr)),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = gui,
		ZIndex = 400,
	})
	AddCorner(banner, 6)
	if okBuild then
		task.delay(7, function()
			pcall(function() banner:Destroy() end)
		end)
	end
end

task.spawn(function()
	task.wait(0.5)
	Hub:Notify("Azure loaded - " .. tostring(State["ui.menuKey"]) .. " to toggle")
end)

return Hub
