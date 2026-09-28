local _, BJ = ...

BJ.Progress = {}
local Progress = BJ.Progress

Progress.batchDepth = 0
Progress.dirty = false
Progress.delveActive = false
Progress.delveInstanceKey = nil
Progress.pvpSnapshot = nil

local CURRENT_SEASON_RAID_INSTANCE_ID = 3004 -- The Venomous Abyss, Season 2.

local function DayKey()
    if date then return date("%Y-%m-%d", BJ:Now()) end
    return tostring(math.floor(BJ:Now() / 86400))
end

local function CurrentInstance()
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    return name or "?", instanceType or "none", tonumber(instanceID) or 0
end

local function ChallengeModeActive()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
end

function Progress:Initialize()
    self:EnsureWeek()

    BJ:RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
        C_Timer.After(0.35, function() Progress:RecordMPlusCompletion() end)
    end)
    BJ:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, groupSize, success)
        Progress:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    end)
    BJ:RegisterEvent("ACHIEVEMENT_EARNED", function(_, achievementID)
        Progress:OnAchievementEarned(achievementID)
    end)
    BJ:RegisterEvent("SCENARIO_UPDATE", function() Progress:UpdateDelveState() end)
    BJ:RegisterEvent("SCENARIO_CRITERIA_UPDATE", function() Progress:UpdateDelveState() end)
    BJ:RegisterEvent("SCENARIO_COMPLETED", function() Progress:OnScenarioCompleted() end)
    BJ:RegisterEvent("PVP_MATCH_ACTIVE", function() Progress:OnPvPMatchActive() end)
    BJ:RegisterEvent("PVP_MATCH_COMPLETE", function(_, winner, duration) Progress:OnPvPMatchComplete(winner, duration) end)
    BJ:RegisterEvent("NEW_MOUNT_ADDED", function(_, mountID) Progress:OnNewMountAdded(mountID) end)
    BJ:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        Progress:EnsureWeek()
        C_Timer.After(0.5, function() Progress:UpdateDelveState() end)
    end)

    -- Tiene il reset corretto anche se il personaggio resta online durante il reset settimanale.
    if C_Timer and C_Timer.NewTicker then
        self.weekTicker = C_Timer.NewTicker(60, function() Progress:EnsureWeek() end)
    end
end

function Progress:EnsureWeek()
    local key = BJ:GetWeekKey()
    local p = BJ.db.progress
    local reset = p.weekKey ~= key
    if reset then
        p.weekKey = key
        p.stats = {}
        p.sets = {}
        BJ:AddMoment("Nuovo reset settimanale: challenge azzerate. Le fiches accumulate restano disponibili.", "RESET")
    end
    p.stats = p.stats or {}
    p.sets = p.sets or {}

    if reset and BJ.UI then
        BJ.UI:RefreshPage("HOME")
        BJ.UI:RefreshPage("CHALLENGES")
        BJ.UI:RefreshPage("REWARDS")
    end
    return p
end

function Progress:GetStat(key)
    self:EnsureWeek()
    return tonumber(BJ.db.progress.stats[key]) or 0
end

function Progress:AddStat(key, amount)
    self:EnsureWeek()
    local s = BJ.db.progress.stats
    s[key] = (tonumber(s[key]) or 0) + (tonumber(amount) or 1)
    self:Changed()
    return s[key]
end

function Progress:AddSetValue(key, value)
    if value == nil then return end
    self:EnsureWeek()
    local sets = BJ.db.progress.sets
    sets[key] = sets[key] or {}
    sets[key][tostring(value)] = true
    self:Changed()
end

function Progress:GetSetCount(key)
    self:EnsureWeek()
    return BJ:CountTable(BJ.db.progress.sets[key])
end

function Progress:BeginBatch()
    self.batchDepth = (self.batchDepth or 0) + 1
end

function Progress:EndBatch()
    self.batchDepth = math.max(0, (self.batchDepth or 1) - 1)
    if self.batchDepth == 0 and self.dirty then
        self.dirty = false
        self:CommitChanged()
    end
