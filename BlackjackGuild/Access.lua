local _, BJ = ...

BJ.Access = {}
local Access = BJ.Access

Access.guildName = "Blackjack"
Access.guildRealm = "Nemesis"
Access.authorized = false
Access.lastGuildName = nil
Access.lastGuildRealm = nil

local function NormalizeRealm(value)
    value = tostring(value or "")
    value = value:gsub("[%s%-']", "")
    return value:lower()
end

function Access:Evaluate()
    if not IsInGuild() then
        return false, nil, nil
    end

    local guildName, _, _, guildRealm = GetGuildInfo("player")
    if not guildName or guildName == "" then
        return false, nil, nil
    end

    local realm = guildRealm
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    end

    local okName = guildName == self.guildName
    local okRealm = NormalizeRealm(realm) == NormalizeRealm(self.guildRealm)
    return okName and okRealm, guildName, realm
end

function Access:IsAuthorized()
    local ok = self:Evaluate()
    return ok and true or false
end

function Access:Refresh(silent)
    local wasAuthorized = self.authorized
    local ok, guildName, guildRealm = self:Evaluate()
    self.authorized = ok and true or false
    self.lastGuildName = guildName
    self.lastGuildRealm = guildRealm

    if not self.authorized then
        if BJ.UI then BJ.UI:Hide() end
        if BJ.HUD and BJ.HUD.frame then BJ.HUD:Hide() end
        if BJ.Minimap and BJ.Minimap.button then BJ.Minimap.button:Hide() end
    elseif BJ.Minimap and BJ.Minimap.button and BJ.db and BJ.db.settings.showMinimap then
        BJ.Minimap.button:Show()
    end

    if not wasAuthorized and self.authorized then
        -- Guild data can become available a little after ADDON_LOADED/PLAYER_LOGIN.
        -- If Access hid the HUD while authorization was unresolved, restore it as soon
        -- as the Blackjack membership check succeeds. This does not reopen a HUD that
        -- the user manually closes later in the same session because this branch only
        -- runs on the false -> true authorization transition.
        if BJ.HUD and BJ.db and BJ.db.settings.showHUDOnLogin then
            if BJ.HUD.frame then BJ.HUD:Show(false) else BJ.HUD.pendingShow = true end
        end
        if BJ.Guild then BJ.Guild:RequestRoster() end
        if BJ.Comms then
            C_Timer.After(0.5, function()
                if Access:IsAuthorized() then
                    BJ.Comms:Announce()
                    BJ.Comms:BroadcastAll()
                end
            end)
        end
        if not silent then BJ:Print("Accesso Blackjack verificato: " .. self.guildName .. " - " .. self.guildRealm .. ".") end
    end

    if BJ.UI then BJ.UI:RefreshPage("SETTINGS") end
    return self.authorized
end

function Access:Require()
    if self:IsAuthorized() then return true end
    BJ:Print("Questo addon e riservato ai membri Blackjack su Nemesis EU.")
    return false
end

function Access:Initialize()
    BJ:RegisterEvent("PLAYER_GUILD_UPDATE", function()
        C_Timer.After(0.3, function() Access:Refresh(false) end)
    end)
    BJ:RegisterEvent("GUILD_ROSTER_UPDATE", function()
        Access:Refresh(true)
    end)
    BJ:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(1.0, function() Access:Refresh(true) end)
    end)
end
