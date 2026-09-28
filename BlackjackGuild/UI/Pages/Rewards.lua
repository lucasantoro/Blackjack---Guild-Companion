local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local TYPE_ITEMS = {
    { id="ALL", label="Titoli + badge" },
    { id="title", label="Solo titoli" },
    { id="badge", label="Solo badge" },
}

local STATUS_ITEMS = {
    { id="ALL", label="Tutti gli stati" },
    { id="BUYABLE", label="Acquistabili ora" },
    { id="OWNED", label="Sbloccati" },
    { id="EQUIPPED", label="Equipaggiati" },
    { id="LOCKED", label="Non acquistabili" },
}

local SORT_ITEMS = {
    { id="SMART", label="Disponibilita" },
    { id="PRICE_ASC", label="Costo crescente" },
    { id="PRICE_DESC", label="Costo decrescente" },
    { id="NAME", label="Nome A-Z" },
}

local function Lower(value)
    return string.lower(tostring(value or ""))
end

local function IsEquipped(reward)
    return BJ.Rewards:IsEquipped(reward)
end

local function SetActionState(button, enabled, kind, text, onClick)
    button:SetText(text)
    button:SetKind(kind or (enabled and "primary" or "disabled"))
    if enabled then
        button:Enable()
        button:SetScript("OnClick", onClick)
    else
        button:Disable()
        button:SetScript("OnClick", nil)
    end
end

local function RewardState(reward, balance)
    local unlocked = BJ.Rewards:IsUnlocked(reward.id)
    local equipped = IsEquipped(reward)
    local price = tonumber(reward.price) or 0
    if equipped then return "EQUIPPED", unlocked, equipped, price end
    if unlocked then return "OWNED", unlocked, equipped, price end
    if balance >= price then return "BUYABLE", unlocked, equipped, price end
    return "LOCKED", unlocked, equipped, price
end

local function StateLabel(state)
    if state == "EQUIPPED" then return "EQUIPAGGIATO" end
    if state == "OWNED" then return "SBLOCCATO" end
    if state == "BUYABLE" then return "ACQUISTABILE" end
    return "BLOCCATO"
end

