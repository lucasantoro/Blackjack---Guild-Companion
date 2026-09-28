local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

function UI:CreateMembersPage()
    local p = self:CreatePage("MEMBERS")
    self:PageTitle(p, "Blackjack Passport", "La scheda sociale del personaggio: presentati, fai sapere cosa ti piace fare e in cosa puoi aiutare gli altri.")

    local listCard = W:Card(p, 300, 515, true)
    listCard:SetPoint("TOPLEFT", 2, -68)
    local lt = W:Text(listCard, "MEMBRI ONLINE", 10, T.gold)
    lt:SetPoint("TOPLEFT", 12, -12)

    self.memberScroll, self.memberList = W:ScrollArea(listCard, 270, 466)
    self.memberScroll:SetPoint("TOPLEFT", 10, -38)

    local detail = W:Card(p, 500, 515, true)
    detail:SetPoint("TOPLEFT", 314, -68)
    self.memberDetail = detail

    self.memberName = W:Text(detail, BJ:ShortName(BJ.player), 18, T.white, "OUTLINE")
    self.memberName:SetPoint("TOPLEFT", 16, -14)
    self.memberName:SetWidth(290)

    self.myPassportButton = W:Button(detail, "Il mio Passport", 150, 30, "primary")
    self.myPassportButton:SetPoint("TOPRIGHT", -16, -13)
    self.myPassportButton:SetScript("OnClick", function()
        UI:OpenMyPassport()
    end)

    self.memberRank = W:Text(detail, "", 10, T.muted)
    self.memberRank:SetPoint("TOPLEFT", self.memberName, "BOTTOMLEFT", 0, -5)

    self.memberTitle = W:Text(detail, "", 11, T.gold)
    self.memberTitle:SetPoint("TOPLEFT", 16, -61)

    self.memberBadge = W:Text(detail, "", 10, T.accent)
    self.memberBadge:SetPoint("TOPLEFT", 16, -82)

    self.profileModeHint = W:Text(detail, "", 9, T.muted)
    self.profileModeHint:SetPoint("TOPLEFT", 16, -105)
    self.profileModeHint:SetWidth(460)

    self.profileLabels = {}
    self.profileBoxes = {}
    local fields = {
        { key="tagline", label="Frase personale", y=-134, max=56 },
        { key="likes", label="Mi piace fare", y=-201, max=56 },
        { key="help", label="Puoi chiedermi aiuto per", y=-268, max=56 },
        { key="alts", label="Alt principali", y=-335, max=40 },
    }

    for i = 1, #fields do
        local field = fields[i]
        local l = W:SectionLabel(detail, field.label)
        l:SetPoint("TOPLEFT", 16, field.y)

        local b = W:EditBox(detail, 466, 31, field.max, false)
        b:SetPoint("TOPLEFT", 16, field.y - 20)
        b:SetScript("OnTextChanged", function(_, userInput)
            if userInput and not UI.loadingProfile and UI.selectedMember == BJ.player then
                UI.profileDirty = true
                UI:RefreshPassportEditState()
            end
        end)

        self.profileLabels[field.key] = l
        self.profileBoxes[field.key] = b
    end

    self.profileSave = W:Button(detail, "Salva e sincronizza", 170, 32, "primary")
    self.profileSave:SetPoint("BOTTOMLEFT", 16, 16)
    self.profileSave:SetScript("OnClick", function() UI:SaveMyProfile() end)

    self.profileWhisper = W:Button(detail, "Whisper", 110, 32)
    self.profileWhisper:SetPoint("BOTTOMLEFT", 196, 16)
    self.profileWhisper:SetScript("OnClick", function()
        if UI.selectedMember and UI.selectedMember ~= BJ.player then
            ChatFrame_SendTell(UI.selectedMember)
        end
    end)

    self.memberSummary = W:Text(detail, "", 9, T.muted)
    self.memberSummary:SetPoint("BOTTOMRIGHT", -16, 18)
    self.memberSummary:SetWidth(180)
    self.memberSummary:SetJustifyH("RIGHT")

    self.selectedMember = BJ.player
    self.profileDirty = false
    self:RegisterRefresher("MEMBERS", function() UI:RefreshMembers() end)
end

function UI:OpenMyPassport()
    if not self.pages or not self.pages.MEMBERS then return end
    self:SelectMember(BJ.player)
    for _, box in pairs(self.profileBoxes or {}) do
        box:EnableMouse(true)
    end
end

function UI:RefreshPassportEditState()
    if not self.profileModeHint then return end
    local mine = self.selectedMember == BJ.player
    if mine then
        if self.profileDirty then
            self.profileModeHint:SetText("IL MIO PASSPORT - modifiche non salvate")
            self.profileModeHint:SetTextColor(UI.UnpackColor(T.gold))
            self.profileSave:SetText("Salva e sincronizza")
            self.profileSave:SetKind("primary")
            self.profileSave:Enable()
        else
            self.profileModeHint:SetText("IL MIO PASSPORT - puoi modificare i campi qui sotto")
            self.profileModeHint:SetTextColor(UI.UnpackColor(T.accent))
            self.profileSave:SetText("Salvato")
            self.profileSave:SetKind("disabled")
            self.profileSave:Disable()
        end
    else
        self.profileModeHint:SetText("PROFILO IN SOLA LETTURA - usa 'Il mio Passport' per modificare il tuo")
        self.profileModeHint:SetTextColor(UI.UnpackColor(T.muted))
    end
end

