local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

local function ConfigureTestButton(button, enabled)
    button:SetKind(enabled and "primary" or "disabled")
    if enabled then button:Enable() else button:Disable() end
end

function UI:CreateSettingsPage()
    local p = self:CreatePage("SETTINGS")
    self:PageTitle(p, "Impostazioni & dati", "Qui trovi cosa viene salvato, cosa si resetta, sincronizzazione e laboratorio di test separato dai dati reali.")

    local display = W:Card(p, 814, 168, true)
    display:SetPoint("TOPLEFT", 2, -68)

    local dt = W:Text(display, "INTERFACCIA", 10, T.gold)
    dt:SetPoint("TOPLEFT", 14, -12)

    self.accessStatus = W:Text(display, "", 9, T.muted)
    self.accessStatus:SetPoint("TOPRIGHT", -14, -12)

    local strataLabel = W:SectionLabel(display, "Frame strata")
    strataLabel:SetPoint("TOPLEFT", 14, -44)

    local strataItems = {
        {id="HIGH",label="HIGH"},
        {id="DIALOG",label="DIALOG"},
        {id="FULLSCREEN_DIALOG",label="FULLSCREEN_DIALOG"},
        {id="TOOLTIP",label="TOOLTIP - sopra la UI normale"},
    }

    self.strataDD = W:Dropdown(display, 250, strataItems, BJ.db.settings.strata, function(value)
        BJ.db.settings.strata = value
        UI:ApplyFrameStrata()
        if BJ.HUD then BJ.HUD:ApplyFrameStrata() end
    end)
    self.strataDD:SetPoint("TOPLEFT", 14, -64)

    local directionLabel = W:SectionLabel(display, "Apertura HUD")
    directionLabel:SetPoint("TOPLEFT", 284, -44)

    local directionItems = {
        {id="DOWN",label="Verso il basso"},
        {id="UP",label="Verso l'alto"},
        {id="RIGHT",label="Verso destra"},
        {id="LEFT",label="Verso sinistra"},
    }

    self.hudDirectionDD = W:Dropdown(display, 180, directionItems, BJ.db.settings.hudExpandDirection or "DOWN", function(value)
        BJ.db.settings.hudExpandDirection = value or "DOWN"
        if BJ.HUD then BJ.HUD:ApplyExpandDirection() end
    end)
    self.hudDirectionDD:SetPoint("TOPLEFT", 284, -64)

    local hudResizeHint = W:Text(display, "HUD ridimensionabile: trascina l'angolo in basso a destra.", 8, T.muted)
    hudResizeHint:SetPoint("TOPLEFT", 482, -72)
    hudResizeHint:SetWidth(310)

    self.toggleMinimap = W:Toggle(display, "Pulsante minimappa", function()
        return BJ.db.settings.showMinimap
    end, function(v)
        BJ.db.settings.showMinimap = v
        if BJ.Minimap and BJ.Minimap.button then BJ.Minimap.button:SetShown(v) end
    end, 250)
    self.toggleMinimap:SetPoint("TOPLEFT", 14, -112)

    self.toggleProfile = W:Toggle(display, "Condividi Passport", function()
        return BJ.db.settings.shareProfile
    end, function(v)
        BJ.db.settings.shareProfile = v
        BJ.profile.updated = math.max(BJ:Now(), (tonumber(BJ.profile.updated) or 0) + 1)
        if BJ.Comms then BJ.Comms:BroadcastProfile() end
    end, 250)
    self.toggleProfile:SetPoint("TOPLEFT", 276, -112)

    self.toggleHud = W:Toggle(display, "HUD al login", function()
        return BJ.db.settings.showHUDOnLogin
    end, function(v)
        BJ.db.settings.showHUDOnLogin = v
    end, 250)
    self.toggleHud:SetPoint("TOPLEFT", 538, -112)

    local data = W:Card(p, 814, 252, true)
    data:SetPoint("TOPLEFT", 2, -250)

    local dtitle = W:Text(data, "SALVATAGGIO, RESET E SINCRONIZZAZIONE", 10, T.gold)
    dtitle:SetPoint("TOPLEFT", 14, -13)

    local text = W:Text(data,
        "- WoW salva BlackjackDB nelle SavedVariables dell'account durante logout e /reload.\n" ..
        "- Le challenge reali sono tracciate solo dagli eventi del client WoW: nessun checkbox o +1 manuale.\n" ..
        "- Challenge e progressi si azzerano automaticamente a ogni reset settimanale.\n" ..
        "- Le fiches REALI non si azzerano: restano nel saldo finche non le spendi nel Reward Shop.\n" ..
        "- Titoli e badge reali restano disponibili. Il Passport e separato per personaggio.\n" ..
        "- La modalita TEST usa una sandbox separata: titolo/badge e Cassa TEST si sincronizzano solo con altri client in TEST; i dati reali non cambiano.\n" ..
        "- Passport e campi sociali vengono trasmessi sul canale GUILD, quindi funzionano anche tra realm non connessi della stessa gilda.\n" ..
        "- La Cassa Blackjack sincronizza le richieste 250g e conserva localmente lo storico officer.\n" ..
        "- Raider gestisce il contributo mensile da 8.000g: ledger, depositi Guild Bank, alt e mesi saldati.\n" ..
        "- Gli ordini Crafting di tipo Guild vengono rilevati dal client e pubblicati automaticamente nel modulo Crafting.",
        10, T.text)
    text:SetPoint("TOPLEFT", 14, -40)
    text:SetWidth(780)
    text:SetHeight(154)
    text:SetJustifyV("TOP")

    self.settingsResetText = W:Text(data, "", 9, T.gold)
    self.settingsResetText:SetPoint("BOTTOMRIGHT", -14, 58)

    local sync = W:Button(data, "Sincronizza adesso", 160, 32, "primary")
    sync:SetPoint("BOTTOMLEFT", 14, 14)
    sync:SetScript("OnClick", function()
        BJ.Comms:BroadcastAll()
        BJ:Print("Sync inviata.")
    end)

    local cache = W:Button(data, "SHIFT: svuota cache", 170, 32)
    cache:SetPoint("LEFT", sync, "RIGHT", 10, 0)
    cache:SetScript("OnClick", function()
        if not IsShiftKeyDown() then
            BJ:Print("Tieni premuto SHIFT per svuotare la cache di rete.")
            return
        end
        BJ.Storage:ResetNetworkCache()
        BJ:Print("Cache di rete svuotata.")
        UI:RefreshAll()
    end)

    local progress = W:Button(data, "SHIFT: reset challenge", 185, 32, "danger")
    progress:SetPoint("LEFT", cache, "RIGHT", 10, 0)
    progress:SetScript("OnClick", function()
        if not IsShiftKeyDown() then
            BJ:Print("Tieni premuto SHIFT per azzerare solo le challenge REALI della settimana.")
            return
        end
        BJ.Storage:ResetWeeklyProgress()
        BJ:Print("Challenge reali settimanali azzerate. Le fiches non sono state toccate.")
        UI:RefreshAll()
    end)

    local craftReset = W:Button(data, "SHIFT: reset crafting", 180, 32, "danger")
    craftReset:SetPoint("LEFT", progress, "RIGHT", 10, 0)
    craftReset:SetScript("OnClick", function()
        if not IsShiftKeyDown() then
            BJ:Print("Tieni premuto SHIFT per resettare i dati Crafting locali. Gli ordini reali di WoW non vengono cancellati.")
            return
        end
        local n = BJ.Crafting and BJ.Crafting:ResetAllLocalData() or 0
        BJ:Print("Crafting Blackjack resettato. " .. tostring(n or 0) .. " ID precedenti verranno ignorati se WoW li ripropone dalla cache.")
        UI:RefreshAll()
    end)

    local test = W:Card(p, 814, 80, true)
    self.testPanel = test
    test:SetShown(BJ.Guild and BJ.Guild:IsOfficer() or false)
    test:SetPoint("TOPLEFT", 2, -518)

    local tt = W:Text(test, "LAB TEST - SANDBOX SEPARATA", 10, T.red, "OUTLINE")
    tt:SetPoint("TOPLEFT", 14, -9)
    local th = W:Text(test, "Non modifica dati reali; sync TEST solo tra client in modalita TEST.", 9, T.muted)
    th:SetPoint("TOPRIGHT", -14, -9)

    self.testToggle = W:Toggle(test, "Modalita test", function()
        return BJ.TestMode and BJ.TestMode:IsEnabled()
    end, function(v)
        if BJ.TestMode then BJ.TestMode:SetEnabled(v) end
    end, 180)
    self.testToggle:SetPoint("BOTTOMLEFT", 14, 8)

    self.testChips = W:Button(test, "5000 fiches", 112, 36, "disabled")
    self.testChips:SetPoint("LEFT", self.testToggle, "RIGHT", 8, 0)
    self.testChips:SetScript("OnClick", function() BJ.TestMode:SetChips(5000) end)

    self.testChallenges = W:Button(test, "Completa tutte", 128, 36, "disabled")
    self.testChallenges:SetPoint("LEFT", self.testChips, "RIGHT", 8, 0)
    self.testChallenges:SetScript("OnClick", function()
        BJ.TestMode:SetAllChallengesComplete(not (BJ.db.test and BJ.db.test.forceAllChallenges))
    end)

    self.testUnlock = W:Button(test, "Sblocca reward", 128, 36, "disabled")
    self.testUnlock:SetPoint("LEFT", self.testChallenges, "RIGHT", 8, 0)
    self.testUnlock:SetScript("OnClick", function() BJ.TestMode:UnlockAllRewards() end)

    self.testReset = W:Button(test, "Reset test", 104, 36, "disabled")
    self.testReset:SetPoint("LEFT", self.testUnlock, "RIGHT", 8, 0)
    self.testReset:SetScript("OnClick", function() BJ.TestMode:ResetSandbox() end)

    self:RegisterRefresher("SETTINGS", function() UI:RefreshSettings() end)
