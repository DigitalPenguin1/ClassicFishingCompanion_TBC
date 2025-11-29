-- Classic Fishing Companion - Core Module
-- Handles initialization, event handling, and core functionality

local addonName, addon = ...
CFC = LibStub("AceAddon-3.0"):NewAddon("ClassicFishingCompanion", "AceEvent-3.0", "AceConsole-3.0") or {}

-- Create namespace if Ace3 not available
if not CFC.RegisterEvent then
    CFC = {
        events = {},
        db = {}
    }
end

-- Local references
local CFC = CFC

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
    }
}

-- Initialize database
function CFC:OnInitialize()
    -- Initialize saved variables
    if not ClassicFishingCompanionDB then
        ClassicFishingCompanionDB = {}
    end

    self.db = ClassicFishingCompanionDB

    -- Set defaults if not exist
    if not self.db.profile then
        self.db.profile = defaults.profile
    end

    -- Ensure all default structures exist
    for key, value in pairs(defaults.profile) do
        if self.db.profile[key] == nil then
            self.db.profile[key] = value
        end
    end

    -- Reset session statistics on login
    self.db.profile.statistics.sessionCatches = 0
    self.db.profile.statistics.sessionStartTime = time()

    print("|cff00ff00Classic Fishing Companion|r loaded! v1.0.4 by Relyk. Type |cffff8800/cfc|r to open or use the minimap button.")
end

