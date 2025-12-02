-- Classic Fishing Companion - Core Module
-- Handles initialization, event handling, and core functionality

CFC = LibStub("AceAddon-3.0"):NewAddon("ClassicFishingCompanion", "AceEvent-3.0", "AceConsole-3.0") or {}

-- Create namespace if Ace3 not available
if not CFC.RegisterEvent then
    CFC = {
        events = {},
        db = {}
    }
end

-- Default database structure
local defaults = {
    profile = {
        minimap = {
            hide = false,  -- Show by default
            minimapPos = 220,
        },
        settings = {
            announceBuffs = true,  -- Warn when fishing without buff (enabled by default)
            announceCatches = false,  -- Announce fish catches in chat
            announceSkillUps = true,  -- Announce fishing skill increases (enabled by default)
        },
        hud = {
            show = true,  -- Show stats HUD by default
            locked = false,  -- HUD is unlocked by default (can be dragged)
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            xOffset = 0,
            yOffset = 200,
        },
        catches = {},  -- Stores all fish catches
        statistics = {
            totalCatches = 0,
            sessionCatches = 0,
            sessionStartTime = 0,
            totalFishingTime = 0,
            currentSkill = 0,
            maxSkill = 0,
        },
        fishData = {},  -- Stores data per fish type
        sessions = {},  -- Stores fishing session data
        buffUsage = {},  -- Tracks fishing buff usage (lures, bobbers, etc)
        skillLevels = {},  -- Tracks fishing skill level ups
        poleUsage = {},  -- Tracks fishing pole usage
        gearSets = {
            fishing = {},  -- Fishing gear set (saved item links)
            combat = {},   -- Combat gear set (saved item links)
            currentMode = "combat",  -- Current gear mode: "fishing" or "combat"
        },
        backup = {
            enabled = true,  -- Enable automatic backups (enabled by default)
            lastBackupTime = 0,  -- Timestamp of last backup (total play time in seconds)
            lastExportReminder = 0,  -- Timestamp of last export reminder (total play time in seconds)
            data = nil,  -- Backup snapshot of fishing data
        },
    }
}

-- Initialize database
function CFC:OnInitialize()
    -- Initialize saved variables
    if not ClassicFishingCompanionDB then
        ClassicFishingCompanionDB = {}
    end

    -- Set database reference
    self.db = ClassicFishingCompanionDB

    -- Set defaults if not exist
    if not self.db.profile then
        self.db.profile = {}
    end

    -- Ensure all default structures exist
    for key, value in pairs(defaults.profile) do
        if self.db.profile[key] == nil then
            -- Deep copy for nested tables
            if type(value) == "table" then
                self.db.profile[key] = {}
                for k, v in pairs(value) do
                    if type(v) == "table" then
                        self.db.profile[key][k] = {}
                        for kk, vv in pairs(v) do
                            self.db.profile[key][k][kk] = vv
                        end
                    else
                        self.db.profile[key][k] = v
                    end
                end
            else
                self.db.profile[key] = value
            end
        end
    end

    -- Reset session statistics on login
    self.db.profile.statistics.sessionCatches = 0
    self.db.profile.statistics.sessionStartTime = time()

    print("|cff00ff00Classic Fishing Companion|r loaded! v1.0.5 by Relyk. Type |cffff8800/cfc|r to open or use the minimap button.")
    print("|cffffcc00Tip:|r Always export your fishing data from Settings for backup!")
end

-- Handle addon loading
function CFC:OnEnable()
    -- Initialize spell tracking variables
    self.lastSpellTime = 0
    self.isFishing = false
    self.lastSkillCheck = 0
    self.lastLootWasFishing = false
    self.lastBuffWarningTime = 0  -- Track when we last warned about missing buff
    self.currentTrackedBuff = nil  -- Track currently active buff to detect changes
    self.currentBuffExpiration = 0  -- Track buff expiration time to detect reapplications
    self.currentTrackedPole = nil  -- Track current pole to detect changes
    self.lastPoleTrackTime = 0  -- Track last time we counted a pole cast
    self.lastBuffTrackTime = 0  -- Track last time we counted a buff application

    -- Create scanning tooltip for lure detection
    if not CFC_ScanTooltip then
        CFC_ScanTooltip = CreateFrame("GameTooltip", "CFC_ScanTooltip", nil, "GameTooltipTemplate")
        CFC_ScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    -- Register events
    self:RegisterEvent("CHAT_MSG_LOOT", "OnLootReceived")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEntering")
    self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
    self:RegisterEvent("CHAT_MSG_SKILL", "OnSkillUpdate")

    -- Register fishing detection events
    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCastSucceeded")

    -- Create frame for periodic checking (Classic WoW compatible)
    -- Check every 2 seconds for fishing state and lure changes
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame.timeSinceLastUpdate = 0
    self.updateFrame.timeSinceLastBackupCheck = 0
    self.updateFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceLastUpdate = self.timeSinceLastUpdate + elapsed
        self.timeSinceLastBackupCheck = self.timeSinceLastBackupCheck + elapsed

        if self.timeSinceLastUpdate >= 2 then
            CFC:CheckFishingState()
            CFC:CheckLureChanges()
            self.timeSinceLastUpdate = 0
        end

        -- Check backup/reminder needs every 60 seconds
        if self.timeSinceLastBackupCheck >= 60 then
            CFC:CheckBackupNeeded()
            self.timeSinceLastBackupCheck = 0
        end
    end)

    -- Initialize UI
    if CFC.InitializeUI then
        CFC:InitializeUI()
    end

    -- Initialize Minimap button
    if CFC.InitializeMinimap then
        CFC:InitializeMinimap()
    end

    -- Initialize HUD
    if CFC.InitializeHUD then
        CFC:InitializeHUD()
    end
end

-- Handle player entering world
function CFC:OnPlayerEntering()
    -- Update session start time
    self.db.profile.statistics.sessionStartTime = time()

    -- Update fishing skill
    self:UpdateFishingSkill()
end

-- Update fishing skill from character info
function CFC:UpdateFishingSkill()
    -- Get fishing skill (profession ID 356 for Fishing)
    local numSkills = GetNumSkillLines()
    for i = 1, numSkills do
        local skillName, _, _, skillLevel, _, _, skillMaxLevel = GetSkillLineInfo(i)
        if skillName and string.find(skillName, "Fishing") then
            local oldSkill = self.db.profile.statistics.currentSkill or 0
            self.db.profile.statistics.currentSkill = skillLevel
            self.db.profile.statistics.maxSkill = skillMaxLevel

            -- Track skill level up
            if oldSkill > 0 and skillLevel > oldSkill then
                table.insert(self.db.profile.skillLevels, {
                    timestamp = time(),
                    oldLevel = oldSkill,
                    newLevel = skillLevel,
                    date = date("%Y-%m-%d %H:%M:%S", time()),
                })
                if self.db.profile.settings.announceSkillUps then
                    print("|cff00ff00Classic Fishing Companion:|r Fishing skill increased to " .. skillLevel .. "!")
                end
            end
            break
        end
    end
end

-- Handle skill updates
function CFC:OnSkillUpdate()
    self:UpdateFishingSkill()
end

