local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local function TimeLeft(order)
    local expires = tonumber(order.expirationTime) or 0
    if expires <= 0 then return "-" end
    return BJ:FormatTimeLeft(math.max(0, expires - BJ:Now()))
end

local function AddOfferTooltip(frame, order)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(BJ.Crafting:GetItemName(order), 1, 1, 1)
        GameTooltip:AddLine("Ordine di: " .. BJ:ShortName(order.owner), 0.58, 0.65, 0.62)
        if order.notes and order.notes ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(order.notes, 0.84, 0.88, 0.85, true)
        end
        local interested = BJ.Crafting:GetInterested(order.id)
        GameTooltip:AddLine(" ")
        if #interested == 0 then
            GameTooltip:AddLine("Nessun crafter Blackjack si e ancora proposto.", 0.58, 0.65, 0.62, true)
        else
            GameTooltip:AddLine("Crafter disponibili:", 0.94, 0.78, 0.41)
            for i = 1, #interested do GameTooltip:AddLine("- " .. BJ:ShortName(interested[i]), 0.49, 1.00, 0.66) end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:CreateCraftingPage()
    local p = self:CreatePage("CRAFTING")
    self:PageTitle(p, "Crafting di gilda", "Gli ordini Guild creati dai membri vengono rilevati dal client e pubblicati automaticamente qui. Gli altri possono segnalare che possono craftarli.")

    local statusCard = W:Card(p, 814, 76, true)
    statusCard:SetPoint("TOPLEFT", 2, -68)
    self.craftingStatus = W:Text(statusCard, "", 10, T.text)
    self.craftingStatus:SetPoint("TOPLEFT", 14, -13)
    self.craftingStatus:SetWidth(520)
    self.craftingHint = W:Text(statusCard, "", 9, T.muted)
    self.craftingHint:SetPoint("TOPLEFT", 14, -39)
    self.craftingHint:SetWidth(560)

    self.craftingToggle = W:Button(statusCard, "Auto: ON", 100, 30, "primary")
    self.craftingToggle:SetPoint("RIGHT", -122, 0)
    self.craftingToggle:SetScript("OnClick", function()
        BJ.Crafting:SetAutoPublish(not BJ.Crafting:IsAutoPublishEnabled())
    end)

    self.craftingRefresh = W:Button(statusCard, "Aggiorna", 104, 30, "primary")
    self.craftingRefresh:SetPoint("RIGHT", -12, 0)
    self.craftingRefresh:SetScript("OnClick", function()
        BJ.Crafting:RequestState(true)
        BJ.Crafting:RequestMyOrders(false)
        C_Timer.After(0.5, function() UI:RefreshPage("CRAFTING") end)
    end)

    self.craftingScroll, self.craftingList = W:ScrollArea(p, 810, 444)
    self.craftingScroll:SetPoint("TOPLEFT", 2, -160)

    self:RegisterRefresher("CRAFTING", function() UI:RefreshCrafting() end)
end