function UI:CreateRewardsPage()
    local p = self:CreatePage("REWARDS")
    self:PageTitle(p, "Fiches & Reward", "Catalogo reward: filtra, cerca e sblocca senza sacrificare spazio alla lista.")

    self.rewardFilters = self.rewardFilters or {
        search = "",
        type = "ALL",
        status = "ALL",
        sort = "SMART",
    }

    -- Barra compatta: saldo + stato Busta del Dealer nello stesso spazio.
    local summary = W:Card(p, 814, 82, true)
    summary:SetPoint("TOPLEFT", 2, -62)
    self.rewardSummaryCard = summary

    self.rewardBalance = W:Text(summary, "0", 27, T.gold, "OUTLINE")
    self.rewardBalance:SetPoint("TOPLEFT", 16, -10)

    local l = W:Text(summary, "FICHES", 8, T.muted)
    l:SetPoint("TOPLEFT", 18, -47)

    self.rewardLifetime = W:Text(summary, "", 9, T.text)
    self.rewardLifetime:SetPoint("TOPLEFT", 130, -15)
    self.rewardLifetime:SetWidth(225)

    local hint = W:Text(summary, "Saldo permanente tra i reset settimanali.", 8, T.muted)
    hint:SetPoint("TOPLEFT", 130, -39)
    hint:SetWidth(225)

    local gt = W:Text(summary, "BUSTA DEL DEALER - 250 GOLD", 10, T.gold, "OUTLINE")
    gt:SetPoint("TOPLEFT", 370, -10)

    self.goldDesc = W:Text(summary, "", 8, T.text)
    self.goldDesc:SetPoint("TOPLEFT", 370, -29)
    self.goldDesc:SetWidth(265)
    self.goldDesc:SetHeight(34)
    self.goldDesc:SetJustifyV("TOP")

    self.goldCost = W:Text(summary, "", 8, T.gold)
    self.goldCost:SetPoint("BOTTOMLEFT", 370, 8)

    self.goldAction = W:Button(summary, "", 140, 30, "disabled")
    self.goldAction:SetPoint("RIGHT", -12, 0)

    local filterCard = W:Card(p, 814, 64, true)
    filterCard:SetPoint("TOPLEFT", 2, -151)
    self.rewardFilterCard = filterCard

    self.rewardSearch = W:SearchBox(filterCard, 190, "Cerca reward...", function(text)
        UI.rewardFilters.search = Lower(text)
        UI:RefreshRewards()
    end)
    self.rewardSearch:SetPoint("TOPLEFT", 9, -8)

    self.rewardTypeFilter = W:Dropdown(filterCard, 145, TYPE_ITEMS, self.rewardFilters.type, function(value)
        UI.rewardFilters.type = value
        UI:RefreshRewards()
    end)
    self.rewardTypeFilter:SetPoint("LEFT", self.rewardSearch, "RIGHT", 8, 0)

    self.rewardStatusFilter = W:Dropdown(filterCard, 170, STATUS_ITEMS, self.rewardFilters.status, function(value)
        UI.rewardFilters.status = value
        UI:RefreshRewards()
    end)
    self.rewardStatusFilter:SetPoint("LEFT", self.rewardTypeFilter, "RIGHT", 8, 0)

    self.rewardSortFilter = W:Dropdown(filterCard, 160, SORT_ITEMS, self.rewardFilters.sort, function(value)
        UI.rewardFilters.sort = value
        UI:RefreshRewards()
    end)
    self.rewardSortFilter:SetPoint("LEFT", self.rewardStatusFilter, "RIGHT", 8, 0)

    self.rewardFilterSummary = W:Text(filterCard, "", 8, T.muted)
    self.rewardFilterSummary:SetPoint("BOTTOMLEFT", 11, 7)
    self.rewardFilterSummary:SetWidth(675)

    local reset = W:Button(filterCard, "Reset", 84, 23)
    reset:SetPoint("BOTTOMRIGHT", -9, 5)
    reset:SetScript("OnClick", function()
        UI.rewardFilters.search = ""
        UI.rewardFilters.type = "ALL"
        UI.rewardFilters.status = "ALL"
        UI.rewardFilters.sort = "SMART"
        UI.rewardSearch:SetText("")
        UI.rewardTypeFilter:SetValue("ALL", true)
        UI.rewardStatusFilter:SetValue("ALL", true)
        UI.rewardSortFilter:SetValue("SMART", true)
        UI:RefreshRewards()
    end)

    -- Quasi tutta la parte bassa della pagina e ora dedicata al catalogo.
    self.rewardScroll, self.rewardList = W:ScrollArea(p, 810, 387)
    self.rewardScroll:SetPoint("TOPLEFT", 2, -223)

    self:RegisterRefresher("REWARDS", function() UI:RefreshRewards() end)
end

