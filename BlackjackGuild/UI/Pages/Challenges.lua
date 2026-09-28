local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local GROUP_LABELS = {
    MPLUS = "MYTHIC+",
    SEASON = "SEASON 2",
    RAID = "RAID",
    DUNGEON = "DUNGEON NON-M+",
    LEGACY = "VECCHIO CONTENUTO",
    PVP = "PVP",
    CRAFTING = "CRAFTING DI GILDA",
    COMMUNITY = "COMMUNITY",
}

local GROUP_ORDER = {
    MPLUS = 1,
    SEASON = 2,
    RAID = 3,
    DUNGEON = 4,
    LEGACY = 5,
    PVP = 6,
    CRAFTING = 7,
    COMMUNITY = 8,
}

local CATEGORY_ITEMS = {
    { id="ALL", label="Tutte le categorie" },
    { id="MPLUS", label="Mythic+" },
    { id="SEASON", label="Season 2" },
    { id="RAID", label="Raid" },
    { id="DUNGEON", label="Dungeon non-M+" },
    { id="LEGACY", label="Vecchio contenuto" },
    { id="PVP", label="PvP" },
    { id="CRAFTING", label="Crafting di gilda" },
    { id="COMMUNITY", label="Community" },
}

local STATUS_ITEMS = {
    { id="ALL", label="Tutti gli stati" },
    { id="CLAIMABLE", label="Da riscuotere" },
    { id="IN_PROGRESS", label="In corso" },
    { id="NOT_STARTED", label="Non iniziate" },
    { id="COMPLETED", label="Completate" },
    { id="CLAIMED", label="Gia riscosse" },
}

local SORT_ITEMS = {
    { id="PRIORITY", label="Priorita" },
    { id="GROUP", label="Per categoria" },
    { id="PROGRESS", label="Piu vicine" },
    { id="REWARD", label="Piu fiches" },
    { id="NAME", label="Nome A-Z" },
}

local function Lower(value)
    return string.lower(tostring(value or ""))
end

local function ChallengeState(value, goal, claimed)
    local done = value >= goal
    if claimed then return "CLAIMED", done end
    if done then return "CLAIMABLE", done end
    if value > 0 then return "IN_PROGRESS", done end
    return "NOT_STARTED", done
end

local function StateLabel(state)
    if state == "CLAIMABLE" then return "DA RISCUOTERE" end
    if state == "CLAIMED" then return "RISCOSSA" end
    if state == "IN_PROGRESS" then return "IN CORSO" end
    return "NON INIZIATA"
end

local function MatchesSearch(ch, query)
    if query == "" then return true end
    local haystack = Lower((ch.title or "") .. " " .. (ch.description or "") .. " " .. (GROUP_LABELS[ch.group] or ch.group or ""))
    return string.find(haystack, query, 1, true) ~= nil
end

