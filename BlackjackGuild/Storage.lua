local _, BJ = ...

BJ.Storage = {}
local Storage = BJ.Storage

local DEFAULTS = {
    schema = 20,
    settings = {
        strata = "TOOLTIP",
        showMinimap = true,
        showHUDOnLogin = true,
        hudExpandDirection = "DOWN",
        notifications = true,
        shareProfile = true,
        debug = false,
        testMode = false,
        craftingAutoPublish = true,
    },
    ui = {
        lastPage = "HOME",
        main = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        hud = { point = "TOP", relativePoint = "TOP", x = 0, y = -115, width = 530, height = 42 },
    },
    profiles = {},
    network = {
        peers = {},
        profiles = {},
        profileTombstones = {},
        activities = {},
        activityTombstones = {},
        summaries = {},
        craftingOrders = {},
        craftingHistory = {},
        craftOffers = {},
        craftingTombstones = {},
    },
    joinedActivities = {},
    activityLeaves = {},
    crafting = {
        owned = {},
        history = {},
        joined = {},
        joinedCharacter = "",
        lastRefresh = 0,
        resetAt = 0,
        deliveries = {},
        deliveryHistory = {},
    },
    progress = {
        weekKey = "",
        stats = {},
        sets = {},
    },
    rewards = {
        chips = 0,
        lifetime = 0,
        claimed = {},
        unlocked = { starter = true },
        weeklyGoldClaims = {},
        history = {},
    },
    test = {
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
    },
    treasury = {
        claims = {},
        history = {},
        seenTransactions = {},
        lastBankScan = 0,
    },
    raider = {
        monthlyCopper = 8000 * 10000,
        startYear = 2026,
        startMonth = 9,
        flags = {},
        flagUpdated = {},
        altMap = {},
        altMapUpdated = {},
        ledger = {},
        exemptions = {},
        exemptionUpdated = {},
        personal = {},
        unassigned = {},
        bankSeen = {},
        depositReceipts = {},
        lastBankScan = 0,
        revision = 0,
    },
    moments = {},
}

local function MergeDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = MergeDefaults(value, dst[key])
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
    return dst
end

