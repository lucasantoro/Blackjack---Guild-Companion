local _, BJ = ...

BJ.Treasury = {}
local Treasury = BJ.Treasury

Treasury.GOLD_COPPER = 250 * 10000
Treasury.bankOpen = false
Treasury.lastStatus = nil
Treasury.lastBankScan = 0
Treasury.lastStateRequestAt = 0

local function InTest()
    return BJ.TestMode and BJ.TestMode:IsEnabled()
end

local function IsGuildBankInteraction(interactionType)
    local interactionEnum = Enum and Enum.PlayerInteractionType
    local guildBanker = interactionEnum and interactionEnum.GuildBanker
    if guildBanker ~= nil then return interactionType == guildBanker end
    return tonumber(interactionType) == 10
end

local function ClaimKey(player, weekKey)
    return tostring(player or "?") .. "#" .. tostring(weekKey or "?")
end

local function NormalizePlayer(name)
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

function Treasury:GetStore(isTest)
    if isTest == nil then isTest = InTest() end
    if isTest then
        BJ.TestMode:Initialize()
        return BJ.db.test.treasury
    end
    BJ.db.treasury = BJ.db.treasury or { claims = {}, history = {}, seenTransactions = {}, lastBankScan = 0 }
    BJ.db.treasury.claims = BJ.db.treasury.claims or {}
    BJ.db.treasury.history = BJ.db.treasury.history or {}
    BJ.db.treasury.seenTransactions = BJ.db.treasury.seenTransactions or {}
    return BJ.db.treasury
end

function Treasury:HandleGuildBankOpened(source)
    local wasOpen = self.bankOpen
    self.bankOpen = true
    if wasOpen then return false end
    self.lastStatus = "Banca di gilda aperta" .. (source and (" [" .. source .. "]") or "") .. ". Richiesta lettura registro gold."
    if not InTest() then self:QueryBankLog() end
    if BJ.UI then BJ.UI:RefreshPage("CASSA"); BJ.UI:RefreshPage("REWARDS") end
    return true
end

function Treasury:HandleGuildBankClosed()
    if not self.bankOpen then return false end
    self.bankOpen = false
    if BJ.UI then BJ.UI:RefreshPage("CASSA"); BJ.UI:RefreshPage("REWARDS") end
    return true
end

function Treasury:Initialize()
    self:GetStore(false)
    if BJ.TestMode then BJ.TestMode:Initialize() end

    BJ:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
        if IsGuildBankInteraction(interactionType) then Treasury:HandleGuildBankOpened("INTERACTION") end
    end)
    BJ:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, interactionType)
        if IsGuildBankInteraction(interactionType) then Treasury:HandleGuildBankClosed() end
    end)
    BJ:RegisterEvent("GUILDBANKFRAME_OPENED", function()
        Treasury:HandleGuildBankOpened("LEGACY_EVENT")
    end)
    BJ:RegisterEvent("GUILDBANKFRAME_CLOSED", function()
        Treasury:HandleGuildBankClosed()
    end)
    BJ:RegisterEvent("GUILDBANKLOG_UPDATE", function()
        if Treasury.bankOpen and not InTest() then Treasury:ScanBankLog() end
    end)

    C_Timer.After(4, function()
        if BJ.Access and BJ.Access:IsAuthorized() then Treasury:RequestState() end
    end)
end

function Treasury:IsOfficer()
    return BJ.Guild and BJ.Guild:IsOfficer() or false
end

function Treasury:Key(player, weekKey)
    return ClaimKey(NormalizePlayer(player), weekKey)
end

function Treasury:GetClaim(player, weekKey, isTest)
    local store = self:GetStore(isTest)
    return store.claims[self:Key(player, weekKey)]
end

function Treasury:GetCurrentPlayerClaim(isTest)
    return self:GetClaim(BJ.player, BJ:GetWeekKey(), isTest)
end

function Treasury:RegisterClaim(player, weekKey, amount, cost, claimTime, source, isTest)
    if isTest == nil then isTest = InTest() end
    player = NormalizePlayer(player)
    if not player or not weekKey then return nil end
    local store = self:GetStore(isTest)
    local key = self:Key(player, weekKey)
    local existing = store.claims[key]
    local record = existing or {}
    record.player = player
    record.weekKey = tostring(weekKey)
    record.amount = tonumber(amount) or 250
    record.cost = tonumber(cost) or 0
    record.claimTime = tonumber(claimTime) or BJ:Now()
    record.receivedAt = BJ:Now()
    record.status = record.status == "PAID" and "PAID" or "PENDING"
    record.source = source or record.source or "SYNC"
    record.test = isTest and true or nil
    store.claims[key] = record
    if BJ.UI then BJ.UI:RefreshPage("CASSA"); BJ.UI:RefreshPage("REWARDS") end
    return record
