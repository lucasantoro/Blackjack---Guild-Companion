local _, BJ = ...

BJ.Rewards = {}
local Rewards = BJ.Rewards

local function InTest()
    return BJ.TestMode and BJ.TestMode:IsEnabled()
end

function Rewards:GetStore()
    if InTest() then
        BJ.TestMode:Initialize()
        return BJ.db.test
    end
    return BJ.db.rewards
end

function Rewards:Initialize()
    local key = BJ:GetWeekKey()
    BJ.db.rewards.claimed[key] = BJ.db.rewards.claimed[key] or {}
    BJ.db.rewards.weeklyGoldClaims = BJ.db.rewards.weeklyGoldClaims or {}
    BJ.db.rewards.unlocked.starter = true
    if BJ.TestMode then
        BJ.TestMode:Initialize()
        BJ.db.test.claimed[key] = BJ.db.test.claimed[key] or {}
    end
end

function Rewards:GetBalance()
    return tonumber(self:GetStore().chips) or 0
end

function Rewards:GetLifetime()
    return tonumber(self:GetStore().lifetime) or 0
end

function Rewards:IsClaimed(challengeId)
    local key = BJ:GetWeekKey()
    local week = self:GetStore().claimed[key]
    return week and week[challengeId] and true or false
end

function Rewards:Claim(challenge)
    if BJ.Access and not BJ.Access:IsAuthorized() then return false, "Accesso Blackjack non verificato" end
    if not challenge or self:IsClaimed(challenge.id) then return false, "Gia riscossa" end
    if not BJ.Challenges:IsCompleted(challenge) then return false, "Challenge non completata" end

    local store = self:GetStore()
    local key = BJ:GetWeekKey()
    store.claimed[key] = store.claimed[key] or {}
    store.claimed[key][challenge.id] = true

    local amount = tonumber(challenge.reward) or 0
    store.chips = self:GetBalance() + amount
    store.lifetime = self:GetLifetime() + amount

    table.insert(store.history, 1, { time=BJ:Now(), kind="CLAIM", id=challenge.id, amount=amount, weekKey=key })
    while #store.history > 100 do table.remove(store.history) end

    if InTest() then
        BJ:Print("[TEST] +" .. amount .. " fiches per " .. challenge.title .. ".")
    else
        BJ:AddMoment("Ricompensa riscossa: +" .. amount .. " fiches per " .. challenge.title .. ".", "REWARD")
        if BJ.Comms then BJ.Comms:BroadcastSummary() end
    end
    if BJ.UI then BJ.UI:RefreshAll() end
    return true
end

function Rewards:IsUnlocked(rewardId)
    return self:GetStore().unlocked[rewardId] and true or false
end

function Rewards:Unlock(reward)
    if BJ.Access and not BJ.Access:IsAuthorized() then return false, "Accesso Blackjack non verificato" end
    if not reward then return false, "Reward non valida" end
    if reward.type == "weekly_gold" then return self:ClaimWeeklyGold(reward) end
    if self:IsUnlocked(reward.id) then return false, "Gia sbloccata" end

    local price = tonumber(reward.price) or 0
    if self:GetBalance() < price then return false, "Fiches insufficienti" end

    local store = self:GetStore()
    store.chips = self:GetBalance() - price
    store.unlocked[reward.id] = true
    table.insert(store.history, 1, { time=BJ:Now(), kind="UNLOCK", id=reward.id, amount=-price })
    while #store.history > 100 do table.remove(store.history) end

    if InTest() then
        BJ:Print("[TEST] Reward sbloccata: " .. reward.title .. ".")
    else
        BJ:AddMoment("Reward sbloccata: " .. reward.title .. ".", "REWARD")
    end
    if BJ.UI then BJ.UI:RefreshAll() end
    return true
end

function Rewards:GetWeeklyGoldClaim()
    local key = BJ:GetWeekKey()
    local store = self:GetStore()
    return store.weeklyGoldClaims and store.weeklyGoldClaims[key] or nil
end

function Rewards:HasClaimedWeeklyGold()
    return self:GetWeeklyGoldClaim() ~= nil
