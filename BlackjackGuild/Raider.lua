local _, BJ = ...

BJ.Raider = {}
local Raider = BJ.Raider

Raider.MONTHLY_GOLD = 8000
Raider.MONTHLY_COPPER = Raider.MONTHLY_GOLD * 10000
Raider.START_YEAR = 2026
Raider.START_MONTH = 9
Raider.bankOpen = false
Raider.lastStatus = nil
Raider.lastBankScan = 0
Raider.lastStateRequestAt = 0
Raider.bankRefreshSerial = 0
Raider.lastBankQueryAt = 0
Raider.lastMoneyLogCount = 0
Raider.bankRefreshSequence = 0
Raider.bankPollSerial = 0
Raider.bankPolling = false
Raider.bankLogScanSerial = 0
Raider.lastBankLogEventAt = 0
Raider.lastBankPollAt = 0
Raider.lastImportedAt = 0
Raider.lastBankDeposits = 0
Raider.lastBankMatched = 0
Raider.lastBankImported = 0
Raider.lastBankUnassigned = 0
Raider.lastBankIncomplete = 0
Raider.pendingOwnDeposits = {}
Raider.pendingOwnSerial = 0
Raider.depositHooked = false
Raider.lastBankBalance = nil
Raider.lastPlayerMoney = nil
Raider.playerMoneyEventBaseline = nil
Raider.bankMoneyEventBaseline = nil
Raider.lastOwnDepositDetected = 0
Raider.lastOwnDepositConfirmed = 0
Raider.lastPlayerMoneyDelta = 0
Raider.lastPlayerMoneyEventAt = 0
Raider.lastGuildBankOpenAt = 0
Raider.lastGuildBankCloseAt = 0
Raider.lastGuildBankOpenSource = nil
Raider.lastGuildBankCloseSource = nil
Raider.lastInteractionShowAt = 0
Raider.lastInteractionHideAt = 0
Raider.ownConfirmUsed = {}

local MONTHS = { "Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic" }
local AUTO_RANKS = {
    ["High Roller"] = true,
    ["Buy-In"] = true,
    ["Buy In"] = true,
}
local FLAG_RANKS = {
    ["Casinò Royale"] = true,
    ["Casino Royale"] = true,
    ["Pit Boss"] = true,
    ["Jack"] = true,
}

local function MonthIndex(year, month)
    return (tonumber(year) or 0) * 12 + (tonumber(month) or 0)
end

local function MonthKey(year, month)
    return string.format("%04d-%02d", tonumber(year) or 0, tonumber(month) or 0)
end

local function Normalize(name)
    if not name or name == "" then return nil end
    if BJ.Guild and BJ.Guild.ResolveMember then
        local resolved = BJ.Guild:ResolveMember(name)
        if resolved then return resolved end
    end
    return BJ:NormalizeName(name) or name
end

local function ApproxTransactionTime(years, months, days, hours)
    local age = (tonumber(years) or 0) * 365 * 86400
        + (tonumber(months) or 0) * 30 * 86400
        + (tonumber(days) or 0) * 86400
        + (tonumber(hours) or 0) * 3600
    return BJ:Now() - age
end

local function IsAfterStart(timestamp)
    local d = date("*t", tonumber(timestamp) or BJ:Now())
    if not d then return true end
    return MonthIndex(d.year, d.month) >= MonthIndex(Raider.START_YEAR, Raider.START_MONTH)
end

local function ParseExemptCSV(csv)
    local result = {}
    for key in tostring(csv or ""):gmatch("[^,]+") do
        if key:match("^%d%d%d%d%-%d%d$") then result[key] = true end
    end
    return result
end

local function ExemptCSV(exemptions, player)
    local keys = {}
    local prefix = tostring(player or "") .. "#"
    for id, value in pairs(exemptions or {}) do
        if value == true and id:sub(1, #prefix) == prefix then
            keys[#keys + 1] = id:sub(#prefix + 1)
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function IsGuildBankInteraction(interactionType)
    local interactionEnum = Enum and Enum.PlayerInteractionType
    local guildBanker = interactionEnum and interactionEnum.GuildBanker
    if guildBanker ~= nil then return interactionType == guildBanker end
    -- Retail has used 10 for GuildBanker since the interaction manager was introduced.
    return tonumber(interactionType) == 10
end

function Raider:HandleGuildBankOpened(source)
    source = source or "UNKNOWN"
    local wasOpen = self.bankOpen
    self.bankOpen = true

    -- If both the modern and legacy signals fire for the same interaction, do
    -- not reset baselines or start a second refresh sequence. Just make sure the
    -- live monitor is attached.
    if wasOpen then
        self:InstallDepositHook()
        if self:CanAccess() then self:StartBankPolling() end
        return false
    end

    self.lastGuildBankOpenAt = BJ:Now()
    self.lastGuildBankOpenSource = source

    -- Blizzard_GuildBankUI is load-on-demand. The interaction-manager event is
    -- the reliable Retail signal, but the deposit function can appear one frame
    -- later, so retry the hook shortly after opening too.
    self:InstallDepositHook()
    C_Timer.After(0, function() if Raider.bankOpen then Raider:InstallDepositHook() end end)
    C_Timer.After(0.25, function() if Raider.bankOpen then Raider:InstallDepositHook() end end)

    if not wasOpen then
        self.lastBankBalance = GetGuildBankMoney and tonumber(GetGuildBankMoney()) or nil
        self.lastPlayerMoney = GetMoney and tonumber(GetMoney()) or nil
        self.bankMoneyEventBaseline = self.lastBankBalance
        self.playerMoneyEventBaseline = self.lastPlayerMoney
    end

    if self:CanAccess() then
        -- Query immediately and keep polling while the physical Guild Bank
        -- interaction is open. The log remains the authoritative source.
        self:ScheduleBankRefresh("OPEN_" .. source, 0.35)
        C_Timer.After(1.4, function()
            if Raider.bankOpen and Raider:CanAccess() then Raider:ScheduleBankRefresh("OPEN_RETRY", 0) end
        end)
        self:StartBankPolling()
    end

    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
end

function Raider:HandleGuildBankClosed(source)
    source = source or "UNKNOWN"
    self.lastGuildBankCloseAt = BJ:Now()
    self.lastGuildBankCloseSource = source
    if not self.bankOpen then return end

    self.bankOpen = false
    self.bankRefreshSerial = self.bankRefreshSerial + 1
    self.bankRefreshSequence = (tonumber(self.bankRefreshSequence) or 0) + 1
    self:StopBankPolling()
    self.bankLogScanSerial = (tonumber(self.bankLogScanSerial) or 0) + 1
    self.lastBankBalance = nil
    self.lastPlayerMoney = nil
    self.bankMoneyEventBaseline = nil
    self.playerMoneyEventBaseline = nil
    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
end

function Raider:GetStore()
    BJ.db.raider = BJ.db.raider or {}
    local s = BJ.db.raider
    s.monthlyCopper = tonumber(s.monthlyCopper) or self.MONTHLY_COPPER
    s.startYear = tonumber(s.startYear) or self.START_YEAR
    s.startMonth = tonumber(s.startMonth) or self.START_MONTH
    s.flags = s.flags or {}
    s.flagUpdated = s.flagUpdated or {}
    s.altMap = s.altMap or {}
    s.altMapUpdated = s.altMapUpdated or {}
    s.ledger = s.ledger or {}
    s.exemptions = s.exemptions or {}
    s.exemptionUpdated = s.exemptionUpdated or {}
    s.personal = s.personal or {}
    s.unassigned = s.unassigned or {}
    s.bankSeen = s.bankSeen or {}
    s.depositReceipts = s.depositReceipts or {}
    s.lastBankScan = tonumber(s.lastBankScan) or 0
    s.revision = tonumber(s.revision) or 0
    return s
end

function Raider:Initialize()
    self:GetStore()
    self:InstallDepositHook()

    -- Retail 10.0+ routes NPC interactions through the Player Interaction
    -- Manager. The legacy Guild Bank frame events are kept as fallbacks because
    -- they still exist in some clients/branches, but they are not reliable on
    -- modern Retail.
    BJ:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
        if IsGuildBankInteraction(interactionType) then
            Raider.lastInteractionShowAt = BJ:Now()
            Raider:HandleGuildBankOpened("INTERACTION")
        end
    end)
    BJ:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, interactionType)
        if IsGuildBankInteraction(interactionType) then
            Raider.lastInteractionHideAt = BJ:Now()
            Raider:HandleGuildBankClosed("INTERACTION")
        end
    end)
    BJ:RegisterEvent("GUILDBANKFRAME_OPENED", function()
        Raider:HandleGuildBankOpened("LEGACY_EVENT")
    end)
    BJ:RegisterEvent("GUILDBANKFRAME_CLOSED", function()
        Raider:HandleGuildBankClosed("LEGACY_EVENT")
    end)
    BJ:RegisterEvent("GUILDBANKLOG_UPDATE", function()
        if Raider.bankOpen and Raider:CanAccess() then
            Raider.lastBankLogEventAt = BJ:Now()
            -- Do not read the money log in the same frame as Blizzard's update
            -- event. Multiple bank-log responses can arrive back-to-back and the
            -- money rows may still be cached/partial. Debounce from the LAST event.
            Raider:ScheduleBankLogScan("EVENT", 0.50)
        end
    end)
    BJ:RegisterEvent("GUILDBANK_UPDATE_MONEY", function()
        if Raider.bankOpen then
            -- PLAYER_MONEY and GUILDBANK_UPDATE_MONEY are not guaranteed to arrive
            -- in the same order. Re-sample the local character money here too: if
            -- PLAYER_MONEY was delayed/missed, the real decrease is still visible
            -- against playerMoneyEventBaseline and can confirm the deposit.
            Raider:HandlePlayerMoneyChanged("GUILDBANK_UPDATE_MONEY")
            Raider.bankMoneyEventBaseline = GetGuildBankMoney and tonumber(GetGuildBankMoney()) or Raider.bankMoneyEventBaseline
        end
        if Raider.bankOpen and Raider:CanAccess() then
            -- The Guild Bank balance can also change because another member deposits.
            -- It remains an authoritative-log refresh signal, never a standalone
            -- attribution to the local Raider.
            Raider:ScheduleBankRefreshSequence("MONEY_CHANGED")
        end
    end)
    BJ:RegisterEvent("PLAYER_MONEY", function()
        if Raider.bankOpen then Raider:HandlePlayerMoneyChanged("PLAYER_MONEY") end
    end)
    BJ:RegisterEvent("GUILD_ROSTER_UPDATE", function()
        -- Rank data may arrive after the Guild Bank was already opened. In that
        -- case CanAccess() was false during GUILDBANKFRAME_OPENED and older builds
        -- never started the money-log reader for that visit. Attach it as soon as
        -- the roster proves the player is an authorized Raider/admin.
        if Raider.bankOpen then
            if Raider:CanAccess() then
                if not Raider.bankPolling then
                    Raider.lastBankBalance = GetGuildBankMoney and tonumber(GetGuildBankMoney()) or Raider.lastBankBalance
                    Raider.lastPlayerMoney = GetMoney and tonumber(GetMoney()) or Raider.lastPlayerMoney
                    Raider.bankMoneyEventBaseline = Raider.lastBankBalance
                    Raider.playerMoneyEventBaseline = Raider.lastPlayerMoney
                    Raider:ScheduleBankRefresh("ROSTER_READY", 0.15)
                    Raider:StartBankPolling()
                end
            elseif Raider.bankPolling then
                Raider:StopBankPolling()
            end
        end

        -- Once the roster is available, an admin asks again so peers can forward
        -- receipts cached while Casino Royale/Pit Boss were offline.
        if Raider:CanManage() then
            local now = BJ:Now()
            if now - (tonumber(Raider.lastRosterReceiptRequestAt) or 0) >= 20 then
                Raider.lastRosterReceiptRequestAt = now
                C_Timer.After(0.5, function()
                    if Raider:CanManage() then Raider:RequestState(true) end
                end)
            end
        end
    end)

    C_Timer.After(4, function()
        if BJ.Access and BJ.Access:IsAuthorized() then Raider:RequestState() end
    end)
