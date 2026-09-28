local _, BJ = ...

BJ.Comms = {}
local Comms = BJ.Comms

Comms.queue = {}
Comms.pendingActivityText = {}
Comms.profileRequestAt = {}
Comms.lastProfileStatus = nil
Comms.profileWire = 3
Comms.lastSendResult = nil
Comms.lastSendAt = 0
Comms.lastReceiveAt = 0
Comms.lastReceiveKind = nil
Comms.prefixResult = nil
Comms.requestAt = {}

function Comms:Cleanup()
    local now = BJ:Now()
    for key, row in pairs(self.pendingActivityText) do
        if now - (row.at or 0) > 300 then self.pendingActivityText[key] = nil end
    end
    for key, at in pairs(self.requestAt) do
        if now - at > 300 then self.requestAt[key] = nil end
    end
    for key, at in pairs(self.profileRequestAt) do
        if now - at > 300 then self.profileRequestAt[key] = nil end
    end
    for key, peer in pairs(BJ.db.network.peers) do
        if now - (peer.lastSeen or 0) > 86400 then BJ.db.network.peers[key] = nil end
    end
    for name, profile in pairs(BJ.db.network.profiles) do
        if now - (profile.updated or 0) > 30 * 86400 then BJ.db.network.profiles[name] = nil end
    end
    for name, summary in pairs(BJ.db.network.summaries) do
        if now - (summary.updated or 0) > 7 * 86400 then BJ.db.network.summaries[name] = nil end
    end
end

function Comms:StoreActivityText(id, sender, title, description)
    if #id > 100 or id == "" or BJ.Activities:IsDeleted(id, sender) then return end
    local entry = BJ.db.network.activities[id]
    if entry and entry.owner ~= sender then return end
    self:Cleanup()
    if BJ:CountTable(self.pendingActivityText) >= 256 then return end
    self.pendingActivityText[id .. "|" .. sender] = {
        sender = sender, title = title, description = description, at = BJ:Now(),
    }
end

local function ResultCode(result)
    if type(result) == "number" then return result end
    return tonumber(result)
end

local function IsSuccess(result)
    local code = ResultCode(result)
    if code == 0 then return true end
    if Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success then return true end
    return false
end

local function IsRetryable(result)
    local code = ResultCode(result)
    -- AddonMessageThrottle / ChannelThrottle / GeneralError / AddOnMessageLockdown.
    return code == 3 or code == 8 or code == 9 or code == 11
end

function Comms:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        self.prefixResult = select(-1, C_ChatInfo.RegisterAddonMessagePrefix(BJ.prefix))
    end
    BJ:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, message, channel, sender)
        Comms:OnMessage(false, prefix, message, channel, sender)
    end)
    BJ:RegisterEvent("CHAT_MSG_ADDON_LOGGED", function(_, prefix, message, channel, sender)
        Comms:OnMessage(true, prefix, message, channel, sender)
    end)
    self.ticker = C_Timer.NewTicker(1.10, function() Comms:FlushOne() end)
    self.cleanupTicker = C_Timer.NewTicker(60, function() Comms:Cleanup() end)
    -- Passport V3 deliberately uses the GUILD channel instead of WHISPER.
    -- Addon whispers only work across the same/connected realms, while modern
    -- guild rosters can contain players on realms that are not connected.
    self.profileHeartbeat = C_Timer.NewTicker(300, function()
        if BJ.Access and BJ.Access:IsAuthorized() and IsInGuild() then
            Comms:BroadcastProfile()
            if BJ.Treasury then BJ.Treasury:BroadcastState() end
            if BJ.Crafting then BJ.Crafting:BroadcastState() end
        end
    end)
end

function Comms:Make(kind, ...)
    return BJ:JoinFields("V" .. BJ.protocol, kind, ...)
end

