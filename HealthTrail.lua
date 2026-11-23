-- Health Trail: a lingering "health lost" bar behind any nameplate health bar.
-- Works with secret health values: the trail never compares or does math on health.
-- Health values are only stored and passed to StatusBar:SetMinMaxValues/SetValue.
-- Health ticks are placed by the game via invisible StatusBars, so they never read health either.

local _, ns = ... -- shared with Options.lua and Minimap.lua

local DB_VERSION = 1

local DEFAULTS = {
    linger = 0.6,                        -- seconds the lost chunk holds before draining
    trailColor = { 1, 0.85, 0.5, 0.9 },    -- pale gold
    bgColor = { 0, 0, 0, 0.6 },            -- replaces the host bar's background
    showTicks = true,                      -- vertical divider lines on the health bar
    tickColor = { 0.25, 0.25, 0.25, 0.7 }, -- thin lines: dark grey
    majorTickColor = { 0.2, 0.2, 0.2, 0.9 }, -- thick lines: slightly darker grey
    minimap = { hide = false, angle = 225 }, -- angle in degrees around the minimap
    maxTickLines = 100,                    -- thin lines made per bar (coverage vs. frames)
    majorEvery = 10,                       -- a thick line every N thin lines: 10, 4 or 2
    -- Per mob type: preset = "default" or a percent of the default spacing
    -- ("10" .. "1000", see ns.TICK_PRESETS), or "custom" (uses `custom`).
    -- Thick = thin x majorEvery.
    tickSpacing = {
        player = { preset = "default", custom = 100 },
        normal = { preset = "default", custom = 100 },
        elite  = { preset = "default", custom = 1000 },
        boss   = { preset = "default", custom = 10000 },
    },
}
ns.DEFAULTS = DEFAULTS

local function Copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = Copy(x) end
    return c
end

-- Fill missing keys (recursively) without overwriting saved values.
local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = Copy(v)
        elseif type(v) == "table" and type(target[k]) == "table" and #v == 0 then
            ApplyDefaults(target[k], v) -- nested settings table (not a colour array)
        end
    end
end

-- Default thin-line spacing by mob type (thick lines are majorEvery x this).
local TICK_BASE = { player = 100, normal = 100, elite = 1000, boss = 10000 }
ns.TICK_BASE = TICK_BASE
ns.TICK_KINDS = { "player", "normal", "elite", "boss" } -- display order
ns.TICK_PRESETS = {
    ["10"] = 0.1, ["25"] = 0.25, ["50"] = 0.5, default = 1,
    ["200"] = 2, ["400"] = 4, ["1000"] = 10,
}
ns.MAX_CUSTOM_SPACING = 10000000
ns.MIN_TICK_LINES, ns.MAX_TICK_LINES = 50, 500
ns.MAJOR_EVERY_CHOICES = { 10, 4, 2 }

-- Thin lines per thick line, from the saved setting (falls back to 10).
function ns.MajorEvery()
    local n = ns.db.majorEvery
    for _, choice in ipairs(ns.MAJOR_EVERY_CHOICES) do
        if n == choice then return n end
    end
    return 10
end

-- Thin and thick line spacing for a mob type from the saved settings.
function ns.TickSpacing(kind)
    local s = ns.db.tickSpacing[kind] -- ns.db: this is defined above `local db`
    local base = TICK_BASE[kind]
    local minor
    if s.preset == "custom" then
        minor = math.floor(tonumber(s.custom) or base)
        minor = math.max(1, math.min(minor, ns.MAX_CUSTOM_SPACING))
    else
        minor = math.floor(base * (ns.TICK_PRESETS[s.preset] or 1) + 0.5)
    end
    return minor, minor * ns.MajorEvery()
end

local TICK_WIDTH = 1        -- pixels
local MAJOR_TICK_WIDTH = 2  -- pixels

local db
local trails = {} -- [plate] = { bar, host, unit, token, pending, timerRunning, tickTier }
local hostTicks = {} -- [host] = { holder, mask, lines = { { bar, tex, hp }, ... } }
local tickErrorShown = false -- report a tick drawing error once per session
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

-- Some region properties (e.g. draw layer of heal-prediction textures on
-- Blizzard plates) come back as secret values, which can't be compared.
local IsSecret = issecretvalue or function() return false end

