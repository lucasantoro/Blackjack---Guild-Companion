local _, BJ = ...

BJ.Crafting = {}
local Crafting = BJ.Crafting

Crafting.customerOpen = false
Crafting.lastStatus = nil
Crafting.lastRequestAt = 0
Crafting.lastClaimed = {}
Crafting.customerNames = {}
Crafting.lastCompletion = nil
Crafting.lastRemovalAt = 0
Crafting.pendingNotes = {}
Crafting.pendingOffers = {}
Crafting.pendingOffersAt = {}
Crafting.pendingWorkState = {}
Crafting.pendingCloses = {}
Crafting.mailOpen = false
Crafting.orderRequestSerial = 0
Crafting.listCallback = nil

local GUILD_ORDER = (Enum and Enum.CraftingOrderType and Enum.CraftingOrderType.Guild) or 1
local OK_RESULT = (Enum and Enum.CraftingOrderResult and Enum.CraftingOrderResult.Ok) or 0
local CUSTOMER_FULFILL_MAIL_REASON = (Enum and Enum.RcoCloseReason and Enum.RcoCloseReason.Fulfill) or 0

local function IsOk(result)
    return tonumber(result) == tonumber(OK_RESULT) or tonumber(result) == 0
end

local function OrderKey(orderID)
    if orderID == nil then return nil end
    return tostring(orderID)
end

local function IsActiveState(state)
    state = tonumber(state) or 0
    -- Fulfilled=11, Canceling=12, Canceled=13, Expiring=14, Expired=15.
    return state > 0 and state < 11
end

local function TerminalReason(state)
    state = tonumber(state) or 0
    if state == 11 then return "COMPLETATO" end
    if state == 12 then return "ANNULLAMENTO" end
    if state == 13 then return "ANNULLATO" end
    if state == 14 then return "SCADENZA" end
    if state == 15 then return "SCADUTO" end
    return "CHIUSO"
end

