local _, BJ = ...

BJ.TestMode = {}
local TestMode = BJ.TestMode

local function FreshState()
    return {
        chips = 0,
        lifetime = 0,
        claimed = {},
        unlocked = { starter = true },
        weeklyGoldClaims = {},
        history = {},
        forceAllChallenges = false,
        titleId = "starter",
        badgeId = "",
        profileRevision = 0,
        remoteProfiles = {},
        treasury = { claims = {}, history = {} },
    }
end

function TestMode:Initialize()
    BJ.db.test = BJ.db.test or FreshState()
    BJ.db.test.claimed = BJ.db.test.claimed or {}
    BJ.db.test.unlocked = BJ.db.test.unlocked or { starter = true }
    BJ.db.test.unlocked.starter = true
    BJ.db.test.weeklyGoldClaims = BJ.db.test.weeklyGoldClaims or {}
    BJ.db.test.history = BJ.db.test.history or {}
    BJ.db.test.titleId = BJ.db.test.titleId or "starter"
    BJ.db.test.badgeId = BJ.db.test.badgeId or ""
    BJ.db.test.profileRevision = tonumber(BJ.db.test.profileRevision) or 0
    BJ.db.test.remoteProfiles = BJ.db.test.remoteProfiles or {}
    BJ.db.test.treasury = BJ.db.test.treasury or { claims = {}, history = {} }
    BJ.db.test.treasury.claims = BJ.db.test.treasury.claims or {}
    BJ.db.test.treasury.history = BJ.db.test.treasury.history or {}
    if BJ.db.test.forceAllChallenges == nil then BJ.db.test.forceAllChallenges = false end
end

function TestMode:IsEnabled()
    return BJ.db and BJ.db.settings and BJ.db.settings.testMode
        and BJ.Guild and BJ.Guild:IsOfficer() or false
end

function TestMode:SetEnabled(enabled)
    if not BJ.db then return end
    if enabled and not (BJ.Guild and BJ.Guild:IsOfficer()) then return end
    self:Initialize()
    BJ.db.settings.testMode = enabled and true or false
    if enabled then
        BJ:Print("|cffff6a63MODALITA TEST ATTIVA|r - sandbox separata dai dati reali; titolo/badge e Cassa TEST sono visibili solo agli altri client in TEST.")
        C_Timer.After(0.2, function()
            if BJ.Comms and BJ.TestMode:IsEnabled() then BJ.Comms:BroadcastTestProfileStyle() end
            if BJ.Treasury and BJ.TestMode:IsEnabled() then BJ.Treasury:BroadcastState() end
        end)
    else
        BJ:Print("Modalita test disattivata. I dati reali non sono stati modificati.")
        if BJ.Comms then BJ.Comms:BroadcastProfile() end
        if BJ.Treasury then BJ.Treasury:BroadcastState() end
    end
    if BJ.UI then
        if BJ.UI.RefreshTestIndicator then BJ.UI:RefreshTestIndicator() end
        BJ.UI:RefreshAll()
    end
end

function TestMode:ResetSandbox()
    BJ.db.test = FreshState()
    BJ:Print("Sandbox test azzerata.")
    if BJ.Comms and self:IsEnabled() then BJ.Comms:BroadcastTestProfileStyle() end
    if BJ.UI then BJ.UI:RefreshAll() end
end

function TestMode:SetChips(amount)
    self:Initialize()
    amount = math.max(0, tonumber(amount) or 0)
    BJ.db.test.chips = amount
    BJ.db.test.lifetime = math.max(tonumber(BJ.db.test.lifetime) or 0, amount)
    BJ:Print("Saldo TEST impostato a " .. amount .. " fiches.")
    if BJ.UI then BJ.UI:RefreshAll() end
end

function TestMode:SetAllChallengesComplete(enabled)
    self:Initialize()
    BJ.db.test.forceAllChallenges = enabled and true or false
    BJ:Print(enabled and "Tutte le challenge risultano complete in modalita TEST." or "Completamento forzato challenge TEST disattivato.")
    if BJ.UI then BJ.UI:RefreshAll() end
end

function TestMode:UnlockAllRewards()
    self:Initialize()
    for i = 1, #BJ.Data.rewards do
        local reward = BJ.Data.rewards[i]
        if reward.type ~= "weekly_gold" then
            BJ.db.test.unlocked[reward.id] = true
        end
    end
    BJ.db.test.unlocked.starter = true
    BJ:Print("Tutti i titoli e badge sono sbloccati nella sandbox TEST.")
    if BJ.UI then BJ.UI:RefreshAll() end
end
