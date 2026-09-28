local _, BJ = ...

BJ.Activities = {}
local Activities = BJ.Activities

Activities.listeners = {}

function Activities:Initialize()
    self:Cleanup()
    C_Timer.NewTicker(20, function()
        Activities:Cleanup()
        if BJ.HUD then BJ.HUD:Refresh() end
    end)
    -- Recovery sync: ask current owners for their active tables shortly after load.
    C_Timer.After(3.5, function()
        if BJ.Comms then BJ.Comms:RequestActivities() end
    end)
    -- Re-announce only owned active tables at a low cadence. This recovers from a
    -- missed guild packet without creating a noisy all-to-all synchronization loop.
    C_Timer.NewTicker(90, function()
        if BJ.Access and BJ.Access:IsAuthorized() and BJ.Comms then
            BJ.Comms:BroadcastActivities("GUILD")
        end
    end)
end

function Activities:NotifyChanged()
    if BJ.UI then
        BJ.UI:RefreshPage("HOME")
        BJ.UI:RefreshPage("ACTIVITIES")
    end
    if BJ.HUD then BJ.HUD:Refresh() end
end

function Activities:NewID()
    -- The old timestamp + 12 random bits could collide between guild members.
    BJ.db.activitySerial = (tonumber(BJ.db.activitySerial) or 0) + 1
    return string.format("%s:%x:%x", UnitGUID("player") or BJ.player, BJ:Now(), BJ.db.activitySerial)
end

function Activities:Create(data)
    if BJ.Access and not BJ.Access:Require() then return nil end
    if not IsInGuild() then
        BJ:Print("Devi essere in una gilda per pubblicare un'attivita Blackjack.")
        return nil
    end

    local now = BJ:Now()
    local duration = BJ.Data:GetDuration(data.durationId or "60")
    local target = BJ.Data:GetTarget(data.targetId or "5")
    local preset = BJ.Data:GetPreset(data.category or "MPLUS", data.presetId)
    local id = self:NewID()

    local entry = {
        id = id,
        owner = BJ.player,
        category = data.category or "MPLUS",
        presetId = preset and preset.id or "",
        title = BJ:Utf8Truncate(data.title and data.title ~= "" and data.title or (preset and preset.title) or "Attivita Blackjack", 42),
        description = BJ:Utf8Truncate(data.description and data.description ~= "" and data.description or (preset and preset.description) or "", 92),
        keyBand = data.keyBand or "ANY",
        role = data.role or "ANY",
        target = target.value,
        created = now,
        expires = now + duration.seconds,
        count = 1,
        participants = { [BJ.player] = true },
        localOwned = true,
        revision = 1,
    }

    BJ.db.network.activities[id] = entry
    BJ.db.joinedActivities[id] = true
    if BJ.db.activityLeaves[BJ.player] then BJ.db.activityLeaves[BJ.player][id] = nil end
    if BJ.Progress then BJ.Progress:AddSetValue("openedActivityIds", id) end
    if BJ.Comms then BJ.Comms:BroadcastActivity(entry) end
    BJ:AddMoment("Nuovo tavolo: " .. entry.title .. " (" .. BJ.Data:GetCategory(entry.category).label .. ")", "ACTIVITY")
    self:NotifyChanged()
    return entry
end

function Activities:Delete(id)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner ~= BJ.player then return end
    self:RememberDeletion(id, BJ.player, entry.expires)
    BJ.db.network.activities[id] = nil
    BJ.db.joinedActivities[id] = nil
    if BJ.Comms then BJ.Comms:SendSystem("ACTDEL", "GUILD", nil, id) end
    self:NotifyChanged()
end

function Activities:Join(id)
    if BJ.Access and not BJ.Access:Require() then return end
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner == BJ.player then return end
    if BJ.db.joinedActivities[id] then return end
    BJ.db.joinedActivities[id] = true
    if BJ.db.activityLeaves[BJ.player] then BJ.db.activityLeaves[BJ.player][id] = nil end
    if BJ.Progress then BJ.Progress:AddSetValue("joinedActivityIds", id) end
    if BJ.Comms then BJ.Comms:SendSystem("JOIN", "GUILD", nil, id) end
    self:NotifyChanged()
end

function Activities:Leave(id)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner == BJ.player then return end
    if not BJ.db.joinedActivities[id] then return end
    BJ.db.joinedActivities[id] = nil
    BJ.db.activityLeaves[BJ.player] = BJ.db.activityLeaves[BJ.player] or {}
    BJ.db.activityLeaves[BJ.player][id] = entry.expires
    if BJ.Comms then BJ.Comms:SendSystem("LEAVE", "GUILD", nil, id) end
    self:NotifyChanged()