end

function Treasury:RegisterLocalClaim(claim)
    if not claim then return end
    local isTest = claim.test and true or false
    local weekKey = claim.weekKey or BJ:GetWeekKey()
    local record = self:RegisterClaim(BJ.player, weekKey, claim.amount, claim.cost, claim.time, "LOCAL", isTest)
    if not record then return end

    self.lastStatus = isTest
        and ("[TEST] Richiesta simulata " .. tostring(record.amount or 250) .. "g inserita nella Cassa TEST.")
        or ("Richiesta " .. tostring(record.amount or 250) .. "g inserita nella Cassa e inviata alla gilda.")

    if BJ.Comms then
        self:BroadcastClaim(record)
        -- Recovery announcements: cheap, queued and useful if the first packet lands
        -- while another client is still loading its guild roster.
        C_Timer.After(2.0, function()
            if BJ.Treasury then BJ.Treasury:BroadcastClaim(record) end
        end)
        C_Timer.After(7.0, function()
            if BJ.Treasury then BJ.Treasury:BroadcastClaim(record) end
        end)
    end
end

function Treasury:BroadcastClaim(record)
    if not record or not BJ.Comms or not IsInGuild() then return end
    local kind = record.test and "TGCLAIM" or "GCLAIM"
    BJ.Comms:SendSystem(kind, "GUILD", nil,
        record.weekKey, record.amount or 250, record.cost or 0, record.claimTime or BJ:Now())
end

function Treasury:BroadcastCurrentClaim()
    local isTest = InTest()
    local rewardStore = isTest and BJ.db.test or BJ.db.rewards
    local key = BJ:GetWeekKey()
    local claim = rewardStore and rewardStore.weeklyGoldClaims and rewardStore.weeklyGoldClaims[key] or nil
    if claim then
        claim.weekKey = claim.weekKey or key
        claim.test = isTest and true or nil
        local record = self:RegisterClaim(BJ.player, claim.weekKey, claim.amount, claim.cost, claim.time, "LOCAL", isTest)
        self:BroadcastClaim(record)
    end
end

function Treasury:RequestState(force)
    if not BJ.Comms or not IsInGuild() then return false end
    local now = BJ:Now()
    if not force and now - (tonumber(self.lastStateRequestAt) or 0) < 15 then return false end
    self.lastStateRequestAt = now
    BJ.Comms:SendSystem("GCREQ", "GUILD")
    return true
end

function Treasury:HandleRemoteClaim(sender, weekKey, amount, cost, claimTime, isTest)
    if isTest and not InTest() then return end
    local resolved = BJ.Guild and BJ.Guild:ResolveMember(sender) or nil
    if BJ.Guild and not resolved then
        -- Roster can still be loading at login. Ask for it and let the sender's
        -- scheduled rebroadcast recover the claim rather than accepting strangers.
        BJ.Guild:RequestRoster()
        return
    end
    sender = resolved or NormalizePlayer(sender)
    if not sender then return end
    self:RegisterClaim(sender, weekKey, amount, cost, claimTime, isTest and "REMOTE_TEST" or "REMOTE", isTest)
    self.lastStatus = (isTest and "[TEST] " or "") .. "Richiesta ricevuta da " .. BJ:ShortName(sender) .. "."
end