end

function Raider:GetRankInfo(name)
    name = Normalize(name)
    local info = name and BJ.Guild and BJ.Guild.members and BJ.Guild.members[name] or nil
    return info and info.rankName or nil, info
end

function Raider:IsAdminRank(name)
    if name == BJ.player then return BJ.Guild and BJ.Guild:IsOfficer() or false end
    return BJ.Guild and BJ.Guild:IsOfficerName(name) or false
end

function Raider:IsFlagRank(name)
    local rank = self:GetRankInfo(name)
    return rank and FLAG_RANKS[rank] or false
end

function Raider:IsAutoRaider(name)
    local rank = self:GetRankInfo(name)
    return rank and AUTO_RANKS[rank] or false
end

function Raider:CanManage()
    return self:IsAdminRank(BJ.player)
end

function Raider:IsRaider(name)
    name = Normalize(name)
    if not name then return false end
    if self:IsAutoRaider(name) then return true end
    if self:IsFlagRank(name) then
        return self:GetStore().flags[name] == true
    end
    return false
end

function Raider:IsEligible(name)
    name = Normalize(name)
    if not name then return false end
    return self:IsAutoRaider(name) or self:IsFlagRank(name)
end

function Raider:CanAccess()
    return self:CanManage() or self:IsRaider(BJ.player)
end

function Raider:StoreDepositReceipt(id, player, actor, amount, timestamp, origin, verified, relayedBy)
    id = tostring(id or "")
    player = Normalize(player)
    actor = Normalize(actor or player)
    origin = Normalize(origin or player)
    amount = math.floor(tonumber(amount) or 0)
    timestamp = tonumber(timestamp) or BJ:Now()
    if id == "" or not player or not actor or not origin or amount <= 0 then return nil end

    local s = self:GetStore()
    local receipt = s.depositReceipts[id]
    if not receipt then
        receipt = {
            id = id,
            player = player,
            actor = actor,
            amount = amount,
            time = timestamp,
            origin = origin,
            firstSeenAt = BJ:Now(),
            seenAt = BJ:Now(),
            verified = verified and true or false,
            relayedBy = relayedBy and Normalize(relayedBy) or nil,
        }
        s.depositReceipts[id] = receipt
    else
        receipt.seenAt = BJ:Now()
        if verified then receipt.verified = true end
        if relayedBy then receipt.relayedBy = Normalize(relayedBy) or relayedBy end
    end
    return receipt
end

function Raider:PruneDepositReceipts()
    local receipts = self:GetStore().depositReceipts
    local cutoff = BJ:Now() - (180 * 86400)
    for id, receipt in pairs(receipts) do
        local ts = tonumber(receipt.time) or tonumber(receipt.firstSeenAt) or 0
        if ts > 0 and ts < cutoff then receipts[id] = nil end
    end
end

function Raider:GetPendingReceiptCount()
    self:PruneDepositReceipts()
    local s = self:GetStore()
    local n = 0
    for id, receipt in pairs(s.depositReceipts) do
        if type(receipt) == "table" and not receipt.verified and not s.ledger[id] then n = n + 1 end
    end
    return n
end

function Raider:FindDepositReceiptMatch(owner, actor, amount, timestamp, used)
    owner, actor = Normalize(owner), Normalize(actor)
    amount, timestamp = tonumber(amount) or 0, tonumber(timestamp) or 0
    local best, bestDiff
    for id, receipt in pairs(self:GetStore().depositReceipts) do
        if not (used and used[id])
            and Normalize(receipt.player) == owner
            and Normalize(receipt.actor) == actor
            and tonumber(receipt.amount) == amount then
            local diff = math.abs((tonumber(receipt.time) or 0) - timestamp)
            if diff <= 2 * 60 * 60 and (not bestDiff or diff < bestDiff) then
                best, bestDiff = receipt, diff
            end
        end
    end
    return best
end