end

function Rewards:ClaimWeeklyGold(reward)
    if BJ.Access and not BJ.Access:IsAuthorized() then return false, "Accesso Blackjack non verificato" end
    reward = reward or BJ.Data:GetReward("weekly_gold_250")
    if not reward or reward.type ~= "weekly_gold" then return false, "Reward gold non valida" end
    if self:HasClaimedWeeklyGold() then return false, "Il reward da 250g e gia stato riscattato in questo reset" end

    local price = tonumber(reward.price) or 0
    if self:GetBalance() < price then return false, "Fiches insufficienti" end

    local store = self:GetStore()
    local key = BJ:GetWeekKey()
    local amount = tonumber(reward.gold) or 250
    store.chips = self:GetBalance() - price
    store.weeklyGoldClaims[key] = {
        amount = amount,
        cost = price,
        time = BJ:Now(),
        player = BJ.player,
        test = InTest() and true or nil,
        weekKey = key,
        status = InTest() and "TEST" or "PENDING",
    }
    table.insert(store.history, 1, {
        time=BJ:Now(), kind="GOLD_CLAIM", id=reward.id, amount=-price, gold=amount, weekKey=key,
    })
    while #store.history > 100 do table.remove(store.history) end

    if InTest() then
        BJ:Print("[TEST] Busta del Dealer riscattata. Richiesta inserita nella Cassa TEST; nessun pagamento reale da effettuare.")
        if BJ.Treasury then BJ.Treasury:RegisterLocalClaim(store.weeklyGoldClaims[key]) end
    else
        BJ:AddMoment("Busta del Dealer riscattata: credito di " .. amount .. " gold registrato per questo reset.", "REWARD")
        BJ:Print("Credito " .. amount .. "g registrato nella Cassa Blackjack. Gli officer vedranno la richiesta automaticamente.")
        if BJ.Treasury then BJ.Treasury:RegisterLocalClaim(store.weeklyGoldClaims[key]) end
        if BJ.Comms then BJ.Comms:BroadcastSummary() end
    end
    if BJ.UI then BJ.UI:RefreshAll() end
    return true
end

function Rewards:GetEquippedTitleId()
    if InTest() then return self:GetStore().titleId or "starter" end
    return BJ.profile.titleId or "starter"
end

function Rewards:GetEquippedBadgeId()
    if InTest() then return self:GetStore().badgeId or "" end
    return BJ.profile.badgeId or ""
end

function Rewards:IsEquipped(reward)
    if not reward then return false end
    if reward.type == "badge" then return self:GetEquippedBadgeId() == reward.id end
    return self:GetEquippedTitleId() == reward.id
end

function Rewards:Equip(rewardId)
    if BJ.Access and not BJ.Access:IsAuthorized() then return false end
    local reward = BJ.Data:GetReward(rewardId)
    if not reward or not self:IsUnlocked(rewardId) then return false end

    if InTest() then
        local store = self:GetStore()
        if reward.type == "badge" then store.badgeId = rewardId else store.titleId = rewardId end
        store.profileRevision = math.max(BJ:Now(), (tonumber(store.profileRevision) or 0) + 1)
        BJ:Print("[TEST] Equipaggiato: " .. reward.title .. ".")
        if BJ.Comms then BJ.Comms:BroadcastTestProfileStyle() end
    else
        if reward.type == "badge" then BJ.profile.badgeId = rewardId else BJ.profile.titleId = rewardId end
        local now = BJ:Now()
        BJ.profile.updated = math.max(now, (tonumber(BJ.profile.updated) or 0) + 1)
        if BJ.Comms then BJ.Comms:BroadcastProfile() end
    end

    if BJ.UI then BJ.UI:RefreshPage("MEMBERS"); BJ.UI:RefreshPage("REWARDS") end
    return true
end

function Rewards:GetEquipped()
    return BJ.Data:GetReward(self:GetEquippedTitleId())
end

function Rewards:GetEquippedBadge()
    local id = self:GetEquippedBadgeId()
    if not id or id == "" then return nil end
    return BJ.Data:GetReward(id)
end