function Treasury:SetPaid(player, weekKey, paidBy, method, paidAt, transactionId, broadcast, isTest)
    if isTest == nil then isTest = InTest() end
    player = NormalizePlayer(player)
    local record = self:GetClaim(player, weekKey, isTest)
    if not record then
        record = self:RegisterClaim(player, weekKey, 250, 0, paidAt or BJ:Now(), "PAID_ONLY", isTest)
    end
    if not record then return false end

    record.status = "PAID"
    record.paidAt = tonumber(paidAt) or BJ:Now()
    record.paidBy = NormalizePlayer(paidBy) or paidBy or BJ.player
    record.method = method or "MANUAL"
    record.transactionId = transactionId or record.transactionId
    record.receivedAt = BJ:Now()

    local store = self:GetStore(isTest)
    table.insert(store.history, 1, {
        player = record.player,
        weekKey = record.weekKey,
        amount = record.amount,
        paidAt = record.paidAt,
        paidBy = record.paidBy,
        method = record.method,
        transactionId = record.transactionId,
        test = isTest and true or nil,
    })
    while #store.history > 120 do table.remove(store.history) end

    if record.player == BJ.player then
        local rewardStore = isTest and BJ.db.test or BJ.db.rewards
        local localClaim = rewardStore and rewardStore.weeklyGoldClaims and rewardStore.weeklyGoldClaims[tostring(record.weekKey)] or nil
        if not localClaim and tostring(record.weekKey) == tostring(BJ:GetWeekKey()) then
            localClaim = rewardStore and rewardStore.weeklyGoldClaims and rewardStore.weeklyGoldClaims[BJ:GetWeekKey()] or nil
        end
        if localClaim then
            localClaim.status = "PAID"
            localClaim.paidAt = record.paidAt
            localClaim.paidBy = record.paidBy
            localClaim.method = record.method
        end
    end

    if broadcast and BJ.Comms then
        BJ.Comms:SendSystem(isTest and "TGPAID" or "GPAID", "GUILD", nil,
            record.player, record.weekKey, record.paidAt, record.method or "MANUAL", record.transactionId or "")
    end
    if BJ.UI then BJ.UI:RefreshPage("CASSA"); BJ.UI:RefreshPage("REWARDS"); BJ.UI:RefreshPage("MEMBERS") end
    return true
end

function Treasury:MarkPaid(player, weekKey, method, transactionId)
    if not self:IsOfficer() then return false, "Solo GM/officer possono confermare i pagamenti" end
    local isTest = InTest()
    local record = self:GetClaim(player, weekKey, isTest)
    if not record then return false, "Richiesta non trovata" end
    if record.status == "PAID" then return false, "Reward gia segnato come pagato" end
    self:SetPaid(player, weekKey, BJ.player, method or "MANUAL", BJ:Now(), transactionId, true, isTest)
    self.lastStatus = (isTest and "[TEST] " or "") .. BJ:ShortName(player) .. " segnato PAGATO."
    return true
end

function Treasury:HandleRemotePaid(officer, player, weekKey, paidAt, method, transactionId, isTest)
    if isTest and not InTest() then return end
    officer = BJ.Guild and BJ.Guild:ResolveMember(officer) or NormalizePlayer(officer)
    if not officer or not (BJ.Guild and BJ.Guild:IsOfficerName(officer)) then return end
    self:SetPaid(player, weekKey, officer, method or "MANUAL", paidAt, transactionId, false, isTest)
end

function Treasury:BroadcastOfficerPaidState()
    if not self:IsOfficer() or not BJ.Comms then return end
    local isTest = InTest()
    local currentWeek = tostring(BJ:GetWeekKey())
    local store = self:GetStore(isTest)
    for _, record in pairs(store.claims) do
        if record.status == "PAID" and tostring(record.weekKey) == currentWeek then
            BJ.Comms:SendSystem(isTest and "TGPAID" or "GPAID", "GUILD", nil,
                record.player, record.weekKey, record.paidAt or BJ:Now(), record.method or "MANUAL", record.transactionId or "")
        end
    end
end

function Treasury:BroadcastState()
    self:BroadcastCurrentClaim()
    self:BroadcastOfficerPaidState()
end

function Treasury:GetPendingCount()
    local count, gold = 0, 0
    local store = self:GetStore()
    for _, record in pairs(store.claims) do
        if record.status ~= "PAID" then
            count = count + 1
            gold = gold + (tonumber(record.amount) or 250)
        end
    end
    return count, gold
end