local function MigrateOld(old)
    if type(old) ~= "table" then return {} end
    if old.schema == 20 then return old end

    local previousSchema = tonumber(old.schema) or 0
    local migrated = old
    migrated.schema = 20
    migrated.settings = migrated.settings or {}
    migrated.settings.hudMaxRows = nil
    migrated.settings.hudExpandDirection = migrated.settings.hudExpandDirection or "DOWN"
    -- v2.7.1: the HUD is now opt-out instead of opt-in. Older builds shipped
    -- showHUDOnLogin=false as the default, which made it look broken after relog/character swap.
    -- Enable it once during migration; the user can still disable it explicitly afterwards.
    if previousSchema < 10 then migrated.settings.showHUDOnLogin = true end
    migrated.ui = migrated.ui or {}
    migrated.ui.hud = migrated.ui.hud or { point = "TOP", relativePoint = "TOP", x = 0, y = -115 }
    migrated.ui.hud.width = tonumber(migrated.ui.hud.width) or 530
    migrated.ui.hud.height = tonumber(migrated.ui.hud.height) or 42
    migrated.progress = migrated.progress or {}
    -- Dalla v2.2 il progresso challenge e solo automatico. I vecchi campi
    -- manual/manualCounts vengono eliminati per evitare qualsiasi ambiguita.
    migrated.progress.manual = nil
    migrated.progress.manualCounts = nil
    migrated.progress.stats = migrated.progress.stats or {}
    migrated.progress.sets = migrated.progress.sets or {}
    migrated.rewards = migrated.rewards or {}
    migrated.rewards.weeklyGoldClaims = migrated.rewards.weeklyGoldClaims or {}
    migrated.rewards.unlocked = migrated.rewards.unlocked or {}
    migrated.rewards.unlocked.starter = true
    migrated.network = migrated.network or {}
    -- Passport V3 uses a different transport/identity model; discard stale V4 cache
    -- so old empty or frozen profiles cannot mask fresh guild broadcasts.
    migrated.network.profiles = {}
    migrated.network.craftingOrders = migrated.network.craftingOrders or {}
    migrated.network.craftingHistory = migrated.network.craftingHistory or {}
    migrated.network.craftOffers = migrated.network.craftOffers or {}
    migrated.crafting = migrated.crafting or { owned = {}, history = {}, joined = {}, lastRefresh = 0 }
    migrated.crafting.owned = migrated.crafting.owned or {}
    migrated.crafting.history = migrated.crafting.history or {}
    migrated.crafting.joined = migrated.crafting.joined or {}
    migrated.crafting.resetAt = tonumber(migrated.crafting.resetAt) or 0
    migrated.crafting.deliveries = migrated.crafting.deliveries or {}
    migrated.crafting.deliveryHistory = migrated.crafting.deliveryHistory or {}
    -- v2.9.5: CWORK is only a board/history reconciliation packet. Older builds could
    -- create POSTA alerts from it, and MAIL_RECOVERY also accepted crafter-side settlement
    -- mail. Drop those ambiguous alerts once; legitimate uncollected customer mail will
    -- be rediscovered safely the next time the mailbox is opened.
    if previousSchema < 15 then
        for _, deliveryStore in pairs(migrated.crafting.deliveries) do
            if type(deliveryStore) == "table" then
                for id, delivery in pairs(deliveryStore) do
                    local source = type(delivery) == "table" and delivery.source or nil
                    if source == "CWORK" or source == "MAIL_RECOVERY" or source == "MY_ORDERS" then
                        deliveryStore[id] = nil
                    end
                end
            end
        end
        for id, delivery in pairs(migrated.crafting.deliveryHistory) do
            local source = type(delivery) == "table" and delivery.source or nil
            if source == "CWORK" or source == "MAIL_RECOVERY" or source == "MY_ORDERS" then
                migrated.crafting.deliveryHistory[id] = nil
            end
        end
    end
    -- v2.9.2: remove false POSTA alerts created by old builds from historical
    -- fulfilled rows returned by GetMyOrders when opening a crafting station.
    for _, deliveryStore in pairs(migrated.crafting.deliveries) do
        if type(deliveryStore) == "table" then
            for id, delivery in pairs(deliveryStore) do
                if type(delivery) == "table" and delivery.source == "MY_ORDERS" then
                    deliveryStore[id] = nil
                end
            end
        end
    end
    for id, delivery in pairs(migrated.crafting.deliveryHistory) do
        if type(delivery) == "table" and delivery.source == "MY_ORDERS" then
            migrated.crafting.deliveryHistory[id] = nil
        end
    end
    migrated.raider = migrated.raider or {}
    migrated.raider.monthlyCopper = tonumber(migrated.raider.monthlyCopper) or (8000 * 10000)
    migrated.raider.startYear = tonumber(migrated.raider.startYear) or 2026
    migrated.raider.startMonth = tonumber(migrated.raider.startMonth) or 9
    migrated.raider.flags = migrated.raider.flags or {}
    migrated.raider.flagUpdated = migrated.raider.flagUpdated or {}
    migrated.raider.altMap = migrated.raider.altMap or {}
    migrated.raider.altMapUpdated = migrated.raider.altMapUpdated or {}
    migrated.raider.ledger = migrated.raider.ledger or {}
    migrated.raider.exemptions = migrated.raider.exemptions or {}
    migrated.raider.exemptionUpdated = migrated.raider.exemptionUpdated or {}
    migrated.raider.personal = migrated.raider.personal or {}
    migrated.raider.unassigned = migrated.raider.unassigned or {}
    migrated.raider.bankSeen = migrated.raider.bankSeen or {}
    migrated.raider.depositReceipts = migrated.raider.depositReceipts or {}
    -- v3.0.6: v3.0.0-v3.0.5 rounded negative manual adjustments with
    -- math.floor(raw - 0.5), making every negative MANUAL entry one copper too
    -- negative. Repair those historical entries once so exactly 8,000g is truly
    -- 80,000,000 copper and the current-month status can become IN REGOLA.
    if previousSchema < 20 then
        for _, entry in pairs(migrated.raider.ledger or {}) do
            local amount = type(entry) == "table" and tonumber(entry.amount) or nil
            if amount and amount < 0 and entry.source == "MANUAL" then
                entry.amount = amount + 1
            end
        end
    end
    -- v3.0.4: rebuild the derived money-log fingerprints once. Earlier builds
    -- could mark a newly shifted/identical row as already seen even when no
    -- corresponding ledger entry had been created. The ledger itself is kept;
    -- current bank rows are rebound one-to-one by semantic matching.
    if previousSchema < 18 then migrated.raider.bankSeen = {} end
    migrated.raider.lastBankScan = tonumber(migrated.raider.lastBankScan) or 0
    migrated.raider.revision = tonumber(migrated.raider.revision) or 0
    migrated.treasury = migrated.treasury or { claims = {}, history = {}, seenTransactions = {}, lastBankScan = 0 }
    migrated.treasury.claims = migrated.treasury.claims or {}
    migrated.treasury.history = migrated.treasury.history or {}
    migrated.treasury.seenTransactions = migrated.treasury.seenTransactions or {}
    migrated.test = migrated.test or {}
    migrated.test.remoteProfiles = migrated.test.remoteProfiles or {}
    migrated.test.profileRevision = tonumber(migrated.test.profileRevision) or 0
    migrated.test.treasury = migrated.test.treasury or { claims = {}, history = {} }
    migrated.test.treasury.claims = migrated.test.treasury.claims or {}
    migrated.test.treasury.history = migrated.test.treasury.history or {}
    return migrated
