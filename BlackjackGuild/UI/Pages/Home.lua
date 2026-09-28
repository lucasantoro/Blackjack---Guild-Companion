local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

function UI:CreateHomePage()
    local p = self:CreatePage("HOME")
    self:PageTitle(p, "Benvenuto al tavolo", "Attivita aperte, challenge settimanali e un motivo in piu per giocare con la gilda.")

    self.homeStats = {}
    local labels = {"ONLINE", "TAVOLI / CRAFT", "CHALLENGE", "FICHES"}
    for i = 1, 4 do
        local card = W:Card(p, 197, 78, true)
        card:SetPoint("TOPLEFT", 2 + (i - 1) * 207, -68)
        local l = W:Text(card, labels[i], 9, T.muted)
        l:SetPoint("TOPLEFT", 12, -11)
        local v = W:Text(card, "0", 22, i == 4 and T.gold or T.accent, "OUTLINE")
        v:SetPoint("BOTTOMLEFT", 12, 10)
        self.homeStats[i] = v
    end

    local ideaTitle = W:Text(p, "IDEE PRONTE", 10, T.gold)
    ideaTitle:SetPoint("TOPLEFT", 2, -163)

    self.homeIdeas = {}
    local ideas = {
        { category="MPLUS", preset="season2_tour" },
        { category="RAID", preset="venomous_abyss" },
        { category="OLDRAID", preset="legacy_glory" },
    }

    for i = 1, #ideas do
        local idea = ideas[i]
        local preset = BJ.Data:GetPreset(idea.category, idea.preset)
        local cat = BJ.Data:GetCategory(idea.category)
        local card = W:Card(p, 262, 112)
        card:SetPoint("TOPLEFT", 2 + (i - 1) * 274, -184)

        local stripe = card:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", 0, 0)
        stripe:SetPoint("BOTTOMLEFT", 0, 0)
        stripe:SetWidth(4)
        stripe:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)

        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(cat.icon)
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 13, -13)

        local title = W:Text(card, preset.title, 13, T.white)
        title:SetPoint("TOPLEFT", 50, -14)
        title:SetWidth(195)

        local desc = W:Text(card, preset.description, 9, T.muted)
        desc:SetPoint("TOPLEFT", 14, -48)
        desc:SetWidth(232)
        desc:SetHeight(34)
        desc:SetJustifyV("TOP")

        local b = W:Button(card, "Prepara", 82, 25, "primary")
        b:SetPoint("BOTTOMRIGHT", -10, 9)
        b:SetScript("OnClick", function() UI:PrepareActivity(idea.category, idea.preset) end)

        self.homeIdeas[#self.homeIdeas + 1] = card
    end

    local momentsCard = W:Card(p, 814, 270, true)
    momentsCard:SetPoint("TOPLEFT", 2, -316)

    local mt = W:Text(momentsCard, "ULTIMI BLACKJACK MOMENTS", 10, T.gold)
    mt:SetPoint("TOPLEFT", 14, -13)

    self.homeReset = W:Text(momentsCard, "", 9, T.muted)
    self.homeReset:SetPoint("TOPRIGHT", -14, -13)

    self.homeMoments = {}
    for i = 1, 6 do
        local line = W:Text(momentsCard, "", 11, T.text)
        line:SetPoint("TOPLEFT", 16, -43 - (i - 1) * 34)
        line:SetWidth(780)
        self.homeMoments[i] = line
    end

    self:RegisterRefresher("HOME", function() UI:RefreshHome() end)
end

function UI:RefreshHome()
    local active = BJ.Activities:GetActive()
    local completed = BJ.Challenges:GetCompletedCount()
    local total = #BJ.Challenges:GetAll()

    self.homeStats[1]:SetText((BJ.Guild.online or 0) .. " / " .. (BJ.Guild.total or 0))
    local crafts = BJ.Crafting and BJ.Crafting:GetActiveOrders() or {}
    self.homeStats[2]:SetText(tostring(#active) .. " / " .. tostring(#crafts))
    self.homeStats[3]:SetText(completed .. " / " .. total)
    self.homeStats[4]:SetText(tostring(BJ.Rewards:GetBalance()))
    self.homeReset:SetText("Reset challenge tra " .. BJ:FormatWeeklyReset())

    local moments = BJ.db.moments or {}
    for i = 1, #self.homeMoments do
        local m = moments[i]
        if m then
            local age = BJ:FormatTimeLeft(math.max(0, BJ:Now() - (m.time or BJ:Now())))
            self.homeMoments[i]:SetText("|cfff0c868-|r " .. (m.text or "") .. "  |cff68766f(" .. age .. " fa)|r")
        else
            self.homeMoments[i]:SetText(i == 1 and "|cff94a59dNessun momento registrato ancora. Il caos arrivera.|r" or "")
        end
    end
end
