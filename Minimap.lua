-- Health Trail minimap button (no libraries).
-- Left-click: options. Right-click: toggle health ticks. Drag: move around the minimap.
-- Named and parented to the Minimap so minimap button-bag addons can collect it.

local _, ns = ...

local ICON = "Interface\\Icons\\Spell_Holy_FlashHeal"
-- The tracking-border art's ring sits slightly right/down of the button's
-- centre; nudge the icon to match. Adjust if it still looks off-centre.
local ICON_X, ICON_Y = 1, -1
local button

-- Minimap shapes that have square corners, by quadrant (for addons that
-- reshape the minimap via GetMinimapShape). true = round in that quadrant.
local SHAPES = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function UpdatePosition()
    local angle = math.rad(ns.db.minimap.angle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end

    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local round = (SHAPES[shape] or SHAPES.ROUND)[quadrant]
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    if round then
        x, y = x * w, y * h
    else
        -- Square corner: push out to the edge, then clamp to the square.
        local diagW, diagH = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Health Trail", 1, 1, 1)
    GameTooltip:AddLine("Left-click: open options", nil, nil, nil, true)
    GameTooltip:AddLine(("Right-click: turn health ticks %s"):format(ns.db.showTicks and "off" or "on"), nil, nil, nil, true)
    GameTooltip:AddLine("Drag: move this button", nil, nil, nil, true)
    GameTooltip:Show()
end

local function CreateButton()
    local b = CreateFrame("Button", "HealthTrailMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("CENTER", ICON_X, ICON_Y)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("CENTER", ICON_X, ICON_Y)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.SetShowTicks(not ns.db.showTicks)
            if GameTooltip:GetOwner() == self then ShowTooltip(self) end
        else
            ns.ToggleOptions()
        end
    end)
    b:SetScript("OnMouseDown", function() icon:SetTexCoord(0, 1, 0, 1) end)
    b:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function ns.SetMinimapShown(show)
    ns.db.minimap.hide = not show
    if button then button:SetShown(show) end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.InitMinimap()
    if not Minimap then return end
    button = CreateButton()
    UpdatePosition()
    button:SetShown(not ns.db.minimap.hide)
end

-- Retail AddOns menu (the "addon compartment" by the minimap), via the TOC.
function HealthTrail_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then
        ns.SetShowTicks(not ns.db.showTicks)
    else
        ns.ToggleOptions()
    end
end