function UI:RefreshMembers()
    W:ClearDynamic(self.memberList)
    local members = BJ.Guild:GetOnlineMembers()
    local y = 0

    for i = 1, #members do
        local info = members[i]
        local row = W:AddDynamic(self.memberList, W:Button(self.memberList, "", 244, 34))
        row:SetPoint("TOPLEFT", 0, -y)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetJustifyH("LEFT")

        local hasAddon = (info.name == BJ.player) or (BJ.db.network.peers[info.name] and (BJ:Now() - (BJ.db.network.peers[info.name].lastSeen or 0) < 900))
        local prefix = hasAddon and "|cff7effa8[ON]|r " or "|cff59635e[--]|r "
        local mineTag = info.name == BJ.player and " |cfff0c868[IO]|r" or ""
        row:SetText(prefix .. BJ:ShortName(info.name) .. mineTag)
        row.label:SetTextColor(UI.UnpackColor(UI.ClassColor(info.class)))
        row:SetScript("OnClick", function() UI:SelectMember(info.name) end)

        y = y + 38
    end

    self.memberList:SetHeight(math.max(y, 460))
    self:SelectMember(self.selectedMember or BJ.player)
end

function UI:SelectMember(name)
    self.selectedMember = name or BJ.player
    local mine = self.selectedMember == BJ.player
    if not mine and BJ.Comms and BJ.Comms.RequestProfile then
        BJ.Comms:RequestProfile(self.selectedMember)
    end
    local info = BJ.Guild.members[self.selectedMember] or {}
    local profile = mine and BJ.profile or BJ.db.network.profiles[self.selectedMember] or {}
    if BJ.TestMode and BJ.TestMode:IsEnabled() then
        local testProfile = {}
        for k, v in pairs(profile) do testProfile[k] = v end
        if mine then
            testProfile.titleId = BJ.Rewards:GetEquippedTitleId()
            testProfile.badgeId = BJ.Rewards:GetEquippedBadgeId()
        else
            BJ.TestMode:Initialize()
            local remoteTest = BJ.db.test.remoteProfiles[self.selectedMember]
            if remoteTest then
                testProfile.titleId = remoteTest.titleId or testProfile.titleId
                testProfile.badgeId = remoteTest.badgeId or testProfile.badgeId
            end
        end
        profile = testProfile
    end

    local titleReward = BJ.Data:GetReward(profile.titleId or "starter")
    local badgeReward = profile.badgeId and profile.badgeId ~= "" and BJ.Data:GetReward(profile.badgeId) or nil
    if badgeReward and badgeReward.type ~= "badge" then badgeReward = nil end

    self.memberName:SetText(BJ:ShortName(self.selectedMember))
    self.memberName:SetTextColor(UI.UnpackColor(UI.ClassColor(info.class)))
    self.memberRank:SetText((info.rankName or "Membro Blackjack") .. (info.zone and info.zone ~= "" and (" - " .. info.zone) or ""))
    self.memberTitle:SetText("Titolo: |cffffffff" .. (titleReward.title or "Credere nel piano") .. "|r")
    self.memberBadge:SetText(badgeReward and ("Badge: |cffffffff" .. badgeReward.title:gsub("^Badge:%s*", "") .. "|r") or "Badge: nessuno")

    self.loadingProfile = true
    for key, box in pairs(self.profileBoxes) do
        box:SetText(profile[key] or "")
        if mine then box:Enable() else box:Disable() end
        box:EnableMouse(mine)
        box:SetAlpha(mine and 1 or 0.72)
    end
    self.loadingProfile = false

    if mine then self.profileDirty = false end
    self.profileSave:SetShown(mine)
    self.profileWhisper:SetShown(not mine)
    self:RefreshPassportEditState()

    local s = mine and {
        lifetime=BJ.Rewards:GetLifetime(),
        completed=BJ.Challenges:GetCompletedCount(),
        mplusGuildRuns=BJ.Progress:GetStat("mplusGuildRuns"),
        weeklyGoldClaimed=BJ.Rewards:HasClaimedWeeklyGold(),
    } or BJ.db.network.summaries[self.selectedMember]

    if s then
        local goldLine = s.weeklyGoldClaimed and "\n250g sett.: richiesti" or ""
        self.memberSummary:SetText((s.completed or 0) .. " challenge\n" .. (s.mplusGuildRuns or 0) .. " M+ gilda\n" .. (s.lifetime or 0) .. " fiches totali" .. goldLine)
    else
        self.memberSummary:SetText("Nessun riepilogo\nsincronizzato")
    end
end

function UI:SaveMyProfile()
    if self.selectedMember ~= BJ.player then
        self:OpenMyPassport()
        return
    end

    BJ.profile.tagline = BJ:Utf8Truncate(self.profileBoxes.tagline:GetText(), 56)
    BJ.profile.likes = BJ:Utf8Truncate(self.profileBoxes.likes:GetText(), 56)
    BJ.profile.help = BJ:Utf8Truncate(self.profileBoxes.help:GetText(), 56)
    BJ.profile.alts = BJ:Utf8Truncate(self.profileBoxes.alts:GetText(), 40)
    local now = BJ:Now()
    BJ.profile.updated = math.max(now, (tonumber(BJ.profile.updated) or 0) + 1)
    self.profileDirty = false
    self:RefreshPassportEditState()
    if BJ.Comms then BJ.Comms:BroadcastProfile() end
    BJ:Print("Passport salvato. Sincronizzazione inviata alla gilda.")
end