end

function UI:RefreshSettings()
    self.testPanel:SetShown(BJ.Guild and BJ.Guild:IsOfficer() or false)
    self.strataDD:SetValue(BJ.db.settings.strata, true)
    self.hudDirectionDD:SetValue(BJ.db.settings.hudExpandDirection or "DOWN", true)
    self.toggleMinimap:Refresh()
    self.toggleProfile:Refresh()
    self.toggleHud:Refresh()
    self.testToggle:Refresh()
    self.settingsResetText:SetText("Prossimo reset: " .. BJ:FormatWeeklyReset())

    local testEnabled = BJ.TestMode and BJ.TestMode:IsEnabled()
    ConfigureTestButton(self.testChips, testEnabled)
    ConfigureTestButton(self.testChallenges, testEnabled)
    ConfigureTestButton(self.testUnlock, testEnabled)
    ConfigureTestButton(self.testReset, testEnabled)
    if testEnabled and BJ.db.test and BJ.db.test.forceAllChallenges then
        self.testChallenges:SetText("Ripristina tracking")
    else
        self.testChallenges:SetText("Completa tutte")
    end

    local authorized = not BJ.Access or BJ.Access:IsAuthorized()
    if authorized then
        self.accessStatus:SetText("ACCESSO: BLACKJACK - NEMESIS [OK]")
        self.accessStatus:SetTextColor(UI.UnpackColor(T.accent))
    else
        self.accessStatus:SetText("ACCESSO: NON AUTORIZZATO")
        self.accessStatus:SetTextColor(UI.UnpackColor(T.red))
    end
end