end

function Activities:HandleJoin(id, sender)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner ~= BJ.player then return end
    sender = BJ:NormalizeName(sender)
    if not sender then return end
    entry.participants = entry.participants or { [BJ.player] = true }
    if entry.participants[sender] then return end
    entry.participants[sender] = true
    entry.count = BJ:CountTable(entry.participants)
    entry.revision = (entry.revision or 0) + 1
    if BJ.Comms then BJ.Comms:BroadcastActivityCount(entry) end
    BJ:Print(BJ:ShortName(sender) .. " si e unito a |cffffffff" .. entry.title .. "|r.")
    self:NotifyChanged()
end

function Activities:HandleLeave(id, sender)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner ~= BJ.player then return end
    sender = BJ:NormalizeName(sender)
    if not sender or sender == BJ.player or not (entry.participants and entry.participants[sender]) then return end
    if entry.participants and sender then entry.participants[sender] = nil end
    entry.count = math.max(1, BJ:CountTable(entry.participants))
    entry.revision = (entry.revision or 0) + 1
    if BJ.Comms then BJ.Comms:BroadcastActivityCount(entry) end
    self:NotifyChanged()
end

function Activities:HandleRemoteActivity(sender, fields)
    -- Protocol V4 ACT layout:
    -- V4 | ACT | id | category | presetId | keyBand | role | target | expires | count
    local id = fields[3]
    local expires = tonumber(fields[9]) or 0
    sender = BJ:NormalizeName(sender)
    local count, target = tonumber(fields[10]), tonumber(fields[8])
    if not sender or type(id) ~= "string" or id == "" or #id > 100
        or not (expires > BJ:Now() and expires <= BJ:Now() + 10860)
        or not count or count < 1 or count > 1000 or count ~= math.floor(count)
        or not target or target < 1 or target > 40 or target ~= math.floor(target) then return nil end
    if self:IsDeleted(id, sender) then return nil end

    local category = fields[4] or "SOCIAL"
    local presetId = fields[5] or ""
    local preset = BJ.Data and BJ.Data:GetPreset(category, presetId)
    local old = BJ.db.network.activities[id] or {}
    -- A received packet never transfers ownership, including an echo of our own
    -- activity or an ID collision from an older client.
    if sender == BJ.player or (old.owner and old.owner ~= sender) then return nil end
    local revision = tonumber(fields[11]) or 0
    if revision < 0 or revision > 9007199254740991 or revision ~= math.floor(revision) then return nil end
    if revision < (old.revision or 0) then return nil end
    old.id = id
    old.owner = BJ:NormalizeName(sender) or sender
    old.category = category
    old.presetId = presetId
    old.title = old.title or (preset and preset.title) or "Attivita Blackjack"
    old.description = old.description or (preset and preset.description) or ""
    old.keyBand = fields[6] or "ANY"
    old.role = fields[7] or "ANY"
    old.target = tonumber(fields[8]) or 5
    old.expires = expires
    old.count = tonumber(fields[10]) or old.count or 1
    old.revision = revision
    old.localOwned = false
    BJ.db.network.activities[id] = old
    -- Reassert subscriptions on the owner's heartbeat, recovering a lost JOIN.
    if BJ.db.joinedActivities[id] and BJ.Comms then BJ.Comms:SendSystem("JOIN", "GUILD", nil, id) end
    self:NotifyChanged()
    return id
end

function Activities:HandleRemoteActivityText(id, sender, title, description)
    local entry = id and BJ.db.network.activities[id]
    if not entry then return false end
    local normalized = BJ:NormalizeName(sender) or sender
    if normalized ~= entry.owner then return false end
    if title and title ~= "" then entry.title = title end
    if description then entry.description = description end
    self:NotifyChanged()
    return true
end

function Activities:HandleCount(id, count, sender, revision)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner ~= BJ:NormalizeName(sender) or entry.owner == BJ.player then return end
    count, revision = tonumber(count), tonumber(revision) or 0
    if revision < 0 or revision > 9007199254740991 or revision ~= math.floor(revision) then return end
    if not count or count < 1 or count > 1000 or count ~= math.floor(count) or revision < (entry.revision or 0) then return end
    entry.count, entry.revision = count, revision
    self:NotifyChanged()
end

function Activities:IsDeleted(id, sender)
    local row = BJ.db.network.activityTombstones[id .. "|" .. sender]
    return row and row.expires > BJ:Now()
end