local function SafeItemName(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return "Oggetto sconosciuto" end
    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name and name ~= "" then return name end
    end
    if GetItemInfo then
        local name = GetItemInfo(itemID)
        if name and name ~= "" then return name end
    end
    return "Item #" .. tostring(itemID)
end

local function SafeItemIcon(itemID)
    itemID = tonumber(itemID) or 0
    if itemID > 0 and C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    if itemID > 0 and GetItemIcon then return GetItemIcon(itemID) end
    return "Interface\\Icons\\INV_Misc_Note_01"
end

local function CopyOrderForHistory(order, reason)
    local copy = {}
    for k, v in pairs(order or {}) do
        if type(v) ~= "table" then copy[k] = v end
    end
    copy.closedAt = BJ:Now()
    copy.closeReason = reason or "CLOSED"
    return copy
end

function Crafting:EnsureStore()
    BJ.db.crafting = BJ.db.crafting or { owned = {}, history = {}, joined = {}, lastRefresh = 0 }
    BJ.db.crafting.owned = BJ.db.crafting.owned or {}
    BJ.db.crafting.history = BJ.db.crafting.history or {}
    BJ.db.crafting.joined = BJ.db.crafting.joined or {}
    BJ.db.crafting.deliveries = BJ.db.crafting.deliveries or {}
    BJ.db.crafting.deliveryHistory = BJ.db.crafting.deliveryHistory or {}
    BJ.db.network.craftingOrders = BJ.db.network.craftingOrders or {}
    BJ.db.network.craftingHistory = BJ.db.network.craftingHistory or {}
    BJ.db.network.craftOffers = BJ.db.network.craftOffers or {}
    BJ.db.network.craftingTombstones = BJ.db.network.craftingTombstones or {}
end

local function SameShortName(a, b)
    if not a or not b or a == "" or b == "" then return false end
    return string.lower(BJ:ShortName(a)) == string.lower(BJ:ShortName(b))
end

local function GetInboxCountsSafe()
    if not GetInboxNumItems then return 0, 0 end
    -- GetInboxNumItems() returns TWO values (loaded, total). Passing the call
    -- directly to tonumber() accidentally forwards the second value as the numeric
    -- base and can raise "base out of range". Capture both values explicitly.
    local loaded, total = GetInboxNumItems()
    loaded = tonumber(loaded) or 0
    total = tonumber(total) or loaded
    return loaded, total
end

local function IsCustomerFulfillMail(info)
    if not info then return false end
    if tonumber(info.reason) ~= tonumber(CUSTOMER_FULFILL_MAIL_REASON) then return false end

    -- Fulfill is the CUSTOMER-side mail ("fulfilled by ..."). CrafterFulfill is the
    -- CRAFTER-side settlement mail and must never create a "ritira dalla posta" alert.
    local playerGUID = UnitGUID and UnitGUID("player") or nil
    if info.customerGUID and info.customerGUID ~= "" and playerGUID and info.customerGUID ~= playerGUID then
        return false
    end
    if info.customerName and info.customerName ~= "" and not SameShortName(info.customerName, BJ.player) then
        return false
    end
    return true
end

function Crafting:GetDeliveryStore()
    self:EnsureStore()
    BJ.db.crafting.deliveries[BJ.player] = BJ.db.crafting.deliveries[BJ.player] or {}
    return BJ.db.crafting.deliveries[BJ.player]
end

function Crafting:GetPendingDeliveries()
    local out = {}
    for _, delivery in pairs(self:GetDeliveryStore()) do
        if delivery and not delivery.collectedAt then out[#out + 1] = delivery end
    end
    table.sort(out, function(a, b)
        return (tonumber(a.completedAt) or 0) > (tonumber(b.completedAt) or 0)
    end)
    return out
end

function Crafting:GetPendingDeliveryCount()
    return #self:GetPendingDeliveries()
end

function Crafting:MarkDeliveryPending(id, order, crafter, source)
    id = OrderKey(id) or ("mail-" .. tostring(BJ:Now()))
    local store = self:GetDeliveryStore()
    local collected = BJ.db.crafting.deliveryHistory[id]
    if collected and collected.collectedAt then return false end
    local existing = store[id]
    if existing and not existing.collectedAt then
        if crafter and crafter ~= "" then existing.crafter = crafter end
        if order and tonumber(order.itemID) and tonumber(order.itemID) > 0 then existing.itemID = tonumber(order.itemID) end
        return false
    end

    local delivery = {
        id = id,
        itemID = tonumber(order and order.itemID) or 0,
        crafter = crafter or (order and order.workingBy) or "",
        completedAt = tonumber(order and order.completedAt) or BJ:Now(),
        seenInMailbox = false,
        lastSeenAt = 0,
        source = source or "CRAFT",
    }
    store[id] = delivery
    self.lastStatus = "Il tuo ordine di gilda e stato completato: ritira l'oggetto dalla posta."
    if BJ.db.settings.notifications ~= false then
        local crafterText = (delivery.crafter and delivery.crafter ~= "") and (" da " .. BJ:ShortName(delivery.crafter)) or ""
        BJ:Print("Il tuo craft |cfff0c868" .. SafeItemName(delivery.itemID) .. "|r e pronto" .. crafterText .. ". Ritiralo dalla posta.")
    end
    if BJ.HUD and BJ.HUD.FlashCraftDelivery then BJ.HUD:FlashCraftDelivery() end
    self:NotifyChanged()
    return true
end

function Crafting:CompleteDelivery(id, reason)
    local store = self:GetDeliveryStore()
    local delivery = store[id]
    if not delivery then return false end
    delivery.collectedAt = BJ:Now()
    delivery.collectReason = reason or "MAIL"
    BJ.db.crafting.deliveryHistory[id] = delivery
    store[id] = nil
    self.lastStatus = "Craft ritirato dalla posta: notifica completata."
    self:NotifyChanged()
    return true
end

function Crafting:ScanMailboxDeliveries()
    if not self.mailOpen then return false end
    if not GetInboxNumItems or not GetInboxItem then return false end

    local pending = self:GetPendingDeliveries()
    if #pending == 0 then return true end

    local matched = {}
    local num, total = GetInboxCountsSafe()
    local inboxComplete = total <= num
    local maxAttachments = tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16

    for mailIndex = 1, num do
        local info = C_Mail and C_Mail.GetCraftingOrderMailInfo and C_Mail.GetCraftingOrderMailInfo(mailIndex) or nil
        if IsCustomerFulfillMail(info) then
            for attachment = 1, maxAttachments do
                local _, itemID = GetInboxItem(mailIndex, attachment)
                itemID = tonumber(itemID) or 0
                if itemID > 0 then
                    for i = 1, #pending do
                        local delivery = pending[i]
                        if not matched[delivery.id]
                            and (tonumber(delivery.itemID) or 0) == itemID
                            and ((not delivery.crafter or delivery.crafter == "") or SameShortName(delivery.crafter, info.crafterName)) then
                            matched[delivery.id] = true
                            delivery.seenInMailbox = true
                            delivery.lastSeenAt = BJ:Now()
                            delivery.mailCrafter = info.crafterName
                            delivery.mailCrafterGUID = info.crafterGUID
                            delivery.mailRecipe = info.recipeName
                            delivery.mailReason = tonumber(info.reason)
                            break
                        end
                    end
                end
            end
        end
    end

    -- The inbox can arrive in multiple batches. Never interpret an item as collected
    -- while Blizzard still reports more mail than is currently loaded, otherwise a
    -- temporary partial snapshot can turn the HUD off incorrectly.
    if inboxComplete then
        local completed = {}
        for i = 1, #pending do
            local delivery = pending[i]
            -- A delivery is collected only after we positively saw its attachment in a
            -- CUSTOMER Fulfill mail and a later COMPLETE inbox snapshot no longer has it.
            if delivery.seenInMailbox and not matched[delivery.id] then
                completed[#completed + 1] = delivery.id
            end
        end
        for i = 1, #completed do self:CompleteDelivery(completed[i], "MAIL_ATTACHMENT_TAKEN") end
    end
    return true
end

function Crafting:DiscoverDeliveriesFromMailbox()
    if not self.mailOpen or not GetInboxNumItems or not GetInboxItem then return false end
    local store = self:GetDeliveryStore()
    local num = select(1, GetInboxCountsSafe())
    local maxAttachments = tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16
    local changed = false
    local usedDelivery = {}

    for mailIndex = 1, num do
        local info = C_Mail and C_Mail.GetCraftingOrderMailInfo and C_Mail.GetCraftingOrderMailInfo(mailIndex) or nil
        if IsCustomerFulfillMail(info) then
            for attachment = 1, maxAttachments do
                local _, itemID = GetInboxItem(mailIndex, attachment)
                itemID = tonumber(itemID) or 0
                if itemID > 0 then
                    local found = false
                    for key, d in pairs(store) do
                        if not usedDelivery[key]
                            and (tonumber(d.itemID) or 0) == itemID
                            and ((not d.crafter or d.crafter == "") or SameShortName(d.crafter, info.crafterName)) then
                            d.seenInMailbox = true
                            d.lastSeenAt = BJ:Now()
                            d.mailCrafter = info.crafterName
                            d.mailCrafterGUID = info.crafterGUID
                            d.mailRecipe = info.recipeName
                            d.mailReason = tonumber(info.reason)
                            usedDelivery[key] = true
                            found = true
                            break
                        end
                    end
                    if not found then
                        -- Offline recovery is deliberately restricted to CUSTOMER Fulfill
                        -- mail. CrafterFulfill is a commission/settlement mail for the
                        -- crafter and previously caused false POSTA notifications.
                        local synthetic = "mail:" .. tostring(info.crafterGUID or info.crafterName or "?") .. ":" .. tostring(itemID) .. ":" .. tostring(mailIndex)
                        store[synthetic] = {
                            id = synthetic,
                            itemID = itemID,
                            crafter = info.crafterName or "",
                            completedAt = BJ:Now(),
                            seenInMailbox = true,
                            lastSeenAt = BJ:Now(),
                            mailCrafter = info.crafterName,
                            mailCrafterGUID = info.crafterGUID,
                            mailRecipe = info.recipeName,
                            mailReason = tonumber(info.reason),
                            customerGUID = info.customerGUID,
                            source = "MAIL_RECOVERY",
                        }
                        changed = true
                    end
                end
            end
        end
    end
    if changed then
        if BJ.db.settings.notifications ~= false then BJ:Print("Hai un craft completato da ritirare nella posta.") end
        if BJ.HUD and BJ.HUD.FlashCraftDelivery then BJ.HUD:FlashCraftDelivery() end
        self:NotifyChanged()
    end
    return true
end

function Crafting:RefreshMailboxDeliveries()
    if not self.mailOpen then return end
    self:DiscoverDeliveriesFromMailbox()
    self:ScanMailboxDeliveries()
end

function Crafting:ResetSessionCache()
    self:EnsureStore()
    -- network.craftingOrders is a live peer cache, not authoritative storage. Keeping
    -- it across /reload, relog or character switches is what allows already completed
    -- remote jobs to survive forever on a crafter. Rebuild it from this character's
    -- own Blizzard orders, then CREQ repopulates remote orders from online owners.
    BJ.db.network.craftingOrders = {}
    BJ.db.network.craftOffers = {}

    if BJ.db.crafting.joinedCharacter ~= BJ.player then
        BJ.db.crafting.joined = {}
    end
    BJ.db.crafting.joinedCharacter = BJ.player

    for id, order in pairs(BJ.db.crafting.owned or {}) do
        if order.owner == BJ.player and IsActiveState(order.orderState)
            and ((tonumber(order.expirationTime) or 0) <= 0 or tonumber(order.expirationTime) > BJ:Now()) then
            BJ.db.network.craftingOrders[id] = order
        end
    end

    self.pendingNotes = {}
    self.pendingOffers = {}
    self.pendingOffersAt = {}
    self.pendingWorkState = {}
    self.pendingCloses = {}
    self.customerNames = {}
end

function Crafting:PurgeLegacyStationDeliveries()
    -- Old builds could incorrectly create POSTA notifications from fulfilled rows
    -- (source=MY_ORDERS) or from replayed CWORK state. Neither source is authoritative
    -- evidence that the customer still has an attachment to collect.
    self:EnsureStore()
    local removed = 0
    for _, store in pairs(BJ.db.crafting.deliveries or {}) do
        if type(store) == "table" then
            for id, delivery in pairs(store) do
                if type(delivery) == "table" and (delivery.source == "MY_ORDERS" or delivery.source == "CWORK") then
                    store[id] = nil
                    removed = removed + 1
                end
            end
        end
    end
    for id, delivery in pairs(BJ.db.crafting.deliveryHistory or {}) do
        if type(delivery) == "table" and (delivery.source == "MY_ORDERS" or delivery.source == "CWORK") then
            BJ.db.crafting.deliveryHistory[id] = nil
        end
    end
    if removed > 0 then
        self.lastStatus = tostring(removed) .. " vecchia/e notifica/he POSTA errata/e rimossa/e."
    end
    return removed
end

function Crafting:Initialize()
    self:EnsureStore()
    self:PurgeLegacyStationDeliveries()
    self:ResetSessionCache()
    self:Cleanup()

    BJ:RegisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER", function()
        Crafting.customerOpen = true
        C_Timer.After(0.15, function() Crafting:RequestMyOrders(true) end)
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_HIDE_CUSTOMER", function()
        Crafting.customerOpen = false
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE", function(_, result)
        if IsOk(result) then
            Crafting.lastStatus = "Ordine creato: lettura degli ordini di gilda in corso."
            C_Timer.After(0.20, function() Crafting:RequestMyOrders(true) end)
            C_Timer.After(0.90, function() Crafting:RequestMyOrders(true) end)
            C_Timer.After(2.00, function() Crafting:RequestMyOrders(true) end)
        end
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_ORDER_CANCEL_RESPONSE", function(_, result)
        if IsOk(result) then
            C_Timer.After(0.35, function() Crafting:RequestMyOrders(true) end)
            C_Timer.After(1.20, function() Crafting:RequestMyOrders(true) end)
            C_Timer.After(2.50, function() Crafting:RequestMyOrders(true) end)
        end
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_UPDATE_ORDER_COUNT", function(_, orderType)
        if tonumber(orderType) == tonumber(GUILD_ORDER) and Crafting.customerOpen then
            C_Timer.After(0.25, function() Crafting:RequestMyOrders(true) end)
        end
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_CLAIMED_ORDER_ADDED", function()
        Crafting:RememberClaimedOrder()
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_CLAIMED_ORDER_UPDATED", function()
        Crafting:RememberClaimedOrder()
    end)
    -- Retail may fill the customer name asynchronously. Blizzard's crafter UI
    -- listens to this event too; keep the orderID -> customer mapping so FULFILL
    -- can always address the personal completion notification.
    BJ:RegisterEvent("CRAFTINGORDERS_UPDATE_CUSTOMER_NAME", function(_, customerName, orderID)
        Crafting:RememberCustomerName(customerName, orderID)
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_CLAIMED_ORDER_REMOVED", function()
        -- Blizzard clears the claimed-order frame after fulfill/release/reject. The
        -- response events below carry the orderID, so this event is only a local
        -- reconciliation/refresh fallback and must not guess whether it was completed.
        Crafting.lastRemovalAt = BJ:Now()
        C_Timer.After(0.05, function() Crafting:NotifyChanged() end)
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_CLAIM_ORDER_RESPONSE", function(_, result, orderID)
        if IsOk(result) then C_Timer.After(0, function() Crafting:RememberClaimedOrder(orderID) end) end
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_CRAFT_ORDER_RESPONSE", function(_, result, orderID)
        if IsOk(result) then C_Timer.After(0, function() Crafting:RememberClaimedOrder(orderID) end) end
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", function(_, result, orderID)
        Crafting:OnFulfillResponse(result, orderID)
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_RELEASE_ORDER_RESPONSE", function(_, result, orderID)
        if IsOk(result) then
            Crafting:BroadcastWorkState(orderID, 2)
            Crafting.lastClaimed[OrderKey(orderID)] = nil
        end
    end)
    BJ:RegisterEvent("CRAFTINGORDERS_REJECT_ORDER_RESPONSE", function(_, result, orderID)
        if IsOk(result) then
            Crafting:BroadcastWorkState(orderID, 2)
            Crafting.lastClaimed[OrderKey(orderID)] = nil
        end
    end)
    BJ:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(5, function() Crafting:RequestState(false) end)
    end)
    BJ:RegisterEvent("MAIL_SHOW", function()
        Crafting.mailOpen = true
        C_Timer.After(0.25, function() Crafting:RefreshMailboxDeliveries() end)
        C_Timer.After(1.00, function() Crafting:RefreshMailboxDeliveries() end)
    end)
    BJ:RegisterEvent("MAIL_INBOX_UPDATE", function()
        if Crafting.mailOpen then C_Timer.After(0.20, function() Crafting:RefreshMailboxDeliveries() end) end
    end)
    BJ:RegisterEvent("MAIL_SUCCESS", function()
        if Crafting.mailOpen then C_Timer.After(0.30, function() Crafting:RefreshMailboxDeliveries() end) end
    end)
    BJ:RegisterEvent("MAIL_CLOSED", function()
        Crafting.mailOpen = false
        Crafting.orderRequestSerial = 0
        Crafting.listCallback = nil
    end)

    C_Timer.NewTicker(60, function()
        Crafting:Cleanup()
    end)
    C_Timer.NewTicker(180, function()
        if BJ.Access and BJ.Access:IsAuthorized() then Crafting:BroadcastState() end
    end)
    C_Timer.After(4.5, function() Crafting:RequestState(true) end)
end

function Crafting:IsAutoPublishEnabled()
    return BJ.db.settings.craftingAutoPublish ~= false
end

function Crafting:SetAutoPublish(enabled)
    enabled = enabled and true or false
    BJ.db.settings.craftingAutoPublish = enabled
    self.lastStatus = enabled and "Pubblicazione automatica ordini Guild attiva." or "Pubblicazione automatica ordini Guild disattivata."
    if enabled then
        self:RequestMyOrders(false)
        self:BroadcastState()
    elseif BJ.Comms and IsInGuild() then
        -- Ritira dalla bacheca di gilda le copie gia pubblicate, senza cancellare
        -- gli ordini reali o la copia locale del proprietario.
        for id, order in pairs(BJ.db.crafting.owned or {}) do
            if order.owner == BJ.player then
                BJ.Comms:SendSystem("CDEL", "GUILD", nil, id, "PUBBLICAZIONE OFF", BJ:Now())
            end
        end
    end
    if BJ.UI then BJ.UI:RefreshPage("CRAFTING") end
end

function Crafting:BuildSnapshot(order)
    if not order then return nil end
    local id = OrderKey(order.orderID)
    if not id then return nil end
    local previous = BJ.db.crafting.owned[id] or BJ.db.network.craftingOrders[id]
    local now = BJ:Now()
    return {
        id = id,
        owner = BJ.player,
        ownerGUID = (UnitGUID and UnitGUID("player")) or order.customerGuid or "",
        itemID = tonumber(order.itemID) or 0,
        spellID = tonumber(order.spellID) or 0,
        minQuality = tonumber(order.minQuality) or 0,
        tipAmount = tonumber(order.tipAmount) or 0,
        expirationTime = tonumber(order.expirationTime) or 0,
        reagentState = tonumber(order.reagentState) or 0,
        isRecraft = order.isRecraft and true or false,
        orderState = tonumber(order.orderState) or 0,
        notes = BJ:Utf8Truncate(order.customerNotes or "", 150),
        firstSeen = previous and previous.firstSeen or now,
        updated = now,
        localOwned = true,
    }
end

function Crafting:RecordMyOrderHistory(snapshot, reason)
    if not snapshot or not snapshot.id then return false end
    self:EnsureStore()
    local id = OrderKey(snapshot.id)
    local existing = BJ.db.crafting.history[id] or BJ.db.network.craftingHistory[id]
    local history = existing or {}
    local preservedClosedAt = tonumber(history.closedAt) or 0
    for k, v in pairs(snapshot) do
        if type(v) ~= "table" then history[k] = v end
    end
    history.id = id
    history.owner = history.owner or BJ.player
    history.localOwned = true
    history.closeReason = reason or TerminalReason(snapshot.orderState)
    history.closedAt = preservedClosedAt > 0 and preservedClosedAt or BJ:Now()
    history.source = history.source or "MY_ORDERS_HISTORY"
    BJ.db.crafting.history[id] = history
    BJ.db.network.craftingHistory[id] = history
    BJ.db.crafting.owned[id] = nil
    BJ.db.network.craftingOrders[id] = nil
    BJ.db.crafting.joined[id] = nil
    BJ.db.network.craftOffers[id] = nil
    self:AddTombstone(id, tonumber(snapshot.orderState) or 13, history.workingBy, history.closedAt)
    return true
end

function Crafting:Signature(order)
    return table.concat({
        tostring(order.itemID or 0), tostring(order.spellID or 0), tostring(order.minQuality or 0),
        tostring(order.tipAmount or 0), tostring(order.expirationTime or 0), tostring(order.reagentState or 0),
        order.isRecraft and "1" or "0", tostring(order.orderState or 0)
    }, ":")
end

function Crafting:RequestMyOrders(allowClose)
    if BJ.Access and not BJ.Access:IsAuthorized() then return false end
    if not C_CraftingOrders or not C_CraftingOrders.GetMyOrders or not C_CraftingOrders.ListMyOrders then
        self.lastStatus = "API Crafting Orders non disponibile."
        return false
    end
    if not C_FunctionContainers or not C_FunctionContainers.CreateCallback then
        self.lastStatus = "Callback Crafting Orders non disponibile."
        return false
    end

    -- GetMyOrders() is a client-side cache populated by ListMyOrders(). Never read it
    -- on an arbitrary timer: if the server reply is late that would re-process the
    -- previous/stale snapshot and resurrect orders that were already closed.
    self.orderRequestSerial = (tonumber(self.orderRequestSerial) or 0) + 1
    local serial = self.orderRequestSerial

    if self.listCallback and self.listCallback.Cancel then
        pcall(function() self.listCallback:Cancel() end)
    end
    self.listCallback = nil

    local function requestPage(offset)
        if serial ~= Crafting.orderRequestSerial then return end
        local callback
        callback = C_FunctionContainers.CreateCallback(function(result, expectMoreRows, responseOffset)
            if serial ~= Crafting.orderRequestSerial then return end
            if not IsOk(result) then
                Crafting.lastStatus = "Impossibile aggiornare gli ordini personali (result " .. tostring(result) .. ")."
                Crafting.listCallback = nil
                return
            end

            local orders = C_CraftingOrders.GetMyOrders() or {}
            local more = expectMoreRows and true or false
            -- Blizzard's own My Orders page requests further pages only after the
            -- previous callback has completed. Mirror that behaviour so our final
            -- reconciliation is based on one authoritative snapshot.
            if more then
                Crafting.listCallback = nil
                requestPage(#orders)
                return
            end

            Crafting.listCallback = nil
            Crafting:ProcessMyOrders(allowClose and true or false)
        end)
        Crafting.listCallback = callback

        local request = {
            primarySort = { sortType = (Enum and Enum.CraftingOrderSortType and Enum.CraftingOrderSortType.TimeRemaining) or 6, reversed = false },
            secondarySort = { sortType = (Enum and Enum.CraftingOrderSortType and Enum.CraftingOrderSortType.ItemName) or 0, reversed = false },
            offset = tonumber(offset) or 0,
            callback = callback,
        }
        local ok = pcall(C_CraftingOrders.ListMyOrders, request)
        if not ok then
            Crafting.listCallback = nil
            Crafting.lastStatus = "Richiesta ordini personali non riuscita."
            return false
        end
        Crafting.lastRequestAt = BJ:Now()
        return true
    end

    return requestPage(0)
end

function Crafting:ProcessMyOrders(allowClose)
    self:EnsureStore()
    if not C_CraftingOrders or not C_CraftingOrders.GetMyOrders then return false end
    local orders = C_CraftingOrders.GetMyOrders()
    if type(orders) ~= "table" then return false end

    local found = {}
    local published = 0
    local importedHistory = 0
    for i = 1, #orders do
        local order = orders[i]
        if order and tonumber(order.orderType) == tonumber(GUILD_ORDER) then
            local snapshot = self:BuildSnapshot(order)
            if snapshot then
                local expired = snapshot.expirationTime > 0 and snapshot.expirationTime <= BJ:Now()
                local active = IsActiveState(snapshot.orderState) and not expired
                if active then
                    -- Tombstones only suppress ACTIVE resurrection. A terminal row may
                    -- still be imported below into history without creating POSTA.
                    if self:HasTombstone(snapshot.id) then
                        BJ.db.crafting.owned[snapshot.id] = nil
                        BJ.db.network.craftingOrders[snapshot.id] = nil
                    else
                        found[snapshot.id] = true
                        local old = BJ.db.crafting.owned[snapshot.id]
                        local changed = not old or self:Signature(old) ~= self:Signature(snapshot) or (old.notes or "") ~= (snapshot.notes or "")
                        BJ.db.crafting.owned[snapshot.id] = snapshot
                        BJ.db.network.craftingOrders[snapshot.id] = snapshot
                        if changed and self:IsAutoPublishEnabled() then
                            self:BroadcastOrder(snapshot)
                            published = published + 1
                            if not old then
                                BJ:AddMoment("Nuovo ordine di gilda pubblicato: " .. SafeItemName(snapshot.itemID) .. ".", "CRAFT")
                            end
                        end
                    end
                else
                    -- Blizzard keeps fulfilled/cancelled rows in My Orders. They are
                    -- useful as HISTORY, but they are never proof of a new mail delivery.
                    -- Import/update them without calling MarkDeliveryPending().
                    found[snapshot.id] = true
                    local existed = BJ.db.crafting.history[snapshot.id] ~= nil or BJ.db.network.craftingHistory[snapshot.id] ~= nil
                    self:RecordMyOrderHistory(snapshot, expired and "SCADUTO" or TerminalReason(snapshot.orderState))
                    if not existed then importedHistory = importedHistory + 1 end
                end
            end
        end
    end

    if allowClose then
        local toClose = {}
        for id, ownedOrder in pairs(BJ.db.crafting.owned) do
            if ownedOrder.owner == BJ.player and not found[id] then toClose[#toClose + 1] = id end
        end
        for i = 1, #toClose do self:CloseOwnedOrder(toClose[i], "NON PIU ATTIVO", true) end
    end

    BJ.db.crafting.lastRefresh = BJ:Now()
    if published > 0 then
        self.lastStatus = published .. " ordine/i Guild pubblicato/i."
    elseif importedHistory > 0 then
        self.lastStatus = importedHistory .. " ordine/i completato/i importato/i nello storico."
    else
        self.lastStatus = "Ordini Guild aggiornati."
    end
    self:NotifyChanged()
    return true
end

function Crafting:BroadcastOrder(order)
    if not order or not BJ.Comms or not IsInGuild() or not self:IsAutoPublishEnabled() then return false end
    BJ.Comms:SendSystem("CRAFT", "GUILD", nil,
        order.id, order.itemID or 0, order.spellID or 0, order.minQuality or 0,
        order.tipAmount or 0, order.expirationTime or 0, order.reagentState or 0,
        order.isRecraft and 1 or 0, order.orderState or 0, order.firstSeen or BJ:Now(), order.ownerGUID or "")
    local safeNote = BJ:Utf8Truncate(order.notes or "", 150):gsub("|", "/")
    BJ.Comms:Queue("BJCRAFTNOTE " .. tostring(order.id) .. " " .. safeNote, "GUILD", nil, true)
    return true
end

function Crafting:BroadcastState()
    self:EnsureStore()
    if self:IsAutoPublishEnabled() then
        for _, order in pairs(BJ.db.crafting.owned) do
            if order.owner == BJ.player and IsActiveState(order.orderState)
                and (order.expirationTime <= 0 or order.expirationTime > BJ:Now()) then
                self:BroadcastOrder(order)
            end
        end
    end
    -- A crafter repeats recently completed orders for a while. This acts as a
    -- recovery path when the owner's client missed the first completion packet;
    -- otherwise that owner could keep re-announcing a stale active order.
    local now = BJ:Now()
    for id, order in pairs(BJ.db.network.craftingHistory or {}) do
        if order.closeReason == "COMPLETATO" and order.workingBy == BJ.player
            and now - (tonumber(order.closedAt) or 0) <= 1800 then
            self:SendWorkState(id, 11)
        end
    end
    self:BroadcastOwnOffers()
end

function Crafting:RequestState(force)
    if not BJ.Comms or not IsInGuild() then return false end
    local now = BJ:Now()
    if not force and now - (tonumber(self.lastStateRequestAt) or 0) < 12 then return false end
    self.lastStateRequestAt = now
    BJ.Comms:SendSystem("CREQ", "GUILD")
    return true
end

function Crafting:AddTombstone(id, state, worker, closedAt)
    self:EnsureStore()
    id = OrderKey(id)
    if not id then return end
    BJ.db.network.craftingTombstones[id] = {
        state = tonumber(state) or 0,
        worker = worker,
        closedAt = tonumber(closedAt) or BJ:Now(),
    }
end

function Crafting:HasTombstone(id)
    self:EnsureStore()
    id = OrderKey(id)
    local t = id and BJ.db.network.craftingTombstones[id]
    if not t then return false end
    if BJ:Now() - (tonumber(t.closedAt) or 0) > 90 * 86400 then
        BJ.db.network.craftingTombstones[id] = nil
        return false
    end
    return true
end

function Crafting:HandleRemoteOrder(sender, fields)
    self:EnsureStore()
    local id = fields[3]
    if not id then return end
    -- A terminal state always wins over a later/stale CRAFT announcement.
    -- This prevents completed orders from being resurrected by the owner's
    -- periodic broadcast when the owner missed the original completion packet.
    if self:HasTombstone(id) then return end
    local expires = tonumber(fields[8]) or 0
    local state = tonumber(fields[11]) or 0
    if expires > 0 and expires <= BJ:Now() then return end
    if not IsActiveState(state) then return end

    sender = (BJ.Guild and BJ.Guild:ResolveMember(sender)) or BJ:NormalizeName(sender) or sender
    if not sender then return end
    local old = BJ.db.network.craftingOrders[id]
    if old and old.owner ~= sender then return end
    local isNew = old == nil
    local order = old or {}
    order.id = id
    order.owner = sender
    order.itemID = tonumber(fields[4]) or 0
    order.spellID = tonumber(fields[5]) or 0
    order.minQuality = tonumber(fields[6]) or 0
    order.tipAmount = tonumber(fields[7]) or 0
    order.expirationTime = expires
    order.reagentState = tonumber(fields[9]) or 0
    order.isRecraft = tonumber(fields[10]) == 1
    order.orderState = state
    order.firstSeen = tonumber(fields[12]) or order.firstSeen or BJ:Now()
    order.ownerGUID = (fields[13] and fields[13] ~= "") and fields[13] or order.ownerGUID or ""
    order.updated = BJ:Now()
    order.localOwned = sender == BJ.player
    BJ.db.network.craftingOrders[id] = order

    -- Network packets can legitimately arrive in a different order. Reconcile any
    -- note/offer/work/close packet that reached this client before the CRAFT row.
    local pendingClose = self.pendingCloses[id]
    if pendingClose and pendingClose.sender == sender then
        self.pendingCloses[id] = nil
        self:HandleRemoteClose(sender, id, pendingClose.reason, pendingClose.closedAt)
        return
    end

    local pendingNote = self.pendingNotes[id]
    if pendingNote and pendingNote.sender == sender then
        order.notes = pendingNote.note
        self.pendingNotes[id] = nil
    end

    local pendingOffers = self.pendingOffers[id]
    if pendingOffers then
        local offers = BJ.db.network.craftOffers[id] or {}
        for name, interested in pairs(pendingOffers) do
            if interested then offers[name] = true else offers[name] = nil end
        end
        BJ.db.network.craftOffers[id] = offers
        self.pendingOffers[id] = nil
        self.pendingOffersAt[id] = nil
    end

    local pendingWork = self.pendingWorkState[id]
    if pendingWork then
        self.pendingWorkState[id] = nil
        self:ApplyWorkState(pendingWork.sender, id, pendingWork.state, pendingWork.owner, pendingWork.itemID)
        if not BJ.db.network.craftingOrders[id] then return end
    end

    if isNew and BJ.db.settings.notifications ~= false and sender ~= BJ.player then
        BJ:Print("Nuovo ordine Guild: |cffffffff" .. SafeItemName(order.itemID) .. "|r da " .. BJ:ShortName(sender) .. ".")
    end
    if BJ.db.crafting.joined[id] and BJ.Comms then
        C_Timer.After(0.25 + math.random() * 0.4, function()
            if BJ.Crafting and BJ.db.crafting.joined[id] then BJ.Crafting:BroadcastOffer(id, true) end
        end)
    end
    self:NotifyChanged()
end

function Crafting:HandleRemoteNote(sender, id, notes)
    self:EnsureStore()
    id = OrderKey(id)
    if not id then return false end
    local normalized = (BJ.Guild and BJ.Guild:ResolveMember(sender)) or BJ:NormalizeName(sender) or sender
    if not normalized then return false end
    local safeNote = BJ:Utf8Truncate(notes or "", 150)
    local order = BJ.db.network.craftingOrders[id]
    if not order then
        self.pendingNotes[id] = { sender = normalized, note = safeNote, at = BJ:Now() }
        return true
    end
    if normalized ~= order.owner then return false end
    order.notes = safeNote
    order.updated = BJ:Now()
    self:NotifyChanged()
    return true
end

function Crafting:CloseOwnedOrder(id, reason, broadcast)
    self:EnsureStore()
    id = OrderKey(id)
    local order = id and (BJ.db.crafting.owned[id] or BJ.db.network.craftingOrders[id])
    if not order then return false end
    local history = CopyOrderForHistory(order, reason)
    BJ.db.crafting.history[id] = history
    BJ.db.network.craftingHistory[id] = history
    BJ.db.crafting.owned[id] = nil
    BJ.db.network.craftingOrders[id] = nil
    BJ.db.crafting.joined[id] = nil
    BJ.db.network.craftOffers[id] = nil
    self:AddTombstone(id, tonumber(order.orderState) or 13, order.workingBy, history.closedAt)
    if broadcast and BJ.Comms then BJ.Comms:SendSystem("CDEL", "GUILD", nil, id, reason or "CLOSED", BJ:Now()) end
    self:NotifyChanged()
    return true
end

function Crafting:HandleRemoteClose(sender, id, reason, closedAt)
    self:EnsureStore()
    id = OrderKey(id)
    if not id then return end
    local normalized = (BJ.Guild and BJ.Guild:ResolveMember(sender)) or BJ:NormalizeName(sender) or sender
    if not normalized then return end
    local order = BJ.db.network.craftingOrders[id]
    if not order then
        -- Ignore our own echo after the local close already removed the row. For
        -- remote senders keep the close briefly so it can beat an out-of-order CRAFT.
        if normalized ~= BJ.player then
            self.pendingCloses[id] = { sender = normalized, reason = reason, closedAt = tonumber(closedAt) or BJ:Now(), at = BJ:Now() }
        end
        return
    end
    if normalized ~= order.owner then return end

    -- Turning automatic publication off only withdraws the Blackjack copy; the
    -- real Blizzard order still exists and may be published again later.
    if reason == "PUBBLICAZIONE OFF" then
        BJ.db.network.craftingOrders[id] = nil
        BJ.db.crafting.joined[id] = nil
        BJ.db.network.craftOffers[id] = nil
        self:NotifyChanged()
        return
    end

    local history = CopyOrderForHistory(order, reason)
    history.closedAt = tonumber(closedAt) or BJ:Now()
    BJ.db.network.craftingHistory[id] = history
    BJ.db.network.craftingOrders[id] = nil
    BJ.db.crafting.joined[id] = nil
    BJ.db.network.craftOffers[id] = nil
    self:AddTombstone(id, tonumber(order.orderState) or 13, order.workingBy, history.closedAt)
    self:NotifyChanged()
end

function Crafting:BroadcastOffer(id, interested)
    if not BJ.Comms or not IsInGuild() then return end
    BJ.Comms:SendSystem("COFFER", "GUILD", nil, id, interested and 1 or 0)
end

function Crafting:ToggleOffer(id)
    self:EnsureStore()
    local order = BJ.db.network.craftingOrders[id]
    if not order or order.owner == BJ.player then return false end
    local joined = not not BJ.db.crafting.joined[id]
    if joined then
        BJ.db.crafting.joined[id] = nil
        self:BroadcastOffer(id, false)
    else
        BJ.db.crafting.joined[id] = true
        self:BroadcastOffer(id, true)
    end
    self:NotifyChanged()
    return true
end

function Crafting:BroadcastOwnOffers()
    for id in pairs(BJ.db.crafting.joined or {}) do
        if BJ.db.network.craftingOrders[id] then self:BroadcastOffer(id, true) end
    end
end

function Crafting:HandleOffer(sender, id, interested)
    self:EnsureStore()
    id = OrderKey(id)
    if not id then return end
    sender = (BJ.Guild and BJ.Guild:ResolveMember(sender)) or BJ:NormalizeName(sender) or sender
    if not sender then return end
    local value = tonumber(interested) == 1
    if not BJ.db.network.craftingOrders[id] then
        self.pendingOffers[id] = self.pendingOffers[id] or {}
        self.pendingOffers[id][sender] = value
        self.pendingOffersAt[id] = self.pendingOffersAt[id] or BJ:Now()
        return
    end
    local offers = BJ.db.network.craftOffers[id] or {}
    if value then offers[sender] = true else offers[sender] = nil end
    BJ.db.network.craftOffers[id] = offers
    self:NotifyChanged()
end

function Crafting:GetInterested(id)
    self:EnsureStore()
    local out = {}
    for name in pairs(BJ.db.network.craftOffers[id] or {}) do out[#out + 1] = name end
    table.sort(out, function(a, b) return BJ:ShortName(a) < BJ:ShortName(b) end)
    return out
end

function Crafting:GetInterestedCount(id)
    self:EnsureStore()
    return BJ:CountTable(BJ.db.network.craftOffers[id])
end

function Crafting:IsInterested(id)
    self:EnsureStore()
    return BJ.db.crafting.joined[id] and true or false
end

function Crafting:GetOwnedCount()
    self:EnsureStore()
    local count = 0
    for _, order in pairs(BJ.db.crafting.owned or {}) do
        if order.owner == BJ.player and IsActiveState(order.orderState)
            and ((tonumber(order.expirationTime) or 0) <= 0 or tonumber(order.expirationTime) > BJ:Now()) then
            count = count + 1
        end
    end
    return count
end

function Crafting:GetActiveOrders()
    self:EnsureStore()
    self:Cleanup()
    local out = {}
    for id, order in pairs(BJ.db.network.craftingOrders) do
        if IsActiveState(order.orderState) and not self:HasTombstone(id) then
            out[#out + 1] = order
        end
    end
    table.sort(out, function(a, b)
        local as = tonumber(a.orderState) or 0
        local bs = tonumber(b.orderState) or 0
        local ap = (as == 2) and 0 or 1
        local bp = (bs == 2) and 0 or 1
        if ap ~= bp then return ap < bp end
        local ae = tonumber(a.expirationTime) or math.huge
        local be = tonumber(b.expirationTime) or math.huge
        if ae ~= be then return ae < be end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

function Crafting:GetHistory()
    self:EnsureStore()
    local out = {}
    for _, order in pairs(BJ.db.network.craftingHistory) do out[#out + 1] = order end
    table.sort(out, function(a, b) return (tonumber(a.closedAt) or 0) > (tonumber(b.closedAt) or 0) end)
    return out
end

function Crafting:Cleanup()
    if not BJ.db then return end
    self:EnsureStore()
    local now = BJ:Now()
    local stale = {}
    for id, order in pairs(BJ.db.network.craftingOrders) do
        local state = tonumber(order.orderState) or 0
        local expired = order.expirationTime and order.expirationTime > 0 and order.expirationTime <= now
        if expired or not IsActiveState(state) or self:HasTombstone(id) then
            stale[#stale + 1] = {
                id = id,
                owned = order.owner == BJ.player,
                state = state,
                reason = expired and "SCADUTO" or TerminalReason(state),
            }
        end
    end
    for i = 1, #stale do
        local row = stale[i]
        if row.owned then
            self:CloseOwnedOrder(row.id, row.reason, true)
        else
            local order = BJ.db.network.craftingOrders[row.id]
            if order then
                local history = CopyOrderForHistory(order, row.reason)
                history.orderState = row.state
                BJ.db.network.craftingHistory[row.id] = history
                BJ.db.network.craftingOrders[row.id] = nil
                BJ.db.network.craftOffers[row.id] = nil
                BJ.db.crafting.joined[row.id] = nil
                self:AddTombstone(row.id, row.state, order.workingBy, history.closedAt)
            end
        end
    end

    -- Bound recovery metadata so SavedVariables cannot grow indefinitely.
    for id, tombstone in pairs(BJ.db.network.craftingTombstones) do
        if now - (tonumber(tombstone.closedAt) or 0) > 90 * 86400 then
            BJ.db.network.craftingTombstones[id] = nil
        end
    end
    for id, claimed in pairs(self.lastClaimed) do
        if now - (tonumber(claimed.savedAt) or 0) > 600 then self.lastClaimed[id] = nil end
    end
    for id, row in pairs(self.customerNames or {}) do
        if now - (tonumber(row.at) or 0) > 900 then self.customerNames[id] = nil end
    end
    for id, row in pairs(self.pendingNotes) do
        if now - (tonumber(row.at) or 0) > 300 then self.pendingNotes[id] = nil end
    end
    for id in pairs(self.pendingOffers) do
        if now - (tonumber(self.pendingOffersAt[id]) or 0) > 300 then
            self.pendingOffers[id] = nil
            self.pendingOffersAt[id] = nil
        end
    end
    for id, row in pairs(self.pendingWorkState) do
        if now - (tonumber(row.at) or 0) > 300 then self.pendingWorkState[id] = nil end
    end
    for id, row in pairs(self.pendingCloses) do
        if now - (tonumber(row.at) or 0) > 300 then self.pendingCloses[id] = nil end
    end

    local history = self:GetHistory()
    for i = 31, #history do
        if history[i] and history[i].id then BJ.db.network.craftingHistory[history[i].id] = nil end
    end
    local deliveries = self:GetDeliveryStore()
    for id, delivery in pairs(deliveries) do
        if now - (tonumber(delivery.completedAt) or now) > 30 * 86400 then deliveries[id] = nil end
    end
    for id, delivery in pairs(BJ.db.crafting.deliveryHistory or {}) do
        if now - (tonumber(delivery.collectedAt) or now) > 30 * 86400 then BJ.db.crafting.deliveryHistory[id] = nil end
    end
    if #stale > 0 then self:NotifyChanged() end
end

function Crafting:PrintDiagnostics()
    self:EnsureStore()
    local pending = self:GetPendingDeliveries()
    local myGUID = UnitGUID and UnitGUID("player") or "?"
    BJ:Print("Craft diag v" .. tostring(BJ.version) .. " | GUID " .. tostring(myGUID) .. " | POSTA " .. tostring(#pending) .. " | mailOpen=" .. tostring(self.mailOpen))
    BJ:Print("Ultimo stato: " .. tostring(self.lastStatus or "-") .. " | ultimo RX=" .. tostring(BJ.Comms and BJ.Comms.lastReceiveKind or "-"))
    if self.lastCompletion then
        BJ:Print("Ultimo fulfill: id=" .. tostring(self.lastCompletion.id) .. " target=" .. tostring(self.lastCompletion.customer or "") .. " guid=" .. tostring(self.lastCompletion.customerGUID or "") .. " item=" .. tostring(self.lastCompletion.itemID or 0))
    end
    for i = 1, math.min(#pending, 5) do
        local d = pending[i]
        BJ:Print("POSTA " .. i .. ": id=" .. tostring(d.id) .. " item=" .. tostring(d.itemID or 0) .. " source=" .. tostring(d.source or "?") .. " seen=" .. tostring(d.seenInMailbox))
    end
end

function Crafting:ResetAllLocalData()
    self:EnsureStore()
    local now = BJ:Now()
    local suppressed = 0

    -- Preserve anti-resurrection markers. Also mark every Guild order currently
    -- present in Blizzard's local My Orders cache: this is the important part for a
    -- user who explicitly wants to forget legacy/stale rows that the client may keep
    -- returning when the station is reopened.
    local function suppress(id, state, worker)
        id = OrderKey(id)
        if not id then return end
        if not BJ.db.network.craftingTombstones[id] then suppressed = suppressed + 1 end
        self:AddTombstone(id, tonumber(state) or 13, worker, now)
    end

    for id, order in pairs(BJ.db.crafting.owned or {}) do
        if order.owner == BJ.player then suppress(id, order.orderState, order.workingBy) end
    end
    for id, order in pairs(BJ.db.network.craftingOrders or {}) do
        if order.owner == BJ.player then suppress(id, order.orderState, order.workingBy) end
    end
    if C_CraftingOrders and C_CraftingOrders.GetMyOrders then
        local ok, orders = pcall(C_CraftingOrders.GetMyOrders)
        if ok and type(orders) == "table" then
            for i = 1, #orders do
                local order = orders[i]
                if order and tonumber(order.orderType) == tonumber(GUILD_ORDER) then
                    suppress(order.orderID, order.orderState, order.crafterName)
                end
            end
        end
    end

    BJ.db.crafting.owned = {}
    BJ.db.crafting.history = {}
    BJ.db.crafting.joined = {}
    BJ.db.crafting.joinedCharacter = BJ.player
    BJ.db.crafting.lastRefresh = 0
    BJ.db.crafting.deliveries = {}
    BJ.db.crafting.deliveryHistory = {}
    BJ.db.crafting.resetAt = now

    BJ.db.network.craftingOrders = {}
    BJ.db.network.craftingHistory = {}
    BJ.db.network.craftOffers = {}
    -- Deliberately keep craftingTombstones: they are not cosmetic cache; they are
    -- what stops a stale local/API/network row from coming back after this reset.

    self.lastClaimed = {}
    self.customerNames = {}
    self.lastCompletion = nil
    self.pendingNotes = {}
    self.pendingOffers = {}
    self.pendingOffersAt = {}
    self.pendingWorkState = {}
    self.pendingCloses = {}
    self.orderRequestSerial = (tonumber(self.orderRequestSerial) or 0) + 1
    if self.listCallback and self.listCallback.Cancel then pcall(function() self.listCallback:Cancel() end) end
    self.listCallback = nil

    self.lastStatus = "Reset Crafting completato: " .. tostring(suppressed) .. " vecchi ID ignorati. I nuovi ordini avranno nuovi ID e saranno rilevati normalmente."
    self:NotifyChanged()
    return suppressed
end

function Crafting:NotifyChanged()
    if BJ.UI then
        BJ.UI:RefreshPage("CRAFTING")
        BJ.UI:RefreshPage("HOME")
    end
    if BJ.HUD then BJ.HUD:Refresh() end
end

function Crafting:GetItemName(order)
    return SafeItemName(order and order.itemID)
end

function Crafting:GetItemIcon(order)
    return SafeItemIcon(order and order.itemID)
end

function Crafting:GetStateLabel(order)
    local state = tonumber(order and order.orderState) or 0
    if state == 2 then return "DISPONIBILE" end
    if state >= 3 and state <= 10 then return "IN LAVORAZIONE" end
    if state == 11 then return "COMPLETATO" end
    if state >= 12 then return "CHIUSO" end
    return "ORDINE"
end

function Crafting:GetReagentLabel(order)
    local state = tonumber(order and order.reagentState) or 0
    if state == 0 then return "tutti forniti" end
    if state == 1 then return "parziali" end
    if state == 2 then return "a carico crafter" end
    return "non specificati"
end

function Crafting:FormatMoney(copper)
    copper = math.max(0, tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if gold > 0 then return string.format("%dg %02ds", gold, silver) end
    if silver > 0 then return string.format("%ds %02dc", silver, c) end
    return tostring(c) .. "c"
end

function Crafting:SendWorkState(orderID, state, owner, itemID)
    local id = OrderKey(orderID)
    if not id or not BJ.Comms or not IsInGuild() then return false end

    -- Terminal packets must carry enough information for the customer to react even
    -- if their active-order cache was already cleared by Blizzard before CWORK arrives.
    local meta = self.lastClaimed[id]
        or BJ.db.network.craftingOrders[id]
        or BJ.db.crafting.owned[id]
        or BJ.db.network.craftingHistory[id]
        or BJ.db.crafting.history[id]
    owner = owner or (meta and (meta.owner or meta.customerName))
    itemID = tonumber(itemID) or tonumber(meta and meta.itemID) or 0
    if owner and owner ~= "" and BJ.Guild and BJ.Guild.ResolveMember then
        owner = BJ.Guild:ResolveMember(owner) or owner
    end

    BJ.Comms:SendSystem("CWORK", "GUILD", nil, id, tonumber(state) or 0, owner or "", itemID)
    return true
end

function Crafting:ApplyWorkState(sender, id, state, payloadOwner, payloadItemID)
    self:EnsureStore()
    id = OrderKey(id)
    if not id then return false end
    sender = (BJ.Guild and BJ.Guild:ResolveMember(sender)) or BJ:NormalizeName(sender) or sender
    if not sender then return false end
    state = tonumber(state) or 0
    local order = BJ.db.network.craftingOrders[id]

    local resolvedOwner = nil
    if payloadOwner and payloadOwner ~= "" then
        resolvedOwner = (BJ.Guild and BJ.Guild:ResolveMember(payloadOwner)) or BJ:NormalizeName(payloadOwner) or payloadOwner
    end
    local itemID = tonumber(payloadItemID) or tonumber(order and order.itemID) or 0

    if state >= 11 then
        -- Record the terminal state only from the crafter who actually claimed the
        -- order when that information is known. Compare normalized short names too,
        -- because connected-realm formatting can differ between API surfaces.
        if order and order.workingBy and not SameShortName(order.workingBy, sender) then return false end

        local isMine = order and order.owner == BJ.player
        if not isMine and resolvedOwner then
            isMine = resolvedOwner == BJ.player
        end
        if not isMine and payloadOwner and payloadOwner ~= "" then
            local resolved = BJ.Guild and BJ.Guild.ResolveMember and BJ.Guild:ResolveMember(payloadOwner) or nil
            if resolved then isMine = resolved == BJ.player
            elseif BJ:ShortName(payloadOwner) == BJ:ShortName(BJ.player) then isMine = true end
        end

        -- CWORK is board/history state only. It must NEVER create a POSTA alert.
        -- Completion packets are intentionally replayed for reconciliation, so using
        -- CWORK as a delivery signal resurrected old "da ritirare" notifications.

        -- The tombstone prevents a stale owner broadcast from resurrecting the order.
        self:AddTombstone(id, state, sender, BJ:Now())
        if order then
            local history = CopyOrderForHistory(order, TerminalReason(state))
            history.closedAt = BJ:Now()
            history.workingBy = sender
            history.orderState = state
            BJ.db.network.craftingHistory[id] = history
            if order.owner == BJ.player then
                BJ.db.crafting.history[id] = history
                BJ.db.crafting.owned[id] = nil
            end
            BJ.db.network.craftingOrders[id] = nil
            BJ.db.network.craftOffers[id] = nil
            BJ.db.crafting.joined[id] = nil
        else
            -- The active row may already have disappeared locally. Preserve/update an
            -- existing historical row rather than dropping the terminal information.
            local history = BJ.db.crafting.history[id] or BJ.db.network.craftingHistory[id]
            if history then
                history.orderState = state
                history.closeReason = TerminalReason(state)
                history.workingBy = sender
                history.closedAt = tonumber(history.closedAt) or BJ:Now()
                if itemID > 0 then history.itemID = itemID end
                if resolvedOwner then history.owner = resolvedOwner end
                BJ.db.network.craftingHistory[id] = history
                if isMine then BJ.db.crafting.history[id] = history end
            end
        end
        self:NotifyChanged()
        return true
    end

    if not order then
        self.pendingWorkState[id] = { sender = sender, state = state, owner = resolvedOwner, itemID = itemID, at = BJ:Now() }
        return true
    end
    order.orderState = state
    order.workingBy = state >= 3 and sender or nil
    order.updated = BJ:Now()
    self:NotifyChanged()
    return true
end

function Crafting:BroadcastWorkState(orderID, state, owner, itemID)
    local id = OrderKey(orderID)
    if not id then return false end
    -- Apply locally first, then broadcast. Owner/itemID travel with the packet so the
    -- customer's notification no longer depends on still having the active row cached.
    self:ApplyWorkState(BJ.player, id, state, owner, itemID)
    return self:SendWorkState(id, state, owner, itemID)
end

function Crafting:HandleWorkState(sender, id, state, owner, itemID)
    self:ApplyWorkState(sender, id, state, owner, itemID)
end

function Crafting:RememberCustomerIdentity(customerName, orderID, customerGUID)
    local id = OrderKey(orderID)
    if not id then return false end
    local row = self.customerNames[id] or {}
    if customerName and customerName ~= "" then
        row.name = (BJ.Guild and BJ.Guild.ResolveMember and BJ.Guild:ResolveMember(customerName))
            or BJ:NormalizeName(customerName) or customerName
    end
    if customerGUID and customerGUID ~= "" then row.guid = customerGUID end
    if not row.name and not row.guid then return false end
    row.at = BJ:Now()
    self.customerNames[id] = row
    if self.lastClaimed[id] then
        if row.name then self.lastClaimed[id].customerName = row.name end
        if row.guid then self.lastClaimed[id].customerGUID = row.guid end
    end
    return true
end

function Crafting:RememberCustomerName(customerName, orderID)
    return self:RememberCustomerIdentity(customerName, orderID, nil)
end

function Crafting:GetRememberedCustomerName(orderID)
    local id = OrderKey(orderID)
    local row = id and self.customerNames[id] or nil
    if row and BJ:Now() - (tonumber(row.at) or 0) <= 900 then return row.name end
    return nil
end

function Crafting:GetRememberedCustomerGUID(orderID)
    local id = OrderKey(orderID)
    local row = id and self.customerNames[id] or nil
    if row and BJ:Now() - (tonumber(row.at) or 0) <= 900 then return row.guid end
    return nil
end

function Crafting:SendDeliveryReady(orderID, customer, itemID, customerGUID)
    local id = OrderKey(orderID)
    if not id or not BJ.Comms or not IsInGuild() then return false end
    local resolved = nil
    if customer and customer ~= "" then
        resolved = (BJ.Guild and BJ.Guild.ResolveMember and BJ.Guild:ResolveMember(customer))
            or BJ:NormalizeName(customer) or customer
    end
    customerGUID = customerGUID or self:GetRememberedCustomerGUID(id) or ""
    if (not resolved or resolved == "") and customerGUID == "" then return false end

    -- GUILD transport is deliberate for cross/connected-realm guilds. The payload is
    -- personal: every client receives it, but only the matching GUID/name accepts it.
    if BJ.Comms.SendPrioritySystem then
        return BJ.Comms:SendPrioritySystem("CREADY", "GUILD", nil, id, resolved or "", tonumber(itemID) or 0, BJ:Now(), customerGUID)
    end
    return BJ.Comms:SendSystem("CREADY", "GUILD", nil, id, resolved or "", tonumber(itemID) or 0, BJ:Now(), customerGUID)
end

function Crafting:HandleDeliveryReady(sender, orderID, customer, itemID, completedAt, customerGUID)
    local id = OrderKey(orderID)
    if not id then return false end

    local myGUID = UnitGUID and UnitGUID("player") or nil
    local hasTargetGUID = customerGUID and customerGUID ~= ""
    local isMine = false
    if hasTargetGUID and myGUID then
        isMine = customerGUID == myGUID
    elseif customer and customer ~= "" then
        local resolved = (BJ.Guild and BJ.Guild.ResolveMember and BJ.Guild:ResolveMember(customer))
            or BJ:NormalizeName(customer) or customer
        isMine = resolved == BJ.player or SameShortName(resolved, BJ.player) or SameShortName(customer, BJ.player)
    end
    if not isMine then return false end

    local order = BJ.db.network.craftingOrders[id]
        or BJ.db.crafting.owned[id]
        or BJ.db.crafting.history[id]
        or BJ.db.network.craftingHistory[id]
        or { id = id, owner = BJ.player, itemID = tonumber(itemID) or 0, orderState = 11 }
    if (tonumber(order.itemID) or 0) <= 0 then order.itemID = tonumber(itemID) or 0 end
    order.customerGUID = customerGUID or order.customerGUID
    order.completedAt = tonumber(completedAt) or BJ:Now()
    return self:MarkDeliveryPending(id, order, sender, "CREADY")
end

function Crafting:RememberClaimedOrder(fallbackOrderID)
    local order = C_CraftingOrders and C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder() or nil
    local id = order and OrderKey(order.orderID) or OrderKey(fallbackOrderID)
    if not id then return end

    if order and tonumber(order.orderType) == tonumber(GUILD_ORDER) then
        self.lastClaimed[id] = {
            id = id,
            itemID = tonumber(order.itemID) or 0,
            orderType = tonumber(order.orderType),
            customerName = order.customerName or self:GetRememberedCustomerName(id),
            customerGUID = order.customerGuid or self:GetRememberedCustomerGUID(id),
            savedAt = BJ:Now(),
        }
        self:RememberCustomerIdentity(order.customerName, id, order.customerGuid)
        local cached = BJ.db.network.craftingOrders[id]
        if cached then
            if (tonumber(self.lastClaimed[id].itemID) or 0) <= 0 then self.lastClaimed[id].itemID = tonumber(cached.itemID) or 0 end
            if not self.lastClaimed[id].customerName or self.lastClaimed[id].customerName == "" then
                self.lastClaimed[id].customerName = cached.owner
            end
            if not self.lastClaimed[id].customerGUID or self.lastClaimed[id].customerGUID == "" then
                self.lastClaimed[id].customerGUID = cached.ownerGUID
            end
        end
        self:BroadcastWorkState(id, tonumber(order.orderState) or 4)
        return
    end

    -- Fallback for event timing where GetClaimedOrder() has already changed but the
    -- response still gives us the orderID. Only infer Guild from an order already
    -- known through the Blackjack Guild board.
    local cached = BJ.db.network.craftingOrders[id]
    if cached then
        self.lastClaimed[id] = {
            id = id, itemID = tonumber(cached.itemID) or 0, orderType = GUILD_ORDER,
            customerName = cached.owner, customerGUID = cached.ownerGUID, savedAt = BJ:Now(),
        }
        self:BroadcastWorkState(id, 4)
    end
end

function Crafting:OnFulfillResponse(result, orderID, retry)
    if not IsOk(result) then return end
    local id = OrderKey(orderID)
    local cached = id and BJ.db.network.craftingOrders[id] or nil
    local claimed = id and self.lastClaimed[id]

    if not claimed and C_CraftingOrders and C_CraftingOrders.GetClaimedOrder then
        local order = C_CraftingOrders.GetClaimedOrder()
        if order and tonumber(order.orderType) == tonumber(GUILD_ORDER) then
            local oid = OrderKey(order.orderID)
            claimed = {
                id = oid,
                itemID = tonumber(order.itemID) or 0,
                orderType = tonumber(order.orderType),
                customerName = order.customerName or self:GetRememberedCustomerName(oid),
                customerGUID = order.customerGuid or self:GetRememberedCustomerGUID(oid),
                savedAt = BJ:Now(),
            }
            self:RememberCustomerIdentity(order.customerName, oid, order.customerGuid)
            if oid then self.lastClaimed[oid] = claimed end
        end
    end
    if not claimed and id and cached then
        claimed = { id = id, itemID = tonumber(cached.itemID) or 0, orderType = GUILD_ORDER, customerName = cached.owner, customerGUID = cached.ownerGUID, savedAt = BJ:Now() }
        self.lastClaimed[id] = claimed
    end
    if not claimed or tonumber(claimed.orderType) ~= tonumber(GUILD_ORDER) then return end

    local completedID = id or claimed.id
    cached = cached or (completedID and BJ.db.network.craftingOrders[completedID]) or nil
    local customer = claimed.customerName
        or self:GetRememberedCustomerName(completedID)
        or (cached and cached.owner)
    local customerGUID = claimed.customerGUID
        or self:GetRememberedCustomerGUID(completedID)
        or (cached and cached.ownerGUID)
    local itemID = tonumber(claimed.itemID) or tonumber(cached and cached.itemID) or 0

    -- Name and GUID can arrive on slightly different events. A GUID is sufficient to
    -- address the notification exactly, so retry only while BOTH identities are missing.
    if (not customer or customer == "") and (not customerGUID or customerGUID == "") and (tonumber(retry) or 0) < 3 then
        local nextRetry = (tonumber(retry) or 0) + 1
        C_Timer.After(nextRetry == 1 and 0.15 or 0.35, function()
            if BJ.Crafting then BJ.Crafting:OnFulfillResponse(result, orderID, nextRetry) end
        end)
        return
    end

    if customer and customer ~= "" and BJ.Guild and BJ.Guild.ResolveMember then
        customer = BJ.Guild:ResolveMember(customer) or customer
    end
    claimed.customerName = customer
    claimed.customerGUID = customerGUID
    claimed.itemID = itemID
    self.lastCompletion = { id = completedID, customer = customer or "", customerGUID = customerGUID or "", itemID = itemID, at = BJ:Now() }

    -- CWORK manages board/history. CREADY is a separate, personal HUD notification.
    -- This prevents cache reconciliation from swallowing the user's delivery alert.
    self:BroadcastWorkState(completedID, 11, customer, itemID)
    if (customer and customer ~= "") or (customerGUID and customerGUID ~= "") then
        self:SendDeliveryReady(completedID, customer, itemID, customerGUID)
    end

    self.lastStatus = ((customer and customer ~= "") or (customerGUID and customerGUID ~= ""))
        and ("Ordine Guild completato. Notifica personale inviata" .. ((customer and customer ~= "") and (" a " .. BJ:ShortName(customer)) or "") .. ".")
        or "Ordine Guild completato, ma il committente non era identificabile; la mailbox fara recovery."

    -- Both messages are retried. MarkDeliveryPending deduplicates by orderID.
    C_Timer.After(2, function()
        if BJ.Crafting then
            BJ.Crafting:SendWorkState(completedID, 11, customer, itemID)
            if (customer and customer ~= "") or (customerGUID and customerGUID ~= "") then BJ.Crafting:SendDeliveryReady(completedID, customer, itemID, customerGUID) end
        end
    end)
    C_Timer.After(7, function()
        if BJ.Crafting then
            BJ.Crafting:SendWorkState(completedID, 11, customer, itemID)
            if (customer and customer ~= "") or (customerGUID and customerGUID ~= "") then BJ.Crafting:SendDeliveryReady(completedID, customer, itemID, customerGUID) end
        end
    end)

    if BJ.Progress then
        BJ.Progress:EnsureWeek()
        local key = tostring(completedID or "?")
        local set = BJ.db.progress.sets.guildCraftOrderIds or {}
        BJ.db.progress.sets.guildCraftOrderIds = set
        if not set[key] then
            BJ.Progress:BeginBatch()
            BJ.Progress:AddSetValue("guildCraftOrderIds", key)
            BJ.Progress:AddStat("guildCraftsCompleted", 1)
            BJ.Progress:AddSetValue("contentTypes", "CRAFTING")
            BJ.Progress:EndBatch()
            BJ:AddMoment("Ordine di gilda completato come crafter: " .. SafeItemName(itemID) .. ".", "CRAFT")
        end
    end
    if completedID then self.lastClaimed[completedID] = nil end
    self:NotifyChanged()
end