function UI:RefreshCrafting()
    if not BJ.Crafting then return end
    BJ.Crafting:RequestState(false)
    local active = BJ.Crafting:GetActiveOrders()
    local history = BJ.Crafting:GetHistory()
    local deliveries = BJ.Crafting:GetPendingDeliveries()
    local auto = BJ.Crafting:IsAutoPublishEnabled()

    self.craftingToggle:SetText(auto and "Auto: ON" or "Auto: OFF")
    self.craftingToggle:SetKind(auto and "primary" or "default")
    self.craftingStatus:SetText("Ordini attivi: |cffffffff" .. #active .. "|r   Tuoi pubblicati: |cfff0c868" .. BJ.Crafting:GetOwnedCount() .. "|r   Da ritirare: |cfff0c868" .. #deliveries .. "|r")
    self.craftingHint:SetText(BJ.Crafting.lastStatus or "Quando crei un ordine di tipo Guild, Blackjack lo rileva dopo la conferma di WoW e lo condivide alla gilda.")

    W:ClearDynamic(self.craftingList)
    local y = 0

    if #deliveries > 0 then
        local readyHead = W:AddDynamic(self.craftingList, W:Text(self.craftingList, "PRONTI NELLA POSTA", 11, T.gold, "OUTLINE"))
        readyHead:SetPoint("TOPLEFT", 2, -y)
        y = y + 28
        for i = 1, #deliveries do
            local delivery = deliveries[i]
            local row = W:AddDynamic(self.craftingList, W:Card(self.craftingList, 772, 74, true))
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetBackdropColor(0.16, 0.12, 0.03, 0.96)
            row:SetBackdropBorderColor(T.gold[1], T.gold[2], T.gold[3], 1)
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(BJ.Crafting:GetItemIcon(delivery))
            icon:SetSize(38, 38)
            icon:SetPoint("LEFT", 14, 0)
            local title = W:Text(row, BJ.Crafting:GetItemName(delivery), 11, T.white, "OUTLINE")
            title:SetPoint("TOPLEFT", 64, -13)
            title:SetWidth(480)
            local crafter = (delivery.crafter and delivery.crafter ~= "") and BJ:ShortName(delivery.crafter) or "crafter Blackjack"
            local sub = W:Text(row, "Completato da " .. crafter .. " - ritira l'allegato dalla posta", 9, T.gold)
            sub:SetPoint("TOPLEFT", 64, -37)
            sub:SetWidth(560)
            local state = W:Text(row, "DA RITIRARE", 9, T.gold, "OUTLINE")
            state:SetPoint("RIGHT", -14, 0)
            y = y + 82
        end
        y = y + 8
    end

    local head = W:AddDynamic(self.craftingList, W:Text(self.craftingList, "ORDINI ATTIVI", 11, T.gold, "OUTLINE"))
    head:SetPoint("TOPLEFT", 2, -y)
    y = y + 28

    if #active == 0 then
        local empty = W:AddDynamic(self.craftingList, W:Card(self.craftingList, 772, 72))
        empty:SetPoint("TOPLEFT", 0, -y)
        local t = W:Text(empty, "Nessun ordine Guild Blackjack attivo sincronizzato.", 11, T.muted)
        t:SetPoint("LEFT", 14, 0)
        y = y + 82
    else
        for i = 1, #active do
            local order = active[i]
            local row = W:AddDynamic(self.craftingList, W:Card(self.craftingList, 772, 118, order.owner == BJ.player))
            row:SetPoint("TOPLEFT", 0, -y)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(BJ.Crafting:GetItemIcon(order))
            icon:SetSize(44, 44)
            icon:SetPoint("TOPLEFT", 14, -14)

            local title = W:Text(row, BJ.Crafting:GetItemName(order) .. (order.isRecraft and "  [RECRAFT]" or ""), 12, T.white, "OUTLINE")
            title:SetPoint("TOPLEFT", 68, -12)
            title:SetWidth(440)

            local stateColor = (tonumber(order.orderState) == 2) and T.accent or T.gold
            local state = W:Text(row, BJ.Crafting:GetStateLabel(order), 9, stateColor, "OUTLINE")
            state:SetPoint("TOPRIGHT", -14, -13)

            local ownerLine = "Da: " .. BJ:ShortName(order.owner) .. "   |   Scade tra: " .. TimeLeft(order)
            if order.workingBy then ownerLine = ownerLine .. "   |   Crafter: " .. BJ:ShortName(order.workingBy) end
            local owner = W:Text(row, ownerLine, 9, T.muted)
            owner:SetPoint("TOPLEFT", 68, -34)
            owner:SetWidth(520)

            local details = "Qualita min: " .. ((tonumber(order.minQuality) or 0) > 0 and tostring(order.minQuality) or "qualsiasi")
                .. "   |   Commissione: " .. BJ.Crafting:FormatMoney(order.tipAmount)
                .. "   |   Reagenti: " .. BJ.Crafting:GetReagentLabel(order)
            local detail = W:Text(row, details, 9, T.text)
            detail:SetPoint("TOPLEFT", 68, -54)
            detail:SetWidth(570)

            local noteText = (order.notes and order.notes ~= "") and ("Nota: " .. order.notes) or "Nota: nessuna"
            local note = W:Text(row, noteText, 9, T.muted)
            note:SetPoint("TOPLEFT", 14, -80)
            note:SetWidth(570)
            note:SetHeight(25)
            note:SetJustifyV("TOP")

            local count = BJ.Crafting:GetInterestedCount(order.id)
            local interested = W:Text(row, count .. (count == 1 and " crafter disponibile" or " crafter disponibili"), 9, count > 0 and T.accent or T.muted)
            interested:SetPoint("BOTTOMRIGHT", -126, 15)

            local action = W:Button(row, "", 108, 30, "disabled")
            action:SetPoint("BOTTOMRIGHT", -12, 10)
            if order.owner == BJ.player then
                action:SetText("Tuo ordine")
                action:SetKind("disabled")
                action:Disable()
            else
                local joined = BJ.Crafting:IsInterested(order.id)
                action:SetKind("primary")
                action:Enable()
                action:SetText(joined and "Ritira" or "Posso craftarlo")
                action:SetScript("OnClick", function() BJ.Crafting:ToggleOffer(order.id) end)
            end
            AddOfferTooltip(row, order)
            y = y + 126
        end
    end

    if #history > 0 then
        y = y + 8
        local hh = W:AddDynamic(self.craftingList, W:Text(self.craftingList, "RECENTI / CHIUSI", 11, T.gold, "OUTLINE"))
        hh:SetPoint("TOPLEFT", 2, -y)
        y = y + 28
        local maxHistory = math.min(8, #history)
        for i = 1, maxHistory do
            local order = history[i]
            local row = W:AddDynamic(self.craftingList, W:Card(self.craftingList, 772, 66))
            row:SetPoint("TOPLEFT", 0, -y)
            local title = W:Text(row, BJ.Crafting:GetItemName(order), 11, T.muted)
            title:SetPoint("TOPLEFT", 14, -12)
            title:SetWidth(470)
            local sub = W:Text(row, "Di " .. BJ:ShortName(order.owner) .. " - " .. tostring(order.closeReason or "CHIUSO"), 9, T.muted)
            sub:SetPoint("TOPLEFT", 14, -35)
            local closed = W:Text(row, "CHIUSO", 9, T.muted, "OUTLINE")
            closed:SetPoint("RIGHT", -14, 0)
            y = y + 74
        end
    end

    self.craftingList:SetHeight(math.max(y + 10, 440))
end