end

function Progress:CommitChanged()
    if BJ.Challenges then BJ.Challenges:Refresh() end
    if BJ.UI then
        BJ.UI:RefreshPage("HOME")
        BJ.UI:RefreshPage("CHALLENGES")
        BJ.UI:RefreshPage("REWARDS")
    end
    if BJ.Comms then BJ.Comms:BroadcastSummary() end
end

function Progress:Changed()
    if (self.batchDepth or 0) > 0 then
        self.dirty = true
        return
    end
    self:CommitChanged()
end

local function CompletionMembers(info)
    local names = {}
    if info and info.members then
        for i = 1, #info.members do
            local m = info.members[i]
            if m and m.name then
                local name = BJ:NormalizeName(m.name)
                if name then names[name] = true end
            end
        end
    end
    if BJ:CountTable(names) == 0 and BJ.Guild then
        names = BJ.Guild:GetGuildNamesInGroup()
    end
    return names
end

function Progress:AddGuildmatesToSets(names, extraSet)
    for name in pairs(names or {}) do
        if name ~= BJ.player and BJ.Guild and BJ.Guild:IsMember(name) then
            self:AddSetValue("allGuildmates", name)
            if extraSet then self:AddSetValue(extraSet, name) end
        end
    end
end

function Progress:RecordMPlusCompletion()
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    self:EnsureWeek()
    if not C_ChallengeMode or not C_ChallengeMode.GetChallengeCompletionInfo then return end
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if not info then return end

    local members = CompletionMembers(info)
    local guildCount = 0
    for name in pairs(members) do
        if BJ.Guild and BJ.Guild:IsMember(name) then guildCount = guildCount + 1 end
    end

    local level = tonumber(info.level) or 0
    local mapID = tonumber(info.mapChallengeModeID) or 0
    local deaths, deathCountKnown = 0, false
    if C_ChallengeMode.GetDeathCount then
        local rawDeaths = C_ChallengeMode.GetDeathCount()
        if rawDeaths ~= nil then
            deaths = tonumber(rawDeaths) or 0
            deathCountKnown = true
        end
    end

    self:BeginBatch()
    self:AddStat("mplusRuns", 1)

    if guildCount >= 3 then
        self:AddStat("mplusGuildRuns", 1)
        self:AddStat("mplusLevelSum", math.max(0, level))
        if mapID > 0 then self:AddSetValue("mplusMaps", mapID) end
        self:AddGuildmatesToSets(members, "mplusGuildmates")
        self:AddSetValue("contentTypes", "MPLUS")

        if level > 0 and level <= 12 then self:AddStat("mplusLowGuildRuns", 1) end
        if level == 12 then self:AddStat("mplusExact12GuildRuns", 1) end
        if level > 0 and level % 2 == 0 then self:AddStat("mplusEvenGuildRuns", 1) end
        if level > 0 and level % 2 == 1 then self:AddStat("mplusOddGuildRuns", 1) end
        if guildCount >= 5 then self:AddStat("mplusFullGuildRuns", 1) end
        if info.onTime then self:AddStat("mplusTimedGuildRuns", 1) else self:AddStat("mplusOutOfTimeGuildRuns", 1) end
        if deathCountKnown and deaths == 0 then self:AddStat("mplusZeroDeathGuildRuns", 1) end

        local dungeonName = "Mythic+"
        if C_ChallengeMode.GetMapUIInfo and mapID > 0 then
            dungeonName = C_ChallengeMode.GetMapUIInfo(mapID) or dungeonName
        end
        BJ:AddMoment(string.format("%s +%d completata con %d Blackjack%s.", dungeonName, level, guildCount, info.onTime and " in tempo" or " fuori tempo ma insieme"), "MPLUS")
    end
    self:EndBatch()
end