end

function Storage:Initialize()
    BlackjackDB = MigrateOld(BlackjackDB or {})
    BlackjackDB = MergeDefaults(DEFAULTS, BlackjackDB)
    BlackjackDB.schema = 20
    BJ.db = BlackjackDB
    -- Identity is authoritative; localOwned from an account-wide cache is not.
    for _, entry in pairs(BJ.db.network.activities) do
        entry.owner = BJ:NormalizeName(entry.owner)
        entry.localOwned = entry.owner == BJ.player
        if entry.participants then
            local normalized = {}
            for name, joined in pairs(entry.participants) do normalized[BJ:NormalizeName(name)] = joined end
            entry.participants = normalized
        end
    end
    BJ.db.activityJoins = BJ.db.activityJoins or {}
    local previous = BJ.db.activityJoinCharacter
    if previous then BJ.db.activityJoins[previous] = BJ.db.joinedActivities end
    -- Legacy joinedActivities had no character identity; never assign another
    -- character's subscriptions to the current one during migration.
    BJ.db.joinedActivities = BJ.db.activityJoins[BJ.player] or {}
    BJ.db.activityJoins[BJ.player] = BJ.db.joinedActivities
    BJ.db.activityJoinCharacter = BJ.player

    -- v2.3 normalizes the local character name to Name-Realm. Preserve any profile
    -- saved by older builds under the short character name.
    local shortPlayer = BJ:ShortName(BJ.player)
    if not BJ.db.profiles[BJ.player] and shortPlayer and BJ.db.profiles[shortPlayer] then
        BJ.db.profiles[BJ.player] = BJ.db.profiles[shortPlayer]
        BJ.db.profiles[shortPlayer] = nil
    end

    BJ.db.profiles[BJ.player] = BJ.db.profiles[BJ.player] or {
        tagline = "",
        likes = "Mythic+, raid e serate di gilda",
        help = "",
        alts = "",
        titleId = "starter",
        badgeId = "",
    }
    BJ.profile = BJ.db.profiles[BJ.player]
    BJ.profile.titleId = BJ.profile.titleId or "starter"
    BJ.profile.badgeId = BJ.profile.badgeId or ""
end

function Storage:ResetPositions()
    BJ.db.ui.main = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    BJ.db.ui.hud = { point = "TOP", relativePoint = "TOP", x = 0, y = -115, width = 530, height = 42 }
end

function Storage:ResetWeeklyProgress()
    BJ.db.progress = {
        weekKey = BJ:GetWeekKey(),
        stats = {},
        sets = {},
    }
    if BJ.Challenges then BJ.Challenges:Refresh() end
end

function Storage:ResetNetworkCache()
    BJ.db.network.peers = {}
    BJ.db.network.profiles = {}
    for id, entry in pairs(BJ.db.network.activities) do
        -- Preserve activities owned by any character on this account.
        if not BJ.db.profiles[entry.owner] and entry.owner ~= BJ.player then
            BJ.db.network.activities[id] = nil
        end
    end
    BJ.db.network.summaries = {}
    BJ.db.network.craftingOrders = {}
    for id, order in pairs(BJ.db.crafting.owned) do
        BJ.db.network.craftingOrders[id] = order
    end
    -- Completion history also drives recovery broadcasts; keep lifecycle data.
    BJ.db.network.craftOffers = {}
    -- Tombstones are lifecycle guards, not disposable network cache. Clearing them
    -- would allow already completed/removed crafting orders to resurrect.
    BJ.db.network.craftingTombstones = BJ.db.network.craftingTombstones or {}
    if BJ.Comms then
        BJ.Comms.pendingActivityText = {}
        BJ.Comms.profileRequestAt = {}
        BJ.Comms:RequestActivities()
        BJ.Comms:Announce()
        BJ.Comms:BroadcastAll()
    end
end
