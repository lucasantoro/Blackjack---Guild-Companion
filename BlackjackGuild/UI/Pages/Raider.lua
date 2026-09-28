local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local function DateText(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "-" end
    return date and date("%d/%m/%Y %H:%M", ts) or tostring(ts)
end

local function StatusColor(status)
    if status == "IN REGOLA" then return T.accent end
    if status == "PARZIALE" or status == "DA PAGARE" then return T.gold end
    if status == "INSOLUTO" then return T.red end
    return T.muted
end

local function ParseGold(text)
    local s = tostring(text or ""):gsub("%s+", "")
    s = s:gsub("%.", ""):gsub(",", ".")
    return tonumber(s)
end

local function LedgerSourceLabel(source)
    if source == "BANK" then return "BANCA" end
    if source == "MANUAL" then return "RETTIFICA" end
    return tostring(source or "MOVIMENTO")
end

function UI:CreateRaiderPage()
    local p = self:CreatePage("RAIDER")
    self:PageTitle(p, "Raider", "Contributo mensile alla Guild Bank: 8.000g da settembre 2026. I depositi vengono distribuiti automaticamente dal primo mese non saldato.")

    self.raiderTab = "MINE"
    self.raiderYear = select(1, BJ.Raider:GetCurrentDate())
    self.raiderAdminYear = self.raiderYear
    self.raiderDetailPlayer = nil

    self.raiderMineTab = W:Button(p, "Il mio contributo", 165, 32, "primary")
    self.raiderMineTab:SetPoint("TOPLEFT", 2, -58)
    self.raiderMineTab:SetScript("OnClick", function()
        UI.raiderTab = "MINE"
        UI.raiderDetailPlayer = nil
        UI:RefreshRaider()
    end)

    self.raiderOverviewTab = W:Button(p, "Panoramica Raider", 170, 32, "disabled")
    self.raiderOverviewTab:SetPoint("LEFT", self.raiderMineTab, "RIGHT", 8, 0)
    self.raiderOverviewTab:SetScript("OnClick", function()
        if not BJ.Raider:CanManage() then return end
        UI.raiderTab = "OVERVIEW"
        UI.raiderDetailPlayer = nil
        UI:RefreshRaider()
    end)

    self.raiderStatus = W:Text(p, "", 9, T.muted)
    self.raiderStatus:SetPoint("TOPRIGHT", -2, -68)
    self.raiderStatus:SetWidth(430)
    self.raiderStatus:SetJustifyH("RIGHT")

    self.raiderBody = CreateFrame("Frame", nil, p)
    self.raiderBody:SetPoint("TOPLEFT", 2, -102)
    self.raiderBody:SetPoint("BOTTOMRIGHT", -2, 2)
    self.raiderBody._dynamic = {}

    self:RegisterRefresher("RAIDER", function() UI:RefreshRaider() end)
end

function UI:RaiderAddMonthCard(container, player, state, x, y, width, adminControls)
    width = tonumber(width) or 393
    local card = W:AddDynamic(container, W:Card(container, width, 52, BJ.Raider:IsPaidAmount(state.paid, state.due) and state.active and not state.exempt))
    card:SetPoint("TOPLEFT", x, y)

    local monthName = BJ.Raider:GetMonthLabel(state.month):upper()
    local label = W:Text(card, monthName .. " " .. tostring(state.year), 10, state.active and T.white or T.muted, "OUTLINE")
    label:SetPoint("TOPLEFT", 10, -8)
    -- Some localized month names (SETTEMBRE/NOVEMBRE/DICEMBRE) need more
    -- room than the old fixed 90 px label. Keep the text inside its card.
    local labelWidth = math.max(112, math.min(138, math.floor(width * 0.35)))
    label:SetWidth(labelWidth)
    label:SetWordWrap(false)

    local statusText, statusColor
    if not state.active then
        statusText, statusColor = "N/A", T.muted
    elseif state.exempt then
        statusText, statusColor = "ESENTE", T.blue
    elseif BJ.Raider:IsPaidAmount(state.paid, state.due) then
        statusText, statusColor = "SALDATO", T.accent
    elseif state.paid > 0 then
        statusText, statusColor = BJ.Raider:FormatGold(state.paid) .. " / 8.000g", T.gold
    else
        statusText, statusColor = "0 / 8.000g", T.muted
    end

    local status = W:Text(card, statusText, 9, statusColor)
    status:SetPoint("TOPRIGHT", adminControls and -82 or -10, -8)
    status:SetWidth(math.max(105, width - labelWidth - (adminControls and 112 or 40)))
    status:SetJustifyH("RIGHT")
    status:SetWordWrap(false)

    local bar = CreateFrame("Frame", nil, card, "BackdropTemplate")
    bar:SetPoint("BOTTOMLEFT", 10, 9)
    bar:SetPoint("BOTTOMRIGHT", adminControls and -82 or -10, 9)
    bar:SetHeight(12)
    W:Backdrop(bar, T.bgDeep, T.line)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    local ratio = 0
    if state.exempt then ratio = 1
    elseif state.due and state.due > 0 then ratio = math.max(0, math.min(1, (state.paid or 0) / state.due)) end
    fill:SetWidth(math.max(1, (bar:GetWidth() > 0 and bar:GetWidth() or (width - 20 - (adminControls and 72 or 0))) * ratio))
    fill:SetHeight(10)
    fill:SetColorTexture((state.exempt and T.blue[1]) or (ratio >= 1 and T.accentStrong[1] or T.gold[1]), (state.exempt and T.blue[2]) or (ratio >= 1 and T.accentStrong[2] or T.gold[2]), (state.exempt and T.blue[3]) or (ratio >= 1 and T.accentStrong[3] or T.gold[3]), 0.90)
    if ratio <= 0 then fill:Hide() end

    if adminControls and state.active then
        local exempt = W:Button(card, state.exempt and "Ripristina" or "Esenta", 66, 28, state.exempt and "default" or "disabled")
        exempt:SetPoint("RIGHT", -8, -4)
        exempt:Enable()
        exempt:SetScript("OnClick", function()
            local ok, err = BJ.Raider:SetExempt(player, state.year, state.month, not state.exempt)
            if not ok and err then BJ:Print(err) end
            UI:RefreshRaider()
        end)
    end
end

function UI:RaiderRenderYear(container, player, year, adminControls, yOffset)
    local months, yearPaid, yearDue, credit = BJ.Raider:GetYearState(player, year)
    local startY = yOffset or -104

    -- The Raider page has an 814 px design width, but calculate the two
    -- month columns from the actual container so they cannot escape the UI
    -- if the parent is narrower (for example inside the admin scroll view).
    local available = tonumber(container:GetWidth()) or 814
    if available <= 0 then available = 814 end
    available = math.min(814, available)
    local gap = 16
    local cardWidth = math.floor((available - gap) / 2)
    local rightX = cardWidth + gap

    for i = 1, 6 do
        self:RaiderAddMonthCard(container, player, months[i], 0, startY - (i - 1) * 59, cardWidth, adminControls)
        self:RaiderAddMonthCard(container, player, months[i + 6], rightX, startY - (i - 1) * 59, cardWidth, adminControls)
    end
    return yearPaid, yearDue, credit
end

function UI:RaiderYearControls(container, year, setter, anchorY)
    local prev = W:AddDynamic(container, W:Button(container, "<", 34, 28))
    prev:SetPoint("TOPLEFT", 0, anchorY)
    prev:SetScript("OnClick", function() setter(year - 1) end)
    local txt = W:AddDynamic(container, W:Text(container, tostring(year), 13, T.white, "OUTLINE"))
    txt:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    txt:SetWidth(70)
    txt:SetJustifyH("CENTER")
    local next = W:AddDynamic(container, W:Button(container, ">", 34, 28))
    next:SetPoint("LEFT", txt, "RIGHT", 12, 0)
    next:SetScript("OnClick", function() setter(year + 1) end)
    return next
end

function UI:RaiderRenderMine()
    local c = self.raiderBody
    local player = BJ.player
    local active = BJ.Raider:IsRaider(player)
    local status, missing, firstOpen = BJ.Raider:GetStatus(player)
    local total, lastAmount, lastTime = BJ.Raider:GetContributionTotal(player)

    local summary = W:AddDynamic(c, W:Card(c, 814, 88, true))
    summary:SetPoint("TOPLEFT", 0, 0)
    local title = W:Text(summary, active and "CONTRIBUTO RAIDER ATTIVO" or "CONTRIBUTO NON ATTIVO", 11, active and T.accent or T.muted, "OUTLINE")
    title:SetPoint("TOPLEFT", 14, -12)
    local rank = BJ.Raider:GetRankInfo(player) or "-"
    local sub = W:Text(summary, BJ:ShortName(player) .. "  |  " .. rank .. "  |  Totale registrato: " .. BJ.Raider:FormatGold(total), 10, T.text)
    sub:SetPoint("TOPLEFT", 14, -35)
    local state = W:Text(summary, active and status or "NON SOGGETTO", 11, StatusColor(status), "OUTLINE")
    state:SetPoint("TOPRIGHT", -14, -12)
    state:SetJustifyH("RIGHT")
    local detail = "Ultimo deposito: " .. (lastTime > 0 and (BJ.Raider:FormatGold(lastAmount) .. " - " .. DateText(lastTime)) or "nessun movimento sincronizzato")
    if active and missing > 0 and firstOpen then
        detail = detail .. "   |   Mancano " .. BJ.Raider:FormatGold(firstOpen.missing) .. " per " .. BJ.Raider:GetMonthLabel(firstOpen.month) .. " " .. firstOpen.year
    end
    local last = W:Text(summary, detail, 9, T.muted)
    last:SetPoint("TOPLEFT", 14, -61)
    last:SetWidth(780)

    local year = tonumber(self.raiderYear) or BJ.Raider.START_YEAR
    self:RaiderYearControls(c, year, function(v) UI.raiderYear = math.max(BJ.Raider.START_YEAR, v); UI:RefreshRaider() end, -99)
    local yp, yd, credit = self:RaiderRenderYear(c, player, year, false, -138)
    local yr = W:AddDynamic(c, W:Text(c, "Anno: " .. BJ.Raider:FormatGold(yp) .. " / " .. BJ.Raider:FormatGold(yd) .. "   |   Credito oltre l'anno: " .. BJ.Raider:FormatGold(credit), 9, T.muted))
    yr:SetPoint("TOPRIGHT", -10, -106)
    yr:SetJustifyH("RIGHT")
end

function UI:RaiderRenderOverviewList()
    local c = self.raiderBody
    local stats = BJ.Raider:GetOverallStats()
    local summary = W:AddDynamic(c, W:Card(c, 814, 78, true))
    summary:SetPoint("TOPLEFT", 0, 0)
    local a = W:Text(summary, "RAIDER ATTIVI  " .. stats.active, 11, T.white, "OUTLINE")
    a:SetPoint("TOPLEFT", 14, -13)
    local b = W:Text(summary, "In regola: " .. stats.ok .. "   |   Parziali/da pagare: " .. stats.partial .. "   |   Insoluti: " .. stats.overdue .. "   |   Flag non attive: " .. stats.inactive, 10, T.text)
    b:SetPoint("TOPLEFT", 14, -38)
    local unassigned = #BJ.Raider:GetUnassigned()
    local pendingReceipts = BJ.Raider:GetPendingReceiptCount()
    local bank = W:Text(summary, "Depositi da attribuire: " .. unassigned .. "   |   Segnalazioni da verificare: " .. pendingReceipts
        .. "   |   Money log: " .. tostring(BJ.Raider.lastMoneyLogCount or 0)
        .. " righe   |   Nuovi: " .. tostring(BJ.Raider.lastBankImported or 0), 9, (unassigned > 0 or pendingReceipts > 0) and T.gold or T.muted)
    bank:SetPoint("TOPLEFT", 14, -59)

    local verify = W:Button(summary, BJ.Raider.bankOpen and "Aggiorna banca" or "Apri Guild Bank", 130, 30, BJ.Raider.bankOpen and "primary" or "disabled")
    verify:SetPoint("RIGHT", -14, 0)
    if BJ.Raider.bankOpen then
        verify:Enable()
        verify:SetScript("OnClick", function()
            local ok, err = BJ.Raider:QueryBankLog("MANUAL")
            if not ok and err then BJ:Print(err) end
            -- ScanBankLog is intentionally NOT called on a timer here: we wait
            -- for Blizzard's GUILDBANKLOG_UPDATE so we never import stale rows.
        end)
    else
        verify:Disable()
    end

    local h = W:AddDynamic(c, W:Text(c, "RAIDER / CANDIDATI", 10, T.gold))
    h:SetPoint("TOPLEFT", 0, -94)

    local scroll = W:AddDynamic(c, select(1, W:ScrollArea(c, 810, 397)))
    local list = scroll:GetScrollChild()
    W:AddDynamic(c, list)
    scroll:SetPoint("TOPLEFT", 0, -116)
    local rows = BJ.Raider:GetEligibleMembers(true)
    local y = 0
    for _, member in ipairs(rows) do
        local status = member.active and BJ.Raider:GetStatus(member.name) or "NON SOGGETTO"
        local cy = select(1, BJ.Raider:GetCurrentDate())
        local _, paidYear, dueYear = BJ.Raider:GetYearState(member.name, cy)
        local row = W:Card(list, 772, 58, member.active)
        row:SetPoint("TOPLEFT", 0, -y)
        local n = W:Text(row, BJ:ShortName(member.name), 12, member.active and T.white or T.muted, "OUTLINE")
        n:SetPoint("TOPLEFT", 12, -10); n:SetWidth(180)
        local r = W:Text(row, member.rankName, 9, T.muted)
        r:SetPoint("TOPLEFT", 12, -32); r:SetWidth(180)
        local st = W:Text(row, status, 10, member.active and StatusColor(status) or T.muted, "OUTLINE")
        st:SetPoint("LEFT", 220, 0); st:SetWidth(120)
        local gold = W:Text(row, BJ.Raider:FormatGold(paidYear) .. " / " .. BJ.Raider:FormatGold(dueYear), 9, T.text)
        gold:SetPoint("LEFT", 365, 0); gold:SetWidth(180)
        local open = W:Button(row, "Dettaglio", 94, 28)
        open:SetPoint("RIGHT", -12, 0)
        open:SetScript("OnClick", function() UI.raiderDetailPlayer = member.name; UI.raiderAdminYear = cy; UI:RefreshRaider() end)
        y = y + 64
    end
    list:SetHeight(math.max(390, y))
end

function UI:RaiderRenderAdminDetail(player)
    local body = self.raiderBody

    -- The admin detail has more controls above the twelve month cards than
    -- the personal view. Previously the last months were drawn below the
    -- bottom edge of the Raider page. Keep the whole detail inside the UI
    -- and scroll only this view when necessary.
    local scroll, c = W:ScrollArea(body, 840, 490)
    W:AddDynamic(body, scroll)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -2, 0)
    c:SetWidth(814)
    c:SetHeight(590)

    local back = W:AddDynamic(c, W:Button(c, "< Panoramica", 112, 28))
    back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() UI.raiderDetailPlayer = nil; UI:RefreshRaider() end)

    local rank = BJ.Raider:GetRankInfo(player) or "-"
    local active = BJ.Raider:IsRaider(player)
    local status = active and BJ.Raider:GetStatus(player) or "NON SOGGETTO"
    local total = BJ.Raider:GetContributionTotal(player)
    local title = W:AddDynamic(c, W:Text(c, BJ:ShortName(player) .. "  |  " .. rank, 14, T.white, "OUTLINE"))
    title:SetPoint("LEFT", back, "RIGHT", 14, 0)
    local st = W:AddDynamic(c, W:Text(c, status, 10, active and StatusColor(status) or T.muted, "OUTLINE"))
    st:SetPoint("TOPRIGHT", -6, -6)

    if BJ.Raider:IsFlagRank(player) then
        local flag = W:AddDynamic(c, W:Button(c, active and "Raider: SI" or "Raider: NO", 100, 28, active and "primary" or "disabled"))
        flag:SetPoint("TOPRIGHT", -120, 0)
        flag:Enable()
        flag:SetScript("OnClick", function()
            local ok, err = BJ.Raider:SetFlag(player, not active)
            if not ok and err then BJ:Print(err) end
            UI:RefreshRaider()
        end)
    end

    local controls = W:AddDynamic(c, W:Card(c, 814, 116, true))
    controls:SetPoint("TOPLEFT", 0, -38)
    local totalText = W:Text(controls, "Totale ledger: " .. BJ.Raider:FormatGold(total), 9, T.muted)
    totalText:SetPoint("TOPLEFT", 12, -10)
    local help = W:Text(controls, "La rettifica modifica il totale: +8000 aggiunge 8.000g, -1000 sottrae 1.000g.", 8, T.muted)
    help:SetPoint("TOPRIGHT", -12, -10); help:SetWidth(480); help:SetJustifyH("RIGHT")

    local amountLabel = W:Text(controls, "IMPORTO RETTIFICA (GOLD)", 8, T.gold, "OUTLINE")
    amountLabel:SetPoint("TOPLEFT", 12, -36)
    local amount = W:EditBox(controls, 120, 28, 14, false)
    amount:SetPoint("TOPLEFT", 12, -52)
    amount:SetText("")

    local noteLabel = W:Text(controls, "NOTA (OPZIONALE)", 8, T.gold, "OUTLINE")
    noteLabel:SetPoint("TOPLEFT", 148, -36)
    local note = W:EditBox(controls, 210, 28, 60, false)
    note:SetPoint("TOPLEFT", 148, -52)

    local adjust = W:Button(controls, "Registra rettifica", 126, 28, "primary")
    adjust:SetPoint("TOPLEFT", 368, -52)
    adjust:SetScript("OnClick", function()
        local gold = ParseGold(amount:GetText())
        local ok, err = BJ.Raider:AddManualAdjustment(player, gold, note:GetText())
        if not ok and err then
            BJ:Print(err)
        else
            amount:SetText("")
            note:SetText("")
        end
        UI:RefreshRaider()
    end)

    local altLabel = W:Text(controls, "ALT DA ASSOCIARE AL RAIDER", 8, T.gold, "OUTLINE")
    altLabel:SetPoint("TOPLEFT", 515, -36)
    local alt = W:EditBox(controls, 130, 28, 40, false)
    alt:SetPoint("TOPLEFT", 515, -52)
    local map = W:Button(controls, "Associa", 72, 28)
    map:SetPoint("LEFT", alt, "RIGHT", 6, 0)
    map:SetScript("OnClick", function()
        local ok, err = BJ.Raider:SetAltMapping(alt:GetText(), player)
        if not ok and err then BJ:Print(err) end
        UI:RefreshRaider()
    end)
    local unmap = W:Button(controls, "Rimuovi mapping", 120, 28)
    unmap:SetPoint("TOPLEFT", 515, -84)
    unmap:SetScript("OnClick", function()
        local ok, err = BJ.Raider:SetAltMapping(alt:GetText(), nil)
        if not ok and err then BJ:Print(err) end
        UI:RefreshRaider()
    end)

    local alts = BJ.Raider:GetAltsFor(player)
    local altText = W:AddDynamic(c, W:Text(c, "Alt associati: " .. (#alts > 0 and table.concat((function()
        local t = {}; for i=1,#alts do t[i] = BJ:ShortName(alts[i]) end; return t
    end)(), ", ") or "nessuno"), 8, T.muted))
    altText:SetPoint("TOPRIGHT", -6, -160)
    altText:SetWidth(390); altText:SetJustifyH("RIGHT")

    local ledger = BJ.Raider:GetLedgerFor(player)
    local pieces = {}
    for i = #ledger, math.max(1, #ledger - 2), -1 do
        local e = ledger[i]
        local amountValue = tonumber(e.amount) or 0
        local sign = amountValue >= 0 and "+" or ""
        pieces[#pieces + 1] = sign .. BJ.Raider:FormatGold(amountValue) .. " " .. LedgerSourceLabel(e.source)
            .. (e.note and e.note ~= "" and (" (" .. e.note .. ")") or "")
    end
    local recent = W:AddDynamic(c, W:Text(c, "Ultimi movimenti: " .. (#pieces > 0 and table.concat(pieces, "  |  ") or "nessuno"), 8, T.text))
    recent:SetPoint("TOPLEFT", 0, -160); recent:SetWidth(600)

    local year = tonumber(self.raiderAdminYear) or select(1, BJ.Raider:GetCurrentDate())
    self:RaiderYearControls(c, year, function(v) UI.raiderAdminYear = math.max(BJ.Raider.START_YEAR, v); UI:RefreshRaider() end, -184)
    local yp, yd, credit = self:RaiderRenderYear(c, player, year, true, -220)
    local yr = W:AddDynamic(c, W:Text(c, "Anno: " .. BJ.Raider:FormatGold(yp) .. " / " .. BJ.Raider:FormatGold(yd) .. "   |   Credito oltre l'anno: " .. BJ.Raider:FormatGold(credit), 9, T.muted))
    yr:SetPoint("TOPRIGHT", -10, -190); yr:SetJustifyH("RIGHT")
end

function UI:RefreshRaider()
    if not BJ.Raider then return end
    if not BJ.Raider:CanAccess() then
        if self.frame and self.frame:IsShown() and BJ.db.ui.lastPage == "RAIDER" then self:SelectPage("HOME") end
        if self.RefreshNavAccess then self:RefreshNavAccess() end
        return
    end

    W:ClearDynamic(self.raiderBody)
    local admin = BJ.Raider:CanManage()
    self.raiderOverviewTab:SetShown(admin)
    self.raiderMineTab:SetKind(self.raiderTab == "MINE" and "primary" or "default")
    self.raiderOverviewTab:SetKind(admin and (self.raiderTab == "OVERVIEW" and "primary" or "default") or "disabled")
    if admin then self.raiderOverviewTab:Enable() else self.raiderOverviewTab:Disable() end

    local status = BJ.Raider.lastStatus or "La banca va aperta fisicamente per importare nuovi depositi."
    if BJ.Raider:GetStore().lastBankScan > 0 then status = status .. " Ultima lettura: " .. DateText(BJ.Raider:GetStore().lastBankScan) end
    self.raiderStatus:SetText(status)

    if self.raiderTab == "OVERVIEW" and admin then
        if self.raiderDetailPlayer then self:RaiderRenderAdminDetail(self.raiderDetailPlayer) else self:RaiderRenderOverviewList() end
    else
        self.raiderTab = "MINE"
        self:RaiderRenderMine()
    end
end