function UI:CreateChallengesPage()
    local p = self:CreatePage("CHALLENGES")
    self:PageTitle(p, "Blackjack Challenges", "Obiettivi settimanali automatici. Filtra per contenuto o stato e trova subito cio che ti interessa.")

    self.challengeFilters = self.challengeFilters or {
        search = "",
        group = "ALL",
        status = "ALL",
        sort = "PRIORITY",
    }

    self.challengeSummary = W:Text(p, "", 10, T.gold)
    self.challengeSummary:SetPoint("TOPLEFT", 2, -62)
    self.challengeReset = W:Text(p, "", 9, T.muted)
    self.challengeReset:SetPoint("TOPRIGHT", -6, -62)

    local filterCard = W:Card(p, 814, 86, true)
    filterCard:SetPoint("TOPLEFT", 2, -84)
    self.challengeFilterCard = filterCard

    self.challengeSearch = W:SearchBox(filterCard, 206, "Cerca challenge...", function(text)
        UI.challengeFilters.search = Lower(text)
        UI:RefreshChallenges()
    end)
    self.challengeSearch:SetPoint("TOPLEFT", 10, -10)

    self.challengeCategoryFilter = W:Dropdown(filterCard, 178, CATEGORY_ITEMS, self.challengeFilters.group, function(value)
        UI.challengeFilters.group = value
        UI:RefreshChallenges()
    end)
    self.challengeCategoryFilter:SetPoint("LEFT", self.challengeSearch, "RIGHT", 9, 0)

    self.challengeStatusFilter = W:Dropdown(filterCard, 166, STATUS_ITEMS, self.challengeFilters.status, function(value)
        UI.challengeFilters.status = value
        UI:RefreshChallenges()
    end)
    self.challengeStatusFilter:SetPoint("LEFT", self.challengeCategoryFilter, "RIGHT", 9, 0)

    self.challengeSortFilter = W:Dropdown(filterCard, 166, SORT_ITEMS, self.challengeFilters.sort, function(value)
        UI.challengeFilters.sort = value
        UI:RefreshChallenges()
    end)
    self.challengeSortFilter:SetPoint("LEFT", self.challengeStatusFilter, "RIGHT", 9, 0)

    self.challengeFilterSummary = W:Text(filterCard, "", 9, T.muted)
    self.challengeFilterSummary:SetPoint("BOTTOMLEFT", 12, 11)
    self.challengeFilterSummary:SetWidth(610)

    local reset = W:Button(filterCard, "Reset filtri", 112, 25)
    reset:SetPoint("BOTTOMRIGHT", -10, 7)
    reset:SetScript("OnClick", function()
        UI.challengeFilters.search = ""
        UI.challengeFilters.group = "ALL"
        UI.challengeFilters.status = "ALL"
        UI.challengeFilters.sort = "PRIORITY"
        UI.challengeSearch:SetText("")
        UI.challengeCategoryFilter:SetValue("ALL", true)
        UI.challengeStatusFilter:SetValue("ALL", true)
        UI.challengeSortFilter:SetValue("PRIORITY", true)
        UI:RefreshChallenges()
    end)

    self.challengeScroll, self.challengeList = W:ScrollArea(p, 810, 421)
    self.challengeScroll:SetPoint("TOPLEFT", 2, -180)
    self:RegisterRefresher("CHALLENGES", function() UI:RefreshChallenges() end)
end