local function Plain(v)
    if IsSecret(v) then return nil end
    return v
end

-- Named background textures used by known nameplate layouts.
local KNOWN_BG_KEYS = { "bgTexture", "background", "Background", "bg" }

-- Hide the host bar's own background textures so the trail behind shows through.
local function HideHostBackground(host)
    local found = false
    for _, key in ipairs(KNOWN_BG_KEYS) do
        local tex = host[key]
        if type(tex) == "table" and tex.SetAlpha and tex ~= host then
            tex:SetAlpha(0)
            found = true
        end
    end
    if found then return end

    -- Fallback: scan regions, skipping anything whose properties are secret.
    local fill = host:GetStatusBarTexture()
    for _, region in ipairs({ host:GetRegions() }) do
        if region ~= fill
            and Plain(region:GetObjectType()) == "Texture"
            and Plain(region:GetDrawLayer()) == "BACKGROUND" then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Health ticks
-- Health values are secret, so line positions are never calculated. Each line
-- is an invisible StatusBar covering the health bar, with min/max set to the
-- unit's (secret) max health and its value set to a fixed amount (100, 200...).
-- The line is drawn at the right edge of that bar's fill, so the game places
-- it. A mask matching the health bar's fill limits the lines to current health
-- (lines beyond max health clamp to the right edge and are hidden by it too).
-- The line textures belong to the health bar itself, just above its fill, so
-- the bar's text (a higher layer or a child frame) stays on top of them.
---------------------------------------------------------------------------

local function SetPixelWidth(tex, px)
    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(tex, px, px)
    else
        tex:SetWidth(px)
    end
end