function Progress:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if success ~= 1 or not IsInInstance() then return end

    local instanceName, instanceType, instanceID = CurrentInstance()
    local guildCount = BJ.Guild and BJ.Guild:CountGuildInGroup() or 0
    local names = BJ.Guild and BJ.Guild:GetGuildNamesInGroup() or {}
    local encounterKey = tostring(instanceID) .. ":" .. tostring(encounterID or 0)

    if instanceType == "raid" then
        self:BeginBatch()

        if guildCount >= 8 then
            self:AddStat("guildRaidBosses", 1)
            self:AddSetValue("guildRaidBossIds", encounterKey)
            self:AddSetValue("raidDays", DayKey())
            if instanceID > 0 then self:AddSetValue("raidInstances", instanceID) end
            self:AddGuildmatesToSets(names, "raidGuildmates")
            self:AddSetValue("contentTypes", "RAID")
        end

        if instanceID == CURRENT_SEASON_RAID_INSTANCE_ID and guildCount >= 8 then
            self:AddStat("currentRaidBosses", 1)
            self:AddSetValue("currentRaidBossIds", encounterKey)
            self:AddSetValue("currentRaidDays", DayKey())
            self:AddGuildmatesToSets(names, "currentRaidGuildmates")
        elseif instanceID ~= CURRENT_SEASON_RAID_INSTANCE_ID and guildCount >= 3 then
            self:AddStat("legacyRaidBosses", 1)
            self:AddSetValue("legacyRaidBossIds", encounterKey)
            if instanceID > 0 then self:AddSetValue("legacyRaidInstances", instanceID) end
            self:AddGuildmatesToSets(names, "legacyRaidGuildmates")
            self:AddSetValue("contentTypes", "LEGACY")
        end

        if guildCount >= 3 then
            BJ:AddMoment((encounterName or "Boss") .. " sconfitto in " .. instanceName .. " con " .. guildCount .. " Blackjack.", "RAID")
        end
        self:EndBatch()
        return
    end

    if instanceType == "party" and not ChallengeModeActive() and guildCount >= 3 then
        self:BeginBatch()
        self:AddStat("guildDungeonBosses", 1)
        self:AddSetValue("dungeonBossIds", encounterKey)
        if instanceID > 0 then self:AddSetValue("dungeonInstances", instanceID) end
        if guildCount >= 5 then self:AddStat("fullGuildDungeonBosses", 1) end
        self:AddGuildmatesToSets(names, "dungeonGuildmates")
        self:AddSetValue("contentTypes", "DUNGEON")
        BJ:AddMoment((encounterName or "Boss") .. " sconfitto in " .. instanceName .. " con " .. guildCount .. " Blackjack.", "DUNGEON")
        self:EndBatch()
    end
end

function Progress:UpdateDelveState()
    if not C_PartyInfo or not C_PartyInfo.IsDelveInProgress then return end
    local inProgress = C_PartyInfo.IsDelveInProgress() and true or false
    if inProgress then
        self.delveActive = true
        local instanceName, _, instanceID = CurrentInstance()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
        self.delveInstanceKey = instanceID > 0 and ("I" .. instanceID) or (mapID and ("M" .. mapID) or instanceName)
    elseif not (C_PartyInfo.IsDelveComplete and C_PartyInfo.IsDelveComplete()) then
        self.delveActive = false
        self.delveInstanceKey = nil
    end
end

function Progress:OnScenarioCompleted()
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    local isDelve = self.delveActive
    if C_PartyInfo and C_PartyInfo.IsDelveComplete and C_PartyInfo.IsDelveComplete() then isDelve = true end
    if not isDelve then return end

    local names = BJ.Guild and BJ.Guild:GetGuildNamesInGroup() or {}
    local guildCount = BJ:CountTable(names)
    if guildCount >= 2 then
        local instanceName, _, instanceID = CurrentInstance()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
        local key = self.delveInstanceKey or (instanceID > 0 and ("I" .. instanceID)) or (mapID and ("M" .. mapID)) or instanceName

        self:BeginBatch()
        self:AddStat("delveGuildRuns", 1)
        self:AddSetValue("delveInstances", key)
        self:AddGuildmatesToSets(names, "delveGuildmates")
        self:AddSetValue("contentTypes", "DELVE")
        BJ:AddMoment("Delve completata con " .. guildCount .. " Blackjack.", "DELVE")
        self:EndBatch()
    end

    self.delveActive = false
    self.delveInstanceKey = nil
