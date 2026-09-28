local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local function DateText(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "-" end
    if date then return date("%d/%m %H:%M", ts) end
    return tostring(ts)
end

function UI:CreateTreasuryPage()
    local p = self:CreatePage("CASSA")
    self:PageTitle(p, "Cassa Blackjack", "Registro dei 250g settimanali. Le richieste arrivano dai claim reali; GM/officer possono confermare i pagamenti e verificare il log della banca.")

    local summary = W:Card(p, 814, 102, true)
    summary:SetPoint("TOPLEFT", 2, -68)
    self.treasurySummary = summary

    self.treasuryAccess = W:Text(summary, "", 12, T.gold, "OUTLINE")
    self.treasuryAccess:SetPoint("TOPLEFT", 14, -12)

    self.treasuryStats = W:Text(summary, "", 11, T.text)
    self.treasuryStats:SetPoint("TOPLEFT", 14, -38)
    self.treasuryStats:SetWidth(500)

    self.treasuryStatus = W:Text(summary, "", 9, T.muted)
    self.treasuryStatus:SetPoint("TOPLEFT", 14, -65)
    self.treasuryStatus:SetWidth(520)

    self.treasuryVerify = W:Button(summary, "Verifica banca", 130, 32, "disabled")
    self.treasuryVerify:SetPoint("RIGHT", -14, 8)
    self.treasuryVerify:SetScript("OnClick", function()
        local ok, err = BJ.Treasury:QueryBankLog()
        if not ok and err then BJ:Print(err) end
        C_Timer.After(0.8, function()
            if BJ.Treasury and BJ.Treasury.bankOpen then BJ.Treasury:ScanBankLog() end
        end)
        UI:RefreshPage("CASSA")
    end)

    local hint = W:Text(p, "DA PAGARE", 10, T.gold)
    hint:SetPoint("TOPLEFT", 2, -188)

    self.treasuryScroll, self.treasuryList = W:ScrollArea(p, 810, 407)
    self.treasuryScroll:SetPoint("TOPLEFT", 2, -209)

    self:RegisterRefresher("CASSA", function() UI:RefreshTreasury() end)
end

function UI:RefreshTreasury()
    if BJ.Treasury then BJ.Treasury:RequestState(false) end
    local officer = BJ.Treasury and BJ.Treasury:IsOfficer()
    local isTest = BJ.TestMode and BJ.TestMode:IsEnabled()
    local pendingCount, pendingGold = BJ.Treasury:GetPendingCount()

    if isTest then
        self.treasuryAccess:SetText(officer and "SANDBOX TEST - GM/OFFICER" or "SANDBOX TEST - SOLA LETTURA")
        self.treasuryAccess:SetTextColor(UI.UnpackColor(T.red))
        self.treasuryStats:SetText("Richieste TEST da pagare: |cffffffff" .. pendingCount .. "|r   Totale simulato: |cfff0c868" .. pendingGold .. "g|r")
    elseif officer then
        self.treasuryAccess:SetText("ACCESSO GM/OFFICER")
        self.treasuryAccess:SetTextColor(UI.UnpackColor(T.accent))
        self.treasuryStats:SetText("Da pagare: |cffffffff" .. pendingCount .. "|r   Totale: |cfff0c868" .. pendingGold .. "g|r")
    else
        self.treasuryAccess:SetText("REGISTRO IN SOLA LETTURA")
        self.treasuryAccess:SetTextColor(UI.UnpackColor(T.muted))
        self.treasuryStats:SetText("I pagamenti possono essere confermati soltanto da GM/officer autorizzati.")
    end

    local status = BJ.Treasury.lastStatus or (isTest
        and "Sandbox TEST: le richieste simulate si sincronizzano solo tra client con Modalita Test attiva."
        or "Le richieste vengono sincronizzate quando i giocatori con l'addon sono online.")
    if BJ.Treasury.lastBankScan and BJ.Treasury.lastBankScan > 0 then
        status = status .. " Ultima verifica: " .. DateText(BJ.Treasury.lastBankScan) .. "."
    end
    self.treasuryStatus:SetText(status)

    local canVerify = officer and BJ.Treasury.bankOpen and not isTest
    self.treasuryVerify:SetKind(canVerify and "primary" or "disabled")
    self.treasuryVerify:SetText(isTest and "Banca off in TEST" or (canVerify and "Verifica banca" or "Banca non aperta"))
    if canVerify then self.treasuryVerify:Enable() else self.treasuryVerify:Disable() end
    self.treasuryVerify:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        if canVerify then
            GameTooltip:SetText("Verifica registro banca", 1, 1, 1)
            GameTooltip:AddLine("Legge il money log della Guild Bank e abbina i prelievi da 250g alle richieste in Cassa.", 0.84, 0.88, 0.85, true)
        else
            GameTooltip:SetText("Banca di gilda non aperta", 1, 1, 1)
            GameTooltip:AddLine("Questo pulsante non apre la banca da remoto. Devi interagire fisicamente con una Guild Bank; a quel punto diventera Verifica banca.", 0.84, 0.88, 0.85, true)
        end
        GameTooltip:Show()
    end)
    self.treasuryVerify:SetScript("OnLeave", function() GameTooltip:Hide() end)

    W:ClearDynamic(self.treasuryList)
    local rows = BJ.Treasury:GetClaimsSorted()
    local y = 0
    if #rows == 0 then
        local empty = W:AddDynamic(self.treasuryList, W:Card(self.treasuryList, 772, 76))
        empty:SetPoint("TOPLEFT", 0, 0)
        local t = W:Text(empty, "Nessuna richiesta 250g sincronizzata in questa modalita.", 12, T.muted)
        t:SetPoint("LEFT", 14, 0)
        y = 84
    else
        for i = 1, #rows do
            local claim = rows[i]
            local paid = claim.status == "PAID"
            local row = W:AddDynamic(self.treasuryList, W:Card(self.treasuryList, 772, 82, paid))
            row:SetPoint("TOPLEFT", 0, -y)

            local name = W:Text(row, BJ:ShortName(claim.player), 13, paid and T.muted or T.white, "OUTLINE")
            name:SetPoint("TOPLEFT", 14, -12)
            name:SetWidth(230)

            local sub = W:Text(row, (claim.amount or 250) .. "g  |  claim " .. DateText(claim.claimTime), 9, T.muted)
            sub:SetPoint("TOPLEFT", 14, -35)
            sub:SetWidth(400)

            local state = W:Text(row, paid and "PAGATO" or "DA PAGARE", 10, paid and T.accent or T.gold)
            state:SetPoint("TOPLEFT", 14, -56)
            if paid then
                local method = claim.method == "BANK" and "banca verificata" or "manuale"
                state:SetText("PAGATO - " .. method .. " - " .. DateText(claim.paidAt))
            end

            local action = W:Button(row, paid and "Pagato" or "Segna pagato", 126, 30, "disabled")
            action:SetPoint("RIGHT", -12, 0)
            if officer and not paid then
                action:SetKind("primary")
                action:Enable()
                action:SetScript("OnClick", function()
                    local ok, err = BJ.Treasury:MarkPaid(claim.player, claim.weekKey, "MANUAL")
                    if not ok and err then BJ:Print(err) end
                    UI:RefreshTreasury()
                end)
            else
                action:SetKind("disabled")
                action:Disable()
                action:SetScript("OnClick", nil)
            end

            y = y + 90
        end
    end
    self.treasuryList:SetHeight(math.max(y, 400))
end
