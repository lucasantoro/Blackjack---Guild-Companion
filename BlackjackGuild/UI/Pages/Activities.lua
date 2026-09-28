local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local ACTIVITY_ROW_H = 124

local function CandidateText(list, limit)
    if not list or #list == 0 then return "Nessuno" end
    limit = limit or 6
    local parts = {}
    for i = 1, math.min(#list, limit) do parts[#parts + 1] = BJ:ShortName(list[i]) end
    if #list > limit then parts[#parts + 1] = "+" .. (#list - limit) end
    return table.concat(parts, ", ")
end

-- ACTIVITIES -----------------------------------------------------------------
function UI:CreateActivitiesPage()
    local p = self:CreatePage("ACTIVITIES")
    self:PageTitle(p, "Attivita di gilda", "Le tue attivita e quelle della gilda vivono in due schede separate: gestione e candidati da una parte, tavoli a cui aderire dall'altra.")

    local form = W:Card(p, 814, 232, true)
    form:SetPoint("TOPLEFT", 2, -68)
    self.activityForm = form

    local categoryLabel = W:SectionLabel(form, "Tipo")
    categoryLabel:SetPoint("TOPLEFT", 14, -12)
    self.activityCategoryDD = W:Dropdown(form, 178, BJ.Data.categories, "MPLUS", function(value)
        UI:UpdateActivityPresets(value)
    end)
    self.activityCategoryDD:SetPoint("TOPLEFT", 14, -31)

    local presetLabel = W:SectionLabel(form, "Idea pronta")
    presetLabel:SetPoint("TOPLEFT", 208, -12)
    self.activityPresetDD = W:Dropdown(form, 205, BJ.Data:GetPresets("MPLUS"), "vault_chill", function(value)
        UI:ApplyPresetToActivityDescription(value)
    end)
    self.activityPresetDD:SetPoint("TOPLEFT", 208, -31)

    local keyLabel = W:SectionLabel(form, "Livello chiave")
    keyLabel:SetPoint("TOPLEFT", 429, -12)
    self.activityKeyDD = W:Dropdown(form, 170, BJ.Data.keyBands, "ANY")
    self.activityKeyDD:SetPoint("TOPLEFT", 429, -31)

    local roleLabel = W:SectionLabel(form, "Cerco")
    roleLabel:SetPoint("TOPLEFT", 615, -12)
    self.activityRoleDD = W:Dropdown(form, 178, BJ.Data.roles, "ANY")
    self.activityRoleDD:SetPoint("TOPLEFT", 615, -31)

    local durationLabel = W:SectionLabel(form, "Durata annuncio")
    durationLabel:SetPoint("TOPLEFT", 14, -76)
    self.activityDurationDD = W:Dropdown(form, 178, BJ.Data.durations, "60")
    self.activityDurationDD:SetPoint("TOPLEFT", 14, -95)

    local targetLabel = W:SectionLabel(form, "Tavolo")
    targetLabel:SetPoint("TOPLEFT", 208, -76)
    self.activityTargetDD = W:Dropdown(form, 205, BJ.Data.targetSizes, "5")
    self.activityTargetDD:SetPoint("TOPLEFT", 208, -95)

    local descLabel = W:SectionLabel(form, "Messaggio")
    descLabel:SetPoint("TOPLEFT", 429, -76)
    self.activityDesc = W:EditBox(form, 364, 66, 92, true)
    self.activityDesc:SetPoint("TOPLEFT", 429, -95)

    local create = W:Button(form, "Apri il tavolo", 178, 34, "primary")
    create:SetPoint("BOTTOMLEFT", 14, 14)
    create:SetScript("OnClick", function() UI:CreateActivityFromForm() end)

    local info = W:Text(form, "I tuoi tavoli restano sempre separati: vedi candidati, da invitare e controlli senza cercarli nella lista della gilda.", 9, T.muted)
    info:SetPoint("BOTTOMLEFT", 208, 18); info:SetWidth(575)

    -- Two real tabs: there is deliberately no combined view.  This keeps owned
    -- activities discoverable even when the guild board becomes very busy.
    self.activityTab = "MINE"
    self.activityMineTab = W:Button(p, "LE MIE ATTIVITA", 402, 36, "primary")
    self.activityMineTab:SetPoint("TOPLEFT", 2, -310)
    self.activityMineTab:SetScript("OnClick", function() UI:SetActivityTab("MINE") end)

    self.activityGuildTab = W:Button(p, "ATTIVITA DELLA GILDA", 402, 36)
    self.activityGuildTab:SetPoint("LEFT", self.activityMineTab, "RIGHT", 8, 0)
    self.activityGuildTab:SetScript("OnClick", function() UI:SetActivityTab("GUILD") end)

    self.activityTabSummary = W:Text(p, "", 9, T.muted)
    self.activityTabSummary:SetPoint("TOPLEFT", 8, -354)
    self.activityTabSummary:SetWidth(792)

    self.activityMineScroll, self.activityMineList = W:ScrollArea(p, 810, 217)
    self.activityMineScroll:SetPoint("TOPLEFT", 2, -374)

    self.activityGuildScroll, self.activityGuildList = W:ScrollArea(p, 810, 217)
    self.activityGuildScroll:SetPoint("TOPLEFT", 2, -374)
    self.activityGuildScroll:Hide()

    self:UpdateActivityPresets("MPLUS")
    self:RegisterRefresher("ACTIVITIES", function() UI:RefreshActivities() end)
end

function UI:SetActivityTab(tab)
    if tab ~= "GUILD" then tab = "MINE" end
    self.activityTab = tab
    if self.activityMineScroll then self.activityMineScroll:SetShown(tab == "MINE") end
    if self.activityGuildScroll then self.activityGuildScroll:SetShown(tab == "GUILD") end
    self:RefreshActivities()
end

-- Compatibility shim for old internal callers from pre-2.8.2 builds.
function UI:SetActivityViewFilter(filter)
    self:SetActivityTab(filter == "OTHERS" and "GUILD" or "MINE")
end

function UI:OpenActivityCreator()
    self:Show("ACTIVITIES")
    self.activityTab = "MINE"
    if self.activityMineScroll then self.activityMineScroll:Show() end
    if self.activityGuildScroll then self.activityGuildScroll:Hide() end
    if not self.activityForm then return end
    self.activityForm:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
    local token = (self.activityFormHighlightToken or 0) + 1
    self.activityFormHighlightToken = token
    C_Timer.After(1.3, function()
        if UI.activityFormHighlightToken ~= token or not UI.activityForm then return end
        UI.activityForm:SetBackdropBorderColor(T.line[1], T.line[2], T.line[3], T.line[4] or 1)
    end)
end

function UI:UpdateActivityPresets(category)
    local presets = BJ.Data:GetPresets(category)
    self.activityPresetDD:SetItems(presets)
    self.activityPresetDD:SetValue(presets[1].id, true)
    self.activityKeyDD:SetAlpha(category == "MPLUS" and 1 or 0.45)
    self.activityKeyDD:EnableMouse(category == "MPLUS")
    self.activityDesc:SetText(presets[1].description or "")
end

function UI:ApplyPresetToActivityDescription(presetId)
    local category = self.activityCategoryDD:GetValue()
    local preset = BJ.Data:GetPreset(category, presetId)
    if preset then self.activityDesc:SetText(preset.description or "") end
end

function UI:SetActivityFormPreset(category, presetId)
    self.activityCategoryDD:SetValue(category, true)
    self:UpdateActivityPresets(category)
    self.activityPresetDD:SetValue(presetId, true)
    self:ApplyPresetToActivityDescription(presetId)
end

function UI:CreateActivityFromForm()
    local category = self.activityCategoryDD:GetValue()
    local presetId = self.activityPresetDD:GetValue()
    local preset = BJ.Data:GetPreset(category, presetId)
    local entry = BJ.Activities:Create({
        category = category,
        presetId = presetId,
        title = preset and preset.title or "Attivita Blackjack",
        description = self.activityDesc:GetText(),
        keyBand = category == "MPLUS" and self.activityKeyDD:GetValue() or "ANY",
        role = self.activityRoleDD:GetValue(),
        durationId = self.activityDurationDD:GetValue(),
        targetId = self.activityTargetDD:GetValue(),
    })
    if entry then
        BJ:Print("Tavolo aperto: |cffffffff" .. entry.title .. "|r")
        self.activityTab = "MINE"
        self:RefreshActivities()
    end
end

function UI:CreateActivityListRow(entry, y, container)
    container = container or self.activityMineList
    local cat = BJ.Data:GetCategory(entry.category)
    local owned = entry.owner == BJ.player
    local joined = not owned and BJ.Activities:GetJoinedState(entry.id)
    local row = W:AddDynamic(container, W:Card(container, 772, ACTIVITY_ROW_H, owned))
    row:SetPoint("TOPLEFT", 0, -y)
    if owned then row:SetBackdropBorderColor(T.accentStrong[1], T.accentStrong[2], T.accentStrong[3], 0.65) end

    local strip = row:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", 0, 0); strip:SetPoint("BOTTOMLEFT", 0, 0); strip:SetWidth(4)
    strip:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(cat.icon); icon:SetSize(34, 34); icon:SetPoint("TOPLEFT", 14, -14)

    local title = W:Text(row, entry.title or cat.label, 13, T.white, "OUTLINE")
    title:SetPoint("TOPLEFT", 58, -10); title:SetWidth(370)

    local ownership = W:Text(row, owned and "MIA" or "GILDA", 9, owned and T.accent or T.gold, "OUTLINE")
    ownership:SetPoint("TOPRIGHT", -126, -12)
    ownership:SetWidth(72); ownership:SetJustifyH("RIGHT")

    local ownerText = owned and "Creata da te" or ("Creata da: " .. BJ:ShortName(entry.owner))
    local meta = W:Text(row, ownerText .. "  |  " .. cat.label .. "  |  " .. (entry.count or 1) .. "/" .. (entry.target or 5) .. "  |  " .. BJ:FormatTimeLeft((entry.expires or 0) - BJ:Now()), 9, T.muted)
    meta:SetPoint("TOPLEFT", 58, -32); meta:SetWidth(520)

    if entry.category == "MPLUS" then
        local key = W:Text(row, UI.LabelFor(BJ.Data.keyBands, entry.keyBand), 9, T.blue)
        key:SetPoint("TOPRIGHT", -126, -34)
        key:SetWidth(120); key:SetJustifyH("RIGHT")
    end

    local messageLabel = W:Text(row, "MESSAGGIO", 8, T.gold)
    messageLabel:SetPoint("TOPLEFT", 14, -57)
    local message = W:Text(row, (entry.description and entry.description ~= "") and entry.description or "Nessun messaggio", 9, T.text)
    message:SetPoint("TOPLEFT", 86, -55)
    message:SetWidth(540)
    message:SetHeight(30)
    message:SetJustifyV("TOP")

    if owned then
        local participants = BJ.Activities:GetParticipants(entry.id)
        local waiting = BJ.Activities:GetInvitableParticipants(entry.id)
        local state = W:Text(row, "Stato: APERTA  |  Candidati: " .. #participants .. "  |  Da invitare: " .. #waiting, 9, T.accent)
        state:SetPoint("BOTTOMLEFT", 14, 25)
        state:SetWidth(520)

        local candidates = W:Text(row, "Candidati: " .. CandidateText(participants, 6), 9, participants[1] and T.text or T.muted)
        candidates:SetPoint("BOTTOMLEFT", 14, 8)
        candidates:SetWidth(570)

        local close = W:Button(row, "Chiudi", 68, 30, "danger")
        close:SetPoint("RIGHT", -12, -20)
        close:SetScript("OnClick", function() BJ.Activities:Delete(entry.id) end)

        local invite = W:Button(row, "INV " .. #waiting, 62, 30, "primary")
        invite:SetPoint("RIGHT", close, "LEFT", -6, 0)
        if #waiting == 0 then invite:SetKind("disabled"); invite:Disable() end
        invite:SetScript("OnClick", function() BJ.Activities:InviteParticipants(entry.id) end)
    else
        local stateText = joined and "Stato: ISCRITTO - hai gia aderito a questa attivita" or "Stato: DISPONIBILE - puoi aderire con Ci sono"
        local state = W:Text(row, stateText, 9, joined and T.accent or T.muted)
        state:SetPoint("BOTTOMLEFT", 14, 11)
        state:SetWidth(570)

        local action = W:Button(row, joined and "Ritira" or "Ci sono", 96, 30, "primary")
        action:SetPoint("RIGHT", -12, -20)
        action:SetScript("OnClick", function()
            if joined then BJ.Activities:Leave(entry.id) else BJ.Activities:Join(entry.id) end
        end)
    end
end

function UI:RefreshActivities()
    if not self.activityMineList or not self.activityGuildList then return end
    W:ClearDynamic(self.activityMineList)
    W:ClearDynamic(self.activityGuildList)

    local all = BJ.Activities:GetActive()
    local mine, guild = {}, {}
    local candidateTotal, invitableTotal, joinedTotal = 0, 0, 0

    for i = 1, #all do
        local entry = all[i]
        if entry.owner == BJ.player then
            mine[#mine + 1] = entry
            candidateTotal = candidateTotal + #BJ.Activities:GetParticipants(entry.id)
            invitableTotal = invitableTotal + #BJ.Activities:GetInvitableParticipants(entry.id)
        else
            guild[#guild + 1] = entry
            if BJ.Activities:GetJoinedState(entry.id) then joinedTotal = joinedTotal + 1 end
        end
    end

    local function byExpiry(a, b)
        if a.expires ~= b.expires then return a.expires < b.expires end
        return (a.title or "") < (b.title or "")
    end
    table.sort(mine, byExpiry)
    table.sort(guild, byExpiry)

    local tab = self.activityTab == "GUILD" and "GUILD" or "MINE"
    self.activityMineTab:SetText("LE MIE ATTIVITA  " .. #mine)
    self.activityGuildTab:SetText("ATTIVITA DELLA GILDA  " .. #guild)
    self.activityMineTab:SetKind(tab == "MINE" and "primary" or "default")
    self.activityGuildTab:SetKind(tab == "GUILD" and "primary" or "default")
    self.activityMineScroll:SetShown(tab == "MINE")
    self.activityGuildScroll:SetShown(tab == "GUILD")

    if tab == "MINE" then
        local summary = #mine .. " tavol" .. (#mine == 1 and "o" or "i") .. " aperti"
        if #mine == 1 then summary = "1 tavolo aperto" end
        summary = summary .. "  |  " .. candidateTotal .. " candidati  |  " .. invitableTotal .. " ancora da invitare"
        self.activityTabSummary:SetText(summary)
        self.activityTabSummary:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    else
        self.activityTabSummary:SetText(#guild .. " tavoli pubblicati dagli altri membri  |  " .. joinedTotal .. " a cui hai aderito")
        self.activityTabSummary:SetTextColor(T.muted[1], T.muted[2], T.muted[3], T.muted[4] or 1)
    end

    local mineY = 0
    for i = 1, #mine do
        self:CreateActivityListRow(mine[i], mineY, self.activityMineList)
        mineY = mineY + ACTIVITY_ROW_H + 8
    end
    if #mine == 0 then
        local empty = W:AddDynamic(self.activityMineList, W:Card(self.activityMineList, 772, 92, true))
        empty:SetPoint("TOPLEFT", 0, 0)
        local title = W:Text(empty, "NON HAI ATTIVITA APERTE", 12, T.gold, "OUTLINE")
        title:SetPoint("TOPLEFT", 14, -17)
        local desc = W:Text(empty, "Crea un tavolo dal modulo sopra o usa + Att. dall'HUD. Qui compariranno sempre e solo le tue attivita.", 9, T.muted)
        desc:SetPoint("TOPLEFT", 14, -44); desc:SetWidth(730)
        mineY = 100
    end
    self.activityMineList:SetHeight(math.max(mineY, 212))

    local guildY = 0
    for i = 1, #guild do
        self:CreateActivityListRow(guild[i], guildY, self.activityGuildList)
        guildY = guildY + ACTIVITY_ROW_H + 8
    end
    if #guild == 0 then
        local empty = W:AddDynamic(self.activityGuildList, W:Card(self.activityGuildList, 772, 92, true))
        empty:SetPoint("TOPLEFT", 0, 0)
        local title = W:Text(empty, "NESSUNA ATTIVITA DELLA GILDA", 12, T.gold, "OUTLINE")
        title:SetPoint("TOPLEFT", 14, -17)
        local desc = W:Text(empty, "Quando un altro membro apre un tavolo comparira qui, separato dalle tue attivita.", 9, T.muted)
        desc:SetPoint("TOPLEFT", 14, -44); desc:SetWidth(730)
        guildY = 100
    end
    self.activityGuildList:SetHeight(math.max(guildY, 212))
end

