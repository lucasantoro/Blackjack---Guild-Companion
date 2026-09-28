local _, BJ = ...

BJ.UI = {}
local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

UI.pages = {}
UI.navButtons = {}
UI.refreshers = {}
UI.activeDropdown = nil

UI.nav = {
    { id="HOME", label="Il Tavolo" },
    { id="ACTIVITIES", label="Attivita" },
    { id="CHALLENGES", label="Challenge" },
    { id="REWARDS", label="Fiches & Reward" },
    { id="CASSA", label="Cassa" },
    { id="RAIDER", label="Raider", access="RAIDER" },
    { id="CRAFTING", label="Crafting" },
    { id="MEMBERS", label="Blackjack" },
    { id="SETTINGS", label="Impostazioni" },
}

local function unpackColor(c) return c[1], c[2], c[3], c[4] or 1 end

function UI:Initialize()
    self:CreateFrame()
    if self.CreatePages then self:CreatePages() end
    self:SelectPage(BJ.db.ui.lastPage or "HOME")
    self.frame:Hide()
end

function UI:CreateFrame()
    local f = CreateFrame("Frame", "BlackjackGuildMainFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(1080, 700)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    W:Backdrop(f, T.bgDeep, T.gold, 1)
    self:ApplySavedPosition()
    self:ApplyFrameStrata()
    table.insert(UISpecialFrames, "BlackjackGuildMainFrame")

    f:SetScript("OnDragStart", function(self)
        if UI.activeDropdown then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        BJ.db.ui.main.point, BJ.db.ui.main.relativePoint, BJ.db.ui.main.x, BJ.db.ui.main.y = point, relativePoint, x, y
    end)
    f:SetScript("OnHide", function() UI:CloseDropdown() end)

    local bgTex = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgTex:SetTexture(T.background)
    bgTex:SetAllPoints()
    bgTex:SetAlpha(0.22)

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(72)
    W:Backdrop(header, T.surfaceStrong, T.line)
    self.header = header

    local mark = header:CreateTexture(nil, "ARTWORK")
    mark:SetTexture(T.mark)
    mark:SetSize(58, 58)
    mark:SetPoint("LEFT", 8, 0)
    mark:SetTexCoord(0, 1, 0, 1)

    local title = W:Text(header, "BLACKJACK", 19, T.white, "OUTLINE")
    title:SetPoint("LEFT", 80, 9)
    local sub = W:Text(header, "Guild Companion - blackjackguild.it", 11, T.muted)
    sub:SetPoint("LEFT", title, "BOTTOMLEFT", 0, -6)

    local close = W:Button(header, "X", 32, 32, "danger")
    close:SetPoint("RIGHT", -14, 0)
    close:SetScript("OnClick", function()
        UI:Hide()
        if BJ.HUD then BJ.HUD:Hide() end
    end)

    local minimize = W:Button(header, "-", 32, 32)
    minimize:SetPoint("RIGHT", close, "LEFT", -7, 0)
    minimize:SetScript("OnClick", function()
        UI:Hide()
        if BJ.HUD then BJ.HUD:Show(true) end
    end)

    self.testBadge = W:Text(header, "MODALITA TEST", 11, T.red, "OUTLINE")
    self.testBadge:SetPoint("RIGHT", minimize, "LEFT", -18, 0)
    self.testBadge:Hide()

    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 14, -86)
    nav:SetPoint("BOTTOMLEFT", 14, 14)
    nav:SetWidth(184)
    W:Backdrop(nav, T.surfaceStrong, T.line)
    self.navFrame = nav

    for i = 1, #self.nav do
        local item = self.nav[i]
        local b = W:Button(nav, item.label, 156, 38)
        b:SetPoint("TOP", 0, -14 - (i - 1) * 46)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 13, 0)
        b.label:SetJustifyH("LEFT")
        b:SetScript("OnClick", function() UI:SelectPage(item.id) end)
        self.navButtons[item.id] = b
        b.navItem = item
    end
    self:RefreshNavAccess()

    local v = W:Text(nav, "v" .. BJ.version .. "\nMidnight 12.1", 9, T.muted)
    v:SetPoint("BOTTOMLEFT", 12, 12)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 14, 0)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    self.content = content

    self.blocker = CreateFrame("Button", nil, f)
    self.blocker:SetAllPoints(f)
    self.blocker:SetFrameLevel(900)
    self.blocker:EnableMouse(true)
    local blockerTex = self.blocker:CreateTexture(nil, "BACKGROUND")
    blockerTex:SetAllPoints()
    blockerTex:SetColorTexture(0, 0, 0, 0.28)
    self.blocker:SetScript("OnClick", function() UI:CloseDropdown() end)
    self.blocker:Hide()

    self.dropdown = CreateFrame("Frame", nil, f, "BackdropTemplate")
    self.dropdown:SetFrameLevel(1000)
    W:Backdrop(self.dropdown, {0.015, 0.035, 0.030, 1.00}, T.gold, 1)
    self.dropdown:Hide()
    self.dropdown.rows = {}

    self:ApplyFrameStrata()
    self:RefreshTestIndicator()
end

function UI:CanAccessPage(id)
    if id == "CASSA" then return BJ.Guild and BJ.Guild:IsOfficer() or false end
    if id == "RAIDER" then return BJ.Raider and BJ.Raider:CanAccess() or false end
    return true
end

