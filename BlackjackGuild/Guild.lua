local _, BJ = ...

BJ.Guild = {}
local Guild = BJ.Guild

Guild.members = {}
Guild.online = 0
Guild.total = 0

function Guild:Initialize()
    BJ:RegisterEvent("GUILD_ROSTER_UPDATE", function() Guild:RefreshRoster() end)
    BJ:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if BJ.UI then BJ.UI:RefreshPage("HOME") end
    end)
    self:RequestRoster()
end

function Guild:RequestRoster()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

function Guild:RefreshRoster()
    wipe(self.members)
    self.online, self.total = 0, 0
    if not IsInGuild() then
        if BJ.UI and BJ.UI.RefreshNavAccess then BJ.UI:RefreshNavAccess() end
        return
    end
    local count = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, count do
        local name, rankName, rankIndex, level, className, zone, note, officerNote, online, status, classFileName = GetGuildRosterInfo(i)
        if name then
            local full = BJ:NormalizeName(name)
            self.members[full] = {
                name = full,
                rankName = rankName,
                rankIndex = rankIndex,
                level = level,
                className = className,
                class = classFileName,
                zone = zone,
                online = online and true or false,
            }
            self.total = self.total + 1
            if online then self.online = self.online + 1 end
        end
    end
    if BJ.UI then
        BJ.UI:RefreshPage("HOME")
        BJ.UI:RefreshPage("MEMBERS")
        BJ.UI:RefreshPage("CASSA")
        BJ.UI:RefreshPage("RAIDER")
        if BJ.UI.RefreshNavAccess then BJ.UI:RefreshNavAccess() end
    end
end

function Guild:ResolveMember(name)
    if not name or name == "" then return nil end
    local full = BJ:NormalizeName(name) or name
    if self.members[full] then return full end

    -- Guild/addon events can format realm names slightly differently on connected
    -- realms. Fall back to the short name only when it identifies exactly one member.
    if name:find("-", 1, true) then return nil end
    local short = BJ:ShortName(name)
    local found
    for memberName in pairs(self.members) do
        if BJ:ShortName(memberName) == short then
            if found and found ~= memberName then return nil end
            found = memberName
        end
    end
    return found
end

function Guild:IsMember(name)
    return self:ResolveMember(name) ~= nil
end

function Guild:GetOnlineMembers()
    local list = {}
    for name, info in pairs(self.members) do
        if info.online then list[#list + 1] = info end
    end
    table.sort(list, function(a, b)
        if a.rankIndex ~= b.rankIndex then return (a.rankIndex or 99) < (b.rankIndex or 99) end
        return a.name < b.name
    end)
    return list
end

function Guild:GetGuildNamesInGroup()
    local names = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local name = BJ:GetUnitFullName(unit)
                if name and self:IsMember(name) then names[name] = true end
            end
        end
    elseif IsInGroup() then
        local player = BJ.player
        if self:IsMember(player) then names[player] = true end
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = BJ:GetUnitFullName(unit)
                if name and self:IsMember(name) then names[name] = true end
            end
        end
    else
        if self:IsMember(BJ.player) then names[BJ.player] = true end
    end
    return names
end

function BJ:GetUnitFullName(unit)
    local name, realm = UnitFullName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    local normalizedRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    return normalizedRealm and (name .. "-" .. normalizedRealm) or name
end

function Guild:CountGuildInGroup()
    return BJ:CountTable(self:GetGuildNamesInGroup())
end

function Guild:IsOfficer()
    if not IsInGuild() then return false end
    -- Rank indices are zero-based: GM and vice GM only. Editing officer notes
    -- is configurable and must not grant administrative access by itself.
    if GetGuildInfo then
        local _, _, rankIndex = GetGuildInfo("player")
        if rankIndex ~= nil then return rankIndex == 0 or rankIndex == 1 end
    end
    return self:IsOfficerName(BJ.player)
end

function Guild:IsOfficerName(name)
    local full = self:ResolveMember(name)
    local info = full and self.members[full] or nil
    if not info then return false end
    local rankIndex = tonumber(info.rankIndex)
    return rankIndex == 0 or rankIndex == 1
end