end

function Progress:OnPvPMatchActive()
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    local instanceName, _, instanceID = CurrentInstance()
    self.pvpSnapshot = {
        names = BJ.Guild and BJ.Guild:GetGuildNamesInGroup() or {},
        instanceName = instanceName,
        instanceID = instanceID,
    }
end

function Progress:OnPvPMatchComplete(winner, duration)
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    local current = BJ.Guild and BJ.Guild:GetGuildNamesInGroup() or {}
    local snap = self.pvpSnapshot or {}
    local names = BJ:CountTable(current) >= BJ:CountTable(snap.names) and current or (snap.names or current)
    local guildCount = BJ:CountTable(names)
    if guildCount < 2 then self.pvpSnapshot = nil; return end

    local instanceName, _, instanceID = CurrentInstance()
    instanceName = (snap.instanceName and snap.instanceName ~= "?") and snap.instanceName or instanceName
    instanceID = (snap.instanceID and snap.instanceID > 0) and snap.instanceID or instanceID
    local key = instanceID > 0 and instanceID or instanceName

    self:BeginBatch()
    self:AddStat("guildPvPMatches", 1)
    self:AddSetValue("pvpInstances", key)
    self:AddGuildmatesToSets(names, "pvpGuildmates")
    self:AddSetValue("contentTypes", "PVP")
    BJ:AddMoment("Match PvP completato con " .. guildCount .. " Blackjack.", "PVP")
    self:EndBatch()
    self.pvpSnapshot = nil
end

function Progress:OnAchievementEarned(achievementID)
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if not BJ.Guild then return end
    local names = BJ.Guild:GetGuildNamesInGroup()
    local guildCount = BJ:CountTable(names)
    if guildCount < 2 then return end

    self:BeginBatch()
    self:AddStat("guildAchievements", 1)
    self:AddSetValue("guildAchievementIds", achievementID or 0)
    self:AddGuildmatesToSets(names, "achievementGuildmates")
    self:AddSetValue("contentTypes", "ACHIEVEMENT")

    local _, instanceType, instanceID = CurrentInstance()
    if instanceType == "raid" and instanceID ~= CURRENT_SEASON_RAID_INSTANCE_ID and guildCount >= 3 then
        self:AddStat("legacyAchievements", 1)
    end

    local achievementName
    if GetAchievementInfo and achievementID then
        local _, name = GetAchievementInfo(achievementID)
        achievementName = name
    end
    BJ:AddMoment("Achievement di gruppo: " .. (achievementName or tostring(achievementID or "sconosciuto")) .. ".", "ACHIEVEMENT")
    self:EndBatch()
end

function Progress:OnNewMountAdded(mountID)
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if not BJ.Guild then return end
    local names = BJ.Guild:GetGuildNamesInGroup()
    local guildCount = BJ:CountTable(names)
    if guildCount < 2 then return end

    self:BeginBatch()
    self:AddStat("guildNewMounts", 1)
    self:AddGuildmatesToSets(names, "collectionGuildmates")
    self:AddSetValue("contentTypes", "COLLECTION")

    local _, instanceType, instanceID = CurrentInstance()
    if instanceType == "raid" and instanceID ~= CURRENT_SEASON_RAID_INSTANCE_ID and guildCount >= 3 then
        self:AddStat("legacyNewMounts", 1)
    end

    BJ:AddMoment("Nuova mount aggiunta alla collezione mentre eri con la gilda.", "MOUNT")
    self:EndBatch()
end
