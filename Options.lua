-- Health Trail options window.
-- A standalone movable window (opened by /healthtrail or the minimap button),
-- plus an entry in the game's AddOns settings list that opens it.
-- Built without templates that vary between game versions where possible.

local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WIDTH, HEIGHT = 720, 470
local COLUMN_WIDTH = 290

local window
local controls = {} -- each has :Refresh() to re-read its value from ns.db

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function HasTemplate(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo(name) ~= nil
    end
    return true -- older clients: assume the long-standing templates exist
end

local function AddTooltip(frame, title, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Header(parent, text, anchor, y, x)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -16)
    fs:SetText(text)
    return fs
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function CreateCheck(parent, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local text = cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    AddTooltip(cb, label, tooltip)
    function cb:Refresh() self:SetChecked(get()) end
    controls[#controls + 1] = cb
    return cb
end

local function CreateSlider(parent, label, tooltip, minV, maxV, step, fmt, get, set)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(COLUMN_WIDTH - 20, 40)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT")
    title:SetText(label)
    local valueText = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    valueText:SetPoint("TOPRIGHT")

    local s = CreateFrame("Slider", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    s:SetPoint("RIGHT", holder, "RIGHT")
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local function Round(v) return math.floor(v / step + 0.5) * step end

    s:SetScript("OnValueChanged", function(self, v)
        v = Round(v)
        valueText:SetText(fmt:format(v))
        if not self.updating then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.min(maxV, math.max(minV, self:GetValue() + delta * step)))
    end)
    AddTooltip(s, label, tooltip)

    function holder:Refresh()
        s.updating = true
        s:SetValue(get())
        valueText:SetText(fmt:format(get()))
        s.updating = false
    end
    controls[#controls + 1] = holder
    return holder
end

-- Opens the game's colour picker; works with both the modern
-- (SetupColorPickerAndShow) and the older field-based API.
local function OpenColorPicker(color, onChange)
    local r, g, b, a = unpack(color)
    a = a or 1

    local function Current()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if ColorPickerFrame.GetColorAlpha then
            na = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame then
            na = 1 - OpacitySliderFrame:GetValue() -- old API stores transparency
        end
        return nr, ng, nb, na
    end
    local function Changed() onChange(Current()) end
    local function Cancel() onChange(r, g, b, a) end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = Changed, opacityFunc = Changed, cancelFunc = Cancel,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = { r, g, b, a }
        ColorPickerFrame.func = Changed
        ColorPickerFrame.opacityFunc = Changed
        ColorPickerFrame.cancelFunc = Cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ShowUIPanel(ColorPickerFrame)
    end
end

local function CreateColor(parent, label, tooltip, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)

    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.6, 0.6, 0.6, 1)
    -- White backing so the swatch shows the colour's transparency.
    local back = b:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", 2, -2)
    back:SetPoint("BOTTOMRIGHT", -2, 2)
    back:SetColorTexture(1, 1, 1, 1)
    local swatch = b:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    swatch:SetTexture(WHITE)

    local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", b, "RIGHT", 8, 0)
    text:SetText(label)

    function b:Refresh() swatch:SetVertexColor(unpack(ns.db[key])) end

    b:SetScript("OnClick", function(self)
        OpenColorPicker(ns.db[key], function(r, g, bl, a)
            ns.db[key] = { r, g, bl, a }
            self:Refresh()
            ns.Refresh()
        end)
    end)
    AddTooltip(b, label, tooltip)
    controls[#controls + 1] = b
    return b
end

local KIND_LABELS = { player = "Players", normal = "Normal mobs", elite = "Elites", boss = "Bosses" }
-- Smallest to largest, with Default in the middle.
local PRESET_ORDER = { "10", "25", "50", "default", "200", "400", "1000", "custom" }
local PRESET_LABELS = {
    ["10"] = "10%", ["25"] = "25%", ["50"] = "50%", default = "Default",
    ["200"] = "200%", ["400"] = "400%", ["1000"] = "1000%", custom = "Custom",
}

local function Num(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- Short form for dropdown labels: 2500 -> 2.5k, 100000 -> 100k, 1000000 -> 1M.
local function Short(n)
    local function trim(x) return (("%.1f"):format(x):gsub("%.0$", "")) end
    if n >= 1000000 then return trim(n / 1000000) .. "M" end
    if n >= 1000 then return trim(n / 1000) .. "k" end
    return tostring(n)
end

local function PresetText(kind, preset)
    if preset == "custom" then return "Custom" end
    local minor = math.floor(ns.TICK_BASE[kind] * ns.TICK_PRESETS[preset] + 0.5)
    return ("%s  (%s / %s)"):format(PRESET_LABELS[preset], Short(minor), Short(minor * ns.MajorEvery()))
end

local dropdownCount = 0

-- Option text may be a function, so labels can reflect current settings.
local function OptText(opt)
    if type(opt.text) == "function" then return opt.text() end
    return opt.text
end

-- Dropdown with the modern menu API where available, else UIDropDownMenu.
-- options: { { value, text }, ... }. Returns the frame, a refresh function,
-- and an x offset that lines the dropdown up with other controls.
local function CreateDropdown(parent, width, options, get, set)
    if MenuUtil and HasTemplate("WowStyle1DropdownTemplate") then
        local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dd:SetWidth(width)
        dd:SetupMenu(function(_, root)
            for _, opt in ipairs(options) do
                root:CreateRadio(OptText(opt),
                    function() return get() == opt.value end,
                    function() set(opt.value) end)
            end
        end)
        return dd, function() dd:GenerateMenu() end, 0
    end

    dropdownCount = dropdownCount + 1
    local dd = CreateFrame("Frame", "HealthTrailDropdown" .. dropdownCount, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width - 30)
    local function TextFor(value)
        for _, opt in ipairs(options) do
            if opt.value == value then return OptText(opt) end
        end
        return ""
    end
    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = OptText(opt)
            info.value = opt.value
            info.checked = get() == opt.value
            info.func = function()
                set(opt.value)
                UIDropDownMenu_SetText(dd, OptText(opt))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    -- UIDropDownMenuTemplate has ~16px of empty space on its left.
    return dd, function() UIDropDownMenu_SetText(dd, TextFor(get())) end, -16
end

-- One row: mob type label, preset dropdown, and a whole-number box for Custom.
local function CreateSpacingRow(parent, kind)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(COLUMN_WIDTH, 26)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT")
    label:SetWidth(76)
    label:SetJustifyH("LEFT")
    label:SetText(KIND_LABELS[kind])

    local options = {}
    for _, preset in ipairs(PRESET_ORDER) do
        options[#options + 1] = { value = preset, text = function() return PresetText(kind, preset) end }
    end

    local dd, refreshDropdown, xFix = CreateDropdown(row, 140, options,
        function() return ns.db.tickSpacing[kind].preset end,
        function(v)
            ns.db.tickSpacing[kind].preset = v
            ns.Refresh()
        end)
    dd:SetPoint("LEFT", label, "RIGHT", xFix, 0)

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(64, 20)
    if xFix == 0 then
        box:SetPoint("LEFT", dd, "RIGHT", 10, 0)
    else
        box:SetPoint("LEFT", dd, "RIGHT", -6, 2) -- old dropdown has padding on the right too
    end
    box:SetAutoFocus(false)
    box:SetNumeric(true) -- digits only, so whole numbers
    box:SetMaxLetters(8)

    local thick = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    thick:SetPoint("LEFT", box, "RIGHT", 6, 0)

    local function Saved() return ns.db.tickSpacing[kind].custom end
    local function Apply(self)
        local n = tonumber(self:GetText())
        if n and n >= 1 then
            ns.db.tickSpacing[kind].custom = math.min(math.floor(n), ns.MAX_CUSTOM_SPACING)
            ns.Refresh()
        end
        self:SetText(tostring(Saved()))
    end
    box:SetScript("OnEnterPressed", function(self) Apply(self); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Apply)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(Saved()))
        self:ClearFocus()
    end)
    AddTooltip(box, "Custom spacing",
        "Health between thin lines (whole number, at least 1). Thick lines follow the 'Thick line every' setting. Press Enter to apply.")

    function row:Refresh()
        refreshDropdown()
        local custom = ns.db.tickSpacing[kind].preset == "custom"
        box:SetShown(custom)
        thick:SetShown(custom)
        if not box:HasFocus() then box:SetText(tostring(Saved())) end
        thick:SetText("/ " .. Num(select(2, ns.TickSpacing(kind))))
    end
    controls[#controls + 1] = row
    return row
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function CreateWindow()
    local f
    if HasTemplate("BasicFrameTemplateWithInset") then
        f = CreateFrame("Frame", "HealthTrailOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    else
        f = CreateFrame("Frame", "HealthTrailOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end

    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "HealthTrailOptionsFrame") -- Escape closes it

    local title = f.TitleText or f.title
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -6)
    end
    title:SetText("Health Trail")

    -- Invisible anchors at the top-left of each column's content area.
    local left = CreateFrame("Frame", nil, f)
    left:SetSize(1, 1)
    left:SetPoint("TOPLEFT", 20, -36) -- below the title bar
    local right = CreateFrame("Frame", nil, f)
    right:SetSize(1, 1)
    right:SetPoint("TOPLEFT", 20 + COLUMN_WIDTH + 40, -36)

    -- Left column: Trail
    local trailHeader = Header(f, "Trail", left, 0)

    local linger = CreateSlider(f, "Linger time",
        "How long the lost chunk holds before draining away.",
        0, 5, 0.05, "%.2f s",
        function() return ns.db.linger end,
        function(v) ns.db.linger = v end)
    linger:SetPoint("TOPLEFT", trailHeader, "BOTTOMLEFT", 4, -12)

    local trailColor = CreateColor(f, "Trail colour",
        "Colour of the lingering health-lost chunk.", "trailColor")
    trailColor:SetPoint("TOPLEFT", linger, "BOTTOMLEFT", 0, -12)

    local bgColor = CreateColor(f, "Background colour",
        "Colour of the empty part of the health bar.", "bgColor")
    bgColor:SetPoint("TOPLEFT", trailColor, "BOTTOMLEFT", 0, -8)

    -- Left column: Minimap
    local mapHeader = Header(f, "Minimap", bgColor, -24, -4)

    local showMinimap = CreateCheck(f, "Show minimap button",
        "Left-click the button to open these options, right-click to toggle health ticks, drag to move it.",
        function() return not ns.db.minimap.hide end,
        function(v) if ns.SetMinimapShown then ns.SetMinimapShown(v) end end)
    showMinimap:SetPoint("TOPLEFT", mapHeader, "BOTTOMLEFT", 0, -6)

    -- Right column: Health ticks
    local tickHeader = Header(f, "Health ticks", right, 0)

    local showTicks = CreateCheck(f, "Show health ticks",
        "Vertical lines on the filled part of the health bar: thin half-height lines, and a thick full-height line every few thin lines (see 'Thick line every').",
        function() return ns.db.showTicks end,
        function(v) ns.SetShowTicks(v) end)
    showTicks:SetPoint("TOPLEFT", tickHeader, "BOTTOMLEFT", 0, -6)

    local tickColor = CreateColor(f, "Thin line colour",
        "Colour of the half-height lines.", "tickColor")
    tickColor:SetPoint("TOPLEFT", showTicks, "BOTTOMLEFT", 4, -6)

    local majorTickColor = CreateColor(f, "Thick line colour",
        "Colour of the full-height lines.", "majorTickColor")
    majorTickColor:SetPoint("TOPLEFT", tickColor, "BOTTOMLEFT", 0, -8)

    local maxLines = CreateSlider(f, "Max lines per bar",
        "How many thin lines each nameplate gets. Lines stop after this many intervals, so high-health " ..
        "targets with small spacing may have no lines on the right of the bar. Higher values use more " ..
        "hidden frames per nameplate.",
        ns.MIN_TICK_LINES, ns.MAX_TICK_LINES, 10, "%d",
        function() return ns.db.maxTickLines end,
        function(v)
            ns.db.maxTickLines = v
            ns.QueueRefresh() -- wait until the slider settles
        end)
    maxLines:SetPoint("TOPLEFT", majorTickColor, "BOTTOMLEFT", 0, -14)

    local ratioRow = CreateFrame("Frame", nil, f)
    ratioRow:SetSize(COLUMN_WIDTH, 26)
    ratioRow:SetPoint("TOPLEFT", maxLines, "BOTTOMLEFT", 0, -10)
    local ratioLabel = ratioRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ratioLabel:SetPoint("LEFT")
    ratioLabel:SetText("Thick line every")
    local ratioOptions = {}
    for _, n in ipairs(ns.MAJOR_EVERY_CHOICES) do
        ratioOptions[#ratioOptions + 1] = { value = n, text = n .. " thin lines" }
    end
    local ratioDropdown, refreshRatio, ratioX = CreateDropdown(ratioRow, 130, ratioOptions,
        function() return ns.MajorEvery() end,
        function(v)
            ns.db.majorEvery = v
            ns.Refresh() -- also updates the spacing labels below
        end)
    ratioDropdown:SetPoint("LEFT", ratioLabel, "RIGHT", 10 + ratioX, 0)
    AddTooltip(ratioDropdown, "Thick line every",
        "How many thin lines between thick lines, for every mob type. For example, with 250 spacing: " ..
        "10 gives thick lines every 2,500; 4 every 1,000; 2 every 500.")
    function ratioRow:Refresh() refreshRatio() end
    controls[#controls + 1] = ratioRow

    local spacingLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    spacingLabel:SetPoint("TOPLEFT", ratioRow, "BOTTOMLEFT", 0, -12)
    spacingLabel:SetText("Line spacing (thin / thick)")

    local previous = spacingLabel
    for _, kind in ipairs(ns.TICK_KINDS) do
        local row = CreateSpacingRow(f, kind)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == spacingLabel and -8 or -6)
        previous = row
    end

    -- Reset
    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(140, 24)
    reset:SetPoint("BOTTOM", 0, 16)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function() ns.ResetDefaults() end)
    AddTooltip(reset, "Reset to defaults", "Restores all settings except the minimap button.")

    f:SetScript("OnShow", function() ns.RefreshOptions() end)
    return f
end

-- Entry in the game's AddOns settings list with a button that opens the window.
local function RegisterSettingsCategory()
    local canvas = CreateFrame("Frame")
    canvas.name = "Health Trail"

    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Health Trail")
    local desc = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Settings are in the Health Trail window (also /healthtrail or the minimap button).")
    local open = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    open:SetText("Open options")
    open:SetScript("OnClick", function() ns.ToggleOptions(true) end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(canvas, "Health Trail")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(canvas)
    end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function ns.RefreshOptions()
    if not window or not window:IsShown() then return end
    for _, c in ipairs(controls) do c:Refresh() end
end

-- show: true = open, false = close, nil = toggle
function ns.ToggleOptions(show)
    if not window then window = CreateWindow() end
    if show == nil then show = not window:IsShown() end
    window:SetShown(show)
end

function ns.InitOptions()
    local ok, err = pcall(RegisterSettingsCategory)
    if not ok then print("Health Trail: could not add settings entry: " .. tostring(err)) end
end