function Raider:BroadcastDepositReceipt(entry)
    if not entry or not BJ.Comms or not IsInGuild() then return false end
    self:StoreDepositReceipt(entry.id, entry.player, entry.actor, entry.amount, entry.time, entry.player, true)
    BJ.Comms:SendSystem("RDEP", "GUILD", nil, entry.id, entry.player, entry.actor or entry.player, entry.amount, entry.time)
    return true
end

function Raider:ForwardDepositReceipts(target)
    if not BJ.Comms or not target then return false end
    target = Normalize(target) or target
    self:PruneDepositReceipts()
    local list = {}
    for _, receipt in pairs(self:GetStore().depositReceipts) do list[#list + 1] = receipt end
    table.sort(list, function(a, b) return (tonumber(a.time) or 0) > (tonumber(b.time) or 0) end)
    local limit = math.min(#list, 80)
    for i = 1, limit do
        local r = list[i]
        BJ.Comms:SendSystem("RRELAY", "WHISPER", target, r.id, r.origin or r.player, r.player, r.actor or r.player, r.amount, r.time)
    end
    return limit > 0
end

function Raider:InstallDepositHook()
    if self.depositHooked or not hooksecurefunc or type(DepositGuildBankMoney) ~= "function" then return false end
    hooksecurefunc("DepositGuildBankMoney", function(amount)
        if Raider.bankOpen and Raider:CanAccess() then Raider:ObserveOwnDepositRequest(amount) end
    end)
    self.depositHooked = true
    return true
end

function Raider:ObserveOwnDepositRequest(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not self.bankOpen or not self:CanAccess() then return false end

    -- hooksecurefunc is a POST hook: DepositGuildBankMoney has already been invoked
    -- when we arrive here. The previous builds captured GetMoney()/bank money here
    -- and incorrectly treated those POST-deposit values as the "before" snapshot.
    -- Use the continuously cached values from before the API call instead.
    local cachedBankBefore = tonumber(self.lastBankBalance)
    local cachedPlayerBefore = tonumber(self.lastPlayerMoney)

    self.pendingOwnSerial = (tonumber(self.pendingOwnSerial) or 0) + 1
    local now = BJ:Now()
    local id = tostring(now) .. ":" .. tostring(self.pendingOwnSerial) .. ":" .. tostring(amount)
    self.pendingOwnDeposits[id] = {
        id = id,
        amount = amount,
        at = now,
        bankBefore = cachedBankBefore,
        playerBefore = cachedPlayerBefore,
    }
    self.lastOwnDepositDetected = now
    self.lastStatus = "Deposito di " .. self:FormatGold(amount) .. " rilevato. Conferma in corso..."

    -- Do not trust the POST hook timing itself, but use it to schedule redundant
    -- balance samples. Retail can deliver PLAYER_MONEY and GUILDBANK_UPDATE_MONEY
    -- in different orders; these polls make the local ledger independent from that
    -- ordering while ConfirmOwnDeposit still deduplicates by the pending/ledger ID.
    for _, delay in ipairs({ 0, 0.05, 0.20, 0.60, 1.20 }) do
        C_Timer.After(delay, function()
            if Raider.bankOpen then Raider:HandlePlayerMoneyChanged("DEPOSIT_POLL") end
        end)
    end
    self:ScheduleBankRefreshSequence("OWN_DEPOSIT")

    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
    return true
end

function Raider:HandlePlayerMoneyChanged(reason)
    local playerNow = GetMoney and tonumber(GetMoney()) or nil
    local previous = tonumber(self.playerMoneyEventBaseline)
    if playerNow then
        -- Keep both baselines coherent on every sample, even if no deposit happened.
        -- This prevents a stale snapshot from being reused by a later deposit.
        self.playerMoneyEventBaseline = playerNow
        self.lastPlayerMoney = playerNow
    end

    if not self.bankOpen or not self:CanAccess() or not playerNow or not previous then return false end
    local player = Normalize(BJ.player) or BJ.player
    if not self:IsRaider(player) then return false end

    local decrease = math.floor(previous - playerNow)
    self.lastPlayerMoneyDelta = decrease
    self.lastPlayerMoneyEventAt = BJ:Now()
    if decrease <= 0 then return false end

    -- PLAYER_MONEY is tied to the local character, so unlike a Guild Bank balance
    -- increase it cannot be caused by another guild member. While the Guild Bank
    -- frame is open this is our reliable local deposit signal. Match an expected
    -- amount captured by the Blizzard deposit API when possible; otherwise create
    -- a synthetic pending record so deposits are still recorded if the API hook
    -- was unavailable/load-on-demand.
    local pending, bestAt
    for _, candidate in pairs(self.pendingOwnDeposits) do
        local age = math.abs(BJ:Now() - (tonumber(candidate.at) or BJ:Now()))
        if not candidate.confirmed and tonumber(candidate.amount) == decrease and age <= 15 then
            local at = tonumber(candidate.at) or 0
            if not bestAt or at < bestAt then pending, bestAt = candidate, at end
        end
    end

    if not pending then
        self.pendingOwnSerial = (tonumber(self.pendingOwnSerial) or 0) + 1
        local now = BJ:Now()
        local id = "MONEY:" .. tostring(now) .. ":" .. tostring(self.pendingOwnSerial) .. ":" .. tostring(decrease)
        pending = { id = id, amount = decrease, at = now, playerBefore = previous }
        self.pendingOwnDeposits[id] = pending
    end

    self.lastOwnDepositDetected = BJ:Now()
    local ok = self:ConfirmOwnDeposit(pending, "PLAYER_MONEY_DELTA")
    -- Keep the generic snapshots coherent for diagnostics/fallback code, without
    -- ever using them as the primary detector again.
    self.lastPlayerMoney = playerNow
    self.lastBankBalance = GetGuildBankMoney and tonumber(GetGuildBankMoney()) or self.lastBankBalance
    return ok
end

function Raider:ConfirmOwnDeposit(pending, reason)
    if type(pending) ~= "table" or pending.confirmed then return false end
    local player = Normalize(BJ.player) or BJ.player
    if not self:IsRaider(player) then return false end

    -- Reuse an already imported bank row if the authoritative log won the race.
    local entry = self:FindSemanticLedgerMatch(player, player, pending.amount, pending.at or BJ:Now(),
        "BANK", self.ownConfirmUsed, 10 * 60)
    if not entry then
        local id = "BANKSELF:" .. tostring(player) .. ":" .. tostring(pending.id)
        entry = self:AddLedgerEntry(player, pending.amount, pending.at or BJ:Now(), "BANK", player,
            "Deposito personale Guild Bank", id, player, true, true)
    end
    if not entry then return false end
    self.ownConfirmUsed[entry.id] = true

    pending.confirmed = true
    self.pendingOwnDeposits[pending.id] = nil
    self.lastOwnDepositConfirmed = BJ:Now()
    self.lastImportedAt = BJ:Now()
    self.lastStatus = "Deposito personale registrato: " .. self:FormatGold(pending.amount) .. "."

    -- Persist locally first, then announce to the guild. Online admins receive it
    -- immediately; any other Blackjack client can cache it and relay it later.
    self:StoreDepositReceipt(entry.id, player, player, entry.amount, entry.time, player, true)
    self:BroadcastDepositReceipt(entry)
    if self:CanManage() then self:SendPersonalSummary(player) end

    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
    return true
end

function Raider:ConfirmPendingOwnDeposits(reason)
    if not self.bankOpen then return false end
    local now = BJ:Now()
    local bankNow = GetGuildBankMoney and tonumber(GetGuildBankMoney()) or nil
    local playerNow = GetMoney and tonumber(GetMoney()) or nil
    local previousBank = tonumber(self.lastBankBalance)
    local previousPlayer = tonumber(self.lastPlayerMoney)
    local confirmedAny = false

    -- These deltas compare against the last event snapshot, which is the actual
    -- pre-deposit value even though DepositGuildBankMoney is observed post-call.
    local bankDelta = (bankNow and previousBank) and math.max(0, bankNow - previousBank) or 0
    local playerDelta = (playerNow and previousPlayer) and math.max(0, previousPlayer - playerNow) or 0
    local eventEvidence = math.max(bankDelta, playerDelta)

    local list = {}
    for _, pending in pairs(self.pendingOwnDeposits) do list[#list + 1] = pending end
    table.sort(list, function(a, b) return (tonumber(a.at) or 0) < (tonumber(b.at) or 0) end)

    for _, pending in ipairs(list) do
        if now - (tonumber(pending.at) or now) > 45 then
            self.pendingOwnDeposits[pending.id] = nil
        else
            local bankConfirmed = bankNow and pending.bankBefore and bankNow >= pending.bankBefore + pending.amount
            local playerConfirmed = playerNow and pending.playerBefore and playerNow <= pending.playerBefore - pending.amount
            local deltaConfirmed = eventEvidence >= pending.amount
            if bankConfirmed or playerConfirmed or deltaConfirmed then
                if self:ConfirmOwnDeposit(pending, reason) then
                    confirmedAny = true
                    eventEvidence = math.max(0, eventEvidence - pending.amount)
                end
            end
        end
    end

    self.lastBankBalance = bankNow or self.lastBankBalance
    self.lastPlayerMoney = playerNow or self.lastPlayerMoney
    return confirmedAny
end


function Raider:GetEligibleMembers(includeInactive)
    local list = {}
    if not BJ.Guild or not BJ.Guild.members then return list end
    for name, info in pairs(BJ.Guild.members) do
        if self:IsEligible(name) and (includeInactive or self:IsRaider(name)) then
            list[#list + 1] = {
                name = name,
                rankName = info.rankName or "-",
                rankIndex = info.rankIndex,
                active = self:IsRaider(name),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.active ~= b.active then return a.active end
        local ai, bi = tonumber(a.rankIndex) or 99, tonumber(b.rankIndex) or 99
        if ai ~= bi then return ai < bi end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

function Raider:SetFlag(name, enabled, remoteUpdated, remoteOfficer, suppressBroadcast)
    if not suppressBroadcast and not self:CanManage() then return false, "Solo Casinò Royale e Pit Boss possono cambiare la flag Raider." end
    name = Normalize(name)
    if not name or not self:IsFlagRank(name) then return false, "Questo grado non usa la flag Raider." end
    local s = self:GetStore()
    local updated = tonumber(remoteUpdated) or BJ:Now()
    if updated < (tonumber(s.flagUpdated[name]) or 0) then return false end
    s.flags[name] = enabled and true or false
    s.flagUpdated[name] = updated
    s.revision = math.max(s.revision or 0, updated)
    self:ReconcileUnassigned()
    self:NotifyChanged(name)
    if not suppressBroadcast then
        self:SendToAdmins("RFLAG", name, enabled and 1 or 0, updated, remoteOfficer or BJ.player)
        self:SendPersonalSummary(name)
    end
    return true
end

function Raider:SetAltMapping(altName, mainName, remoteUpdated, remoteOfficer, suppressBroadcast)
    if not suppressBroadcast and not self:CanManage() then return false, "Solo Casinò Royale e Pit Boss possono gestire gli alt." end
    altName = Normalize(altName)
    mainName = mainName and Normalize(mainName) or nil
    if not altName then return false, "Nome alt non valido." end
    if mainName and not self:IsEligible(mainName) then return false, "Il main deve avere un grado Raider compatibile." end
    local s = self:GetStore()
    local updated = tonumber(remoteUpdated) or BJ:Now()
    if updated < (tonumber(s.altMapUpdated[altName]) or 0) then return false end
    if mainName and mainName ~= altName then s.altMap[altName] = mainName else s.altMap[altName] = nil end
    s.altMapUpdated[altName] = updated
    s.revision = math.max(s.revision or 0, updated)
    self:ReconcileUnassigned()
    self:NotifyChanged(mainName)
    if not suppressBroadcast then
        self:SendToAdmins("RALT", altName, mainName or "-", updated, remoteOfficer or BJ.player)
        if mainName then self:SendPersonalSummary(mainName) end
    end
    return true
end

function Raider:GetMappedMain(name)
    name = Normalize(name)
    if not name then return nil end
    local mapped = self:GetStore().altMap[name]
    if mapped then return Normalize(mapped) or mapped end
    if self:IsRaider(name) then return name end
    return nil
end

function Raider:GetAltsFor(mainName)
    mainName = Normalize(mainName)
    local result = {}
    for alt, main in pairs(self:GetStore().altMap) do
        if Normalize(main) == mainName then result[#result + 1] = alt end
    end
    table.sort(result)
    return result
end

function Raider:SetExempt(name, year, month, enabled, remoteUpdated, remoteOfficer, suppressBroadcast)
    if not suppressBroadcast and not self:CanManage() then return false, "Solo Casinò Royale e Pit Boss possono impostare esenzioni." end
    name = Normalize(name)
    year, month = tonumber(year), tonumber(month)
    if not name or not year or not month or month < 1 or month > 12 then return false end
    if MonthIndex(year, month) < MonthIndex(self.START_YEAR, self.START_MONTH) then return false, "Mese precedente all'inizio del contributo." end
    local s = self:GetStore()
    local id = name .. "#" .. MonthKey(year, month)
    local updated = tonumber(remoteUpdated) or BJ:Now()
    if updated < (tonumber(s.exemptionUpdated[id]) or 0) then return false end
    s.exemptions[id] = enabled and true or nil
    s.exemptionUpdated[id] = updated
    s.revision = math.max(s.revision or 0, updated)
    self:NotifyChanged(name)
    if not suppressBroadcast then
        self:SendToAdmins("REXM", name, year, month, enabled and 1 or 0, updated, remoteOfficer or BJ.player)
        self:SendPersonalSummary(name)
    end
    return true
end

function Raider:IsExempt(name, year, month)
    name = Normalize(name)
    if not name then return false end
    return self:GetStore().exemptions[name .. "#" .. MonthKey(year, month)] == true
end

function Raider:FindSemanticLedgerMatch(owner, actor, amount, timestamp, source, used, maxDiff)
    if source ~= "BANK" then return nil end
    owner, actor = Normalize(owner), Normalize(actor)
    timestamp = tonumber(timestamp) or 0
    amount = tonumber(amount) or 0
    maxDiff = tonumber(maxDiff) or (2 * 60 * 60)
    local best, bestDiff
    for id, entry in pairs(self:GetStore().ledger) do
        if not (used and used[id]) and entry.source == "BANK"
            and Normalize(entry.player) == owner
            and Normalize(entry.actor) == actor
            and tonumber(entry.amount) == amount then
            local diff = math.abs((tonumber(entry.time) or 0) - timestamp)
            if diff <= maxDiff and (not bestDiff or diff < bestDiff) then
                best, bestDiff = entry, diff
            end
        end
    end
    return best
end

function Raider:AddLedgerEntry(player, amount, timestamp, source, actor, note, id, officer, suppressBroadcast, skipSemantic)
    player = Normalize(player)
    actor = Normalize(actor or player)
    amount = math.floor(tonumber(amount) or 0)
    timestamp = tonumber(timestamp) or BJ:Now()
    source = source or "MANUAL"
    if not player or amount == 0 then return nil, "Movimento non valido." end
    local s = self:GetStore()

    id = tostring(id or (source .. ":" .. tostring(BJ:Now()) .. ":" .. tostring(math.random(100000, 999999))))
    if s.ledger[id] then return s.ledger[id], "DUPLICATE" end

    -- New v3.0.3 bank IDs are deterministic and contain '~'. Trust the ID so
    -- two legitimate deposits of the same amount in the same hour stay distinct.
    -- Semantic matching remains only as a compatibility guard for legacy random IDs.
    if source == "BANK" and not skipSemantic and not id:find("~", 1, true) then
        local duplicate = self:FindSemanticLedgerMatch(player, actor, amount, timestamp, source)
        if duplicate then return duplicate, "DUPLICATE" end
    end
    local entry = {
        id = id,
        player = player,
        actor = actor or player,
        amount = amount,
        time = timestamp,
        source = source,
        officer = Normalize(officer or BJ.player) or officer or BJ.player,
        note = BJ:Utf8Truncate(note or "", 90),
        createdAt = BJ:Now(),
    }
    s.ledger[id] = entry
    s.revision = math.max(tonumber(s.revision) or 0, tonumber(entry.createdAt) or BJ:Now())
    self:NotifyChanged(player)
    if not suppressBroadcast and self:CanManage() then
        self:SendToAdmins("RLED", entry.id, entry.player, entry.actor or "-", entry.amount, entry.time, entry.source, entry.officer or BJ.player)
        self:SendPersonalSummary(player)
    end
    return entry
end

function Raider:AddManualAdjustment(player, gold, note)
    if not self:CanManage() then return false, "Solo Casinò Royale e Pit Boss possono inserire rettifiche." end
    player = Normalize(player)
    local amountGold = tonumber(gold)
    if not player or not amountGold or amountGold == 0 then return false, "Inserisci un importo gold valido, positivo o negativo." end
    local rawCopper = amountGold * 10000
    local amountCopper
    if rawCopper >= 0 then
        amountCopper = math.floor(rawCopper + 0.5)
    else
        -- floor(x - .5) is wrong for negative values (e.g. -1000g became
        -- -10,000,001 copper). Round away from the fractional part with ceil.
        amountCopper = math.ceil(rawCopper - 0.5)
    end
    local entry, err = self:AddLedgerEntry(player, amountCopper, BJ:Now(), "MANUAL", BJ.player, note, nil, BJ.player, false)
    if not entry then return false, err end
    self.lastStatus = "Rettifica registrata per " .. BJ:ShortName(player) .. ": " .. tostring(amountGold) .. "g."
    return true
end

function Raider:GetLedgerFor(player)
    player = Normalize(player)
    local list = {}
    for _, entry in pairs(self:GetStore().ledger) do
        if Normalize(entry.player) == player then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        local at, bt = tonumber(a.time) or 0, tonumber(b.time) or 0
        if at ~= bt then return at < bt end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

function Raider:GetContributionTotal(player)
    player = Normalize(player)
    local total, lastAmount, lastTime = 0, 0, 0
    local hasLedger = false
    for _, entry in pairs(self:GetStore().ledger) do
        if Normalize(entry.player) == player then
            hasLedger = true
            total = total + (tonumber(entry.amount) or 0)
            local et = tonumber(entry.time) or 0
            if et > lastTime and (tonumber(entry.amount) or 0) > 0 then
                lastTime, lastAmount = et, tonumber(entry.amount) or 0
            end
        end
    end
    if not hasLedger and player == BJ.player and not self:CanManage() then
        local personal = self:GetStore().personal[player]
        if personal then
            total = tonumber(personal.total) or 0
            lastAmount = tonumber(personal.lastAmount) or 0
            lastTime = tonumber(personal.lastTime) or 0
        end
    end
    return math.max(0, total), lastAmount, lastTime
end

function Raider:GetEffectiveExemptions(player)
    player = Normalize(player)
    local result = {}
    local s = self:GetStore()
    local prefix = tostring(player or "") .. "#"
    for id, enabled in pairs(s.exemptions) do
        if enabled and id:sub(1, #prefix) == prefix then result[id:sub(#prefix + 1)] = true end
    end
    if player == BJ.player and not self:CanManage() and next(result) == nil then
        local personal = s.personal[player]
        if personal and personal.exemptions then
            for key, enabled in pairs(personal.exemptions) do if enabled then result[key] = true end end
        end
    end
    return result
end

function Raider:BuildAllocation(player, throughYear)
    player = Normalize(player)
    throughYear = tonumber(throughYear) or self.START_YEAR
    local total = self:GetContributionTotal(player)
    local remaining = total
    local result = {}
    if not self:IsRaider(player) then
        for year = self.START_YEAR, throughYear do
            for month = 1, 12 do
                result[MonthKey(year, month)] = { active = false, due = 0, paid = 0, exempt = false }
            end
        end
        return result, remaining, total
    end
    local exempt = self:GetEffectiveExemptions(player)
    for year = self.START_YEAR, throughYear do
        for month = 1, 12 do
            local key = MonthKey(year, month)
            if MonthIndex(year, month) < MonthIndex(self.START_YEAR, self.START_MONTH) then
                result[key] = { active = false, due = 0, paid = 0, exempt = false }
            elseif exempt[key] then
                result[key] = { active = true, due = 0, paid = 0, exempt = true }
            else
                local paid = math.min(self.MONTHLY_COPPER, math.max(0, remaining))
                remaining = math.max(0, remaining - paid)
                result[key] = { active = true, due = self.MONTHLY_COPPER, paid = paid, exempt = false }
            end
        end
    end
    return result, remaining, total
end

function Raider:GetYearState(player, year)
    year = tonumber(year) or self.START_YEAR
    local allocation, credit, total = self:BuildAllocation(player, year)
    local months = {}
    local yearPaid, yearDue = 0, 0
    for month = 1, 12 do
        local state = allocation[MonthKey(year, month)] or { active = false, due = 0, paid = 0 }
        state.year, state.month = year, month
        months[month] = state
        yearPaid = yearPaid + (tonumber(state.paid) or 0)
        yearDue = yearDue + (tonumber(state.due) or 0)
    end
    return months, yearPaid, yearDue, credit, total
end

function Raider:GetCurrentDate()
    local d = date("*t", BJ:Now()) or {}
    return tonumber(d.year) or self.START_YEAR, tonumber(d.month) or self.START_MONTH
end

function Raider:IsPaidAmount(paid, due)
    paid = math.floor(tonumber(paid) or 0)
    due = math.floor(tonumber(due) or 0)
    if due <= 0 then return true end
    -- Copper values are integers. The one-copper tolerance exists only to avoid
    -- legacy v3.0.0-v3.0.5 negative-adjustment contamination before migration.
    return paid + 1 >= due
end

function Raider:GetStatus(player)
    player = Normalize(player)
    if not self:IsRaider(player) then return "INACTIVE", 0, nil end

    local currentYear, currentMonth = self:GetCurrentDate()
    if MonthIndex(currentYear, currentMonth) < MonthIndex(self.START_YEAR, self.START_MONTH) then
        return "IN REGOLA", 0, nil
    end

    -- The summary badge describes the CURRENT month only. Older/future months
    -- remain visible in the 12 bars but must not turn today's status partial.
    local allocation = self:BuildAllocation(player, currentYear)
    local st = allocation[MonthKey(currentYear, currentMonth)]
    if not st or not st.active or st.exempt or self:IsPaidAmount(st.paid, st.due) then
        return "IN REGOLA", 0, nil
    end

    local paid = tonumber(st.paid) or 0
    local due = tonumber(st.due) or self.MONTHLY_COPPER
    local missing = math.max(0, due - paid)
    local current = { year = currentYear, month = currentMonth, missing = missing, paid = paid }
    if paid > 0 then return "PARZIALE", missing, current end
    return "DA PAGARE", missing, current
end

function Raider:GetOverallStats()
    local stats = { active = 0, ok = 0, partial = 0, overdue = 0, inactive = 0 }
    for _, member in ipairs(self:GetEligibleMembers(true)) do
        if member.active then
            stats.active = stats.active + 1
            local status = self:GetStatus(member.name)
            if status == "IN REGOLA" then stats.ok = stats.ok + 1
            elseif status == "PARZIALE" or status == "DA PAGARE" then stats.partial = stats.partial + 1
            else stats.overdue = stats.overdue + 1 end
        else
            stats.inactive = stats.inactive + 1
        end
    end
    return stats
end

function Raider:ResolveBankOwner(actor)
    actor = Normalize(actor)
    if not actor then return nil end
    local mapped = self:GetStore().altMap[actor]
    if mapped then return Normalize(mapped) or mapped end
    if self:IsRaider(actor) then return actor end
    return nil
end

local function BankAgeBucket(years, months, days, hours)
    years, months, days, hours = tonumber(years) or 0, tonumber(months) or 0, tonumber(days) or 0, tonumber(hours) or 0
    local now = BJ:Now()
    if years > 0 then return "Y" .. tostring(math.floor(now / (365 * 86400)) - years) end
    if months > 0 then return "M" .. tostring(math.floor(now / (30 * 86400)) - months) end
    if days > 0 then return "D" .. tostring(math.floor(now / 86400) - days) end
    return "H" .. tostring(math.floor(now / 3600) - hours)
end

local function BankFingerprintBase(actor, amount, years, months, days, hours)
    return tostring(Normalize(actor) or actor or "?") .. "~" .. tostring(math.floor(tonumber(amount) or 0)) .. "~" .. BankAgeBucket(years, months, days, hours)
end

function Raider:PruneBankSeen()
    local seen = self:GetStore().bankSeen
    local cutoff = BJ:Now() - (120 * 86400)
    for key, info in pairs(seen) do
        local seenAt = type(info) == "table" and tonumber(info.seenAt) or tonumber(info)
        if seenAt and seenAt < cutoff then seen[key] = nil end
    end
end

function Raider:FindUnassignedMatch(actor, amount, timestamp, used)
    actor = Normalize(actor)
    local best, bestDiff
    for id, entry in pairs(self:GetStore().unassigned) do
        if not (used and used[id]) and Normalize(entry.actor) == actor and tonumber(entry.amount) == tonumber(amount) then
            local diff = math.abs((tonumber(entry.time) or 0) - (tonumber(timestamp) or 0))
            if diff <= 90 * 60 and (not bestDiff or diff < bestDiff) then best, bestDiff = entry, diff end
        end
    end
    return best
end

function Raider:ReconcileUnassigned()
    local s = self:GetStore()
    local moved = 0
    for id, entry in pairs(s.unassigned) do
        local owner = self:ResolveBankOwner(entry.actor)
        if owner then
            local added = self:AddLedgerEntry(owner, entry.amount, entry.time, "BANK", entry.actor, "", "BANK:" .. id, BJ.player, false)
            if added then
                s.unassigned[id] = nil
                moved = moved + 1
            end
        end
    end
    return moved
end


function Raider:StartBankPolling()
    if not self.bankOpen or not self:CanAccess() then return false end
    if self.bankPolling then return true end
    self.bankPolling = true
    self.bankPollSerial = (tonumber(self.bankPollSerial) or 0) + 1
    local serial = self.bankPollSerial

    local function Poll()
        if serial ~= Raider.bankPollSerial then return end
        if not Raider.bankOpen or not Raider:CanAccess() then
            Raider.bankPolling = false
            return
        end
        Raider.lastBankPollAt = BJ:Now()
        Raider:QueryBankLog("POLL")
        C_Timer.After(5.0, Poll)
    end

    -- Opening the bank already schedules two quick reads. Start the steady poll
    -- afterwards so we do not hammer the server during the initial UI load.
    C_Timer.After(2.5, Poll)
    return true
end

function Raider:StopBankPolling()
    self.bankPolling = false
    self.bankPollSerial = (tonumber(self.bankPollSerial) or 0) + 1
end

function Raider:ScheduleBankLogScan(reason, delay)
    if not self.bankOpen or not self:CanAccess() then return false end
    self.bankLogScanSerial = (tonumber(self.bankLogScanSerial) or 0) + 1
    local serial = self.bankLogScanSerial
    delay = math.max(0.10, tonumber(delay) or 0.50)
    C_Timer.After(delay, function()
        if serial ~= Raider.bankLogScanSerial then return end
        if not Raider.bankOpen or not Raider:CanAccess() then return end
        Raider:ScanBankLog(reason)
    end)
    return true
end

function Raider:ScheduleBankRefreshSequence(reason)
    if not self.bankOpen or not self:CanAccess() then return false end
    self.bankRefreshSequence = (tonumber(self.bankRefreshSequence) or 0) + 1
    local serial = self.bankRefreshSequence
    local delays = { 0.60, 2.20, 5.20, 8.50 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            if serial ~= Raider.bankRefreshSequence then return end
            if not Raider.bankOpen or not Raider:CanAccess() then return end
            Raider:QueryBankLog((reason or "REFRESH") .. "_" .. tostring(delay))
        end)
    end
    return true
end

function Raider:ScheduleBankRefresh(reason, delay)
    if not self.bankOpen or not self:CanAccess() then return false end
    self.bankRefreshSerial = (tonumber(self.bankRefreshSerial) or 0) + 1
    local serial = self.bankRefreshSerial
    delay = math.max(0, tonumber(delay) or 0.35)
    C_Timer.After(delay, function()
        if serial ~= Raider.bankRefreshSerial then return end
        if not Raider.bankOpen or not Raider:CanAccess() then return end
        Raider:QueryBankLog(reason)
    end)
    return true
end

function Raider:QueryBankLog(reason)
    if not self.bankOpen then return false, "Apri la banca di gilda." end
    if not self:CanAccess() then return false, "Il registro Raider è disponibile solo ai Raider autorizzati." end
    if not QueryGuildBankLog then return false, "API registro banca non disponibile." end
    local now = BJ:Now()
    -- Avoid hammering the server when several bank-money events arrive together.
    if now - (tonumber(self.lastBankQueryAt) or 0) < 1 then
        return false, "Registro banca in attesa del prossimo refresh."
    end
    self.lastBankQueryAt = now
    local moneyLogTab = (MAX_GUILDBANK_TABS or 8) + 1
    QueryGuildBankLog(moneyLogTab)
    self.lastStatus = "Registro gold richiesto" .. (reason and (" [" .. tostring(reason) .. "]") or "") .. ". In attesa dei movimenti banca..."
    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
    return true
end

function Raider:ScanBankLog(reason)
    if not self.bankOpen or not self:CanAccess() then return false end
    if not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then return false end

    local count = tonumber(GetNumGuildBankMoneyTransactions()) or 0
    self.lastMoneyLogCount = count
    if count <= 0 then
        self.lastBankDeposits, self.lastBankMatched, self.lastBankImported, self.lastBankUnassigned = 0, 0, 0, 0
        self.lastBankIncomplete = 0
        self.lastStatus = "Registro gold vuoto o non ancora caricato."
        if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
        return false
    end

    local s = self:GetStore()
    self:PruneBankSeen()
    local matchedLedger, matchedUnassigned, matchedReceipts = {}, {}, {}
    local occurrences = {}
    local imported, pending, matched, deposits, incomplete = 0, 0, 0, 0, 0
    local fullScan = self:CanManage()
    local selfName = Normalize(BJ.player) or BJ.player

    -- The money log has no stable transaction ID. Scan the currently returned
    -- snapshot and bind each row one-to-one to an existing ledger row whenever
    -- possible. Admins process every Raider; normal Raiders process only themselves.
    for i = count, 1, -1 do
        local transactionType, actor, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
        amount = math.floor(tonumber(amount) or 0)
        actor = actor and Normalize(actor) or nil
        if transactionType and not actor then incomplete = incomplete + 1 end

        if transactionType == "deposit" and actor and amount > 0 and (fullScan or actor == selfName) then
            deposits = deposits + 1
            local txTime = ApproxTransactionTime(years, months, days, hours)
            if IsAfterStart(txTime) then
                local base = BankFingerprintBase(actor, amount, years, months, days, hours)
                occurrences[base] = (occurrences[base] or 0) + 1
                local fingerprint = base .. "#" .. tostring(occurrences[base])
                local seenInfo = s.bankSeen[fingerprint]
                local owner
                if fullScan then
                    owner = self:ResolveBankOwner(actor)
                elseif actor == selfName and self:IsRaider(selfName) then
                    owner = selfName
                end

                if seenInfo then
                    matched = matched + 1
                    if type(seenInfo) == "table" then
                        seenInfo.seenAt = BJ:Now()
                        if seenInfo.ledgerId then matchedLedger[seenInfo.ledgerId] = true end
                        if seenInfo.unassignedId then matchedUnassigned[seenInfo.unassignedId] = true end
                    end
                elseif owner then
                    -- First bind the authoritative bank row to a cached self-report
                    -- if one exists. This is what turns store-and-forward receipts
                    -- into verified ledger movements for an admin who was offline.
                    local receipt = self:FindDepositReceiptMatch(owner, actor, amount, txTime, matchedReceipts)
                    local existing = self:FindSemanticLedgerMatch(owner, actor, amount, txTime, "BANK", matchedLedger, 2 * 60 * 60)
                    if existing then
                        matchedLedger[existing.id] = true
                        s.bankSeen[fingerprint] = { seenAt = BJ:Now(), ledgerId = existing.id, actor = actor, amount = amount }
                        if receipt then
                            receipt.verified = true
                            receipt.verifiedAt = BJ:Now()
                            matchedReceipts[receipt.id] = true
                        end
                        matched = matched + 1
                    else
                        local id = receipt and receipt.id or ("BANK:" .. fingerprint)
                        local entry = self:AddLedgerEntry(owner, amount, txTime, "BANK", actor,
                            receipt and "Confermato dal money log" or "", id, BJ.player, not fullScan, true)
                        if entry then
                            matchedLedger[entry.id] = true
                            s.bankSeen[fingerprint] = { seenAt = BJ:Now(), ledgerId = entry.id, actor = actor, amount = amount }
                            if receipt then
                                receipt.verified = true
                                receipt.verifiedAt = BJ:Now()
                                matchedReceipts[receipt.id] = true
                            end
                            imported = imported + 1
                            self.lastImportedAt = BJ:Now()
                            if not fullScan then
                                self:BroadcastDepositReceipt(entry)
                            end
                        end
                    end
                elseif fullScan then
                    local existing = self:FindUnassignedMatch(actor, amount, txTime, matchedUnassigned)
                    if existing then
                        matchedUnassigned[existing.id] = true
                        s.bankSeen[fingerprint] = { seenAt = BJ:Now(), unassignedId = existing.id, actor = actor, amount = amount }
                        matched = matched + 1
                    else
                        local id = "UNASSIGNED:" .. fingerprint
                        s.unassigned[id] = { id = id, actor = actor, amount = amount, time = txTime, seenAt = BJ:Now() }
                        s.bankSeen[fingerprint] = { seenAt = BJ:Now(), unassignedId = id, actor = actor, amount = amount }
                        matchedUnassigned[id] = true
                        pending = pending + 1
                    end
                end
            end
        end
    end

    if fullScan then self:ReconcileUnassigned() end
    self.lastBankScan = BJ:Now()
    s.lastBankScan = self.lastBankScan
    self.lastBankDeposits = deposits
    self.lastBankMatched = matched
    self.lastBankImported = imported
    self.lastBankUnassigned = pending
    self.lastBankIncomplete = incomplete

    if imported > 0 then
        self.lastStatus = "Registro Raider aggiornato: " .. imported .. " nuovo/i deposito/i importato/i."
    elseif pending > 0 then
        self.lastStatus = "Verifica completata. Alcuni depositi richiedono un mapping alt -> main."
    elseif incomplete > 0 then
        self.lastStatus = "Registro gold ricevuto parzialmente (" .. incomplete .. " riga/e senza giocatore). Riprovo automaticamente."
    else
        self.lastStatus = "Verifica completata: nessun nuovo deposito Raider"
            .. (reason and (" [" .. tostring(reason) .. "]") or "") .. "."
    end
    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
    return true
end

function Raider:GetUnassigned()
    local list = {}
    for _, entry in pairs(self:GetStore().unassigned) do list[#list + 1] = entry end
    table.sort(list, function(a, b) return (tonumber(a.time) or 0) > (tonumber(b.time) or 0) end)
    return list
end

function Raider:NotifyChanged(player)
    if BJ.UI then
        BJ.UI:RefreshPage("RAIDER")
        if BJ.UI.RefreshNavAccess then BJ.UI:RefreshNavAccess() end
    end
end

function Raider:SendToAdmins(kind, ...)
    if not BJ.Comms or not IsInGuild() then return end
    for _, member in ipairs(self:GetEligibleMembers(true)) do
        if self:IsAdminRank(member.name) and member.name ~= BJ.player then
            BJ.Comms:SendSystem(kind, "WHISPER", member.name, ...)
        end
    end
end

function Raider:SendPersonalSummary(player)
    if not self:CanManage() or not BJ.Comms then return false end
    player = Normalize(player)
    if not player then return false end
    local total, lastAmount, lastTime = self:GetContributionTotal(player)
    local active = self:IsRaider(player) and 1 or 0
    local csv = ExemptCSV(self:GetStore().exemptions, player)
    BJ.Comms:SendSystem("RSUM", "WHISPER", player, player, total, lastAmount, lastTime, active, self:GetStore().revision or BJ:Now(), csv)
    return true
end

function Raider:BroadcastAdminState(target)
    if not self:CanManage() or not BJ.Comms or not target then return end
    target = Normalize(target) or target
    local s = self:GetStore()
    for name, enabled in pairs(s.flags) do
        BJ.Comms:SendSystem("RFLAG", "WHISPER", target, name, enabled and 1 or 0, s.flagUpdated[name] or 0, BJ.player)
    end
    for alt, main in pairs(s.altMap) do
        BJ.Comms:SendSystem("RALT", "WHISPER", target, alt, main or "-", s.altMapUpdated[alt] or 0, BJ.player)
    end
    for id, enabled in pairs(s.exemptions) do
        if enabled then
            local player, key = id:match("^(.-)#(%d%d%d%d%-%d%d)$")
            local year, month = key and key:match("^(%d%d%d%d)%-(%d%d)$")
            if player and year then
                BJ.Comms:SendSystem("REXM", "WHISPER", target, player, year, month, 1, s.exemptionUpdated[id] or 0, BJ.player)
            end
        end
    end
    for _, entry in pairs(s.ledger) do
        BJ.Comms:SendSystem("RLED", "WHISPER", target, entry.id, entry.player, entry.actor or "-", entry.amount, entry.time, entry.source or "SYNC", entry.officer or BJ.player)
    end
end

function Raider:RequestState(force)
    if not BJ.Comms or not IsInGuild() then return false end
    local now = BJ:Now()
    if not force and now - (tonumber(self.lastStateRequestAt) or 0) < 8 then return false end
    self.lastStateRequestAt = now
    BJ.Comms:SendSystem("RREQ", "GUILD", nil)
    return true
end

function Raider:HandleStateRequest(sender)
    sender = Normalize(sender) or sender

    -- Every Blackjack client acts as a small store-and-forward cache for verified
    -- self-reported deposits. This lets an admin who was offline recover receipts
    -- from peers when they later log in. The Guild Bank money log remains the
    -- authoritative server-side verification whenever it is available.
    if self:IsAdminRank(sender) then
        C_Timer.After(0.10 + math.random() * 0.60, function() Raider:ForwardDepositReceipts(sender) end)
    end

    if not self:CanManage() then return end
    if self:IsAdminRank(sender) then
        C_Timer.After(0.15 + math.random() * 0.5, function() Raider:BroadcastAdminState(sender) end)
    elseif self:IsEligible(sender) then
        C_Timer.After(0.15 + math.random() * 0.5, function() Raider:SendPersonalSummary(sender) end)
    end
end

function Raider:HandlePersonalSummary(sender, fields)
    if not self:IsAdminRank(sender) then return end
    local target = Normalize(fields[3]) or fields[3]
    if target ~= BJ.player then return end
    local s = self:GetStore()
    local revision = tonumber(fields[8]) or 0
    local current = s.personal[BJ.player]
    if current and revision < (tonumber(current.revision) or 0) then return end
    s.personal[BJ.player] = {
        total = tonumber(fields[4]) or 0,
        lastAmount = tonumber(fields[5]) or 0,
        lastTime = tonumber(fields[6]) or 0,
        active = tonumber(fields[7]) == 1,
        revision = revision,
        exemptions = ParseExemptCSV(fields[9]),
        receivedAt = BJ:Now(),
    }
    if self:IsFlagRank(BJ.player) then
        s.flags[BJ.player] = tonumber(fields[7]) == 1
        s.flagUpdated[BJ.player] = math.max(tonumber(s.flagUpdated[BJ.player]) or 0, revision)
    end
    self:NotifyChanged(BJ.player)
end

function Raider:HandleRemoteFlag(sender, name, enabled, updated, officer)
    if not self:IsAdminRank(sender) then return end
    self:SetFlag(name, tonumber(enabled) == 1, updated, officer or sender, true)
end

function Raider:HandleRemoteAlt(sender, alt, main, updated, officer)
    if not self:IsAdminRank(sender) then return end
    self:SetAltMapping(alt, main ~= "-" and main or nil, updated, officer or sender, true)
end

function Raider:HandleRemoteExempt(sender, name, year, month, enabled, updated, officer)
    if not self:IsAdminRank(sender) then return end
    self:SetExempt(name, year, month, tonumber(enabled) == 1, updated, officer or sender, true)
end

function Raider:HandleObservedDeposit(sender, fields)
    sender = Normalize(sender) or sender
    local id = fields[3]
    local player = Normalize(fields[4]) or fields[4]
    local actor = Normalize(fields[5]) or fields[5]
    local amount = tonumber(fields[6]) or 0
    local timestamp = tonumber(fields[7]) or BJ:Now()
    if not id or amount <= 0 or not player or not actor then return end

    -- Only accept a direct self-report from the character that actually sent the
    -- addon message. Other guild clients may cache this receipt, but cannot invent
    -- a deposit on behalf of another Raider through this message type.
    if sender ~= player or sender ~= actor then return end
    self:StoreDepositReceipt(id, player, actor, amount, timestamp, sender, false)

    if self:CanManage() and self:IsRaider(sender) then
        local entry = self:AddLedgerEntry(player, amount, timestamp, "BANK", actor,
            "Deposito segnalato dal client del Raider", id, sender, true, true)
        if entry then
            self.lastStatus = "Deposito ricevuto da " .. BJ:ShortName(sender) .. ": " .. self:FormatGold(amount)
                .. ". In attesa/verifica con il money log."
            self:SendPersonalSummary(player)
        end
    end
    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
end

function Raider:HandleRelayedDeposit(sender, fields)
    sender = Normalize(sender) or sender
    if not self:CanManage() then return end

    local id = fields[3]
    local origin = Normalize(fields[4]) or fields[4]
    local player = Normalize(fields[5]) or fields[5]
    local actor = Normalize(fields[6]) or fields[6]
    local amount = tonumber(fields[7]) or 0
    local timestamp = tonumber(fields[8]) or BJ:Now()
    if not id or amount <= 0 or not origin or not player or not actor then return end
    if origin ~= player or origin ~= actor then return end

    -- A third-party relay is useful for persistence but is not authoritative by
    -- itself: keep it as a pending receipt until the bank log confirms it. If the
    -- original Raider is the sender, it is equivalent to a direct self-report.
    self:StoreDepositReceipt(id, player, actor, amount, timestamp, origin, false, sender)
    if sender == origin and self:IsRaider(origin) then
        local entry = self:AddLedgerEntry(player, amount, timestamp, "BANK", actor,
            "Deposito risincronizzato dal Raider", id, origin, true, true)
        if entry then self:SendPersonalSummary(player) end
    end
    self.lastStatus = "Ricevuta Raider recuperata: " .. BJ:ShortName(origin) .. " " .. self:FormatGold(amount)
        .. (sender == origin and "." or " (da verificare con la banca).")
    if BJ.UI then BJ.UI:RefreshPage("RAIDER") end
end

function Raider:HandleRemoteLedger(sender, fields)
    if not self:IsAdminRank(sender) or not self:CanManage() then return end
    local id = fields[3]
    local player = fields[4]
    local actor = fields[5] ~= "-" and fields[5] or player
    local amount = tonumber(fields[6]) or 0
    local timestamp = tonumber(fields[7]) or BJ:Now()
    local source = fields[8] or "SYNC"
    local officer = fields[9] or sender
    if not id or amount == 0 then return end
    self:AddLedgerEntry(player, amount, timestamp, source, actor, "", id, officer, true)
end

function Raider:FormatGold(copper)
    local gold = math.floor((tonumber(copper) or 0) / 10000 + 0.5)
    local sign = gold < 0 and "-" or ""
    gold = math.abs(gold)
    local s = tostring(gold)
    while true do
        local replaced, n = s:gsub("^(%d+)(%d%d%d)", "%1.%2")
        s = replaced
        if n == 0 then break end
    end
    return sign .. s .. "g"
end

function Raider:GetMonthLabel(month)
    return MONTHS[tonumber(month) or 1] or "?"
end

function Raider:PrintDiagnostics()
    local s = self:GetStore()
    local total = self:GetContributionTotal(BJ.player)
    BJ:Print("RAIDER v" .. BJ.version .. " access=" .. tostring(self:CanAccess()) .. " admin=" .. tostring(self:CanManage()) .. " rank=" .. tostring(self:GetRankInfo(BJ.player) or "?"))
    BJ:Print("Totale personale=" .. self:FormatGold(total) .. " | ledger=" .. tostring(BJ:CountTable(s.ledger)) .. " unassigned=" .. tostring(BJ:CountTable(s.unassigned)) .. " flag=" .. tostring(s.flags[BJ.player]) .. " bankOpen=" .. tostring(self.bankOpen))
    BJ:Print("MoneyLog=" .. tostring(self.lastMoneyLogCount or 0) .. " depositi=" .. tostring(self.lastBankDeposits or 0) .. " matched=" .. tostring(self.lastBankMatched or 0) .. " importati=" .. tostring(self.lastBankImported or 0) .. " nonAttribuiti=" .. tostring(self.lastBankUnassigned or 0) .. " incomplete=" .. tostring(self.lastBankIncomplete or 0) .. " pendingSelf=" .. tostring(BJ:CountTable(self.pendingOwnDeposits)))
    BJ:Print("HookDeposito=" .. tostring(self.depositHooked) .. " receipts=" .. tostring(BJ:CountTable(s.depositReceipts)) .. " receiptsPending=" .. tostring(self:GetPendingReceiptCount()) .. " lastQuery=" .. tostring(self.lastBankQueryAt or 0) .. " lastScan=" .. tostring(s.lastBankScan or 0))
    BJ:Print("bankLogEvent=" .. tostring(self.lastBankLogEventAt or 0) .. " bankPoll=" .. tostring(self.lastBankPollAt or 0) .. " polling=" .. tostring(self.bankPolling) .. " pollSerial=" .. tostring(self.bankPollSerial or 0) .. " scanSerial=" .. tostring(self.bankLogScanSerial or 0))
    BJ:Print("bankOpenAt=" .. tostring(self.lastGuildBankOpenAt or 0) .. " via=" .. tostring(self.lastGuildBankOpenSource or "-") .. " interactionShow=" .. tostring(self.lastInteractionShowAt or 0) .. " closeAt=" .. tostring(self.lastGuildBankCloseAt or 0) .. " interactionHide=" .. tostring(self.lastInteractionHideAt or 0))
    BJ:Print("lastImport=" .. tostring(self.lastImportedAt or 0) .. " selfDetected=" .. tostring(self.lastOwnDepositDetected or 0) .. " selfConfirmed=" .. tostring(self.lastOwnDepositConfirmed or 0))
    BJ:Print("playerMoneyDelta=" .. self:FormatGold(self.lastPlayerMoneyDelta or 0) .. " playerMoneyEventAt=" .. tostring(self.lastPlayerMoneyEventAt or 0) .. " eventBaseline=" .. tostring(self.playerMoneyEventBaseline or "nil"))
    BJ:Print("Status: " .. tostring(self.lastStatus or "-"))
    local list = self:GetLedgerFor(BJ.player)
    local first = math.max(1, #list - 4)
    for i = #list, first, -1 do
        local e = list[i]
        local sign = (tonumber(e.amount) or 0) >= 0 and "+" or ""
        BJ:Print("Movimento " .. tostring(i) .. ": " .. sign .. self:FormatGold(e.amount) .. " " .. tostring(e.source or "?") .. " actor=" .. BJ:ShortName(e.actor or e.player or "?") .. " note=" .. tostring(e.note or ""))
    end
end