function UI:RefreshNavAccess()
    if not self.navFrame then return end
    local visibleIndex = 0
    for i = 1, #self.nav do
        local item = self.nav[i]
        local button = self.navButtons[item.id]
        local visible = self:CanAccessPage(item.id)
        if button then
            button:SetShown(visible)
            if visible then
                visibleIndex = visibleIndex + 1
                button:ClearAllPoints()
                button:SetPoint("TOP", 0, -14 - (visibleIndex - 1) * 46)
            end
        end
    end
    if BJ.db and BJ.db.ui and not self:CanAccessPage(BJ.db.ui.lastPage) then
        BJ.db.ui.lastPage = "HOME"
        if self.pages.HOME then self:SelectPage("HOME") end
    end
    if self.testPanel then self.testPanel:SetShown(BJ.Guild and BJ.Guild:IsOfficer() or false) end
    self:RefreshTestIndicator()
end

function UI:RefreshTestIndicator()
    if not self.testBadge then return end
    self.testBadge:SetShown(BJ.TestMode and BJ.TestMode:IsEnabled() or false)
end

function UI:ApplySavedPosition()
    if not self.frame or not BJ.db then return end
    local p = BJ.db.ui.main
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
end

function UI:ApplyFrameStrata()
    if not self.frame or not BJ.db then return end
    local strata = BJ.db.settings.strata or "TOOLTIP"
    self.frame:SetFrameStrata(strata)
    self.frame:SetFrameLevel(100)
    if self.dropdown then
        self.dropdown:SetFrameStrata(strata)
        self.dropdown:SetFrameLevel(1000)
    end
    if self.blocker then
        self.blocker:SetFrameStrata(strata)
        self.blocker:SetFrameLevel(900)
    end
    if BJ.HUD and BJ.HUD.frame then BJ.HUD:ApplyFrameStrata() end
end

function UI:CreatePage(id)
    local p = CreateFrame("Frame", nil, self.content)
    p:SetAllPoints()
    p:Hide()
    self.pages[id] = p
    return p
end

function UI:PageTitle(page, title, subtitle)
    local h = W:Text(page, title, 22, T.white, "OUTLINE")
    h:SetPoint("TOPLEFT", 2, -2)
    local s = W:Text(page, subtitle or "", 11, T.muted)
    s:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -7)
    s:SetWidth(820)
    return h, s
end

function UI:RegisterRefresher(id, callback)
    self.refreshers[id] = callback
end

function UI:RefreshPage(id)
    if self.refreshers[id] and self.pages[id] and self.pages[id]:IsShown() then
        self.refreshers[id]()
    end
end

function UI:RefreshAll()
    self:RefreshTestIndicator()
    for id, callback in pairs(self.refreshers) do
        if self.pages[id] and self.pages[id]:IsShown() then callback() end
    end
    if BJ.HUD then BJ.HUD:Refresh() end
end

function UI:SelectPage(id)
    if not self.pages[id] or not self:CanAccessPage(id) then id = "HOME" end
    self:RefreshNavAccess()
    self:CloseDropdown()
    for pageId, page in pairs(self.pages) do page:SetShown(pageId == id) end
    for navId, button in pairs(self.navButtons) do
        if navId == id then
            button:SetBackdropColor(0.07, 0.20, 0.13, 1)
            button:SetBackdropBorderColor(unpackColor(T.accentStrong))
            button.label:SetTextColor(unpackColor(T.white))
        else
            button:SetBackdropColor(unpackColor(T.surfaceSoft))
            button:SetBackdropBorderColor(unpackColor(T.lineStrong))
            button.label:SetTextColor(unpackColor(T.text))
        end
    end
    BJ.db.ui.lastPage = id
    if self.refreshers[id] then self.refreshers[id]() end
end

function UI:Show(page)
    if BJ.Access and not BJ.Access:Require() then return end
    if BJ.HUD then BJ.HUD:Hide() end
    self.frame:Show()
    self:SelectPage(page or BJ.db.ui.lastPage or "HOME")
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function UI:OpenDropdown(anchor, items, currentValue, callback)
    self:CloseDropdown()
    if not anchor or not items or #items == 0 then return end

    local popup = self.dropdown
    local rowHeight = 29
    local maxRows = math.min(#items, 12)
    local width = math.max(anchor:GetWidth(), 190)
    popup:SetSize(width, maxRows * rowHeight + 10)
    popup:ClearAllPoints()

    local left = anchor:GetLeft() or 0
    local bottom = anchor:GetBottom() or 0
    if bottom - (maxRows * rowHeight + 16) < 0 then
        popup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 3)
    else
        popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    end

    self.blocker:Show()
    popup:Show()
    self.activeDropdown = anchor

    for i = 1, math.max(#popup.rows, #items) do
        if popup.rows[i] then popup.rows[i]:Hide() end
    end

    for i = 1, #items do
        local item = items[i]
        local row = popup.rows[i]
        if not row then
            row = W:Button(popup, "", width - 10, rowHeight - 2)
            popup.rows[i] = row
        end
        row:SetSize(width - 10, rowHeight - 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * rowHeight)
        row:SetText(item.label or tostring(item.id))
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 9, 0)
        row.label:SetJustifyH("LEFT")
        if tostring(item.id) == tostring(currentValue) then
            row:SetTextColor(T.accent)
        else
            row:SetTextColor(T.text)
        end
        row:SetScript("OnClick", function()
            UI:CloseDropdown()
            callback(item.id)
        end)
        row:Show()
    end
end

function UI:CloseDropdown()
    if self.dropdown then self.dropdown:Hide() end
    if self.blocker then self.blocker:Hide() end
    self.activeDropdown = nil
end

function UI:PrepareActivity(category, presetId)
    self:Show("ACTIVITIES")
    if self.SetActivityFormPreset then self:SetActivityFormPreset(category, presetId) end
end