-- Check fishing state (called every second via OnUpdate - Classic WoW compatible)
function CFC:CheckFishingState()
    -- Check if player has fishing pole equipped
    local mainHandLink = GetInventoryItemLink("player", 16)
    if not mainHandLink then
        -- No fishing pole, clear fishing state
        if self.isFishing then
            self.isFishing = false
            self.currentTrackedPole = nil
            if self.debug then
                print("|cffff0000[CFC Debug]|r Fishing ended (no pole)")
            end
        end
        return
    end

    -- Check if it's a valid item (assume any item in slot 16 is a fishing pole)
    local itemName = GetItemInfo(mainHandLink)
    if not itemName then
        if self.isFishing then
            self.isFishing = false
            self.currentTrackedPole = nil
        end
        return
    end

    -- We have a fishing pole equipped
    local currentTime = time()

    -- Check if fishing cast timed out (30 seconds since last cast)
    if self.isFishing and currentTime - self.lastSpellTime > 30 then
        -- Cast timed out, reset for next cast
        self.isFishing = false
        self.currentTrackedPole = nil
        if self.debug then
            print("|cffff0000[CFC Debug]|r Fishing cast timed out - ready for next cast")
        end
    end

    -- Update fishing skill periodically
    if currentTime - self.lastSkillCheck > 30 then
        self:UpdateFishingSkill()
        self.lastSkillCheck = currentTime
    end

    -- Check for missing buff warning when we have pole equipped
    if self.db.profile.settings.announceBuffs then
        if currentTime - self.lastBuffWarningTime >= 30 then
            if not self:HasFishingBuff() then
                -- Only warn if in fishing gear mode (we already know pole is equipped since we're in CheckFishingState)
                local currentMode = self:GetCurrentGearMode()
                if currentMode == "fishing" then
                    RaidNotice_AddMessage(RaidWarningFrame, "No Fishing Pole Buff!", ChatTypeInfo["RAID_WARNING"], 10)
                    self.lastBuffWarningTime = currentTime
                    if self.debug then
                        print("|cffff8800[CFC Debug]|r Warning: Fishing without buff!")
                    end
                end
            else
                -- Reset timer when buff is active to restart the 30 second countdown
                self.lastBuffWarningTime = currentTime
            end
        end
    end
end

-- Check for lure changes (called every 2 seconds)
function CFC:CheckLureChanges()
    -- DEBUG: Show this function is being called
    if self.debug then
        print("|cffff00ff[CFC Debug - CheckLureChanges]|r Function called")
    end

    -- Check if player has fishing pole equipped
    local mainHandLink = GetInventoryItemLink("player", 16)

    -- DEBUG: Show equipped item
    if self.debug then
        if mainHandLink then
            print("|cffff00ff[CFC Debug - CheckLureChanges]|r Weapon equipped: " .. mainHandLink)
        else
            print("|cffff00ff[CFC Debug - CheckLureChanges]|r No weapon equipped!")
        end
    end

    if not mainHandLink then
        return
    end

    -- Verify it's actually a fishing pole (not a combat weapon)
    local itemName, _, _, _, _, itemType, itemSubType = GetItemInfo(mainHandLink)
    local isFishingPole = false
    if itemSubType then
        local subTypeLower = string.lower(itemSubType)
        isFishingPole = string.find(subTypeLower, "fishing") ~= nil
    end

    if self.debug then
        print("|cffff00ff[CFC Debug - CheckLureChanges]|r  itemSubType: " .. tostring(itemSubType))
        print("|cffff00ff[CFC Debug - CheckLureChanges]|r  isFishingPole: " .. tostring(isFishingPole))
    end

    -- Don't track lures on combat weapons - only return early without resetting tracking
    -- This preserves lure tracking state when swapping to combat gear
    if not isFishingPole then
        if self.debug then
            print("|cffff00ff[CFC Debug - CheckLureChanges]|r Combat weapon equipped, skipping lure check")
        end
        return
    end

    -- Check weapon enchantment
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID = GetWeaponEnchantInfo()

    -- DEBUG: Show enchant status
    if self.debug then
        print("|cffff00ff[CFC Debug - CheckLureChanges]|r GetWeaponEnchantInfo():")
        print("|cffff00ff[CFC Debug - CheckLureChanges]|r   hasMainHandEnchant: " .. tostring(hasMainHandEnchant))
        if hasMainHandEnchant then
            print("|cffff00ff[CFC Debug - CheckLureChanges]|r   mainHandExpiration (ms): " .. tostring(mainHandExpiration))
        end
    end

    if hasMainHandEnchant then
        -- Convert expiration from milliseconds to seconds
        local expirationSeconds = math.floor(mainHandExpiration / 1000)

        -- Detect the actual lure name from tooltip (don't trust selected lure in UI)
        local lureName = nil
        CFC_ScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        CFC_ScanTooltip:ClearLines()
        CFC_ScanTooltip:SetInventoryItem("player", 16)

        -- DEBUG: Show all tooltip lines
        if self.debug then
            print("|cffff8800[CFC Debug - Core.lua]|r Scanning fishing pole tooltip...")
            print("|cffff8800[CFC Debug - Core.lua]|r NumLines: " .. CFC_ScanTooltip:NumLines())
        end

        for i = 1, CFC_ScanTooltip:NumLines() do
            local line = _G["CFC_ScanTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()

                -- DEBUG: Show each line
                if self.debug and text then
                    print("|cffff8800[CFC Debug - Core.lua]|r Line " .. i .. ": " .. text)
                end

                if text and (string.find(text, "Lure") or string.find(text, "Increased Fishing")) then
                    -- Remove duration text like "(10 min)" or "(13 sec)" to get consistent name
                    lureName = string.gsub(text, "%s*%(%d+%s*%w+%)%s*$", "")

                    -- DEBUG: Show what was found
                    if self.debug then
                        print("|cffff8800[CFC Debug - Core.lua]|r FOUND lure text: " .. text)
                        print("|cffff8800[CFC Debug - Core.lua]|r After stripping duration: " .. lureName)
                    end
                    break
                end
            end
        end

        -- DEBUG: Show final result
        if self.debug then
            if lureName then
                print("|cffff8800[CFC Debug - Core.lua]|r Final lureName: " .. lureName)
            else
                print("|cffff8800[CFC Debug - Core.lua]|r No lure detected!")
            end
        end

        if lureName then
            -- Detect lure application by checking:
            -- 1. Different lure than currently tracked, OR
            -- 2. Expiration time increased significantly (fresh lure application)
            --    Most lures last 10 minutes (600s), so require jump of at least 500s
            -- 3. Account for reloads: check if we already counted this lure recently (within 10 min)
            local isNewApplication = false
            local currentTime = time()

            -- Check if we've already counted this lure recently (handles reloads)
            local lastUsed = self.db.profile.buffUsage[lureName] and self.db.profile.buffUsage[lureName].lastUsed or 0
            local timeSinceLastCount = currentTime - lastUsed

            if self.currentTrackedBuff ~= lureName then
                -- Different lure than runtime tracking
                -- But check if this might be a reload (same lure counted recently)
                if timeSinceLastCount < 540 then
                    -- We counted this lure less than 9 minutes ago (most lures last 10 min)
                    -- This is likely a reload, not a new application
                    isNewApplication = false
                    if self.debug then
                        print("|cffff8800[CFC Debug]|r Lure detected after reload/gear swap: " .. lureName .. " (last counted " .. timeSinceLastCount .. "s ago)")
                    end
                else
                    -- Different lure or enough time has passed for it to be a new application
                    isNewApplication = true
                    if self.debug then
                        print("|cffff8800[CFC Debug]|r Different lure: " .. tostring(self.currentTrackedBuff) .. " -> " .. lureName)
                    end
                end
            elseif expirationSeconds > self.currentBuffExpiration + 500 then
                -- Same lure but expiration time jumped significantly (fresh application)
                -- 500+ second increase indicates a new lure was applied
                isNewApplication = true
                if self.debug then
                    print("|cffff8800[CFC Debug]|r Same lure reapplied: " .. lureName .. " (" .. self.currentBuffExpiration .. "s -> " .. expirationSeconds .. "s)")
                end
            end

            if isNewApplication then
                -- Initialize tracking for this lure if needed
                if not self.db.profile.buffUsage[lureName] then
                    self.db.profile.buffUsage[lureName] = {
                        name = lureName,
                        count = 0,
                        firstUsed = time(),
                        lastUsed = time(),
                    }
                end

                -- Increment count
                self.db.profile.buffUsage[lureName].count = self.db.profile.buffUsage[lureName].count + 1
                self.db.profile.buffUsage[lureName].lastUsed = time()
                self.currentTrackedBuff = lureName
                self.currentBuffExpiration = expirationSeconds

                if self.debug then
                    print("|cffff8800[CFC Debug]|r NEW lure applied: " .. lureName .. " (Total: " .. self.db.profile.buffUsage[lureName].count .. ")")
                end
            else
                -- Not a new application, just update tracking variables
                -- This restores tracking state after reloads
                self.currentTrackedBuff = lureName
                self.currentBuffExpiration = expirationSeconds
            end
        end
    else
        -- No enchantment, reset tracked buff
        if self.currentTrackedBuff ~= nil then
            if self.debug then
                print("|cffff8800[CFC Debug]|r Lure expired or removed")
            end
            self.currentTrackedBuff = nil
            self.currentBuffExpiration = 0
        end
    end
end

-- Check if backup or export reminder is needed (called every 60 seconds)
function CFC:CheckBackupNeeded()
    if not self.db or not self.db.profile or not self.db.profile.backup then
        return
    end

    -- Skip if backup is disabled
    if not self.db.profile.backup.enabled then
        return
    end

    -- Get current time
    local currentTime = time()

    -- Check if this is the first time (no backup exists)
    -- Treat nil lastBackupTime as 0 to ensure initial backup is created
    if not self.db.profile.backup.data or (self.db.profile.backup.lastBackupTime or 0) == 0 then
        -- Create initial backup immediately
        local success = self:CreateBackup()
        if success then
            print("|cff00ff00Classic Fishing Companion:|r Initial backup created")
        end
        return
    end

    -- Check if 24 hours (86400 seconds) have passed since last backup
    local timeSinceLastBackup = currentTime - (self.db.profile.backup.lastBackupTime or 0)
    if timeSinceLastBackup >= 86400 then  -- 24 hours = 86400 seconds
        -- Create automatic backup
        local success = self:CreateBackup()
        if success then
            print("|cff00ff00Classic Fishing Companion:|r Automatic backup created (24 hours elapsed)")
        end
    end

    -- Calculate total play time for export reminder
    local totalPlayTime = (self.db.profile.statistics.totalFishingTime or 0) + (time() - self.db.profile.statistics.sessionStartTime)

    -- Check if 7 days (604800 seconds) have passed since last export reminder
    local timeSinceLastReminder = totalPlayTime - (self.db.profile.backup.lastExportReminder or 0)
    if timeSinceLastReminder >= 604800 then  -- 7 days = 604800 seconds
        -- Show export reminder
        print("|cffffcc00Classic Fishing Companion:|r Reminder: Consider exporting your fishing data for backup!")
        print("|cffffcc00Tip:|r Open Settings and click 'Export Data' to save your data externally.")
        self.db.profile.backup.lastExportReminder = totalPlayTime
    end
end

-- Track fishing pole cast (called when Fishing spell is cast)
function CFC:TrackFishingPoleCast()
    -- Get the main hand item (fishing pole)
    local itemLink = GetInventoryItemLink("player", 16)

    if itemLink then
        local itemName = GetItemInfo(itemLink)

        if itemName then
            -- Initialize pole data if needed
            if not self.db.profile.poleUsage[itemName] then
                self.db.profile.poleUsage[itemName] = {
                    name = itemName,
                    count = 0,
                    firstUsed = time(),
                    lastUsed = time(),
                }
            end

            -- Only increment if this is a different pole from the currently tracked one
            -- currentTrackedPole is reset to nil when fishing ends, so each new cast is counted
            if self.currentTrackedPole ~= itemName then
                self.db.profile.poleUsage[itemName].count = self.db.profile.poleUsage[itemName].count + 1
                self.db.profile.poleUsage[itemName].lastUsed = time()
                self.currentTrackedPole = itemName
                self.lastPoleTrackTime = time()

                if self.debug then
                    print("|cffff8800[CFC Debug]|r Tracked fishing pole cast: " .. itemName .. " (Total: " .. self.db.profile.poleUsage[itemName].count .. ")")
                end
            else
                if self.debug then
                    print("|cffff8800[CFC Debug]|r Skipping duplicate pole cast (already tracked this cast)")
                end
            end

            return itemName
        end
    end

    return nil
end

-- Check if player currently has a fishing buff/lure active
function CFC:HasFishingBuff()
    -- Check weapon enchantment (lures applied to fishing pole)
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantId = GetWeaponEnchantInfo()

    -- DEBUG: Show enchant check
    if self.debug then
        print("|cffff00ff[CFC Debug - HasFishingBuff]|r hasMainHandEnchant: " .. tostring(hasMainHandEnchant))
    end

    if hasMainHandEnchant then
        -- Check if it's a fishing lure by scanning tooltip
        -- Reuse tooltip if it exists
        if not CFC_BuffCheckTooltip then
            CFC_BuffCheckTooltip = CreateFrame("GameTooltip", "CFCBuffCheckTooltip", nil, "GameTooltipTemplate")
        end

        CFC_BuffCheckTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        CFC_BuffCheckTooltip:ClearLines()
        CFC_BuffCheckTooltip:SetInventoryItem("player", 16)

        for i = 1, CFC_BuffCheckTooltip:NumLines() do
            local line = _G["CFCBuffCheckTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()

                -- DEBUG: Show tooltip lines
                if self.debug and text then
                    print("|cffff00ff[CFC Debug - HasFishingBuff]|r Line " .. i .. ": " .. text)
                end

                -- TBC format: "Fishing Lure (+25 Fishing Skill) (10 min)"
                -- Match "Lure" followed by "(+number" OR check for "Increased Fishing"
                if text and (string.match(text, "Lure.*%(%+(%d+)") or string.find(text, "Increased Fishing")) then
                    CFC_BuffCheckTooltip:Hide()

                    if self.debug then
                        print("|cffff00ff[CFC Debug - HasFishingBuff]|r FOUND fishing buff: " .. text)
                    end
                    return true
                end
            end
        end

        CFC_BuffCheckTooltip:Hide()
    end

    -- Check for fishing-related buffs
    local fishingBuffs = {
        "lure", "aquadynamic", "bright baubles", "nightcrawlers",
        "shiny bauble", "flesh eating worm", "attractor", "bait"
    }

    for i = 1, 40 do
        local buffName = UnitBuff("player", i)
        if buffName then
            local buffLower = string.lower(buffName)
            for _, buffPattern in ipairs(fishingBuffs) do
                if string.find(buffLower, buffPattern) then
                    return true
                end
            end
        end
    end

    return false
end

-- Detect fishing pole buffs (lures, bobbers, etc.)

-- Handle loot window opening
function CFC:OnLootOpened()
    -- Check if we have a fishing pole equipped
    local mainHandLink = GetInventoryItemLink("player", 16)

    if self.debug then
        print("|cffff8800[CFC Debug]|r OnLootOpened called")
        print("|cffff8800[CFC Debug]|r  mainHandLink: " .. tostring(mainHandLink))
    end

    if mainHandLink then
        local itemName, _, _, _, _, itemType, itemSubType = GetItemInfo(mainHandLink)

        if self.debug then
            print("|cffff8800[CFC Debug]|r  itemName: " .. tostring(itemName))
            print("|cffff8800[CFC Debug]|r  itemType: " .. tostring(itemType))
            print("|cffff8800[CFC Debug]|r  itemSubType: " .. tostring(itemSubType))
        end

        -- Check if it's actually a fishing pole
        -- In Classic WoW, fishing poles have itemSubType "Fishing Poles"
        local isFishingPole = false
        if itemSubType then
            local subTypeLower = string.lower(itemSubType)
            isFishingPole = string.find(subTypeLower, "fishing") ~= nil
        end

        if self.debug then
            print("|cffff8800[CFC Debug]|r  isFishingPole: " .. tostring(isFishingPole))
        end

        -- Check if it's a fishing pole AND not looting a dead mob AND recently cast Fishing
        -- In Classic WoW, when looting a fishing bobber, you typically don't have a dead target
        -- When looting a mob, UnitIsDead("target") is true
        local hasDeadTarget = UnitExists("target") and UnitIsDead("target")

        -- Check if we recently cast Fishing (within last 30 seconds)
        -- This prevents chest/container loot from being counted as fishing loot
        local currentTime = time()
        local timeSinceLastCast = currentTime - (self.lastSpellTime or 0)
        local recentlyCastFishing = timeSinceLastCast <= 30

        if self.debug then
            print("|cffff8800[CFC Debug]|r  hasDeadTarget: " .. tostring(hasDeadTarget))
            print("|cffff8800[CFC Debug]|r  timeSinceLastCast: " .. tostring(timeSinceLastCast))
            print("|cffff8800[CFC Debug]|r  recentlyCastFishing: " .. tostring(recentlyCastFishing))
        end

        if itemName and isFishingPole and not hasDeadTarget and recentlyCastFishing then
            -- We have fishing pole equipped, no dead target, and recently cast Fishing = successful fishing cast
            self.lastLootWasFishing = true
            self.isFishing = true

            -- Clear lastSpellTime so subsequent loot (chests, etc.) won't be counted as fishing
            -- This prevents chest loot from being tracked if opened shortly after fishing
            self.lastSpellTime = 0

            -- Track the fishing pole cast
            self:TrackFishingPoleCast()

            if self.debug then
                print("|cffff8800[CFC Debug]|r Loot opened from fishing - tracking cast")
                print("|cffff8800[CFC Debug]|r Cleared lastSpellTime to prevent subsequent loot from being tracked")
            end
            return
        elseif self.debug and itemName and not isFishingPole then
            print("|cffff8800[CFC Debug]|r Loot opened with non-fishing-pole equipped: " .. itemName)
        elseif self.debug and itemName and isFishingPole and hasDeadTarget then
            print("|cffff8800[CFC Debug]|r Loot opened with pole equipped but has dead target (combat loot)")
        elseif self.debug and itemName and isFishingPole and not recentlyCastFishing then
            print("|cffff8800[CFC Debug]|r Loot opened with pole equipped but no recent Fishing cast (chest/container loot)")
        end
    end

    -- Not fishing
    self.lastLootWasFishing = false
    if self.debug then
        print("|cffff8800[CFC Debug]|r Loot opened but NOT fishing")
    end
end

-- Handle loot window closing
function CFC:OnLootClosed()
    -- Reset tracked pole so next cast will count
    self.currentTrackedPole = nil
    self.isFishing = false

    if self.debug then
        print("|cffff8800[CFC Debug]|r Loot closed - ready for next cast")
    end
end

-- Handle spell cast succeeded
function CFC:OnSpellCastSucceeded(event, unit, castGUID, spellID)
    -- Only track player's spells
    if unit ~= "player" then
        return
    end

    -- Get spell name from spellID
    local spellName = GetSpellInfo(spellID)

    if self.debug then
        print("|cffff8800[CFC Debug]|r UNIT_SPELLCAST_SUCCEEDED: " .. tostring(spellName) .. " (ID: " .. tostring(spellID) .. ")")
    end

    -- Check if it's Fishing (spell ID 7620 for Fishing in Classic/TBC, but name is more reliable)
    if spellName and string.find(string.lower(spellName), "fishing") then
        self.lastSpellTime = time()

        if self.debug then
            print("|cffff8800[CFC Debug]|r Fishing cast detected! lastSpellTime set to: " .. self.lastSpellTime)
        end
    end
end

-- Handle logout
function CFC:OnLogout()
    -- Save session data
    local sessionTime = time() - self.db.profile.statistics.sessionStartTime
    self.db.profile.statistics.totalFishingTime = self.db.profile.statistics.totalFishingTime + sessionTime
end

-- Check if item is a fishing lure or buff item (should not be tracked as a catch)
function CFC:IsFishingLure(itemName)
    if not itemName then return false end

    local nameLower = string.lower(itemName)

    -- List of specific fishing lures and buff items that should NOT be tracked as catches
    -- Using exact matches or very specific patterns to avoid false positives
    local lureNames = {
        "aquadynamic fish attractor",
        "bright baubles",
        "nightcrawlers",
        "shiny bauble",
        "flesh eating worm",
    }

    -- Check for exact matches
    for _, lureName in ipairs(lureNames) do
        if nameLower == lureName then
            return true
        end
    end

    -- Only check for "lure" keyword if it appears with "fishing"
    if string.find(nameLower, "fishing") and string.find(nameLower, "lure") then
        return true
    end

    return false
end

-- Parse loot message to detect items caught while fishing
function CFC:OnLootReceived(event, message)
    -- Debug: Print all loot messages
    if self.debug then
        print("|cffff8800[CFC Debug]|r LOOT: " .. tostring(message))
    end

    -- Only process "You receive loot:" messages, NOT "You create:" (from cooking/crafting)
    if not string.find(message, "You receive loot:") then
        if self.debug then
            print("|cffff8800[CFC Debug]|r Skipping non-loot message (probably crafting/cooking)")
        end
        return
    end

    -- Pattern for loot: "You receive loot: [Item Name]."
    -- Extract full item link
    local itemLink = string.match(message, "(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    local itemName = string.match(message, "|c%x+|Hitem:.-|h%[(.-)%]|h|r")

    if not itemLink or not itemName then
        return
    end

    -- Skip fishing lures and bait items
    if self:IsFishingLure(itemName) then
        if self.debug then
            print("|cffff8800[CFC Debug]|r Skipping fishing lure: " .. itemName)
        end
        return
    end

    -- Check if this loot was obtained while fishing
    -- Only track if LOOT_OPENED event confirmed this was fishing loot (pole equipped + no dead target)
    local wasFishing = self.lastLootWasFishing

    -- Debug output
    if self.debug then
        print("|cffff8800[CFC Debug]|r Found item: " .. itemName)
        print("|cffff8800[CFC Debug]|r Was fishing: " .. tostring(wasFishing))
        print("|cffff8800[CFC Debug]|r lastLootWasFishing: " .. tostring(self.lastLootWasFishing))
    end

    if wasFishing then
        if self.debug then
            print("|cffff8800[CFC Debug]|r Recording catch from fishing")
        end
        self:RecordFishCatch(itemName)
    else
        if self.debug then
            print("|cffff8800[CFC Debug]|r Skipping - not from fishing")
        end
    end
end

-- Record a fish catch
function CFC:RecordFishCatch(itemName)
    local timestamp = time()
    local zone = GetRealZoneText() or "Unknown"
    local subzone = GetSubZoneText() or ""
    local position = self:GetPlayerPosition()

    -- Create catch record
    local catch = {
        itemName = itemName,
        timestamp = timestamp,
        zone = zone,
        subzone = subzone,
        x = position.x,
        y = position.y,
        date = date("%Y-%m-%d %H:%M:%S", timestamp),
    }

    -- Add to catches table
    table.insert(self.db.profile.catches, catch)

    -- Update statistics
    self.db.profile.statistics.totalCatches = self.db.profile.statistics.totalCatches + 1
    self.db.profile.statistics.sessionCatches = self.db.profile.statistics.sessionCatches + 1

    -- Update fish-specific data
    if not self.db.profile.fishData[itemName] then
        -- Get item icon texture when first catching this fish
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemName)

        self.db.profile.fishData[itemName] = {
            count = 0,
            firstCatch = timestamp,
            lastCatch = timestamp,
            locations = {},
            icon = itemTexture,  -- Cache the icon texture
        }
    end

    local fishData = self.db.profile.fishData[itemName]
    fishData.count = fishData.count + 1
    fishData.lastCatch = timestamp

    -- Update cached icon if we don't have one yet
    if not fishData.icon then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemName)
        if itemTexture then
            fishData.icon = itemTexture
        end
    end

    -- Add location if not already recorded
    local locationKey = zone .. ":" .. subzone
    if not fishData.locations[locationKey] then
        fishData.locations[locationKey] = {
            zone = zone,
            subzone = subzone,
            count = 0,
        }
    end
    fishData.locations[locationKey].count = fishData.locations[locationKey].count + 1

    -- Print notification if setting is enabled
    if self.db.profile.settings.announceCatches then
        print("|cff00ff00Classic Fishing Companion Announcements:|r Caught " .. itemName .. " in " .. zone)
    end

    -- Update UI if open
    if CFC.UpdateUI then
        CFC:UpdateUI()
    end

    -- Update HUD
    if CFC.HUD and CFC.HUD.Update then
        CFC.HUD:Update()
    end
end

-- Get player position
function CFC:GetPlayerPosition()
    local y, x = UnitPosition("player")
    return { x = x or 0, y = y or 0 }
end

-- Calculate fish per hour
function CFC:GetFishPerHour()
    local sessionTime = time() - self.db.profile.statistics.sessionStartTime

    if sessionTime <= 0 then
        return 0
    end

    local hours = sessionTime / 3600
    return self.db.profile.statistics.sessionCatches / hours
end

-- Get total fishing time in hours
function CFC:GetTotalFishingTime()
    local sessionTime = time() - self.db.profile.statistics.sessionStartTime
    local totalSeconds = self.db.profile.statistics.totalFishingTime + sessionTime
    return totalSeconds / 3600
end

-- ========================================
-- GEAR SWAP SYSTEM
-- ========================================

-- Equipment slot IDs
local GEAR_SLOTS = {
    HEADSLOT = 1,
    NECKSLOT = 2,
    SHOULDERSLOT = 3,
    SHIRTSLOT = 4,
    CHESTSLOT = 5,
    WAISTSLOT = 6,
    LEGSSLOT = 7,
    FEETSLOT = 8,
    WRISTSLOT = 9,
    HANDSSLOT = 10,
    FINGER0SLOT = 11,
    FINGER1SLOT = 12,
    TRINKET0SLOT = 13,
    TRINKET1SLOT = 14,
    BACKSLOT = 15,
    MAINHANDSLOT = 16,
    SECONDARYHANDSLOT = 17,
    TABARDSLOT = 19,
}

-- Helper function to count table entries
function CFC:CountTableEntries(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Save current equipment to a gear set
function CFC:SaveGearSet(setName)
    if not self.db or not self.db.profile then
        if self.debug then
            print("|cffff0000[CFC Debug]|r SaveGearSet failed: No database")
        end
        return false
    end

    if not self.db.profile.gearSets then
        self.db.profile.gearSets = {
            fishing = {},
            combat = {},
            currentMode = "combat",
        }
        if self.debug then
            print("|cffff8800[CFC Debug]|r Initialized gearSets database")
        end
    end

    local gearSet = {}
    local itemCount = 0

    if self.debug then
        print("|cffff8800[CFC Debug]|r === Saving " .. setName .. " gear set ===")
    end

    -- Save each equipment slot
    for slotName, slotID in pairs(GEAR_SLOTS) do
        local itemLink = GetInventoryItemLink("player", slotID)
        if itemLink then
            gearSet[slotID] = itemLink
            itemCount = itemCount + 1
            if self.debug then
                local itemName = string.match(itemLink, "%[(.-)%]") or "Unknown"
                print("|cffff8800[CFC Debug]|r   Slot " .. slotID .. " (" .. slotName .. "): " .. itemName)
            end
        end
    end

    self.db.profile.gearSets[setName] = gearSet

    if self.debug then
        print("|cffff8800[CFC Debug]|r Saved " .. itemCount .. " items to " .. setName .. " gear set")
    end

    -- Check if both gear sets are identical
    local otherSet = (setName == "fishing") and "combat" or "fishing"
    if self.db.profile.gearSets[otherSet] and next(self.db.profile.gearSets[otherSet]) then
        local matchingItems = 0
        local totalItems = 0

        for slotID, itemLink in pairs(gearSet) do
            totalItems = totalItems + 1
            local otherItemLink = self.db.profile.gearSets[otherSet][slotID]
            if otherItemLink then
                local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                local otherItemID = tonumber(string.match(otherItemLink, "item:(%d+)"))
                if itemID == otherItemID then
                    matchingItems = matchingItems + 1
                end
            end
        end

        -- If all items match exactly, warn the user
        if totalItems > 0 and matchingItems == totalItems then
            print("|cffffcc00Classic Fishing Companion:|r |cffff8800WARNING:|r Your fishing and combat gear are identical!")
            print("|cffffcc00Tip:|r Equip different gear for each set to make swapping useful.")
        end
    end

    return true
end

-- Load and equip a gear set
function CFC:LoadGearSet(setName)
    if self.debug then
        print("|cffff8800[CFC Debug]|r === Loading " .. setName .. " gear set ===")
    end

    if not self.db or not self.db.profile or not self.db.profile.gearSets then
        print("|cffff0000Classic Fishing Companion:|r No gear sets saved yet!")
        if self.debug then
            print("|cffff0000[CFC Debug]|r Database not initialized")
        end
        return false
    end

    local gearSet = self.db.profile.gearSets[setName]
    if not gearSet or not next(gearSet) then
        print("|cffff0000Classic Fishing Companion:|r No " .. setName .. " gear set saved. Equip your gear and use /cfc save" .. setName .. " first!")
        if self.debug then
            print("|cffff0000[CFC Debug]|r Gear set '" .. setName .. "' is empty or doesn't exist")
        end
        return false
    end

    -- Check if in combat
    if InCombatLockdown() then
        print("|cffff0000Classic Fishing Companion:|r Cannot swap gear while in combat!")
        if self.debug then
            print("|cffff0000[CFC Debug]|r Combat lockdown active")
        end
        return false
    end

    if self.debug then
        print("|cffff8800[CFC Debug]|r Found " .. self:CountTableEntries(gearSet) .. " items in " .. setName .. " gear set")
    end

    local swappedCount = 0
    local notFoundCount = 0
    local alreadyEquippedCount = 0

    -- Equip each item from the set
    for slotID, itemLink in pairs(gearSet) do
        -- Check if this item is already equipped in the correct slot
        local currentItemLink = GetInventoryItemLink("player", slotID)
        local targetItemID = tonumber(string.match(itemLink, "item:(%d+)"))
        local currentItemID = currentItemLink and tonumber(string.match(currentItemLink, "item:(%d+)"))

        if currentItemID == targetItemID then
            -- Item is already equipped in the correct slot, skip it
            alreadyEquippedCount = alreadyEquippedCount + 1
            if self.debug then
                local itemName = string.match(itemLink, "%[(.-)%]") or "Unknown"
                print("|cff00ff00[CFC Debug]|r   Already equipped: " .. itemName .. " (slot " .. slotID .. ")")
            end
        else
            -- Need to equip this item
            local itemID = targetItemID
            if itemID then
                local itemName = string.match(itemLink, "%[(.-)%]") or "Unknown"
                local bag, slot = self:FindItemInBags(itemID)

                if bag and slot then
                    if self.debug then
                        print("|cff00ff00[CFC Debug]|r   Equipping " .. itemName .. " (slot " .. slotID .. ") from bag " .. bag .. ", slot " .. slot)
                    end
                    ClearCursor()  -- Make sure cursor is clear before pickup

                    -- Use C_Container API (TBC)
                    if C_Container and C_Container.PickupContainerItem then
                        C_Container.PickupContainerItem(bag, slot)
                        if self.debug then
                            print("|cffff8800[CFC Debug]|r   Using C_Container.PickupContainerItem")
                        end
                    else
                        PickupContainerItem(bag, slot)
                        if self.debug then
                            print("|cffff8800[CFC Debug]|r   Using legacy PickupContainerItem")
                        end
                    end

                    PickupInventoryItem(slotID)
                    ClearCursor()  -- Clear cursor after swap
                    swappedCount = swappedCount + 1
                else
                    notFoundCount = notFoundCount + 1
                    if self.debug then
                        print("|cffff0000[CFC Debug]|r   Item not in bags: " .. itemName .. " (ID: " .. itemID .. ")")
                    end
                end
            else
                if self.debug then
                    print("|cffff0000[CFC Debug]|r   Could not extract item ID from: " .. itemLink)
                end
            end
        end
    end

    self.db.profile.gearSets.currentMode = setName

    if self.debug then
        print("|cffff8800[CFC Debug]|r Gear swap complete: " .. swappedCount .. " equipped, " .. alreadyEquippedCount .. " already equipped, " .. notFoundCount .. " not found")
    end

    return true
end

-- Find item in bags by item ID
function CFC:FindItemInBags(itemID)
    if self.debug then
        print("|cffff8800[CFC Debug]|r Searching bags for item ID: " .. itemID)
    end

    -- Determine which bag API to use with explicit checks
    local GetNumSlots, GetItemID

    -- Use C_Container API (TBC)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        GetNumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) end
        GetItemID = function(bag, slot)
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            return itemInfo and itemInfo.itemID
        end
        if self.debug then
            print("|cffff8800[CFC Debug]|r Using C_Container API (TBC)")
        end
    -- Fallback to old global API
    elseif _G.GetContainerNumSlots and type(_G.GetContainerNumSlots) == "function" then
        GetNumSlots = _G.GetContainerNumSlots
        GetItemID = _G.GetContainerItemID
        if self.debug then
            print("|cffff8800[CFC Debug]|r Using legacy bag API (Classic Era)")
        end
    else
        print("|cffff0000Classic Fishing Companion:|r ERROR: No bag API available!")
        if self.debug then
            print("|cffff0000[CFC Debug]|r C_Container exists: " .. tostring(C_Container ~= nil))
            if C_Container then
                print("|cffff0000[CFC Debug]|r C_Container.GetContainerNumSlots: " .. tostring(C_Container.GetContainerNumSlots ~= nil))
                print("|cffff0000[CFC Debug]|r C_Container.GetContainerItemInfo: " .. tostring(C_Container.GetContainerItemInfo ~= nil))
            end
            print("|cffff0000[CFC Debug]|r _G.GetContainerNumSlots: " .. tostring(_G.GetContainerNumSlots ~= nil))
        end
        return nil, nil
    end

    for b = 0, 4 do
        local numSlots = GetNumSlots(b) or 0
        if self.debug then
            print("|cffff8800[CFC Debug]|r   Checking bag " .. b .. " (" .. numSlots .. " slots)")
        end

        if numSlots > 0 then
            for s = 1, numSlots do
                local containerItemID = GetItemID(b, s)
                if self.debug and containerItemID then
                    print("|cffff8800[CFC Debug]|r     Bag " .. b .. " Slot " .. s .. ": Item " .. containerItemID)
                end
                if containerItemID and containerItemID == itemID then
                    if self.debug then
                        print("|cff00ff00[CFC Debug]|r   ✓ Found item " .. itemID .. " in bag " .. b .. ", slot " .. s)
                    end
                    return b, s
                end
            end
        end
    end

    if self.debug then
        print("|cffff0000[CFC Debug]|r   ✗ Item " .. itemID .. " not found in any bag")
    end

    return nil, nil
end

-- Swap between fishing and combat gear
function CFC:SwapGear()
    if self.debug then
        print("|cffff8800[CFC Debug]|r ===== GEAR SWAP INITIATED =====")
    end

    -- Check if in combat
    if InCombatLockdown() then
        print("|cffff0000Classic Fishing Companion:|r Cannot swap gear while in combat!")
        if self.debug then
            print("|cffff0000[CFC Debug]|r Combat lockdown active - aborting gear swap")
        end
        return
    end

    -- Check if casting or channeling
    local castingSpell = UnitCastingInfo("player")
    local channelingSpell = UnitChannelInfo("player")

    if castingSpell or channelingSpell then
        local spellName = castingSpell or channelingSpell
        print("|cffff0000Classic Fishing Companion:|r Cannot swap gear while casting!")
        if self.debug then
            print("|cffff0000[CFC Debug]|r Currently casting/channeling: " .. tostring(spellName) .. " - aborting gear swap")
        end
        return
    end

    if not self.db or not self.db.profile or not self.db.profile.gearSets then
        print("|cffff0000Classic Fishing Companion:|r No gear sets configured!")
        print("|cffffcc00Tip:|r Equip your combat gear, then type |cffff8800/cfc savecombat|r")
        print("|cffffcc00Then:|r Equip your fishing gear, then type |cffff8800/cfc savefishing|r")
        if self.debug then
            print("|cffff0000[CFC Debug]|r Gear sets not configured - database missing")
        end
        return
    end

    local currentMode = self.db.profile.gearSets.currentMode or "combat"
    local newMode = (currentMode == "combat") and "fishing" or "combat"

    if self.debug then
        print("|cffff8800[CFC Debug]|r Current mode: " .. currentMode)
        print("|cffff8800[CFC Debug]|r Target mode: " .. newMode)
    end

    -- Check if both gear sets exist
    local hasCombat = self.db.profile.gearSets.combat and next(self.db.profile.gearSets.combat)
    local hasFishing = self.db.profile.gearSets.fishing and next(self.db.profile.gearSets.fishing)

    if self.debug then
        print("|cffff8800[CFC Debug]|r Has combat gear: " .. tostring(hasCombat))
        print("|cffff8800[CFC Debug]|r Has fishing gear: " .. tostring(hasFishing))
    end

    -- Save current gear before swapping
    if self.debug then
        print("|cffff8800[CFC Debug]|r Saving current gear to '" .. currentMode .. "' set...")
    end
    self:SaveGearSet(currentMode)

    -- Load the other gear set
    if self.debug then
        print("|cffff8800[CFC Debug]|r Loading '" .. newMode .. "' gear set...")
    end

    if self:LoadGearSet(newMode) then
        print("|cff00ff00Classic Fishing Companion:|r Swapped to " .. newMode .. " gear!")
        if self.debug then
            print("|cff00ff00[CFC Debug]|r ===== GEAR SWAP COMPLETE =====")
        end
    else
        if self.debug then
            print("|cffff0000[CFC Debug]|r ===== GEAR SWAP FAILED =====")
        end
    end
end

-- Apply selected lure to fishing pole
function CFC:ApplySelectedLure()
    print("|cffff8800[CFC Debug]|r ===== APPLY LURE INITIATED =====")

    -- Check if in combat
    if InCombatLockdown() then
        print("|cffff0000[CFC Debug]|r Cannot apply lure - IN COMBAT!")
        print("|cffff0000Classic Fishing Companion:|r Cannot apply lure while in combat!")
        return
    end
    print("|cff00ff00[CFC Debug]|r Combat check passed - not in combat")

    -- Check database
    if not self.db or not self.db.profile then
        print("|cffff0000[CFC Debug]|r Database not initialized!")
        return
    end
    print("|cff00ff00[CFC Debug]|r Database check passed")

    -- Check if lure is selected
    local selectedLureID = self.db.profile.selectedLure
    print("|cffff8800[CFC Debug]|r Selected lure ID from DB: " .. tostring(selectedLureID))

    if not selectedLureID then
        print("|cffff0000[CFC Debug]|r No lure selected in database!")
        print("|cffff0000Classic Fishing Companion:|r No lure selected!")
        print("|cffffcc00Tip:|r Open the Lure Manager tab to select a lure")
        return
    end
    print("|cff00ff00[CFC Debug]|r Lure selection check passed - ID: " .. selectedLureID)

    -- Lure names mapping
    local lureNames = {
        [6529] = "Shiny Bauble",
        [6530] = "Nightcrawlers",
        [6811] = "Bright Baubles",
        [7307] = "Flesh Eating Worm",
        [6533] = "Aquadynamic Fish Attractor",
    }

    local lureName = lureNames[selectedLureID] or "Unknown Lure"
    print("|cffff8800[CFC Debug]|r Lure name: " .. lureName)

    -- Check if player has the lure in bags
    print("|cffff8800[CFC Debug]|r Scanning bags for lure...")
    local hasLure = false
    local lureBag, lureSlot = nil, nil

    -- Determine which bag API to use
    local GetNumSlots, GetItemInfo

    -- Use C_Container API (TBC)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        GetNumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) end
        GetItemInfo = function(bag, slot)
            return C_Container.GetContainerItemInfo(bag, slot)
        end
        print("|cffff8800[CFC Debug]|r Using C_Container API (TBC)")
    -- Fallback to old global API
    elseif _G.GetContainerNumSlots and type(_G.GetContainerNumSlots) == "function" then
        GetNumSlots = _G.GetContainerNumSlots
        GetItemInfo = function(bag, slot)
            local texture, count, locked, quality, readable, lootable, itemLink = _G.GetContainerItemInfo(bag, slot)
            return { iconFileID = texture, stackCount = count, isLocked = locked, quality = quality, isReadable = readable, hasLoot = lootable, hyperlink = itemLink }
        end
        print("|cffff8800[CFC Debug]|r Using legacy bag API (Classic Era)")
    else
        print("|cffff0000[CFC Debug]|r ERROR: No bag API available!")
        print("|cffff0000Classic Fishing Companion:|r Cannot access bags - API not available")
        return
    end

    -- Use pcall to catch any errors during bag scanning
    local scanSuccess, scanError = pcall(function()
        for bag = 0, 4 do
            local numSlots = GetNumSlots(bag)
            print("|cffff8800[CFC Debug]|r Bag " .. bag .. " has " .. tostring(numSlots) .. " slots")

            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local itemInfo = GetItemInfo(bag, slot)

                    if itemInfo then
                        local itemLink = itemInfo.hyperlink or itemInfo.itemLink

                        if itemLink then
                            -- Parse item ID from itemLink string (format: "item:####")
                            local itemString = string.match(itemLink, "item:(%d+)")
                            local itemID = itemString and tonumber(itemString)

                            if itemID then
                                print("|cffff8800[CFC Debug]|r   Slot " .. slot .. ": ItemID = " .. itemID)
                                if itemID == selectedLureID then
                                    hasLure = true
                                    lureBag = bag
                                    lureSlot = slot
                                    print("|cff00ff00[CFC Debug]|r   FOUND LURE! Bag " .. bag .. " Slot " .. slot)
                                    return  -- Exit the loop
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Check if scanning encountered an error
    if not scanSuccess then
        print("|cffff0000[CFC Debug]|r ERROR during bag scan: " .. tostring(scanError))
        print("|cffff0000Classic Fishing Companion:|r Error scanning bags - please try again")
        return
    end

    if not hasLure then
        print("|cffff0000[CFC Debug]|r Lure not found in bags!")
        print("|cffff0000Classic Fishing Companion:|r You don't have " .. lureName .. " in your bags!")
        return
    end

    print("|cff00ff00[CFC Debug]|r Lure found - Bag: " .. lureBag .. ", Slot: " .. lureSlot)

    -- Check if fishing pole is equipped in main hand
    print("|cffff8800[CFC Debug]|r Checking main hand for fishing pole...")
    local mainHandLink = GetInventoryItemLink("player", 16)
    if not mainHandLink then
        print("|cffff0000[CFC Debug]|r No item equipped in main hand!")
        print("|cffff0000Classic Fishing Companion:|r No fishing pole equipped!")
        return
    end

    print("|cff00ff00[CFC Debug]|r Main hand item: " .. mainHandLink)

    -- Determine which UseContainerItem API to use
    local UseItemFromBag
    if C_Container and type(C_Container.UseContainerItem) == "function" then
        UseItemFromBag = function(bag, slot)
            C_Container.UseContainerItem(bag, slot)
        end
        print("|cffff8800[CFC Debug]|r Using C_Container.UseContainerItem")
    elseif _G.UseContainerItem and type(_G.UseContainerItem) == "function" then
        UseItemFromBag = _G.UseContainerItem
        print("|cffff8800[CFC Debug]|r Using legacy UseContainerItem")
    else
        print("|cffff0000[CFC Debug]|r ERROR: No UseContainerItem API available!")
        print("|cffff0000Classic Fishing Companion:|r Cannot use items from bags")
        return
    end

    -- Apply the lure: Use the lure item (picks it up on cursor), then click the fishing pole
    -- In Classic WoW, we need a small delay between these two actions
    print("|cffff8800[CFC Debug]|r Step 1: Using lure from bag " .. lureBag .. " slot " .. lureSlot)
    UseItemFromBag(lureBag, lureSlot)
    print("|cffff8800[CFC Debug]|r Called UseItemFromBag - lure should now be on cursor")

    -- Wait a short moment for the cursor to update, then apply to fishing pole
    print("|cffff8800[CFC Debug]|r Waiting 0.1 seconds before applying to fishing pole...")
    C_Timer.After(0.1, function()
        print("|cffff8800[CFC Debug]|r Step 2: Checking cursor state...")
        local cursorType, itemID = GetCursorInfo()
        print("|cffff8800[CFC Debug]|r Cursor type: " .. tostring(cursorType) .. ", ItemID: " .. tostring(itemID))

        if cursorType == "item" and itemID == selectedLureID then
            print("|cff00ff00[CFC Debug]|r Cursor has lure! Applying to fishing pole...")
            PickupInventoryItem(16)  -- 16 = main hand weapon slot
            print("|cffff8800[CFC Debug]|r Called PickupInventoryItem(16)")

            -- Check if successful
            C_Timer.After(0.1, function()
                local stillHasCursor = GetCursorInfo()
                if stillHasCursor then
                    print("|cffff0000[CFC Debug]|r WARNING: Cursor still has item - application may have failed")
                    ClearCursor()  -- Clear cursor to prevent issues
                else
                    print("|cff00ff00[CFC Debug]|r Success! Cursor cleared - lure applied")
                end
            end)

            print("|cff00ff00Classic Fishing Companion:|r Applied " .. lureName .. " to fishing pole!")
        else
            print("|cffff0000[CFC Debug]|r ERROR: Cursor doesn't have lure! Type: " .. tostring(cursorType))
            if cursorType then
                ClearCursor()  -- Clear whatever is on cursor
            end
            print("|cffff0000Classic Fishing Companion:|r Failed to apply lure - please try again")
        end
    end)

    print("|cff00ff00[CFC Debug]|r ===== APPLY LURE INITIATED (waiting for completion) =====")
end

-- Update or create the lure macro
function CFC:UpdateLureMacro()
    -- Check if lure is selected
    local selectedLureID = self.db and self.db.profile and self.db.profile.selectedLure
    if not selectedLureID then
        print("|cffff0000Classic Fishing Companion:|r No lure selected! Go to Lure tab to select one.")
        return false
    end

    -- Get lure name and icon
    local lureData = {
        [6529] = { name = "Shiny Bauble", icon = "INV_Misc_Orb_03" },
        [6530] = { name = "Nightcrawlers", icon = "INV_Misc_MonsterTail_03" },
        [6532] = { name = "Bright Baubles", icon = "INV_Misc_Gem_Variety_02" },
        [7307] = { name = "Flesh Eating Worm", icon = "INV_Misc_MonsterTail_03" },
        [6533] = { name = "Aquadynamic Fish Attractor", icon = "INV_Misc_Food_26" },
        [6811] = { name = "Aquadynamic Fish Lens", icon = "INV_Misc_Spyglass_01" },
        [3486] = { name = "Sharpened Fish Hook", icon = "INV_Misc_Hook_01" },
    }
    local lure = lureData[selectedLureID]
    if not lure then
        print("|cffff0000Classic Fishing Companion:|r Unknown lure selected!")
        return false
    end

    local lureName = lure.name
    local lureIcon = lure.icon

    -- Build macro text
    local macroText = "#showtooltip\n/use " .. lureName .. "\n/use 16"
    local macroName = "CFC_ApplyLure"

    -- Check if macro exists
    local macroIndex = GetMacroIndexByName(macroName)

    if macroIndex and macroIndex > 0 then
        -- Macro exists, try to update it
        local success, err = pcall(function()
            EditMacro(macroIndex, macroName, lureIcon, macroText)
        end)

        if success then
            print("|cff00ff00Classic Fishing Companion:|r Macro updated with " .. lureName .. "!")
            return true
        else
            print("|cffff0000Classic Fishing Companion:|r Failed to update macro (protected by Blizzard)")
            print("|cffffcc00→|r Please update the macro manually with the text from the box above")
            return false
        end
    else
        -- Macro doesn't exist, try to create it
        local success, err = pcall(function()
            CreateMacro(macroName, lureIcon, macroText, nil)
        end)

        if success then
            print("|cff00ff00Classic Fishing Companion:|r Macro created with " .. lureName .. "!")
            return true
        else
            print("|cffff0000Classic Fishing Companion:|r Failed to create macro (protected by Blizzard)")
            print("|cffffcc00→|r Please create the macro manually with the text from the box above")
            return false
        end
    end
end

-- Check if gear sets are configured
function CFC:HasGearSets()
    if not self.db or not self.db.profile or not self.db.profile.gearSets then
        if self.debug then
            print("|cffff8800[CFC Debug]|r HasGearSets: No database")
        end
        return false
    end

    local fishing = self.db.profile.gearSets.fishing
    local combat = self.db.profile.gearSets.combat

    local hasFishing = fishing and next(fishing)
    local hasCombat = combat and next(combat)
    local hasGearSets = hasFishing and hasCombat

    if self.debug then
        print("|cffff8800[CFC Debug]|r HasGearSets: fishing=" .. tostring(hasFishing) .. ", combat=" .. tostring(hasCombat) .. ", result=" .. tostring(hasGearSets))
    end

    return hasGearSets
end

-- Get current gear mode
function CFC:GetCurrentGearMode()
    if not self.db or not self.db.profile or not self.db.profile.gearSets then
        if self.debug then
            print("|cffff8800[CFC Debug]|r GetCurrentGearMode: No database, defaulting to 'combat'")
        end
        return "combat"
    end

    local mode = self.db.profile.gearSets.currentMode or "combat"

    if self.debug then
        print("|cffff8800[CFC Debug]|r GetCurrentGearMode: " .. mode)
    end

    return mode
end

-- ========================================
-- DATA IMPORT/EXPORT SYSTEM
-- ========================================

-- Serialize a table to a string (recursive)
local function SerializeTable(tbl, indent)
    indent = indent or 0
    local result = "{\n"
    local indentStr = string.rep("  ", indent + 1)

    for key, value in pairs(tbl) do
        -- Format the key
        local keyStr
        if type(key) == "string" then
            keyStr = string.format('[%q]', key)
        else
            keyStr = "[" .. tostring(key) .. "]"
        end

        -- Format the value
        local valueStr
        if type(value) == "table" then
            valueStr = SerializeTable(value, indent + 1)
        elseif type(value) == "string" then
            valueStr = string.format("%q", value)
        elseif type(value) == "boolean" then
            valueStr = tostring(value)
        elseif type(value) == "number" then
            valueStr = tostring(value)
        else
            valueStr = "nil"
        end

        result = result .. indentStr .. keyStr .. " = " .. valueStr .. ",\n"
    end

    result = result .. string.rep("  ", indent) .. "}"
    return result
end

-- Export all fishing data to a string
function CFC:ExportData()
    if not self.db or not self.db.profile then
        print("|cffff0000Classic Fishing Companion:|r No data to export!")
        return
    end

    -- Create export data structure (only fishing-related data)
    local exportData = {
        version = "1.0.5",
        catches = self.db.profile.catches,
        fishData = self.db.profile.fishData,
        statistics = self.db.profile.statistics,
        sessions = self.db.profile.sessions,
        buffUsage = self.db.profile.buffUsage,
        skillLevels = self.db.profile.skillLevels,
        poleUsage = self.db.profile.poleUsage,
    }

    -- Serialize to string
    local serialized = "return " .. SerializeTable(exportData)

    -- Show export dialog using the custom UI
    if CFC.UI and CFC.UI.ShowExportDialog then
        CFC.UI:ShowExportDialog(serialized)
    else
        print("|cffff0000Classic Fishing Companion:|r Export dialog not available!")
    end

    print("|cff00ff00Classic Fishing Companion:|r Data exported successfully!")
end

-- Purge a specific item from the database
function CFC:PurgeItem(itemName)
    if not itemName or itemName == "" then
        print("|cffff0000Classic Fishing Companion:|r No item name provided!")
        return false
    end

    local removedCount = 0
    local foundInFishData = false
    local foundInPoleUsage = false

    -- Remove from catches array
    local newCatches = {}
    for _, catch in ipairs(self.db.profile.catches) do
        if catch.itemName ~= itemName then
            table.insert(newCatches, catch)
        else
            removedCount = removedCount + 1
        end
    end
    self.db.profile.catches = newCatches

    -- Remove from fishData
    if self.db.profile.fishData[itemName] then
        self.db.profile.fishData[itemName] = nil
        foundInFishData = true
    end

    -- Remove from poleUsage (fishing poles used)
    if self.db.profile.poleUsage[itemName] then
        self.db.profile.poleUsage[itemName] = nil
        foundInPoleUsage = true
    end

    -- Update total catches count
    if removedCount > 0 then
        self.db.profile.statistics.totalCatches = math.max(0, self.db.profile.statistics.totalCatches - removedCount)
    end

    -- Update UI if open
    if self.UpdateUI then
        self:UpdateUI()
    end

    -- Update HUD
    if self.HUD and self.HUD.Update then
        self.HUD:Update()
    end

    if removedCount > 0 or foundInFishData or foundInPoleUsage then
        local message = "|cff00ff00Classic Fishing Companion:|r Removed '" .. itemName .. "' from database"
        if removedCount > 0 then
            message = message .. " (" .. removedCount .. " catches)"
        end
        if foundInPoleUsage then
            message = message .. " (pole usage)"
        end
        print(message)
        return true
    else
        print("|cffffcc00Classic Fishing Companion:|r Item '" .. itemName .. "' not found in database")
        return false
    end
end

-- Import fishing data from a string
function CFC:ImportData(importString)
    if not importString or importString == "" then
        print("|cffff0000Classic Fishing Companion:|r Import failed - no data provided!")
        return
    end

    -- Try to deserialize the data
    local loadFunc, loadError = loadstring(importString)

    if not loadFunc then
        print("|cffff0000Classic Fishing Companion:|r Import failed - invalid data format!")
        print("|cffff0000Error:|r " .. tostring(loadError))
        return
    end

    -- Execute the function to get the data
    local success, importData = pcall(loadFunc)

    if not success or type(importData) ~= "table" then
        print("|cffff0000Classic Fishing Companion:|r Import failed - could not load data!")
        return
    end

    -- Validate version (optional, just for info)
    if importData.version then
        print("|cff00ff00Classic Fishing Companion:|r Importing data from version " .. importData.version)
    end

    -- Import the data
    if importData.catches then
        self.db.profile.catches = importData.catches
    end

    if importData.fishData then
        self.db.profile.fishData = importData.fishData
    end

    if importData.statistics then
        -- Preserve current session info but import totals
        local currentSessionCatches = self.db.profile.statistics.sessionCatches
        local currentSessionStart = self.db.profile.statistics.sessionStartTime

        self.db.profile.statistics = importData.statistics

        -- Restore current session info
        self.db.profile.statistics.sessionCatches = currentSessionCatches
        self.db.profile.statistics.sessionStartTime = currentSessionStart
    end

    if importData.sessions then
        self.db.profile.sessions = importData.sessions
    end

    if importData.buffUsage then
        self.db.profile.buffUsage = importData.buffUsage
    end

    if importData.skillLevels then
        self.db.profile.skillLevels = importData.skillLevels
    end

    if importData.poleUsage then
        self.db.profile.poleUsage = importData.poleUsage
    end

    print("|cff00ff00Classic Fishing Companion:|r Data imported successfully!")

    -- Update UI if open
    if self.UpdateUI then
        self:UpdateUI()
    end

    -- Update HUD
    if self.HUD and self.HUD.Update then
        self.HUD:Update()
    end
end

-- Create an internal backup of fishing data
function CFC:CreateBackup()
    if not self.db or not self.db.profile then
        if self.debug then
            print("|cffff8800[CFC Debug]|r Cannot create backup - no data")
        end
        return false
    end

    -- Create backup snapshot (deep copy of fishing data only)
    local backupData = {
        version = "1.0.5",
        timestamp = time(),
        catches = self:DeepCopy(self.db.profile.catches),
        fishData = self:DeepCopy(self.db.profile.fishData),
        statistics = self:DeepCopy(self.db.profile.statistics),
        sessions = self:DeepCopy(self.db.profile.sessions),
        buffUsage = self:DeepCopy(self.db.profile.buffUsage),
        skillLevels = self:DeepCopy(self.db.profile.skillLevels),
        poleUsage = self:DeepCopy(self.db.profile.poleUsage),
    }

    -- Store backup
    self.db.profile.backup.data = backupData

    -- Update last backup timestamp (real-world time)
    self.db.profile.backup.lastBackupTime = time()

    if self.debug then
        print("|cffff8800[CFC Debug]|r Backup created successfully at " .. date("%Y-%m-%d %H:%M:%S", backupData.timestamp))
    end

    return true
end

-- Restore fishing data from internal backup
function CFC:RestoreFromBackup()
    if not self.db or not self.db.profile or not self.db.profile.backup.data then
        print("|cffff0000Classic Fishing Companion:|r No backup data available to restore!")
        return false
    end

    local backupData = self.db.profile.backup.data

    -- Restore fishing data from backup
    if backupData.catches then
        self.db.profile.catches = self:DeepCopy(backupData.catches)
    end

    if backupData.fishData then
        self.db.profile.fishData = self:DeepCopy(backupData.fishData)
    end

    if backupData.statistics then
        -- Preserve session data, restore everything else
        local sessionCatches = self.db.profile.statistics.sessionCatches
        local sessionStartTime = self.db.profile.statistics.sessionStartTime

        self.db.profile.statistics = self:DeepCopy(backupData.statistics)

        -- Restore current session data
        self.db.profile.statistics.sessionCatches = sessionCatches
        self.db.profile.statistics.sessionStartTime = sessionStartTime
    end

    if backupData.sessions then
        self.db.profile.sessions = self:DeepCopy(backupData.sessions)
    end

    if backupData.buffUsage then
        self.db.profile.buffUsage = self:DeepCopy(backupData.buffUsage)
    end

    if backupData.skillLevels then
        self.db.profile.skillLevels = self:DeepCopy(backupData.skillLevels)
    end

    if backupData.poleUsage then
        self.db.profile.poleUsage = self:DeepCopy(backupData.poleUsage)
    end

    local backupDate = date("%Y-%m-%d %H:%M:%S", backupData.timestamp)
    print("|cff00ff00Classic Fishing Companion:|r Data restored from backup created on " .. backupDate)

    -- Update UI if open
    if self.UpdateUI then
        self:UpdateUI()
    end

    -- Update HUD
    if self.HUD and self.HUD.Update then
        self.HUD:Update()
    end

    return true
end

-- Deep copy helper function
function CFC:DeepCopy(original)
    if type(original) ~= "table" then
        return original
    end

    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = self:DeepCopy(value)
        else
            copy[key] = value
        end
    end

    return copy
end

-- Slash command handler
SLASH_CFC1 = "/cfc"
SLASH_CFC2 = "/fishingcompanion"
SlashCmdList["CFC"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "reset" then
        if CFC.db and CFC.db.profile then
            CFC.db.profile.catches = {}
            CFC.db.profile.fishData = {}
            CFC.db.profile.statistics.totalCatches = 0
            CFC.db.profile.statistics.sessionCatches = 0
            print("|cff00ff00Classic Fishing Companion:|r All data has been reset.")
        end
    elseif msg == "stats" then
        CFC:PrintStats()
    elseif msg == "debug" then
        CFC.debug = not CFC.debug
        if CFC.debug then
            print("|cff00ff00Classic Fishing Companion:|r Debug mode |cff00ff00enabled|r")
        else
            print("|cff00ff00Classic Fishing Companion:|r Debug mode |cffff0000disabled|r")
        end
    elseif msg == "savefishing" then
        if CFC.debug then
            print("|cffff8800[CFC Debug]|r Slash command: savefishing")
        end
        CFC:SaveGearSet("fishing")
        print("|cff00ff00Classic Fishing Companion:|r Fishing gear set saved!")
    elseif msg == "savecombat" then
        if CFC.debug then
            print("|cffff8800[CFC Debug]|r Slash command: savecombat")
        end
        CFC:SaveGearSet("combat")
        print("|cff00ff00Classic Fishing Companion:|r Combat gear set saved!")
    elseif msg == "swap" or msg == "gear" then
        if CFC.debug then
            print("|cffff8800[CFC Debug]|r Slash command: swap/gear")
        end
        CFC:SwapGear()
    elseif msg == "minimap" then
        print("|cff00ff00[CFC Debug]|r CFC.Minimap exists: " .. tostring(CFC.Minimap ~= nil))
        print("|cff00ff00[CFC Debug]|r CFC.minimapButton exists: " .. tostring(CFC.minimapButton ~= nil))

        if CFC.Minimap and CFC.Minimap.ToggleButton then
            CFC.Minimap:ToggleButton()
        elseif CFC.minimapButton then
            -- Try to toggle directly
            if CFC.minimapButton:IsShown() then
                CFC.minimapButton:Hide()
                print("|cff00ff00Classic Fishing Companion:|r Minimap button hidden.")
            else
                CFC.minimapButton:Show()
                print("|cff00ff00Classic Fishing Companion:|r Minimap button shown.")
            end
        else
            print("|cffff0000Classic Fishing Companion:|r Minimap module not loaded or button not created.")
            print("|cffff0000[CFC Debug]|r Try /reload to reinitialize the addon.")
        end
    else
        if CFC.ToggleUI then
            CFC:ToggleUI()
        end
    end
end

-- Print statistics to chat
function CFC:PrintStats()
    local fph = self:GetFishPerHour()
    local totalTime = self:GetTotalFishingTime()

    print("|cff00ff00=== Classic Fishing Companion Statistics ===|r")
    print("|cffffcc00Total Catches:|r " .. self.db.profile.statistics.totalCatches)
    print("|cffffcc00Session Catches:|r " .. self.db.profile.statistics.sessionCatches)
    print("|cffffcc00Fish Per Hour:|r " .. string.format("%.1f", fph))
    print("|cffffcc00Total Fishing Time:|r " .. string.format("%.1f hours", totalTime))
    print("|cffffcc00Unique Fish Types:|r " .. self:GetUniqueFishCount())
end

-- Get count of unique fish types
function CFC:GetUniqueFishCount()
    local count = 0
    for _ in pairs(self.db.profile.fishData) do
        count = count + 1
    end
    return count
end

