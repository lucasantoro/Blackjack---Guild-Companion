local ADDON_NAME, BJ = ...
_G.BlackjackGuild = BJ

BJ.name = ADDON_NAME
BJ.version = "3.0.11"
BJ.protocol = 5
BJ.prefix = "BJGuildV5"
BJ.events = {}
BJ.player = nil
BJ.db = nil
BJ.profile = nil

local floor = math.floor
local format = string.format

function BJ:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7effa8Blackjack|r |cfff0c868>|r " .. tostring(message))
end

function BJ:Debug(message)
    if self.db and self.db.settings and self.db.settings.debug then
        self:Print("|cff94a59dDEBUG:|r " .. tostring(message))
    end
end

function BJ:GetPlayerFullName()
    local name, realm = UnitFullName("player")
    name = name or UnitName("player") or "Unknown"
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    end
    return self:NormalizeName(realm and realm ~= "" and (name .. "-" .. realm) or name)
end

function BJ:ShortName(name)
    if not name then return "?" end
    if Ambiguate then return Ambiguate(name, "short") end
    return name:match("^[^-]+") or name
end

function BJ:NormalizeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local character, realm = name:match("^([^-]+)%-(.+)$")
    character = character or name
    local localRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    realm = realm or localRealm
    if realm and realm ~= "" then
        realm = realm:gsub("[%s%-']", "")
        if localRealm and realm:lower() == localRealm:lower() then realm = localRealm end
        return character .. "-" .. realm
    end
    return character
end

function BJ:GetPassportProfile(name)
    local full = self:NormalizeName(name) or name
    if not full then return nil end
    if full == self.player then return self.profile end
    if self.db and self.db.network and self.db.network.profiles then
        return self.db.network.profiles[full]
    end
    return nil
end

function BJ:Now()
    return GetServerTime and GetServerTime() or time()
end

function BJ:GetSecondsUntilWeeklyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        return math.max(0, tonumber(C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0)
    end
    return 0
end

function BJ:GetWeekKey()
    local now = self:Now()
    local resetEpoch = now + self:GetSecondsUntilWeeklyReset()
    return tostring(floor((resetEpoch + 60) / 3600))
end

function BJ:FormatTimeLeft(seconds)
    seconds = math.max(0, floor(tonumber(seconds) or 0))
    if seconds >= 86400 then
        return format("%dg %02dh", floor(seconds / 86400), floor((seconds % 86400) / 3600))
    elseif seconds >= 3600 then
        return format("%dh %02dm", floor(seconds / 3600), floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return format("%dm", floor(seconds / 60))
    end
    return format("%ds", seconds)
end

function BJ:FormatWeeklyReset()
    local seconds = self:GetSecondsUntilWeeklyReset()
    if seconds <= 0 then return "reset imminente" end
    return self:FormatTimeLeft(seconds)
end

function BJ:Utf8Truncate(value, maxBytes)
    local s = tostring(value or ""):gsub("%c", " "):gsub("%s+", " ")
    maxBytes = maxBytes or 120
    if #s <= maxBytes then return s end

    local cut = maxBytes
    local start = cut
    while start > 0 do
        local b = string.byte(s, start)
        if not b or b < 128 or b >= 192 then break end
        start = start - 1
    end

    if start <= 0 then return "" end
    local lead = string.byte(s, start) or 0
    local charBytes = 1
    if lead >= 240 then charBytes = 4
    elseif lead >= 224 then charBytes = 3
    elseif lead >= 192 then charBytes = 2 end

    if start + charBytes - 1 > cut then cut = start - 1 end
    if cut <= 0 then return "" end
    return string.sub(s, 1, cut)
end

function BJ:Escape(value)
    local s = self:Utf8Truncate(value, 150)
    return s:gsub("|", "/")
end

function BJ:Unescape(value)
    return tostring(value or "")
end

function BJ:JoinFields(...)
    local args = { ... }
    for i = 1, #args do args[i] = self:Escape(args[i]) end
    return table.concat(args, "|")
end

function BJ:SplitFields(message)
    local output, start = {}, 1
    while true do
        local pos = string.find(message, "|", start, true)
        if not pos then
            output[#output + 1] = self:Unescape(string.sub(message, start))
            break
        end
        output[#output + 1] = self:Unescape(string.sub(message, start, pos - 1))
        start = pos + 1
    end
    return output
end

function BJ:RegisterEvent(event, callback)
    if type(callback) ~= "function" then return end
    self.events[event] = self.events[event] or {}
    self.events[event][#self.events[event] + 1] = callback
    self.eventFrame:RegisterEvent(event)
end

function BJ:Dispatch(event, ...)
    local handlers = self.events[event]
    if not handlers then return end
    for i = 1, #handlers do
        local ok, err = pcall(handlers[i], self, ...)
        if not ok then
            self:Print("Errore in " .. event .. ": " .. tostring(err))
        end
    end
end

function BJ:AddMoment(text, kind)
    if not self.db then return end
    local moments = self.db.moments
    table.insert(moments, 1, {
        time = self:Now(),
        kind = kind or "INFO",
        text = self:Utf8Truncate(text, 190),
    })
    while #moments > 40 do table.remove(moments) end
    if self.UI and self.UI.RefreshPage then self.UI:RefreshPage("HOME") end
end

function BJ:CountTable(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

BJ.eventFrame = CreateFrame("Frame")
BJ.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= ADDON_NAME then return end

        BJ.player = BJ:GetPlayerFullName()
        if BJ.Storage then BJ.Storage:Initialize() end
        if BJ.Access then BJ.Access:Initialize(); BJ.Access:Refresh(true) end
        if BJ.Data then BJ.Data:Initialize() end
        if BJ.TestMode then BJ.TestMode:Initialize() end
        if BJ.Guild then BJ.Guild:Initialize() end
        if BJ.Comms then BJ.Comms:Initialize() end
        if BJ.Activities then BJ.Activities:Initialize() end
        if BJ.Progress then BJ.Progress:Initialize() end
        if BJ.Rewards then BJ.Rewards:Initialize() end
        if BJ.Treasury then BJ.Treasury:Initialize() end
        if BJ.Raider then BJ.Raider:Initialize() end
        if BJ.Crafting then BJ.Crafting:Initialize() end
        if BJ.Challenges then BJ.Challenges:Initialize() end
        if BJ.UI then BJ.UI:Initialize() end
        if BJ.HUD then BJ.HUD:Initialize() end
        if BJ.Minimap then BJ.Minimap:Initialize() end

        BJ:Print("v" .. BJ.version .. " caricata. /bj per aprire il tavolo.")
    elseif event == "PLAYER_LOGIN" then
        if BJ.Access then BJ.Access:Refresh(true) end
        if BJ.Access and not BJ.Access:IsAuthorized() then
            BJ:Print("Installazione rilevata. Funzioni bloccate: serve la gilda Blackjack su Nemesis EU.")
            return
        end
        if BJ.Guild then BJ.Guild:RequestRoster() end
        -- PLAYER_LOGIN fires once for each character session. The HUD close button
        -- only hides it for the current session; showHUDOnLogin controls the next login.
        if BJ.HUD and BJ.db and BJ.db.settings.showHUDOnLogin then
            C_Timer.After(0.2, function()
                if BJ.Access and BJ.Access:IsAuthorized() then BJ.HUD:Show(false) end
            end)
        end
        if BJ.Comms then
            C_Timer.After(2, function()
                BJ.Comms:Announce()
                BJ.Comms:BroadcastAll()
            end)
        end
        if BJ.Activities then C_Timer.After(3, function() BJ.Activities:Cleanup() end) end
    else
        BJ:Dispatch(event, ...)
    end
end)
BJ.eventFrame:RegisterEvent("ADDON_LOADED")
BJ.eventFrame:RegisterEvent("PLAYER_LOGIN")

SLASH_BLACKJACKGUILD1 = "/bj"
SLASH_BLACKJACKGUILD2 = "/blackjack"
SlashCmdList.BLACKJACKGUILD = function(message)
    local msg = (message or ""):lower():match("^%s*(.-)%s*$")
    if not BJ.UI then return end
    if msg == "activities" or msg == "attivita" or msg == "lfg" then
        BJ.UI:Show("ACTIVITIES")
    elseif msg == "challenges" or msg == "challenge" then
        BJ.UI:Show("CHALLENGES")
    elseif msg == "rewards" or msg == "premi" then
        BJ.UI:Show("REWARDS")
    elseif msg == "members" or msg == "membri" then
        BJ.UI:Show("MEMBERS")
    elseif msg == "cassa" or msg == "treasury" then
        BJ.UI:Show("CASSA")
    elseif msg == "raider" or msg == "contributo" then
        BJ.UI:Show("RAIDER")
    elseif msg == "craft" or msg == "crafting" or msg == "ordini" then
        BJ.UI:Show("CRAFTING")
    elseif msg == "profile" or msg == "passport" then
        BJ.UI:Show("MEMBERS")
        if BJ.UI.OpenMyPassport then BJ.UI:OpenMyPassport() end
    elseif msg == "settings" or msg == "impostazioni" then
        BJ.UI:Show("SETTINGS")
    elseif msg == "hud" then
        BJ.UI:Hide()
        if BJ.HUD then BJ.HUD:Show(true) end
    elseif msg == "sync" then
        if BJ.Comms then BJ.Comms:BroadcastAll() end
        BJ:Print("Sincronizzazione inviata alla gilda.")
    elseif msg == "resetpos" then
        BJ.Storage:ResetPositions()
        BJ.UI:ApplySavedPosition()
        if BJ.HUD then BJ.HUD:ApplySavedPosition() end
        BJ:Print("Posizioni ripristinate.")
    elseif msg == "net" or msg == "rete" then
        if BJ.Comms and BJ.Comms.PrintDiagnostics then BJ.Comms:PrintDiagnostics() end
    elseif msg == "test" then
        if BJ.TestMode then BJ.TestMode:SetEnabled(not BJ.TestMode:IsEnabled()) end
    elseif msg == "testreset" then
        if BJ.TestMode then BJ.TestMode:ResetSandbox() end
    elseif msg == "craftreset" or msg == "resetcraft" then
        local n = BJ.Crafting and BJ.Crafting:ResetAllLocalData() or 0
        BJ:Print("Crafting Blackjack resettato. " .. tostring(n or 0) .. " vecchi ID verranno ignorati. Gli ordini reali di WoW non sono stati cancellati.")
    elseif msg == "craftdiag" or msg == "diagcraft" then
        if BJ.Crafting and BJ.Crafting.PrintDiagnostics then BJ.Crafting:PrintDiagnostics() end
    elseif msg == "raiderdiag" or msg == "diagraider" then
        if BJ.Raider and BJ.Raider.PrintDiagnostics then BJ.Raider:PrintDiagnostics() end
    elseif msg == "help" then
        BJ:Print("/bj | /bj attivita | /bj challenges | /bj rewards | /bj cassa | /bj raider | /bj crafting | /bj passport | /bj members | /bj settings | /bj hud | /bj sync | /bj net | /bj test | /bj testreset | /bj craftreset | /bj craftdiag | /bj raiderdiag | /bj resetpos")
    else
        BJ.UI:Toggle()
    end
end