-- Handle addon loading
function CFC:OnEnable()
    -- Initialize spell tracking variables
    self.lastSpellCast = nil
    self.lastSpellTime = 0
    self.fishingStartTime = 0
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

    -- Create frame for periodic checking (Classic WoW compatible)
    -- Check every 2 seconds for fishing state and lure changes
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame.timeSinceLastUpdate = 0
    self.updateFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceLastUpdate = self.timeSinceLastUpdate + elapsed
        if self.timeSinceLastUpdate >= 2 then
            CFC:CheckFishingState()
            CFC:CheckLureChanges()
            self.timeSinceLastUpdate = 0
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
                print("|cff00ff00Classic Fishing Companion:|r Fishing skill increased to " .. skillLevel .. "!")
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
    -- Check if fishing cast timed out (30 seconds since last cast)
    if self.isFishing and time() - self.lastSpellTime > 30 then
        -- Cast timed out, reset for next cast
        self.isFishing = false
        self.currentTrackedPole = nil
        if self.debug then
            print("|cffff0000[CFC Debug]|r Fishing cast timed out - ready for next cast")
        end
    end

    -- Update fishing skill periodically
    if time() - self.lastSkillCheck > 30 then
        self:UpdateFishingSkill()
        self.lastSkillCheck = time()
    end

    -- Check for missing buff warning when we have pole equipped
    if self.db.profile.settings.announceBuffs then
        local currentTime = time()
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
    -- Check if player has fishing pole equipped
    local mainHandLink = GetInventoryItemLink("player", 16)
    if not mainHandLink then
        self.currentTrackedBuff = nil
        self.currentBuffExpiration = 0
        return
    end

    -- Check weapon enchantment
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID = GetWeaponEnchantInfo()

    if hasMainHandEnchant then
        -- Convert expiration from milliseconds to seconds
        local expirationSeconds = math.floor(mainHandExpiration / 1000)

        -- Detect the actual lure name from tooltip (don't trust selected lure in UI)
        local lureName = nil
        CFC_ScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        CFC_ScanTooltip:ClearLines()
        CFC_ScanTooltip:SetInventoryItem("player", 16)

        for i = 1, CFC_ScanTooltip:NumLines() do
            local line = _G["CFC_ScanTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()
                if text and (string.find(text, "Lure") or string.find(text, "Increased Fishing")) then
                    -- Remove duration text like "(10 min)" or "(13 sec)" to get consistent name
                    lureName = string.gsub(text, "%s*%(%d+%s*%w+%)%s*$", "")
                    break
                end
            end
        end

        if lureName then
            -- Detect lure application by checking:
            -- 1. Different lure than currently tracked, OR
            -- 2. Expiration time increased significantly (fresh lure application)
            --    Most lures last 10 minutes (600s), so require jump of at least 500s
            local isNewApplication = false

            if self.currentTrackedBuff ~= lureName then
                -- Different lure
                isNewApplication = true
                if self.debug then
                    print("|cffff8800[CFC Debug]|r Different lure: " .. tostring(self.currentTrackedBuff) .. " -> " .. lureName)
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
                -- Just update the expiration time for tracking (time naturally decreases)
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

    if hasMainHandEnchant then
        -- Check if it's a fishing lure by scanning tooltip
        -- Create or reuse tooltip
        if not _G.CFCBuffCheckTooltip then
            CreateFrame("GameTooltip", "CFCBuffCheckTooltip", nil, "GameTooltipTemplate")
        end

        local tooltip = _G.CFCBuffCheckTooltip
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:ClearLines()
        tooltip:SetInventoryItem("player", 16)

        for i = 1, tooltip:NumLines() do
            local line = _G["CFCBuffCheckTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()
                -- Check for lure text (more flexible patterns)
                if text and (string.find(text, "Lure") or string.find(text, "Increased Fishing")) then
                    tooltip:Hide()
                    return true
                end
            end
        end

        tooltip:Hide()
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

        -- Check if it's a fishing pole AND not looting a dead mob
        -- In Classic WoW, when looting a fishing bobber, you typically don't have a dead target
        -- When looting a mob, UnitIsDead("target") is true
        local hasDeadTarget = UnitExists("target") and UnitIsDead("target")

        if self.debug then
            print("|cffff8800[CFC Debug]|r  hasDeadTarget: " .. tostring(hasDeadTarget))
        end

        if itemName and itemType and not hasDeadTarget then
            -- We have fishing pole equipped and no dead target = successful fishing cast
            self.lastLootWasFishing = true
            self.isFishing = true
            self.lastSpellTime = time()

            -- Track the fishing pole cast
            self:TrackFishingPoleCast()

            if self.debug then
                print("|cffff8800[CFC Debug]|r Loot opened from fishing - tracking cast")
            end
            return
        elseif self.debug and itemName and itemType and hasDeadTarget then
            print("|cffff8800[CFC Debug]|r Loot opened with pole equipped but has dead target (combat loot)")
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

-- Handle logout
function CFC:OnLogout()
    -- Save session data
    local sessionTime = time() - self.db.profile.statistics.sessionStartTime
    self.db.profile.statistics.totalFishingTime = self.db.profile.statistics.totalFishingTime + sessionTime
end

-- Check if an item is a fish (Trade Goods -> Fish subtype)
function CFC:IsItemFish(itemLink)
    if not itemLink then return false end

    -- Get item info
    local itemName, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)

    if self.debug then
        print("|cffff8800[CFC Debug]|r Item type: " .. tostring(itemType) .. ", subtype: " .. tostring(itemSubType))
    end

    -- Check if it's a Trade Good with Fish subtype
    -- In Classic WoW, fish are categorized as "Trade Goods" with subtype "Trade Goods" or might have other indicators
    -- We'll use a simple name-based check as fallback
    if itemName then
        local nameLower = string.lower(itemName)
        -- Common fish keywords in Classic WoW
        if string.find(nameLower, "fish") or
           string.find(nameLower, "salmon") or
           string.find(nameLower, "bass") or
           string.find(nameLower, "grouper") or
           string.find(nameLower, "snapper") or
           string.find(nameLower, "rockscale") or
           string.find(nameLower, "trout") or
           string.find(nameLower, "catfish") or
           string.find(nameLower, "eel") or
           string.find(nameLower, "lobster") or
           string.find(nameLower, "clam") or
           string.find(nameLower, "murloc") or
           string.find(nameLower, "firefin") then
            return true
        end
    end

    return false
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
    -- Track all items if we were recently fishing (within last 10 seconds) or loot window opened while fishing
    local timeSinceFishing = time() - self.lastSpellTime
    local wasFishing = self.lastLootWasFishing or self.isFishing or timeSinceFishing < 10

    -- Debug output
    if self.debug then
        print("|cffff8800[CFC Debug]|r Found item: " .. itemName)
        print("|cffff8800[CFC Debug]|r Was fishing: " .. tostring(wasFishing))
        print("|cffff8800[CFC Debug]|r lastLootWasFishing: " .. tostring(self.lastLootWasFishing))
        print("|cffff8800[CFC Debug]|r isFishing: " .. tostring(self.isFishing))
        print("|cffff8800[CFC Debug]|r Time since last cast: " .. timeSinceFishing .. "s")
    end

    if wasFishing then
        self:RecordFishCatch(itemName)
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
        self.db.profile.fishData[itemName] = {
            count = 0,
            firstCatch = timestamp,
            lastCatch = timestamp,
            locations = {},
        }
    end

    local fishData = self.db.profile.fishData[itemName]
    fishData.count = fishData.count + 1
    fishData.lastCatch = timestamp

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

                    -- Use EquipItemByName for TBC/Wrath/Era compatibility (not protected)
                    EquipItemByName(itemID, slotID)
                    swappedCount = swappedCount + 1
                    if self.debug then
                        print("|cff00ff00[CFC Debug]|r   Equipped using EquipItemByName(itemID: " .. itemID .. ", slot: " .. slotID .. ")")
                    end
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

    -- Try C_Container API first (Classic Anniversary / Retail)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        GetNumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) end
        GetItemID = function(bag, slot)
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            return itemInfo and itemInfo.itemID
        end
        if self.debug then
            print("|cffff8800[CFC Debug]|r Using C_Container API (Classic Anniversary)")
        end
    -- Fallback to old global API (Classic Era)
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

-- Update or create the lure macro
function CFC:UpdateLureMacro()
    -- Check if lure is selected
    local selectedLureID = self.db and self.db.profile and self.db.profile.selectedLure
    if not selectedLureID then
        print("|cffff0000Classic Fishing Companion:|r No lure selected! Go to Lure tab to select one.")
        return false
    end

    -- Get lure name
    local lureNames = {
        [6529] = "Shiny Bauble",
        [6530] = "Nightcrawlers",
        [6532] = "Bright Baubles",
        [7307] = "Flesh Eating Worm",
        [6533] = "Aquadynamic Fish Attractor",
        [6811] = "Aquadynamic Fish Lens",
        [3486] = "Sharpened Fish Hook",
    }
    local lureName = lureNames[selectedLureID]
    if not lureName then
        print("|cffff0000Classic Fishing Companion:|r Unknown lure selected!")
        return false
    end

    -- Build macro text
    local macroText = "#showtooltip\n/use " .. lureName .. "\n/use 16"
    local macroName = "CFC_ApplyLure"

    -- Check if macro exists
    local macroIndex = GetMacroIndexByName(macroName)

    if macroIndex and macroIndex > 0 then
        -- Macro exists, try to update it
        local success, err = pcall(function()
            EditMacro(macroIndex, macroName, "INV_Misc_Orb_03", macroText)
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
            CreateMacro(macroName, "INV_Misc_Orb_03", macroText, nil)
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

-- Simple lure application function for HUD button
function CFC:ApplyLureSimple()
    -- Check if in combat
    if InCombatLockdown() then
        print("|cffff0000Classic Fishing Companion:|r Cannot apply lure while in combat!")
        return
    end

    -- Check if lure is selected
    local selectedLureID = self.db and self.db.profile and self.db.profile.selectedLure
    if not selectedLureID then
        print("|cffff0000Classic Fishing Companion:|r No lure selected! Open /cfc and go to Lure tab to select one.")
        return
    end

    -- Check if fishing pole is equipped
    local mainHandLink = GetInventoryItemLink("player", 16)
    if not mainHandLink then
        print("|cffff0000Classic Fishing Companion:|r No fishing pole equipped!")
        return
    end

    -- Find lure in bags
    local bag, slot = self:FindItemInBags(selectedLureID)
    if not bag or not slot then
        local lureNames = {
            [6529] = "Shiny Bauble",
            [6530] = "Nightcrawlers",
            [6532] = "Bright Baubles",
            [7307] = "Flesh Eating Worm",
            [6533] = "Aquadynamic Fish Attractor",
            [6811] = "Aquadynamic Fish Lens",
            [3486] = "Sharpened Fish Hook",
        }
        local lureName = lureNames[selectedLureID] or "Unknown"
        print("|cffff0000Classic Fishing Companion:|r You don't have " .. lureName .. " in your bags!")
        return
    end

    -- Determine which API to use for using items
    local UseItemFromBag
    if C_Container and type(C_Container.UseContainerItem) == "function" then
        UseItemFromBag = function(b, s) C_Container.UseContainerItem(b, s) end
    elseif _G.UseContainerItem then
        UseItemFromBag = _G.UseContainerItem
    else
        print("|cffff0000Classic Fishing Companion:|r Cannot use items - API not available!")
        return
    end

    -- Use the lure from the bag (starts the "apply" cursor)
    UseItemFromBag(bag, slot)

    -- Apply it to the fishing pole (main hand slot = 16)
    UseInventoryItem(16)

    print("|cff00ff00Classic Fishing Companion:|r Lure applied!")
end

-- Apply selected lure to fishing pole (old complex version - kept for compatibility)
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
        [6532] = "Bright Baubles",
        [7307] = "Flesh Eating Worm",
        [6533] = "Aquadynamic Fish Attractor",
        [6811] = "Aquadynamic Fish Lens",
    }

    local lureName = lureNames[selectedLureID] or "Unknown Lure"
    print("|cffff8800[CFC Debug]|r Lure name: " .. lureName)

    -- Check if player has the lure in bags
    print("|cffff8800[CFC Debug]|r Scanning bags for lure...")
    local hasLure = false
    local lureBag, lureSlot = nil, nil

    -- Determine which bag API to use
    local GetNumSlots, GetItemInfo

    -- Try C_Container API first (Classic Anniversary / Retail)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        GetNumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) end
        GetItemInfo = function(bag, slot)
            return C_Container.GetContainerItemInfo(bag, slot)
        end
        print("|cffff8800[CFC Debug]|r Using C_Container API (Classic Anniversary)")
    -- Fallback to old global API (Classic Era)
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