function UI:RefreshRewards()
    if not self.rewardList then return end

    local balance = BJ.Rewards:GetBalance()
    self.rewardBalance:SetText(tostring(balance))
    local isTest = BJ.TestMode and BJ.TestMode:IsEnabled()
    self.rewardLifetime:SetText((isTest and "|cffff6a63TEST|r - " or "") .. "Guadagnate in totale: |cffffffff" .. BJ.Rewards:GetLifetime() .. "|r")

    local goldReward = BJ.Data:GetReward("weekly_gold_250")
    local goldClaim = BJ.Rewards:GetWeeklyGoldClaim()
    local goldPrice = tonumber(goldReward.price) or 0
    self.goldCost:SetText("Costo: " .. goldPrice .. " fiches")

    if goldClaim then
        if isTest then
            self.goldDesc:SetText("[TEST] Claim simulato da " .. (goldClaim.amount or 250) .. "g. Visibile nella Cassa TEST; nessun pagamento reale viene creato.")
            SetActionState(self.goldAction, false, "disabled", "Riscattato", nil)
        elseif goldClaim.status == "PAID" then
            local method = goldClaim.method == "BANK" and "banca verificata" or "officer"
            self.goldDesc:SetText("PAGATO: " .. (goldClaim.amount or 250) .. "g confermati (" .. method .. "). Nuovo claim tra " .. BJ:FormatWeeklyReset() .. ".")
            SetActionState(self.goldAction, false, "disabled", "Pagato", nil)
        elseif BJ.Treasury and BJ.Treasury:CanSelfWithdraw() then
            self.goldDesc:SetText("Reward approvato: puoi ritirare " .. (goldClaim.amount or 250) .. "g dalla banca con il tuo limite attuale.")
            SetActionState(self.goldAction, true, "primary", "Ritira 250g", function()
                local ok, err = BJ.Treasury:WithdrawCurrentReward()
                if not ok and err then BJ:Print(err) end
                UI:RefreshRewards()
            end)
        elseif goldClaim.withdrawRequestedAt then
            self.goldDesc:SetText("Prelievo da " .. (goldClaim.amount or 250) .. "g richiesto. Stato DA VERIFICARE: un officer deve confermare dal log banca.")
            SetActionState(self.goldAction, false, "disabled", "Da verificare", nil)
        else
            self.goldDesc:SetText("Richiesta registrata nella Cassa Blackjack: " .. (goldClaim.amount or 250) .. "g DA PAGARE.")
            SetActionState(self.goldAction, false, "disabled", "In attesa", nil)
        end
    else
        local canAfford = balance >= goldPrice
        self.goldDesc:SetText(isTest and "[TEST] Crea una richiesta simulata nella Cassa TEST." or "Una volta per reset: crea automaticamente una richiesta da 250g nella Cassa Blackjack.")
        SetActionState(self.goldAction, canAfford, canAfford and "primary" or "disabled", "Riscatta 250g", function()
            local ok, err = BJ.Rewards:ClaimWeeklyGold(goldReward)
            if not ok then BJ:Print(err) end
        end)
    end

    W:ClearDynamic(self.rewardList)

    local filters = self.rewardFilters or { search="", type="ALL", status="ALL", sort="SMART" }
    local rows = {}
    local buyableCount, ownedCount = 0, 0

    for i = 1, #BJ.Data.rewards do
        local reward = BJ.Data.rewards[i]
        if reward.type ~= "weekly_gold" then
            local state, unlocked, equipped, price = RewardState(reward, balance)
            local typeOK = filters.type == "ALL" or reward.type == filters.type
            local statusOK = filters.status == "ALL"
                or filters.status == state
                or (filters.status == "OWNED" and unlocked)
            local haystack = Lower((reward.title or "") .. " " .. (reward.subtitle or "") .. " " .. (reward.type or ""))
            local searchOK = (filters.search or "") == "" or string.find(haystack, filters.search, 1, true) ~= nil

            if typeOK and statusOK and searchOK then
                rows[#rows + 1] = {
                    reward = reward,
                    state = state,
                    unlocked = unlocked,
                    equipped = equipped,
                    price = price,
                    catalogIndex = i,
                }
                if state == "BUYABLE" then buyableCount = buyableCount + 1 end
                if unlocked then ownedCount = ownedCount + 1 end
            end
        end
    end

    table.sort(rows, function(a, b)
        if filters.sort == "PRICE_ASC" then
            if a.price ~= b.price then return a.price < b.price end
        elseif filters.sort == "PRICE_DESC" then
            if a.price ~= b.price then return a.price > b.price end
        elseif filters.sort == "NAME" then
            return Lower(a.reward.title) < Lower(b.reward.title)
        else
            -- L'equip e solo uno stato visuale della card: non deve modificarne
            -- la posizione nel catalogo. Per l'ordinamento SMART un reward
            -- equipaggiato appartiene allo stesso gruppo di uno gia sbloccato.
            local function SortBucket(row)
                if row.unlocked then return 2 end
                if row.state == "BUYABLE" then return 1 end
                return 3
            end
            local ap, bp = SortBucket(a), SortBucket(b)
            if ap ~= bp then return ap < bp end
            if a.price ~= b.price then return a.price < b.price end
        end
        local an, bn = Lower(a.reward.title), Lower(b.reward.title)
        if an ~= bn then return an < bn end
        return (a.catalogIndex or 0) < (b.catalogIndex or 0)
    end)

    self.rewardFilterSummary:SetText(#rows .. " reward trovati - " .. buyableCount .. " acquistabili ora - " .. ownedCount .. " gia sbloccati")

    if #rows == 0 then
        local empty = W:AddDynamic(self.rewardList, W:Card(self.rewardList, 772, 84, true))
        empty:SetPoint("TOPLEFT", 0, 0)
        local title = W:Text(empty, "Nessun reward trovato", 13, T.gold, "OUTLINE")
        title:SetPoint("TOPLEFT", 14, -16)
        local desc = W:Text(empty, "Prova a cambiare tipo, stato oppure il testo di ricerca.", 10, T.muted)
        desc:SetPoint("TOPLEFT", 14, -42)
        self.rewardList:SetHeight(377)
        return
    end

    local cardW, cardH, gapX, gapY = 376, 90, 12, 8
    local maxY = 0

    for i = 1, #rows do
        local data = rows[i]
        local reward = data.reward
        local col = (i - 1) % 2
        local rowIndex = math.floor((i - 1) / 2)
        local x = col * (cardW + gapX)
        local y = rowIndex * (cardH + gapY)

        local card = W:AddDynamic(self.rewardList, W:Card(self.rewardList, cardW, cardH))
        card:SetPoint("TOPLEFT", x, -y)

        local typeLabel = reward.type == "badge" and "BADGE" or "TITOLO"
        local typeText = W:Text(card, typeLabel, 8, T.gold, "OUTLINE")
        typeText:SetPoint("TOPLEFT", 12, -10)

        local stateText = W:Text(card, StateLabel(data.state), 8, data.state == "BUYABLE" and T.accent or T.muted, "OUTLINE")
        stateText:SetPoint("TOPRIGHT", -12, -10)
        stateText:SetJustifyH("RIGHT")

        local titleColor = data.unlocked and T.white or (data.state == "BUYABLE" and T.text or T.muted)
        local title = W:Text(card, reward.title, 11, titleColor, "OUTLINE")
        title:SetPoint("TOPLEFT", 12, -26)
        title:SetWidth(348)

        local desc = W:Text(card, reward.subtitle, 8, T.muted)
        desc:SetPoint("TOPLEFT", 12, -44)
        desc:SetWidth(345)
        desc:SetHeight(18)
        desc:SetJustifyV("TOP")

        local priceLabel = data.price == 0 and "Costo: BASE" or ("Costo: " .. data.price .. " fiches")
        local price = W:Text(card, priceLabel, 9, T.gold)
        price:SetPoint("BOTTOMLEFT", 12, 10)

        local action = W:Button(card, "", 100, 26, "disabled")
        action:SetPoint("BOTTOMRIGHT", -10, 6)

        if data.equipped then
            SetActionState(action, false, "disabled", "Equipaggiato", nil)
        elseif data.unlocked then
            SetActionState(action, true, "primary", "Equipaggia", function() BJ.Rewards:Equip(reward.id) end)
        elseif data.state == "BUYABLE" then
            SetActionState(action, true, "primary", "Sblocca", function()
                local ok, err = BJ.Rewards:Unlock(reward)
                if not ok then BJ:Print(err) end
            end)
        else
            SetActionState(action, false, "disabled", "Sblocca", nil)
        end

        maxY = math.max(maxY, y + cardH)
    end

    self.rewardList:SetHeight(math.max(maxY + 8, 377))
end