-- Mob type for line spacing (unit type isn't secret, health amount is).
local function UnitKind(unit)
    if UnitIsPlayer(unit) then return "player" end
    local class = Plain(UnitClassification(unit))
    local level = Plain(UnitLevel(unit))
    if class == "worldboss" or (level == -1 and (class == "elite" or class == "rareelite")) then
        return "boss"
    end
    if class == "elite" or class == "rareelite" then return "elite" end
    return "normal"
end

-- Spacing and line count for a unit, from the saved settings.
local function TierForUnit(unit)
    local kind = UnitKind(unit)
    local minor, major = ns.TickSpacing(kind)
    local lines = math.floor(tonumber(db.maxTickLines) or 100)
    lines = math.max(ns.MIN_TICK_LINES, math.min(lines, ns.MAX_TICK_LINES))
    return { kind = kind, minor = minor, major = major, lines = lines }
end

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Draw layer for the lines: just above the host's fill texture, below text.
local function LineLayer(host)
    local fill = host:GetStatusBarTexture()
    if fill then
        local layer, sub = fill:GetDrawLayer()
        layer, sub = Plain(layer), Plain(sub)
        if layer and sub then return layer, math.min(sub + 1, 7) end
    end
    return "ARTWORK", 7
end

local function GetTicks(host)
    local ticks = hostTicks[host]
    if not ticks then
        -- Holder for the invisible positioning bars (nothing visible in it).
        local holder = CreateFrame("Frame", nil, host)
        holder:SetAllPoints(host)
        -- Mask to the bar's fill (current health), so lines only show on the
        -- filled part. Also hides lines clamped past max health.
        local mask = host:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ticks = { holder = holder, mask = mask, lines = {} }
        hostTicks[host] = ticks
    end
    return ticks
end

local function GetLine(ticks, host, i)
    local line = ticks.lines[i]
    if not line then
        local bar = CreateFrame("StatusBar", nil, ticks.holder)
        bar:SetAllPoints(host)
        bar:SetStatusBarTexture(WHITE)
        bar:SetStatusBarColor(0, 0, 0, 0) -- invisible; only its fill edge is used
        local fill = bar:GetStatusBarTexture()
        local layer, sublevel = LineLayer(host)
        local tex = host:CreateTexture(nil, layer, nil, sublevel)
        tex:SetTexture(WHITE) -- a file texture (not a color texture) so the mask applies
        tex:AddMaskTexture(ticks.mask)
        line = { bar = bar, tex = tex, fill = fill }
        ticks.lines[i] = line
    end
    return line
end

local function HideTicks(host)
    local ticks = host and hostTicks[host]
    if not ticks then return end
    for _, line in ipairs(ticks.lines) do line.tex:Hide() end
end

-- Pass a (possibly secret) max health to every line; no math on it.
-- The value is reapplied after the range, since StatusBars clamp on SetValue.
local function SetTicksMax(t, unit)
    local ticks = t.host and hostTicks[t.host]
    if not ticks or not t.tickTier then return end
    local max = UnitHealthMax(unit)
    for i = 1, t.tickTier.lines do
        local line = ticks.lines[i]
        line.bar:SetMinMaxValues(0, max)
        line.bar:SetValue(line.hp)
    end
end

local function SetupTicks(t, unit)
    local host = t.host
    local ticks = GetTicks(host)
    local tier = TierForUnit(unit)
    t.tickTier = tier

    -- Re-anchor each time: some addons swap the fill texture when restyling.
    local fill = host:GetStatusBarTexture()
    ticks.mask:ClearAllPoints()
    ticks.mask:SetAllPoints(fill or host)

    for i, line in ipairs(ticks.lines) do
        if i > tier.lines then line.bar:Hide(); line.tex:Hide() end
    end
    for i = 1, tier.lines do
        local line = GetLine(ticks, host, i)
        local hp = i * tier.minor
        local isMajor = hp % tier.major == 0
        line.tex:SetVertexColor(unpack(isMajor and db.majorTickColor or db.tickColor))
        SetPixelWidth(line.tex, isMajor and MAJOR_TICK_WIDTH or TICK_WIDTH)
        -- Thick lines span the full height; thin lines only the top half.
        line.tex:ClearAllPoints()
        line.tex:SetPoint("TOPLEFT", line.fill, "TOPRIGHT")
        line.tex:SetPoint("BOTTOMLEFT", line.fill, isMajor and "BOTTOMRIGHT" or "RIGHT")
        line.hp = hp
        line.bar:Show()
        line.tex:SetShown(db.showTicks)
    end
    SetTicksMax(t, unit) -- sets range, then each line's value
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

    if t.host and t.host ~= host then HideTicks(t.host) end
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
    local ok, err = pcall(SetupTicks, t, unit)
    if not ok and not tickErrorShown then
        tickErrorShown = true
        print("Health Trail: could not draw ticks: " .. tostring(err))
    end
end

local function Detach(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local t = plate and trails[plate]
    if not t then return end
    t.token = t.token + 1
    t.timerRunning = false
    t.unit = nil
    t.bar:Hide()
    t.tickTier = nil
    HideTicks(t.host)
end

local function OnHealth(unit, event)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local t = plate and trails[plate]
    if not t or t.unit ~= unit then return end

    HideHostBackground(t.host)     -- some addons re-show their background
    t.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    t.pending = UnitHealth(unit)   -- stored, never compared
    if event == "UNIT_MAXHEALTH" then SetTicksMax(t, unit) end

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
-- API for the options window and minimap button
---------------------------------------------------------------------------

-- Re-apply colours and ticks to every active nameplate after a setting changes.
function ns.Refresh()
    for _, t in pairs(trails) do
        t.bar:SetStatusBarColor(unpack(db.trailColor))
        t.bar.bg:SetColorTexture(unpack(db.bgColor))
        if t.unit then
            HideTicks(t.host)
            local ok, err = pcall(SetupTicks, t, t.unit)
            if not ok then print("Health Trail: could not draw ticks: " .. tostring(err)) end
        end
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Refresh shortly after the last call (for sliders being dragged).
local refreshToken = 0
function ns.QueueRefresh()
    refreshToken = refreshToken + 1
    local token = refreshToken
    C_Timer.After(0.25, function()
        if token == refreshToken then ns.Refresh() end
    end)
end

function ns.SetShowTicks(on)
    db.showTicks = on and true or false
    ns.Refresh()
end

-- Reset everything except the minimap button's position and visibility.
function ns.ResetDefaults()
    for k, v in pairs(DEFAULTS) do
        if k ~= "minimap" then db[k] = Copy(v) end
    end
    ns.Refresh()
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
        if not db.version then
            -- Pre-options builds saved black tick colours; start from the new grey.
            db.tickColor, db.majorTickColor = nil, nil
        end
        db.version = DB_VERSION
        ApplyDefaults(db, DEFAULTS)
        ns.db = db
        f:UnregisterEvent("ADDON_LOADED")

        if ns.InitOptions then ns.InitOptions() end
        if ns.InitMinimap then ns.InitMinimap() end
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
        OnHealth(arg1, event)
    end
end)

---------------------------------------------------------------------------
-- /healthtrail <seconds>
---------------------------------------------------------------------------

SLASH_HEALTHTRAIL1 = "/healthtrail"
SlashCmdList.HEALTHTRAIL = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        local function show(v)
            if IsSecret(v) then return "<secret>" end
            return tostring(v)
        end
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        if not plate then print("Health Trail debug: target has no nameplate"); return end
        local t = trails[plate]
        if not t or not t.host then print("Health Trail debug: no health bar attached to target's plate"); return end
        local host, unit = t.host, t.unit
        local fill = host:GetStatusBarTexture()
        local ticks = hostTicks[host]
        print("Health Trail debug:")
        print("  unit:", show(unit), " health bar:", show(host:GetName() or "<unnamed>"))
        if unit then
            print("  health:", show(UnitHealth(unit)), " max:", show(UnitHealthMax(unit)))
        end
        print("  bar width:", show(host:GetWidth()), " fill width:", fill and show(fill:GetWidth()) or "<no fill>")
        if unit then
            print("  player:", show(UnitIsPlayer(unit)), " classification:", show(UnitClassification(unit)),
                " level:", show(UnitLevel(unit)))
        end
        local tier = t.tickTier
        print("  showTicks:", show(db.showTicks), " type:", tier and tier.kind or "nil",
            " spacing:", tier and (tier.minor .. "/" .. tier.major) or "nil",
            " lines:", tier and tier.lines or 0)
        if ticks then
            local first = ticks.lines[1]
            if first then
                local layer, sub = first.tex:GetDrawLayer()
                print("  first line visible:", show(first.tex:IsVisible()), " width:", show(first.tex:GetWidth()),
                    " layer:", show(layer), show(sub))
            end
            local fill = host:GetStatusBarTexture()
            if fill then
                local layer, sub = fill:GetDrawLayer()
                print("  bar fill layer:", show(layer), show(sub))
            end
            for _, region in ipairs({ host:GetRegions() }) do
                if Plain(region:GetObjectType()) == "FontString" then
                    local layer, sub = region:GetDrawLayer()
                    print("  text on bar:", show(region:GetText()), " layer:", show(layer), show(sub))
                end
            end
        end
        return
    end

    local tickArg = msg:match("^ticks?%s*(%a*)$")
    if tickArg then
        if tickArg == "on" then
            db.showTicks = true
        elseif tickArg == "off" then
            db.showTicks = false
        elseif tickArg == "" then
            db.showTicks = not db.showTicks
        else
            print("Health Trail: usage /healthtrail ticks [on|off]")
            return
        end
        print("Health Trail: health ticks " .. (db.showTicks and "on" or "off"))
        ns.SetShowTicks(db.showTicks)
        return
    end

    if msg == "" or msg == "options" or msg == "config" then
        if ns.ToggleOptions then ns.ToggleOptions() end
        return
    end

    if msg == "minimap" then
        if ns.SetMinimapShown then
            ns.SetMinimapShown(db.minimap.hide) -- hidden -> show, shown -> hide
            print("Health Trail: minimap button " .. (db.minimap.hide and "hidden" or "shown"))
        end
        return
    end

    local n = tonumber(msg)
    if n and n >= 0 and n <= 5 then
        db.linger = n
        if ns.RefreshOptions then ns.RefreshOptions() end
        print(("Health Trail: linger set to %.2f s"):format(n))
    else
        print(("Health Trail: linger is %.2f s, ticks are %s."):format(db.linger, db.showTicks and "on" or "off"))
        print("  /healthtrail - open options")
        print("  /healthtrail <0-5> - set linger seconds")
        print("  /healthtrail ticks [on|off] - health tick lines")
        print("  /healthtrail minimap - show/hide the minimap button")
        print("  /healthtrail debug - diagnose the target's nameplate")
    end
end