function Treasury:GetClaimsSorted()
    local list = {}
    local store = self:GetStore()
    for _, record in pairs(store.claims) do list[#list + 1] = record end
    table.sort(list, function(a, b)
        local ap = a.status ~= "PAID" and 0 or 1
        local bp = b.status ~= "PAID" and 0 or 1
        if ap ~= bp then return ap < bp end
        local at = tonumber(a.claimTime or a.paidAt) or 0
        local bt = tonumber(b.claimTime or b.paidAt) or 0
        if at ~= bt then return at > bt end
        return tostring(a.player or "") < tostring(b.player or "")
    end)
    return list
end

function Treasury:QueryBankLog()
    if InTest() then return false, "La verifica banca reale e disabilitata nella sandbox TEST" end
    if not self.bankOpen then return false, "Apri la banca di gilda" end
    if not self:IsOfficer() then return false, "La verifica automatica e riservata a GM/officer" end
    if not QueryGuildBankLog then return false, "API registro banca non disponibile" end
    local moneyLogTab = (MAX_GUILDBANK_TABS or 8) + 1
    QueryGuildBankLog(moneyLogTab)
    self.lastStatus = "Registro gold richiesto alla banca."
    return true
end

function Treasury:TransactionFingerprint(name, amount, years, months, days, hours)
    return table.concat({
        NormalizePlayer(name) or tostring(name or "?"),
        tostring(amount or 0), tostring(years or 0), tostring(months or 0),
        tostring(days or 0), tostring(hours or 0)
    }, ":")
end

function Treasury:FindPendingForTransaction(name, amount, years, months, days, hours)
    local rawName = name
    name = NormalizePlayer(name)
    if not name then return nil end
    local shortName = BJ:ShortName(rawName or name)
    local gold = math.floor((tonumber(amount) or 0) / 10000 + 0.5)
    local approxTime = ApproxTransactionTime(years, months, days, hours)
    local best
    local store = self:GetStore(false)
    for _, record in pairs(store.claims) do
        local samePlayer = record.player == name or BJ:ShortName(record.player) == shortName
        if record.status ~= "PAID" and samePlayer and (tonumber(record.amount) or 250) == gold then
            local claimTime = tonumber(record.claimTime) or 0
            if approxTime + 3600 >= claimTime then
                if not best or claimTime > (tonumber(best.claimTime) or 0) then best = record end
            end
        end
    end
    return best
end

function Treasury:ScanBankLog()
    if not self.bankOpen or not self:IsOfficer() or InTest() then return false end
    if not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then return false end

    local count = tonumber(GetNumGuildBankMoneyTransactions()) or 0
    if count <= 0 then
        self.lastStatus = "Registro banca vuoto o non ancora caricato."
        if BJ.UI then BJ.UI:RefreshPage("CASSA") end
        return false
    end

    local realStore = self:GetStore(false)
    local matched = 0
    for i = 1, count do
        local transactionType, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
        if transactionType == "withdrawal" and name and amount then
            local fingerprint = self:TransactionFingerprint(name, amount, years, months, days, hours)
            if not realStore.seenTransactions[fingerprint] then
                local claim = self:FindPendingForTransaction(name, amount, years, months, days, hours)
                if claim then
                    realStore.seenTransactions[fingerprint] = BJ:Now()
                    self:SetPaid(claim.player, claim.weekKey, BJ.player, "BANK", BJ:Now(), fingerprint, true, false)
                    matched = matched + 1
                end
            end
        end
    end

    self.lastBankScan = BJ:Now()
    realStore.lastBankScan = self.lastBankScan
    self.lastStatus = matched > 0 and ("Verifica banca: " .. matched .. " pagamento/i confermato/i.") or "Verifica banca completata: nessun nuovo pagamento abbinato."
    if BJ.UI then BJ.UI:RefreshPage("CASSA"); BJ.UI:RefreshPage("REWARDS") end
    return true
end

function Treasury:CanSelfWithdraw()
    if InTest() then return false end
    local claim = BJ.Rewards and BJ.Rewards:GetWeeklyGoldClaim() or nil
    if not claim or claim.status == "PAID" or not self.bankOpen then return false end
    if not CanWithdrawGuildBankMoney or not CanWithdrawGuildBankMoney() then return false end
    if not GetGuildBankWithdrawMoney or not GetGuildBankMoney then return false end

    local needed = (tonumber(claim.amount) or 250) * 10000
    local remaining = tonumber(GetGuildBankWithdrawMoney())
    local bankMoney = tonumber(GetGuildBankMoney()) or 0
    local enoughLimit = remaining == -1 or (remaining and remaining >= needed)
    return enoughLimit and bankMoney >= needed
end

function Treasury:WithdrawCurrentReward()
    if not self:CanSelfWithdraw() then return false, "Prelievo diretto non disponibile per il tuo rank o banca non aperta" end
    local claim = BJ.Rewards:GetWeeklyGoldClaim()
    local copper = (tonumber(claim.amount) or 250) * 10000
    WithdrawGuildBankMoney(copper)
    claim.withdrawRequestedAt = BJ:Now()
    self.lastStatus = "Prelievo richiesto. Il pagamento verra verificato dal registro banca da un officer."
    BJ:Print("Richiesto prelievo di " .. tostring(claim.amount or 250) .. "g dalla banca. Attendi la verifica del registro.")
    return true
end
