local _, BJ = ...

BJ.Minimap = {}
local Module = BJ.Minimap
local T = BJ.Theme

local BUTTON_NAME = "BlackjackGuildMinimapButton"

local function IsEllesmereUIActive()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
    return C_AddOns.IsAddOnLoaded("EllesmereUI")
        or C_AddOns.IsAddOnLoaded("EllesmereUIMinimap")
end

function Module:IsEllesmereUIActive()
    return IsEllesmereUIActive()
end

function Module:Initialize()
    local minimapFrame = _G.Minimap
    if not minimapFrame then return end

    -- IMPORTANT: this button must be a DIRECT child of Minimap.
    -- EllesmereUI's addon-button flyout scans Minimap:GetChildren() and only
    -- collects named Button frames at least 20 px wide. Parenting it to
    -- MinimapCluster prevents EllesmereUI from seeing it.
    local b = _G[BUTTON_NAME]
    if not b then
        b = CreateFrame("Button", BUTTON_NAME, minimapFrame)
    else
        b:SetParent(minimapFrame)
    end
    self.button = b

    b:SetSize(34, 34)
    b:SetFrameLevel((minimapFrame:GetFrameLevel() or 0) + 8)
    b:SetClampedToScreen(true)

    if not b.icon then
        local icon = b:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        icon:SetTexCoord(0, 1, 0, 1)
        b.icon = icon
    end
    b.icon:SetTexture(T.icon or T.mark)

    if not b._bjHighlight then
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        b._bjHighlight = true
    end

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        if BJ.Access and not BJ.Access:Require() then return end
        if button == "RightButton" then
            if BJ.HUD then BJ.HUD:Show(true) end
        else
            if BJ.UI then BJ.UI:Toggle() end
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Blackjack Guild Companion")
        GameTooltip:AddLine("Click: apri il tavolo", 0.84, 0.88, 0.85)
        GameTooltip:AddLine("Click destro: Activity HUD", 0.58, 0.65, 0.62)
        if IsEllesmereUIActive() then
            GameTooltip:AddLine("Compatibile con il flyout addon di EllesmereUI", 0.49, 1.00, 0.66)
        end
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", minimapFrame, "TOPRIGHT", -4, -4)
    b:SetShown(BJ.db.settings.showMinimap and (not BJ.Access or BJ.Access:IsAuthorized()))
end
