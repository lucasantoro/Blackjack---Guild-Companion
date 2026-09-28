local ADDON_NAME, BJ = ...

BJ.Compartment = BJ.Compartment or {}
local Module = BJ.Compartment

local ICON = "Interface\\AddOns\\BlackjackGuild\\Media\\blackjack_logo.tga"
local registered = false
local retries = 0

local function Authorized()
    return not BJ.Access or BJ.Access:Require()
end

local function OpenFromCompartment(buttonName)
    if not Authorized() then return end
    if buttonName == "RightButton" then
        if BJ.HUD then BJ.HUD:Show(true) end
    else
        if BJ.UI then BJ.UI:Toggle() end
    end
end

-- Kept global for backwards compatibility with installs that still have the
-- old TOC cached until the next /reload.
function BlackjackGuild_OnAddonCompartmentClick(_, buttonName)
    OpenFromCompartment(buttonName)
end

function BlackjackGuild_OnAddonCompartmentEnter(_, menuButtonFrame)
    if not menuButtonFrame then return end
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("Blackjack Guild Companion")
    GameTooltip:AddLine("Click: apri il tavolo", 0.84, 0.88, 0.85)
    GameTooltip:AddLine("Click destro: Activity HUD", 0.58, 0.65, 0.62)
    GameTooltip:Show()
end

function BlackjackGuild_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local function ManualClick(_, inputData)
    local buttonName = "LeftButton"
    if type(inputData) == "table" and inputData.buttonName then
        buttonName = inputData.buttonName
    elseif type(inputData) == "string" then
        buttonName = inputData
    end
    OpenFromCompartment(buttonName)
end

local function ManualEnter(button)
    if MenuUtil and MenuUtil.ShowTooltip then
        MenuUtil.ShowTooltip(button, function(tooltip)
            tooltip:SetText("Blackjack Guild Companion")
            tooltip:AddLine("Click: apri il tavolo", 0.84, 0.88, 0.85)
            tooltip:AddLine("Click destro: Activity HUD", 0.58, 0.65, 0.62)
        end)
        return
    end

    if button then
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText("Blackjack Guild Companion")
        GameTooltip:AddLine("Click: apri il tavolo", 0.84, 0.88, 0.85)
        GameTooltip:AddLine("Click destro: Activity HUD", 0.58, 0.65, 0.62)
        GameTooltip:Show()
    end
end

local function ManualLeave(button)
    if MenuUtil and MenuUtil.HideTooltip then
        MenuUtil.HideTooltip(button)
    else
        GameTooltip:Hide()
    end
end

function Module:Register()
    if registered then return true end

    local frame = _G.AddonCompartmentFrame
    if not frame or type(frame.RegisterAddon) ~= "function" then
        return false
    end

    frame:RegisterAddon({
        text = "Blackjack - Guild Companion",
        icon = ICON,
        registerForAnyClick = true,
        notCheckable = true,
        keepShownOnClick = false,
        func = ManualClick,
        funcOnEnter = ManualEnter,
        funcOnLeave = ManualLeave,
    })

    registered = true
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local function TryRegister()
        if Module:Register() then return end
        retries = retries + 1
        if retries < 10 then
            C_Timer.After(0.5, TryRegister)
        else
            BJ:Debug("AddonCompartmentFrame non disponibile dopo 10 tentativi.")
        end
    end

    C_Timer.After(0, TryRegister)
end)
