-- Health Trail: a lingering "health lost" bar behind any nameplate health bar.
-- Works with secret health values: nothing here compares or does math on health.
-- Health values are only stored and passed to StatusBar:SetMinMaxValues/SetValue.

local DEFAULTS = {
    linger = 0.6,                        -- seconds the lost chunk holds before draining
    trailColor = { 1, 0.85, 0.5, 0.9 },    -- pale gold
    bgColor = { 0, 0, 0, 0.6 },            -- replaces the host bar's background
}

local db
local trails = {} -- [plate] = { bar, host, unit, token, pending, timerRunning }
local EASE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

---------------------------------------------------------------------------
-- Finding the health bar
---------------------------------------------------------------------------

local function IsStatusBar(obj)
    return obj and obj.GetObjectType and obj:GetObjectType() == "StatusBar"
end

local function Usable(bar)
    return IsStatusBar(bar) and not bar:IsForbidden() and bar:IsVisible() and not bar.isHealthTrail
end

-- Known layouts first (checked for visibility, so a hidden Blizzard frame
-- underneath a replacement addon is ignored).
local function KnownHealthBar(plate)
    local candidates = {}
    if plate.unitFrame then                              -- Plater
        candidates[#candidates + 1] = plate.unitFrame.healthBar
    end
    if plate.UnitFrame then                              -- Blizzard default
        candidates[#candidates + 1] = plate.UnitFrame.healthBar
        local c = plate.UnitFrame.HealthBarsContainer
        if c then candidates[#candidates + 1] = c.healthBar end
    end
    for _, bar in ipairs(candidates) do
        if Usable(bar) then return bar end
    end
end

-- Fallback for other addons: the widest visible status bar on the plate
-- that isn't obviously a cast or power bar.
local function ScanForHealthBar(frame, depth, best)
    if depth > 5 then return best end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not child:IsForbidden() and not child.isHealthTrail then
            if Usable(child) then
                local name = (child:GetName() or ""):lower()
                if not name:find("cast") and not name:find("power") then
                    if not best or child:GetWidth() > best:GetWidth() then
                        best = child
                    end
                end
            end
            best = ScanForHealthBar(child, depth + 1, best)
        end
    end
    return best
end

-- Hide the host bar's own background textures so the trail behind shows through.
local function HideHostBackground(host)
    local fill = host:GetStatusBarTexture()
    for _, region in ipairs({ host:GetRegions() }) do
        if region ~= fill and region:GetObjectType() == "Texture"
            and region:GetDrawLayer() == "BACKGROUND" then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Trail bars
---------------------------------------------------------------------------

local function GetTrail(plate, host)
    local t = trails[plate]
    if not t then
        local bar = CreateFrame("StatusBar")
        bar.isHealthTrail = true
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bar.bg = bg
        t = { bar = bar, token = 0 }
        trails[plate] = t
    end

    local bar = t.bar
    bar:SetStatusBarColor(unpack(db.trailColor))
    bar.bg:SetColorTexture(unpack(db.bgColor))

    t.host = host
    bar:SetParent(host:GetParent())
    bar:ClearAllPoints()
    bar:SetAllPoints(host)
    bar:SetFrameStrata(host:GetFrameStrata())
    bar:SetFrameLevel(math.max(host:GetFrameLevel() - 1, 0))
    return t
end

local function Snap(t, unit)
    t.token = t.token + 1          -- cancels any pending drain
    t.timerRunning = false
    t.pending = nil
    t.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    t.bar:SetValue(UnitHealth(unit))
    t.bar:Show()
end

local function Attach(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return end

    local host = KnownHealthBar(plate) or ScanForHealthBar(plate, 1, nil)
    if not host then return end

    local t = GetTrail(plate, host)
    t.unit = unit
    HideHostBackground(host)
    Snap(t, unit)
end

local function Detach(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local t = plate and trails[plate]
    if not t then return end
    t.token = t.token + 1
    t.timerRunning = false
    t.unit = nil
    t.bar:Hide()
end

local function OnHealth(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local t = plate and trails[plate]
    if not t or t.unit ~= unit then return end

    HideHostBackground(t.host)     -- some addons re-show their background
    t.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    t.pending = UnitHealth(unit)   -- stored, never compared

    if t.timerRunning then return end
    t.timerRunning = true
    local token = t.token

    C_Timer.After(db.linger, function()
        if t.token ~= token then return end -- plate was reused or removed
        t.timerRunning = false
        if EASE then
            t.bar:SetValue(t.pending, EASE)
        else
            t.bar:SetValue(t.pending)
        end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("UNIT_MAXHEALTH")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "HealthTrail" then return end
        HealthTrailDB = HealthTrailDB or {}
        db = HealthTrailDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        f:UnregisterEvent("ADDON_LOADED")
    elseif not db then
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- Defer one frame so the nameplate addon has built/shown its bar.
        local unit = arg1
        C_Timer.After(0, function()
            if UnitExists(unit) then Attach(unit) end
        end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        Detach(arg1)
    elseif arg1 and arg1:find("^nameplate") then
        OnHealth(arg1)
    end
end)

---------------------------------------------------------------------------
-- /healthtrail <seconds>
---------------------------------------------------------------------------

SLASH_HEALTHTRAIL1 = "/healthtrail"
SlashCmdList.HEALTHTRAIL = function(msg)
    local n = tonumber(msg)
    if n and n >= 0 and n <= 5 then
        db.linger = n
        print(("Health Trail: linger set to %.2f s"):format(n))
    else
        print(("Health Trail: linger is %.2f s. Usage: /healthtrail <0-5>"):format(db.linger))
    end
end