function Comms:Queue(message, channel, target, logged, priority)
    if type(message) ~= "string" or #message > 255 then
        BJ:Debug("Messaggio scartato: " .. tostring(type(message) == "string" and #message or 0) .. " bytes")
        return false
    end
    -- Coalesce identical queued snapshots/replies before they accumulate.
    for _, queued in ipairs(self.queue) do
        if queued.message == message and queued.channel == (channel or "GUILD")
            and queued.target == target and queued.logged == (logged and true or false) then return true end
    end
    if #self.queue >= 1024 then
        BJ:Debug("Coda rete piena: messaggio scartato")
        return false
    end
    local item = {
        message = message,
        channel = channel or "GUILD",
        target = target,
        logged = logged and true or false,
        attempts = 0,
        queuedAt = BJ:Now(),
    }
    if priority then table.insert(self.queue, 1, item) else self.queue[#self.queue + 1] = item end
    return true
end

function Comms:FlushOne()
    if #self.queue == 0 then return end
    if not IsInGuild() or (BJ.Access and not BJ.Access:IsAuthorized()) then
        self.queue = {}
        return
    end
    local item = self.queue[1]
    local result

    if item.logged and C_ChatInfo.SendAddonMessageLogged then
        result = select(-1, C_ChatInfo.SendAddonMessageLogged(BJ.prefix, item.message, item.channel, item.target))
    else
        result = select(-1, C_ChatInfo.SendAddonMessage(BJ.prefix, item.message, item.channel, item.target))
    end

    item.attempts = item.attempts + 1
    self.lastSendResult = result
    self.lastSendAt = BJ:Now()

    if IsSuccess(result) then
        table.remove(self.queue, 1)
        return
    end

    if not IsRetryable(result) or item.attempts >= 8 then
        BJ:Debug("Invio fallito: result=" .. tostring(result) .. ", channel=" .. tostring(item.channel) .. ", logged=" .. tostring(item.logged))
        table.remove(self.queue, 1)
    end
end

function Comms:SendSystem(kind, channel, target, ...)
    return self:Queue(self:Make(kind, ...), channel, target, false)
end

function Comms:SendPrioritySystem(kind, channel, target, ...)
    return self:Queue(self:Make(kind, ...), channel, target, false, true)
end

function Comms:SendUser(kind, channel, target, ...)
    return self:Queue(self:Make(kind, ...), channel, target, true)
end

function Comms:Announce()
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if IsInGuild() then self:SendSystem("HELLO", "GUILD", nil, BJ.version) end
end

function Comms:RequestActivities()
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if IsInGuild() then self:SendSystem("AREQ", "GUILD") end
end

function Comms:DropQueuedProfileBroadcasts()
    for i = #self.queue, 1, -1 do
        local item = self.queue[i]
        local m = item.message or ""
        if item.channel == "GUILD" and (m:find("|PMETA|", 1, true) or m:find("|PCLEAR|", 1, true)
            or m:sub(1, 10) == "BJPROFILE " or m:sub(1, 14) == "BJTESTPROFILE ") then
            table.remove(self.queue, i)
        end
    end
end

function Comms:RequestProfile(target, force)
    target = BJ:NormalizeName(target) or target
    if not target or target == BJ.player or not IsInGuild() then return false end
    local now = BJ:Now()
    local last = self.profileRequestAt[target] or 0
    if not force and now - last < 5 then return false end
    self.profileRequestAt[target] = now
    self.lastProfileStatus = "Richiesto Passport di " .. BJ:ShortName(target) .. " via gilda"
    -- Target is part of the payload, not the transport destination. This is the key
    -- cross-realm fix: the owner receives the request through GUILD and replies to GUILD.
    self:SendSystem("PREQ", "GUILD", nil, target)
    return true
end

function Comms:GetRemoteProfile(sender, revision)
    sender = BJ:NormalizeName(sender) or sender
    if not sender then return nil end
    local profile = BJ.db.network.profiles[sender]
    if not profile then
        profile = {
            tagline = "", likes = "", help = "", alts = "",
            titleId = "starter", badgeId = "", revision = tonumber(revision) or 0,
            syncVersion = self.profileWire,
        }
        BJ.db.network.profiles[sender] = profile
    end
    return profile
end

function Comms:RefreshRemoteProfileUI(sender)
    self.lastProfileStatus = "Passport aggiornato: " .. BJ:ShortName(sender)
    if BJ.UI then
        BJ.UI:RefreshPage("MEMBERS")
        BJ.UI:RefreshPage("ACTIVITIES")
    end
end

function Comms:ApplyProfileMeta(sender, revision, wire, titleId, badgeId)
    revision = tonumber(revision) or 0
    if revision <= (BJ.db.network.profileTombstones[sender] or -1) then return false end
    local profile = self:GetRemoteProfile(sender, revision)
    local current = tonumber(profile.revision) or 0
    if revision < current then return false end
    profile.revision = revision
    profile.syncVersion = tonumber(wire) or self.profileWire
    profile.titleId = titleId and titleId ~= "" and titleId or "starter"
    profile.badgeId = badgeId or ""
    profile.updated = BJ:Now()
    profile.metaSeenAt = BJ:Now()
    self:RefreshRemoteProfileUI(sender)
    return true
end

function Comms:ApplyProfileField(sender, revision, field, value)
    revision = tonumber(revision) or 0
    if revision <= (BJ.db.network.profileTombstones[sender] or -1) then return false end
    local profile = self:GetRemoteProfile(sender, revision)
    local current = tonumber(profile.revision) or 0
    if revision < current then return false end
    profile.revision = math.max(current, revision)
    profile.syncVersion = self.profileWire
    if field == "TAGLINE" then profile.tagline = value or ""
    elseif field == "LIKES" then profile.likes = value or ""
    elseif field == "HELP" then profile.help = value or ""
    elseif field == "ALTS" then profile.alts = value or ""
    else return false end
    profile.updated = BJ:Now()
    profile[field:lower() .. "SeenAt"] = BJ:Now()
    self:RefreshRemoteProfileUI(sender)
    return true
end

function Comms:QueueProfileText(revision, field, text)
    local value = BJ:Utf8Truncate(text or "", field == "ALTS" and 40 or 56)
    -- Logged addon messages must remain human-readable because these fields are
    -- written by the user. The sender identity itself identifies the Passport owner.
    local message = "BJPROFILE " .. tostring(revision) .. " " .. field .. " " .. value
    return self:Queue(message, "GUILD", nil, true)
end

function Comms:QueueProfileStyle(revision, titleId, badgeId)
    -- Redundant readable style packet. The four Passport text fields already proved
    -- reliable through CHAT_MSG_ADDON_LOGGED; carrying style here prevents title/badge
    -- from depending solely on PMETA. IDs are addon-owned, short and human-readable.
    local message = "BJPROFILE " .. tostring(revision) .. " STYLE "
        .. tostring(titleId or "starter") .. " " .. tostring(badgeId or "-")
    return self:Queue(message, "GUILD", nil, true)
end

function Comms:BroadcastTestProfileStyle()
    if not (BJ.TestMode and BJ.TestMode:IsEnabled()) or not IsInGuild() then return false end
    BJ.TestMode:Initialize()
    local store = BJ.db.test
    local revision = tonumber(store.profileRevision) or 0
    if revision <= 0 then revision = BJ:Now(); store.profileRevision = revision end
    local message = "BJTESTPROFILE " .. tostring(revision) .. " STYLE "
        .. tostring(store.titleId or "starter") .. " " .. tostring(store.badgeId or "-")
    return self:Queue(message, "GUILD", nil, true)
end

function Comms:BroadcastProfile()
    if not IsInGuild() then return false end
    local p = BJ.profile
    local revision = tonumber(p.updated) or BJ:Now()
    p.updated = revision

    self:DropQueuedProfileBroadcasts()
    if not BJ.db.settings.shareProfile then
        self:SendSystem("PCLEAR", "GUILD", nil, revision)
        return true
    end

    self:SendSystem("PMETA", "GUILD", nil, revision, self.profileWire,
        p.titleId or "starter", p.badgeId or "")
    self:QueueProfileStyle(revision, p.titleId or "starter", p.badgeId or "")
    self:QueueProfileText(revision, "TAGLINE", p.tagline)
    self:QueueProfileText(revision, "LIKES", p.likes)
    self:QueueProfileText(revision, "HELP", p.help)
    self:QueueProfileText(revision, "ALTS", p.alts)
    if BJ.TestMode and BJ.TestMode:IsEnabled() then self:BroadcastTestProfileStyle() end
    self.lastProfileStatus = "Passport rev " .. tostring(revision) .. " inviato alla gilda"
    return true
end

-- ACT deliberately contains protocol-only data and therefore uses the normal addon
-- channel. Free-form title/description are sent separately through ACTTXT using the
-- logged API. This guarantees that a table can still be discovered if Blizzard rejects
-- a logged free-form payload for any reason.
function Comms:BroadcastActivity(entry, channel, target)
    if not entry or entry.owner ~= BJ.player then return end
    local count = entry.count or 1
    local ch = channel or "GUILD"
    self:SendSystem("ACT", ch, target,
        entry.id,
        entry.category,
        entry.presetId or "",
        entry.keyBand or "ANY",
        entry.role or "ANY",
        entry.target or 5,
        entry.expires or 0,
        count,
        entry.revision or 0
    )
    -- Activity free text is intentionally sent as a plain logged payload instead of
    -- a field-serialized protocol packet. The addon prefix already versions the
    -- channel, while keeping the user's message outside JoinFields avoids separator
    -- escaping/validation issues that previously left remote clients on the preset
    -- default text.
    local header = "ACTTXT " .. tostring(entry.id) .. " "
    local description = BJ:Utf8Truncate(entry.description or "", math.min(190, 255 - #header))
    self:Queue(header .. description, ch, target, true)
end

function Comms:BroadcastActivityCount(entry)
    if not entry or entry.owner ~= BJ.player then return end
    self:SendSystem("COUNT", "GUILD", nil, entry.id, entry.count or 1, entry.revision or 0)
end

function Comms:BroadcastActivities(channel, target)
    local list = BJ.Activities and BJ.Activities:GetOwned() or {}
    for i = 1, #list do self:BroadcastActivity(list[i], channel, target) end
    for _, row in pairs(BJ.db.network.activityTombstones) do
        if row.owner == BJ.player and row.expires > BJ:Now() then
            self:SendSystem("ACTDEL", channel or "GUILD", target, row.id)
        end
    end
    for id, expires in pairs(BJ.db.activityLeaves[BJ.player] or {}) do
        if expires > BJ:Now() then self:SendSystem("LEAVE", channel or "GUILD", target, id) end
    end
end

function Comms:BroadcastSummary(channel, target)
    -- La sandbox TEST e esclusivamente locale: non propagare riepiloghi fittizi.
    if BJ.TestMode and BJ.TestMode:IsEnabled() then return end
    local p = BJ.db.progress
    local week = BJ:GetWeekKey()
    local completed = BJ.Challenges and BJ.Challenges:GetCompletedCount() or 0
    local goldClaimed = BJ.Rewards and BJ.Rewards:HasClaimedWeeklyGold() and 1 or 0
    self:SendSystem("SUM", channel or "GUILD", target,
        week, BJ.db.rewards.lifetime or 0, completed, p.stats.mplusGuildRuns or 0, goldClaimed
    )
end

function Comms:BroadcastAll(channel, target)
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if not IsInGuild() then return end
    self:BroadcastProfile()
    if BJ.TestMode and BJ.TestMode:IsEnabled() then self:BroadcastTestProfileStyle() end
    self:BroadcastActivities(channel or "GUILD", target)
    self:BroadcastSummary(channel or "GUILD", target)
    if BJ.Treasury then BJ.Treasury:BroadcastState() end
    if BJ.Crafting then BJ.Crafting:BroadcastState() end
end

function Comms:ApplyPendingActivityText(id)
    local entry = BJ.db.network.activities[id]
    local key = entry and (id .. "|" .. entry.owner)
    local pending = key and self.pendingActivityText[key]
    if not pending or not BJ.Activities then return end
    if BJ.Activities:HandleRemoteActivityText(id, pending.sender, pending.title, pending.description) then
        self.pendingActivityText[key] = nil
    end
end

function Comms:OnMessage(isLogged, prefix, message, channel, sender)
    if BJ.Access and not BJ.Access:IsAuthorized() then return end
    if prefix ~= BJ.prefix or type(message) ~= "string" or #message > 255 then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    sender = BJ:NormalizeName(sender) or sender
    if type(sender) ~= "string" or sender == "" then return end
    if sender == BJ.player then return end

    if channel == "WHISPER" and BJ.Guild and not BJ.Guild:IsMember(sender) then
        return
    end

    -- TEST reward appearance is shared only between clients that explicitly have
    -- Modalita Test enabled. It never writes to the real Passport/profile.
    if isLogged and message:sub(1, 14) == "BJTESTPROFILE " then
        if BJ.TestMode and BJ.TestMode:IsEnabled() then
            local revision, titleId, badgeId = message:match("^BJTESTPROFILE%s+(%d+)%s+STYLE%s+(%S+)%s+(%S+)$")
            if revision and titleId then
                BJ.TestMode:Initialize()
                sender = (BJ.Guild and BJ.Guild:ResolveMember(sender)) or sender
                local remote = BJ.db.test.remoteProfiles[sender] or {}
                if tonumber(revision) >= (tonumber(remote.revision) or 0) then
                    remote.revision = tonumber(revision)
                    remote.titleId = titleId ~= "-" and titleId or "starter"
                    remote.badgeId = badgeId and badgeId ~= "-" and badgeId or ""
                    remote.updated = BJ:Now()
                    BJ.db.test.remoteProfiles[sender] = remote
                    if BJ.UI then BJ.UI:RefreshPage("MEMBERS") end
                end
            end
        end
        return
    end

    -- Passport V3 user fields are broadcast through GUILD as readable logged text:
    -- "BJPROFILE <revision> <FIELD> <text>". This avoids cross-realm WHISPER limits.
    if isLogged and message:sub(1, 10) == "BJPROFILE " then
        local revision, field, value = message:match("^BJPROFILE%s+(%d+)%s+(%S+)%s?(.*)$")
        if revision and field == "STYLE" then
            local titleId, badgeId = (value or ""):match("^(%S+)%s+(%S+)$")
            if titleId then
                self.lastReceiveAt = BJ:Now()
                self.lastReceiveKind = "PROFILE-STYLE"
                BJ.db.network.peers[sender] = BJ.db.network.peers[sender] or {}
                BJ.db.network.peers[sender].lastSeen = BJ:Now()
                self:ApplyProfileMeta(sender, revision, self.profileWire, titleId ~= "-" and titleId or "starter", badgeId and badgeId ~= "-" and badgeId or "")
            end
            return
        end
        local validField = field == "TAGLINE" or field == "LIKES" or field == "HELP" or field == "ALTS"
        if revision and validField then
            self.lastReceiveAt = BJ:Now()
            self.lastReceiveKind = "PROFILE-" .. field
            BJ.db.network.peers[sender] = BJ.db.network.peers[sender] or {}
            BJ.db.network.peers[sender].lastSeen = BJ:Now()
            self:ApplyProfileField(sender, revision, field, value or "")
        end
        return
    end

    -- Crafting order customer notes are user-authored and therefore travel as
    -- readable logged text, separate from the structured CRAFT packet.
    if isLogged and message:sub(1, 12) == "BJCRAFTNOTE " then
        local id, note = message:match("^BJCRAFTNOTE%s+(%S+)%s?(.*)$")
        if id and BJ.Crafting then
            self.lastReceiveAt = BJ:Now()
            self.lastReceiveKind = "CRAFTNOTE"
            BJ.db.network.peers[sender] = BJ.db.network.peers[sender] or {}
            BJ.db.network.peers[sender].lastSeen = BJ:Now()
            BJ.Crafting:HandleRemoteNote(sender, id, note or "")
        end
        return
    end

    -- ACTTXT is a deliberately plain logged message: "ACTTXT <activityId> <text>".
    -- Parse it before the normal field protocol so the whole user message remains
    -- intact (including punctuation) and can be applied even if ACT arrives later.
    if isLogged and message:sub(1, 7) == "ACTTXT " then
        local id, description = message:match("^ACTTXT%s+(%S+)%s?(.*)$")
        if id and BJ.Activities then
            self.lastReceiveAt = BJ:Now()
            self.lastReceiveKind = "ACTTXT"
            BJ.db.network.peers[sender] = BJ.db.network.peers[sender] or {}
            BJ.db.network.peers[sender].lastSeen = BJ:Now()

            local applied = BJ.Activities:HandleRemoteActivityText(id, sender, nil, description or "")
            if not applied then
                self:StoreActivityText(id, sender, nil, description or "")
            end
        end
        return
    end

    local f = BJ:SplitFields(message)
    if f[1] ~= "V" .. BJ.protocol then return end
    local kind = f[2]
    if not kind then return end
    -- Requests trigger multi-packet responses; cap each sender/kind independently.
    if kind == "HELLO" or kind == "AREQ" or kind == "PREQ" or kind == "GCREQ" or kind == "CREQ" or kind == "RREQ" then
        local key = sender .. "|" .. kind
        local now = BJ:Now()
        if self.requestAt[key] and now - self.requestAt[key] < 10 then return end
        self.requestAt[key] = now
    end

    self.lastReceiveAt = BJ:Now()
    self.lastReceiveKind = kind
    BJ.db.network.peers[sender] = BJ.db.network.peers[sender] or {}
    BJ.db.network.peers[sender].lastSeen = BJ:Now()

    if kind == "HELLO" then
        BJ.db.network.peers[sender].version = f[3] or "?"
        -- When a Blackjack client comes online, every existing client re-announces
        -- its own Passport after a small jitter. Each sender has its own throttled
        -- queue, so the newcomer receives a complete roster without cross-realm whispers.
        C_Timer.After(0.4 + math.random() * 2.2, function()
            if BJ.Access:IsAuthorized() then
                Comms:BroadcastProfile()
                if BJ.TestMode and BJ.TestMode:IsEnabled() then Comms:BroadcastTestProfileStyle() end
                Comms:BroadcastSummary("GUILD")
                if BJ.Treasury then BJ.Treasury:BroadcastState() end
                if BJ.Crafting then BJ.Crafting:BroadcastState() end
                if BJ.Raider and BJ.Raider:CanManage() then BJ.Raider:HandleStateRequest(sender) end
            end
        end)
    elseif kind == "AREQ" then
        C_Timer.After(0.15 + math.random() * 0.55, function()
            if BJ.Access:IsAuthorized() then Comms:BroadcastActivities("GUILD") end
        end)
    elseif kind == "PREQ" then
        local requested = BJ:NormalizeName(f[3]) or f[3]
        if requested == BJ.player then
            C_Timer.After(0.05 + math.random() * 0.20, function()
                if BJ.Access:IsAuthorized() then Comms:BroadcastProfile() end
            end)
        end
    elseif kind == "PMETA" then
        self:ApplyProfileMeta(sender, f[3], f[4], f[5], f[6])
    elseif kind == "PCLEAR" then
        local revision = tonumber(f[3]) or 0
        local existing = BJ.db.network.profiles[sender]
        if revision < (existing and tonumber(existing.revision) or 0)
            or revision < (BJ.db.network.profileTombstones[sender] or 0) then return end
        BJ.db.network.profileTombstones[sender] = revision
        BJ.db.network.profiles[sender] = nil
        self.lastProfileStatus = "Passport non condiviso da " .. BJ:ShortName(sender)
        if BJ.UI then BJ.UI:RefreshPage("MEMBERS"); BJ.UI:RefreshPage("ACTIVITIES") end
    elseif kind == "PNOTICE" then
        local revision = tonumber(f[3]) or 0
        local existing = BJ.db.network.profiles[sender]
        if not existing or revision > (tonumber(existing.revision) or 0) then
            self:RequestProfile(sender, true)
        end
    elseif kind == "GCREQ" then
        if BJ.Treasury then
            C_Timer.After(0.1 + math.random() * 0.7, function() BJ.Treasury:BroadcastState() end)
        end
    elseif kind == "GCLAIM" then
        if BJ.Treasury then BJ.Treasury:HandleRemoteClaim(sender, f[3], f[4], f[5], f[6], false) end
    elseif kind == "GPAID" then
        if BJ.Treasury then BJ.Treasury:HandleRemotePaid(sender, f[3], f[4], f[5], f[6], f[7], false) end
    elseif kind == "TGCLAIM" then
        if BJ.Treasury and BJ.TestMode and BJ.TestMode:IsEnabled() then BJ.Treasury:HandleRemoteClaim(sender, f[3], f[4], f[5], f[6], true) end
    elseif kind == "TGPAID" then
        if BJ.Treasury and BJ.TestMode and BJ.TestMode:IsEnabled() then BJ.Treasury:HandleRemotePaid(sender, f[3], f[4], f[5], f[6], f[7], true) end
    elseif kind == "RREQ" then
        if BJ.Raider then BJ.Raider:HandleStateRequest(sender) end
    elseif kind == "RSUM" then
        if BJ.Raider then BJ.Raider:HandlePersonalSummary(sender, f) end
    elseif kind == "RFLAG" then
        if BJ.Raider then BJ.Raider:HandleRemoteFlag(sender, f[3], f[4], f[5], f[6]) end
    elseif kind == "RALT" then
        if BJ.Raider then BJ.Raider:HandleRemoteAlt(sender, f[3], f[4], f[5], f[6]) end
    elseif kind == "REXM" then
        if BJ.Raider then BJ.Raider:HandleRemoteExempt(sender, f[3], f[4], f[5], f[6], f[7], f[8]) end
    elseif kind == "RLED" then
        if BJ.Raider then BJ.Raider:HandleRemoteLedger(sender, f) end
    elseif kind == "RDEP" then
        if BJ.Raider then BJ.Raider:HandleObservedDeposit(sender, f) end
    elseif kind == "RRELAY" then
        if BJ.Raider then BJ.Raider:HandleRelayedDeposit(sender, f) end
    elseif kind == "CREQ" then
        if BJ.Crafting then
            C_Timer.After(0.1 + math.random() * 0.7, function() BJ.Crafting:BroadcastState() end)
        end
    elseif kind == "CRAFT" then
        if BJ.Crafting then BJ.Crafting:HandleRemoteOrder(sender, f) end
    elseif kind == "CDEL" then
        if BJ.Crafting then BJ.Crafting:HandleRemoteClose(sender, f[3], f[4], f[5]) end
    elseif kind == "COFFER" then
        if BJ.Crafting then BJ.Crafting:HandleOffer(sender, f[3], f[4]) end
    elseif kind == "CWORK" then
        if BJ.Crafting then BJ.Crafting:HandleWorkState(sender, f[3], f[4], f[5], f[6]) end
    elseif kind == "CREADY" then
        if BJ.Crafting then BJ.Crafting:HandleDeliveryReady(sender, f[3], f[4], f[5], f[6], f[7]) end
    elseif kind == "ACT" then
        if BJ.Activities then
            local id = BJ.Activities:HandleRemoteActivity(sender, f)
            if id then self:ApplyPendingActivityText(id) end
        end
    elseif kind == "ACTTXT" then
        -- Compatibility with 2.2.4 and earlier V4 clients. New clients send the
        -- activity message through the plain logged ACTTXT format handled above.
        local id = f[3]
        if id and BJ.Activities then
            local applied = BJ.Activities:HandleRemoteActivityText(id, sender, f[4] or "", f[5] or "")
            if not applied then
                self:StoreActivityText(id, sender, f[4] or "", f[5] or "")
            end
        end
    elseif kind == "ACTDEL" then
        local id = f[3]
        if id and BJ.Activities then BJ.Activities:HandleDelete(id, sender) end
        if id then self.pendingActivityText[id .. "|" .. sender] = nil end
    elseif kind == "JOIN" then
        if BJ.Activities then BJ.Activities:HandleJoin(f[3], sender) end
    elseif kind == "LEAVE" then
        if BJ.Activities then BJ.Activities:HandleLeave(f[3], sender) end
    elseif kind == "COUNT" then
        if BJ.Activities then BJ.Activities:HandleCount(f[3], f[4], sender, f[5]) end
    elseif kind == "SUM" then
        BJ.db.network.summaries[sender] = {
            weekKey = f[3],
            lifetime = tonumber(f[4]) or 0,
            completed = tonumber(f[5]) or 0,
            mplusGuildRuns = tonumber(f[6]) or 0,
            weeklyGoldClaimed = tonumber(f[7]) == 1,
            updated = BJ:Now(),
        }
        if BJ.UI then BJ.UI:RefreshPage("MEMBERS") end
    end
end

function Comms:PrintDiagnostics()
    local registered = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(BJ.prefix)
    local peers = BJ.db and BJ.db.network and BJ.db.network.peers and BJ:CountTable(BJ.db.network.peers) or 0
    local activities = BJ.Activities and #BJ.Activities:GetActive() or 0
    local profiles = BJ.db and BJ.db.network and BJ.db.network.profiles and BJ:CountTable(BJ.db.network.profiles) or 0
    local crafts = BJ.Crafting and #BJ.Crafting:GetActiveOrders() or 0
    BJ:Print("RETE v" .. BJ.protocol .. " prefix=" .. BJ.prefix .. " registrato=" .. tostring(registered))
    BJ:Print("Coda=" .. tostring(#self.queue) .. " ultimoInvio=" .. tostring(self.lastSendResult) .. " peers=" .. tostring(peers) .. " tavoli=" .. tostring(activities) .. " craft=" .. tostring(crafts) .. " profili=" .. tostring(profiles))
    if self.lastProfileStatus then BJ:Print("Passport: " .. tostring(self.lastProfileStatus)) end
    if BJ.Crafting then BJ:Print("Crafting: " .. tostring(BJ.Crafting.lastStatus or "-")) end
    if BJ.Treasury then
        local pending, gold = BJ.Treasury:GetPendingCount()
        BJ:Print("Cassa" .. ((BJ.TestMode and BJ.TestMode:IsEnabled()) and " TEST" or "") .. ": pending=" .. tostring(pending) .. " gold=" .. tostring(gold) .. " status=" .. tostring(BJ.Treasury.lastStatus or "-"))
    end
    if self.lastReceiveAt and self.lastReceiveAt > 0 then
        BJ:Print("Ultima ricezione: " .. tostring(self.lastReceiveKind or "?") .. " " .. BJ:FormatTimeLeft(math.max(0, BJ:Now() - self.lastReceiveAt)) .. " fa")
    else
        BJ:Print("Nessun messaggio Blackjack ricevuto in questa sessione.")
    end
end