function UI:RefreshChallenges()
    if not self.challengeList then return end
    W:ClearDynamic(self.challengeList)

    local challenges = BJ.Challenges:GetAll()
    local completed = BJ.Challenges:GetCompletedCount()
    local claimable = BJ.Challenges:GetClaimableCount()
    local filters = self.challengeFilters or { search="", group="ALL", status="ALL", sort="PRIORITY" }

    local testPrefix = (BJ.TestMode and BJ.TestMode:IsEnabled()) and "|cffff6a63[TEST]|r " or ""
    self.challengeSummary:SetText(testPrefix .. completed .. "/" .. #challenges .. " completate - " .. claimable .. " da riscuotere - saldo: " .. BJ.Rewards:GetBalance() .. " fiches")
    self.challengeReset:SetText("Reset tra " .. BJ:FormatWeeklyReset())

    local rows = {}
    local visibleClaimable = 0
    local visibleCompleted = 0

    for i = 1, #challenges do
        local ch = challenges[i]
        local value, goal = BJ.Challenges:GetProgress(ch)
        local claimed = BJ.Rewards:IsClaimed(ch.id)
        local state, done = ChallengeState(value, goal, claimed)

        local groupOK = filters.group == "ALL" or ch.group == filters.group
        local statusOK = filters.status == "ALL"
            or filters.status == state
            or (filters.status == "COMPLETED" and done)
        local searchOK = MatchesSearch(ch, filters.search or "")

        if groupOK and statusOK and searchOK then
            rows[#rows + 1] = {
                ch = ch,
                value = value,
                goal = goal,
                claimed = claimed,
                state = state,
                done = done,
                progress = goal > 0 and math.min(1, value / goal) or 0,
            }
            if state == "CLAIMABLE" then visibleClaimable = visibleClaimable + 1 end
            if done then visibleCompleted = visibleCompleted + 1 end
        end
    end

    table.sort(rows, function(a, b)
        if filters.sort == "NAME" then
            return Lower(a.ch.title) < Lower(b.ch.title)
        elseif filters.sort == "REWARD" then
            if a.ch.reward ~= b.ch.reward then return a.ch.reward > b.ch.reward end
            return Lower(a.ch.title) < Lower(b.ch.title)
        elseif filters.sort == "PROGRESS" then
            if a.progress ~= b.progress then return a.progress > b.progress end
            return Lower(a.ch.title) < Lower(b.ch.title)
        elseif filters.sort == "GROUP" then
            local ag, bg = GROUP_ORDER[a.ch.group] or 99, GROUP_ORDER[b.ch.group] or 99
            if ag ~= bg then return ag < bg end
            return Lower(a.ch.title) < Lower(b.ch.title)
        end

        local priority = { CLAIMABLE=1, IN_PROGRESS=2, NOT_STARTED=3, CLAIMED=4 }
        local ap, bp = priority[a.state] or 9, priority[b.state] or 9
        if ap ~= bp then return ap < bp end
        if a.state == "IN_PROGRESS" and a.progress ~= b.progress then return a.progress > b.progress end
        local ag, bg = GROUP_ORDER[a.ch.group] or 99, GROUP_ORDER[b.ch.group] or 99
        if ag ~= bg then return ag < bg end
        return Lower(a.ch.title) < Lower(b.ch.title)
    end)

    self.challengeFilterSummary:SetText(#rows .. " risultati - " .. visibleClaimable .. " da riscuotere - " .. visibleCompleted .. " completate")

    local y = 0
    local lastGroup = nil
    local showGroupHeaders = filters.group == "ALL" and (filters.sort == "GROUP" or filters.sort == "PRIORITY")

    if #rows == 0 then
        local empty = W:AddDynamic(self.challengeList, W:Card(self.challengeList, 772, 84, true))
        empty:SetPoint("TOPLEFT", 0, 0)
        local title = W:Text(empty, "Nessuna challenge trovata", 13, T.gold, "OUTLINE")
        title:SetPoint("TOPLEFT", 14, -16)
        local desc = W:Text(empty, "Prova a cambiare categoria, stato oppure il testo di ricerca.", 10, T.muted)
        desc:SetPoint("TOPLEFT", 14, -42)
        self.challengeList:SetHeight(410)
        return
    end

    for i = 1, #rows do
        local rowData = rows[i]
        local ch = rowData.ch

        if showGroupHeaders and ch.group ~= lastGroup then
            local h = W:AddDynamic(self.challengeList, W:Text(self.challengeList, GROUP_LABELS[ch.group] or ch.group, 10, T.gold, "OUTLINE"))
            h:SetPoint("TOPLEFT", 2, -y)
            y = y + 23
            lastGroup = ch.group
        end

        local card = W:AddDynamic(self.challengeList, W:Card(self.challengeList, 772, 88))
        card:SetPoint("TOPLEFT", 0, -y)

        local titleColor = rowData.state == "CLAIMABLE" and T.accent or (rowData.claimed and T.muted or T.white)
        local title = W:Text(card, ch.title, 12, titleColor, "OUTLINE")
        title:SetPoint("TOPLEFT", 14, -11)
        title:SetWidth(430)

        local group = W:Text(card, GROUP_LABELS[ch.group] or ch.group, 8, T.gold)
        group:SetPoint("TOPRIGHT", -14, -12)
        group:SetWidth(180)
        group:SetJustifyH("RIGHT")

        local desc = W:Text(card, ch.description, 9, T.text)
        desc:SetPoint("TOPLEFT", 14, -31)
        desc:SetWidth(610)
        desc:SetHeight(24)
        desc:SetJustifyV("TOP")

        local bar = CreateFrame("StatusBar", nil, card)
        bar:SetSize(435, 10)
        bar:SetPoint("BOTTOMLEFT", 14, 14)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetMinMaxValues(0, rowData.goal)
        bar:SetValue(rowData.value)
        bar:SetStatusBarColor(UI.UnpackColor(rowData.done and T.accentStrong or T.gold))
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.03, 0.06, 0.05, 1)

        local prog = W:Text(card, rowData.value .. "/" .. rowData.goal .. "  +" .. ch.reward .. " fiches", 9, T.muted)
        prog:SetPoint("LEFT", bar, "RIGHT", 9, 0)

        if rowData.state == "CLAIMABLE" then
            local claim = W:Button(card, "Riscuoti +" .. ch.reward, 112, 27, "primary")
            claim:SetPoint("BOTTOMRIGHT", -12, 8)
            claim:SetScript("OnClick", function()
                local ok, err = BJ.Rewards:Claim(ch)
                if not ok then BJ:Print(err) end
            end)
        else
            local stateText = W:Text(card, StateLabel(rowData.state), 8, rowData.claimed and T.accent or T.muted, "OUTLINE")
            stateText:SetPoint("BOTTOMRIGHT", -14, 14)
        end

        y = y + 95
    end

    self.challengeList:SetHeight(math.max(y + 8, 410))
end