function Activities:RememberDeletion(id, sender, expires)
    BJ.db.network.activityTombstones[id .. "|" .. sender] = {
        id = id, owner = sender, expires = math.max(tonumber(expires) or 0, BJ:Now() + 10860),
    }
end

function Activities:HandleDelete(id, sender)
    sender = BJ:NormalizeName(sender)
    if not sender or type(id) ~= "string" or id == "" or #id > 100 then return end
    local entry = BJ.db.network.activities[id]
    if sender == BJ.player or (entry and entry.owner ~= sender) then return end
    -- Keep deletions even if ACT has not arrived yet. Key by sender as well as ID
    -- so another member cannot suppress the real owner's announcement.
    if not self:IsDeleted(id, sender) then self:RememberDeletion(id, sender, entry and entry.expires) end
    if entry then
        BJ.db.network.activities[id] = nil
        BJ.db.joinedActivities[id] = nil
        self:NotifyChanged()
    end
end

local function GroupMemberSet()
    local members = {}
    local function addUnit(unit)
        if not UnitExists(unit) then return end
        local name, realm = UnitFullName(unit)
        if not name then return end
        local full = name
        if realm and realm ~= "" then full = name .. "-" .. realm end
        full = BJ:NormalizeName(full) or full
        if full then members[full] = true end
    end

    addUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do addUnit("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do addUnit("party" .. i) end
    end
    return members
end

function Activities:GetParticipants(id)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner ~= BJ.player then return {} end
    local list = {}
    for name in pairs(entry.participants or {}) do
        if name ~= BJ.player then list[#list + 1] = name end
    end
    table.sort(list, function(a, b) return BJ:ShortName(a) < BJ:ShortName(b) end)
    return list
end

function Activities:GetInvitableParticipants(id)
    local grouped = GroupMemberSet()
    local list = {}
    for _, name in ipairs(self:GetParticipants(id)) do
        local full = BJ:NormalizeName(name) or name
        if full and not grouped[full] then list[#list + 1] = full end
    end
    return list
end

function Activities:InviteParticipants(id)
    local entry = BJ.db.network.activities[id]
    if not entry or entry.owner ~= BJ.player then return 0 end

    local invite = C_PartyInfo and C_PartyInfo.InviteUnit
    if not invite then
        BJ:Print("Impossibile invitare: API gruppo non disponibile.")
        return 0
    end

    if IsInGroup() and C_PartyInfo.CanInvite and not C_PartyInfo.CanInvite() then
        BJ:Print("Non puoi invitare giocatori nel gruppo attuale.")
        return 0
    end

    local candidates = self:GetInvitableParticipants(id)
    if #candidates == 0 then
        BJ:Print("Nessun partecipante del tavolo da invitare.")
        return 0
    end

    local invited = 0
    for _, name in ipairs(candidates) do
        C_PartyInfo.InviteUnit(name)
        invited = invited + 1
    end

    if invited == 1 then
        BJ:Print("Invito inviato a " .. BJ:ShortName(candidates[1]) .. ".")
    else
        BJ:Print("Inviti inviati a " .. invited .. " partecipanti del tavolo.")
    end
    return invited
end

function Activities:Cleanup()
    if not BJ.db then return end
    local now = BJ:Now()
    local changed = false
    for key, row in pairs(BJ.db.network.activityTombstones) do
        if row.expires <= now then BJ.db.network.activityTombstones[key] = nil end
    end
    for player, leaves in pairs(BJ.db.activityLeaves) do
        for id, expires in pairs(leaves) do
            if expires <= now then leaves[id] = nil end
        end
        if next(leaves) == nil then BJ.db.activityLeaves[player] = nil end
    end
    for id, entry in pairs(BJ.db.network.activities) do
        if not entry.expires or entry.expires <= now then
            BJ.db.network.activities[id] = nil
            BJ.db.joinedActivities[id] = nil
            changed = true
        end
    end
    if changed then self:NotifyChanged() end
end

function Activities:GetActive()
    self:Cleanup()
    local now, list = BJ:Now(), {}
    for _, entry in pairs(BJ.db.network.activities) do
        if entry.expires and entry.expires > now then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        if a.expires ~= b.expires then return a.expires < b.expires end
        return (a.title or "") < (b.title or "")
    end)
    return list
end

function Activities:GetOwned()
    local list = {}
    for _, entry in ipairs(self:GetActive()) do
        if entry.owner == BJ.player then list[#list + 1] = entry end
    end
    return list
end

function Activities:GetJoinedState(id)
    return BJ.db.joinedActivities[id] and true or false
end
