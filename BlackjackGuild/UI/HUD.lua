local _, BJ = ...

BJ.HUD = {}
local HUD = BJ.HUD
local W = BJ.Widgets
local T = BJ.Theme

local PANEL_W = 520
local PANEL_H = 360
local ROW_W = 482
local ACTIVITY_ROW_H = 94
local CRAFT_ROW_H = 70
local PANEL_GAP = 6
local SCREEN_PAD = 8

local HUD_DEFAULT_W = 530
local HUD_DEFAULT_H = 42
local HUD_MIN_W = 470
local HUD_MIN_H = 38
local HUD_MAX_W = 900
local HUD_MAX_H = 88

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    return math.max(minValue, math.min(maxValue, value))
end

local function KeyBandLabel(id)
    for i = 1, #BJ.Data.keyBands do
        if BJ.Data.keyBands[i].id == id then return BJ.Data.keyBands[i].label end
    end
    return ""
end

local function ItemTimestamp(item)
    if item.kind == "ACTIVITY" then return tonumber(item.data.created) or 0 end
    return tonumber(item.data.updated) or tonumber(item.data.firstSeen) or 0
end

local function ItemKey(item)
    if item.kind == "ACTIVITY" then return "A:" .. tostring(item.data.id or "") end
    return "C:" .. tostring(item.data.id or "")
end

local function CreateInfoText(parent, text, size, color)
    local fs = W:Text(parent, text or "", size or 9, color or T.muted)
    fs:SetJustifyH("LEFT")
    return fs
end

local function TruncateNames(list, maxNames)
    if not list or #list == 0 then return "Nessuno" end
    maxNames = maxNames or 4
    local parts = {}
    local limit = math.min(#list, maxNames)
    for i = 1, limit do parts[#parts + 1] = BJ:ShortName(list[i]) end
    if #list > limit then parts[#parts + 1] = "+" .. (#list - limit) end
    return table.concat(parts, ", ")
end

function HUD:Initialize()
    self.panelFilter = "MINE"
    self:CreateFrame()
    self:ApplySavedPosition()
    self:ApplyFrameStrata()
    self.initializing = true
    self:Refresh()
    self.initializing = false
    self.initialized = true

    -- Access can be resolved before the HUD frame exists during ADDON_LOADED.
    -- Honour any early Show request only after CreateFrame has completed.
    local wantsHUD = (self.pendingShow == true) or (BJ.db and BJ.db.settings.showHUDOnLogin)
    self.pendingShow = false
    if wantsHUD and (not BJ.Access or BJ.Access:IsAuthorized()) then
        self:Show(false)
    else
        self.frame:Hide()
    end
    C_Timer.After(0, function() if HUD.frame then HUD:ClampFrameToScreen(true) end end)
end

function HUD:CreateFrame()
    local f = CreateFrame("Frame", "BlackjackGuildHUD", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(HUD_DEFAULT_W, HUD_DEFAULT_H)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(HUD_MIN_W, HUD_MIN_H, HUD_MAX_W, HUD_MAX_H)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    W:Backdrop(f, T.surfaceStrong, T.gold, 1)
    f:SetScript("OnDragStart", function(self)
        HUD:ClosePanel()
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        HUD:ClampFrameToScreen(true)
    end)
    f:SetScript("OnSizeChanged", function()
        HUD:LayoutCompactControls()
    end)
    f:SetScript("OnHide", function() HUD:ClosePanel() end)

    -- The guild logo is also the shortcut to the full addon.
    self.logoButton = CreateFrame("Button", nil, f)
    self.logoButton:SetPoint("LEFT", 7, 0)
    self.logoTexture = self.logoButton:CreateTexture(nil, "ARTWORK")
    self.logoTexture:SetTexture(T.icon)
    self.logoTexture:SetAllPoints()
    local logoHighlight = self.logoButton:CreateTexture(nil, "HIGHLIGHT")
    logoHighlight:SetAllPoints()
    logoHighlight:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.16)
    self.logoButton:SetScript("OnClick", function()
        HUD:ClosePanel()
        if BJ.UI then BJ.UI:Show(BJ.db.ui.lastPage or "HOME") end
    end)
    self.logoButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Blackjack Guild Companion")
        GameTooltip:AddLine("Apri l'addon", 0.75, 0.85, 0.78)
        GameTooltip:Show()
    end)
    self.logoButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.activityBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    W:Backdrop(self.activityBox, T.bgDeep, T.line)
    self.activityDot = self.activityBox:CreateTexture(nil, "ARTWORK")
    self.activityDot:SetSize(7, 7)
    self.activityDot:SetPoint("LEFT", 9, 0)
    self.activityDot:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    self.activityText = W:Text(self.activityBox, "ATTIVITA 0", 10, T.muted, "OUTLINE")
    self.activityText:SetPoint("LEFT", 23, 0)

    self.craftBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    W:Backdrop(self.craftBox, T.bgDeep, T.line)
    self.craftDot = self.craftBox:CreateTexture(nil, "ARTWORK")
    self.craftDot:SetSize(7, 7)
    self.craftDot:SetPoint("LEFT", 9, 0)
    self.craftDot:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 1)
    self.craftText = W:Text(self.craftBox, "CRAFT 0", 10, T.muted, "OUTLINE")
    self.craftText:SetPoint("LEFT", 23, 0)
    self.craftBox:EnableMouse(true)
    self.craftBox:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        HUD.panelFilter = "CRAFT"
        if HUD.panel and HUD.panel:IsShown() then HUD:RefreshPanel() else HUD:OpenPanel() end
    end)
    self.craftBox:SetScript("OnEnter", function(self)
        local pending = BJ.Crafting and BJ.Crafting:GetPendingDeliveryCount() or 0
        if pending <= 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Craft completati da ritirare")
        GameTooltip:AddLine(tostring(pending) .. (pending == 1 and " oggetto pronto nella posta." or " oggetti pronti nella posta."), 0.94, 0.78, 0.41)
        GameTooltip:AddLine("Il riquadro tornera normale dopo aver ritirato gli allegati.", 0.75, 0.85, 0.78, true)
        GameTooltip:Show()
    end)
    self.craftBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.closeButton = W:Button(f, "X", 28, 28, "danger")
    self.closeButton:SetScript("OnClick", function() HUD:Hide() end)

    self.expand = W:Button(f, "Apri", 58, 28, "primary")
    self.expand:SetScript("OnClick", function() HUD:TogglePanel() end)

    self.newActivity = W:Button(f, "Crea attivita", 92, 28, "primary")
    self.newActivity:SetScript("OnClick", function()
        HUD:ClosePanel()
        if BJ.UI and BJ.UI.OpenActivityCreator then BJ.UI:OpenActivityCreator() elseif BJ.UI then BJ.UI:Show("ACTIVITIES") end
    end)

    -- Resize handle: drag the lower-right corner to change both width and height.
    self.resizeHandle = CreateFrame("Button", nil, f)
    self.resizeHandle:SetSize(16, 16)
    self.resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    self.resizeHandle:SetFrameLevel(f:GetFrameLevel() + 20)
    local grip1 = self.resizeHandle:CreateTexture(nil, "ARTWORK")
    grip1:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0.72)
    grip1:SetSize(8, 2)
    grip1:SetPoint("BOTTOMRIGHT", -2, 3)
    local grip2 = self.resizeHandle:CreateTexture(nil, "ARTWORK")
    grip2:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0.55)
    grip2:SetSize(5, 2)
    grip2:SetPoint("BOTTOMRIGHT", -2, 7)
    local grip3 = self.resizeHandle:CreateTexture(nil, "ARTWORK")
    grip3:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0.38)
    grip3:SetSize(2, 2)
    grip3:SetPoint("BOTTOMRIGHT", -2, 11)
    self.resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        HUD:ClosePanel()
        HUD.isSizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    self.resizeHandle:SetScript("OnMouseUp", function()
        if not HUD.isSizing then return end
        HUD.isSizing = false
        f:StopMovingOrSizing()
        HUD:SaveSize()
        HUD:ClampFrameToScreen(true)
        HUD:ApplyExpandDirection()
    end)
    self.resizeHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Ridimensiona HUD")
        GameTooltip:AddLine("Trascina per cambiare larghezza e altezza.", 0.75, 0.85, 0.78)
        GameTooltip:Show()
    end)
    self.resizeHandle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- A real child frame sits above every HUD child. This makes the notification
    -- pulse a uniform tint instead of leaving black islands from child backdrops.
    self.flashFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    self.flashFrame:SetAllPoints(f)
    self.flashFrame:EnableMouse(false)
    W:Backdrop(self.flashFrame, {0.08, 0.82, 0.38, 0.76}, T.accent, 1)
    self.flashFrame:SetAlpha(0)
    self.flashFrame:Hide()

    self.flashGroup = self.flashFrame:CreateAnimationGroup()
    self.flashGroup:SetLooping("BOUNCE")
    local flash = self.flashGroup:CreateAnimation("Alpha")
    flash:SetFromAlpha(0.10)
    flash:SetToAlpha(0.92)
    flash:SetDuration(0.22)

    self:LayoutCompactControls()
    self:CreatePanel()
end

function HUD:LayoutCompactControls()
    if not self.frame or not self.logoButton then return end
    local width = self.frame:GetWidth() or HUD_DEFAULT_W
    local height = self.frame:GetHeight() or HUD_DEFAULT_H
    local controlH = Clamp(height - 12, 26, 64)
    local logoSize = Clamp(height - 10, 26, 64)

    self.logoButton:SetSize(logoSize, logoSize)

    self.closeButton:ClearAllPoints()
    self.closeButton:SetSize(28, controlH)
    self.closeButton:SetPoint("RIGHT", -22, 0)

    self.expand:ClearAllPoints()
    self.expand:SetSize(58, controlH)
    self.expand:SetPoint("RIGHT", self.closeButton, "LEFT", -5, 0)

    self.newActivity:ClearAllPoints()
    self.newActivity:SetSize(92, controlH)
    self.newActivity:SetPoint("RIGHT", self.expand, "LEFT", -5, 0)

    local fixed = 7 + logoSize + 8 + 8 + 92 + 5 + 58 + 5 + 28 + 22
    local counters = math.max(166, width - fixed)
    local gap = 6
    local usable = math.max(160, counters - gap)
    local activityW = math.floor(usable * 0.56)
    local craftW = usable - activityW
    if activityW < 90 then activityW = 90; craftW = usable - activityW end
    if craftW < 70 then craftW = 70; activityW = usable - craftW end

    self.activityBox:ClearAllPoints()
    self.activityBox:SetSize(activityW, controlH)
    self.activityBox:SetPoint("LEFT", self.logoButton, "RIGHT", 8, 0)
    self.activityText:SetWidth(math.max(40, activityW - 29))

    self.craftBox:ClearAllPoints()
    self.craftBox:SetSize(craftW, controlH)
    self.craftBox:SetPoint("LEFT", self.activityBox, "RIGHT", gap, 0)
    self.craftText:SetWidth(math.max(36, craftW - 29))
end

function HUD:SaveSize()
    if not self.frame or not BJ.db or not BJ.db.ui or not BJ.db.ui.hud then return end
    BJ.db.ui.hud.width = Clamp(self.frame:GetWidth(), HUD_MIN_W, HUD_MAX_W)
    BJ.db.ui.hud.height = Clamp(self.frame:GetHeight(), HUD_MIN_H, HUD_MAX_H)
end

function HUD:CreatePanel()
    local p = CreateFrame("Frame", "BlackjackGuildHUDPanel", UIParent, "BackdropTemplate")
    self.panel = p
    p:SetSize(PANEL_W, PANEL_H)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    W:Backdrop(p, T.surfaceStrong, T.gold, 1)
    p:Hide()

    local title = W:Text(p, "TAVOLI & CRAFT", 12, T.white, "OUTLINE")
    title:SetPoint("TOPLEFT", 12, -11)
    self.panelSummary = W:Text(p, "", 9, T.muted)
    self.panelSummary:SetPoint("TOPLEFT", 12, -30)

    -- The HUD mirrors the full Activities page: owned tables and guild tables
    -- are never mixed in the same list. Crafting stays in its own third tab.
    self.filterMine = W:Button(p, "LE MIE  0", 102, 25, "primary")
    self.filterMine:SetPoint("TOPRIGHT", -202, -9)
    self.filterMine:SetScript("OnClick", function() HUD:SetPanelFilter("MINE") end)
    self.filterGuild = W:Button(p, "GILDA  0", 92, 25)
    self.filterGuild:SetPoint("LEFT", self.filterMine, "RIGHT", 5, 0)
    self.filterGuild:SetScript("OnClick", function() HUD:SetPanelFilter("GUILD") end)
    self.filterCrafts = W:Button(p, "CRAFT  0", 82, 25)
    self.filterCrafts:SetPoint("LEFT", self.filterGuild, "RIGHT", 5, 0)
    self.filterCrafts:SetScript("OnClick", function() HUD:SetPanelFilter("CRAFT") end)

    self.scroll, self.list = W:ScrollArea(p, 504, 302)
    self.scroll:SetPoint("TOPLEFT", 8, -50)

    -- UIPanelScrollFrameTemplate anchors its scrollbar slightly outside the
    -- ScrollFrame by default. In the compact HUD panel that made the bar
    -- protrude past the black container. Keep the complete scrollbar (track,
    -- thumb and arrow buttons) inside the panel instead.
    self:LayoutPanelScrollBar()
    C_Timer.After(0, function()
        if HUD.scroll then HUD:LayoutPanelScrollBar() end
    end)
end

function HUD:LayoutPanelScrollBar()
    if not self.scroll then return end

    local bar = self.scroll.ScrollBar
    if not bar then
        -- Compatibility fallback for template implementations that do not
        -- expose ScrollBar as a parentKey.
        for _, child in ipairs({ self.scroll:GetChildren() }) do
            if child.IsObjectType and child:IsObjectType("Slider") then
                bar = child
                break
            end
        end
    end
    if not bar then return end

    self.panelScrollBar = bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", self.scroll, "TOPRIGHT", -3, -16)
    bar:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", -3, 16)
    if bar.SetWidth then bar:SetWidth(14) end
    bar:SetFrameLevel(math.max(self.scroll:GetFrameLevel() + 8, bar:GetFrameLevel() or 0))
end

function HUD:SavePosition()
    if not self.frame or not BJ.db then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    BJ.db.ui.hud.point = point
    BJ.db.ui.hud.relativePoint = relativePoint
    BJ.db.ui.hud.x = x
    BJ.db.ui.hud.y = y
    self:SaveSize()
end

function HUD:ClampFrameToScreen(save)
    if not self.frame then return end
    local f = self.frame
    local left, right, top, bottom = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not left or not right or not top or not bottom then
        if save then self:SavePosition() end
        return
    end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local width, height = f:GetWidth(), f:GetHeight()
    local newLeft = math.max(SCREEN_PAD, math.min(left, sw - width - SCREEN_PAD))
    local newBottom = math.max(SCREEN_PAD, math.min(bottom, sh - height - SCREEN_PAD))
    if math.abs(newLeft - left) > 0.5 or math.abs(newBottom - bottom) > 0.5 then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
    end
    if save then self:SavePosition() end
end

function HUD:ApplySavedPosition()
    if not self.frame then return end
    local p = BJ.db.ui.hud
    self.frame:SetSize(
        Clamp(p.width or HUD_DEFAULT_W, HUD_MIN_W, HUD_MAX_W),
        Clamp(p.height or HUD_DEFAULT_H, HUD_MIN_H, HUD_MAX_H)
    )
    self:LayoutCompactControls()
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p.point or "TOP", UIParent, p.relativePoint or "TOP", p.x or 0, p.y or -115)
    self:ApplyExpandDirection()
end

function HUD:ApplyFrameStrata()
    if not self.frame then return end
    local strata = BJ.db.settings.strata or "TOOLTIP"
    self.frame:SetFrameStrata(strata)
    self.frame:SetFrameLevel(100)
    if self.flashFrame then
        self.flashFrame:SetFrameStrata(strata)
        self.flashFrame:SetFrameLevel(180)
    end
    if self.resizeHandle then
        self.resizeHandle:SetFrameStrata(strata)
        self.resizeHandle:SetFrameLevel(170)
    end
    if self.panel then
        self.panel:SetFrameStrata(strata)
        self.panel:SetFrameLevel(105)
    end
end

local OPPOSITE = { UP = "DOWN", DOWN = "UP", LEFT = "RIGHT", RIGHT = "LEFT" }

function HUD:GetAvailableSpace()
    local f = self.frame
    if not f then return nil end
    local left, right, top, bottom = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not left or not right or not top or not bottom then return nil end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    return {
        UP = math.max(0, sh - top),
        DOWN = math.max(0, bottom),
        LEFT = math.max(0, left),
        RIGHT = math.max(0, sw - right),
    }
end

function HUD:ResolveExpandDirection()
    local preferred = BJ.db.settings.hudExpandDirection or "DOWN"
    local available = self:GetAvailableSpace()
    if not available then return preferred end
    local need = {
        UP = PANEL_H + PANEL_GAP + SCREEN_PAD,
        DOWN = PANEL_H + PANEL_GAP + SCREEN_PAD,
        LEFT = PANEL_W + PANEL_GAP + SCREEN_PAD,
        RIGHT = PANEL_W + PANEL_GAP + SCREEN_PAD,
    }
    if available[preferred] >= need[preferred] then return preferred end
    local opposite = OPPOSITE[preferred]
    if opposite and available[opposite] >= need[opposite] then return opposite end

    local best, bestRatio = preferred, -1
    for _, dir in ipairs({"DOWN", "UP", "RIGHT", "LEFT"}) do
        local ratio = available[dir] / need[dir]
        if ratio > bestRatio then best, bestRatio = dir, ratio end
    end
    return best
end

function HUD:AnchorPanel(dir)
    if not self.panel or not self.frame then return end
    local p, f = self.panel, self.frame
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local left, right, top, bottom = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    p:ClearAllPoints()

    if dir == "UP" or dir == "DOWN" then
        local alignRight = left and (left + PANEL_W > sw - SCREEN_PAD) and right and (right - PANEL_W >= SCREEN_PAD)
        if dir == "UP" then
            if alignRight then p:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, PANEL_GAP)
            else p:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, PANEL_GAP) end
        else
            if alignRight then p:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -PANEL_GAP)
            else p:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -PANEL_GAP) end
        end
    else
        local alignBottom = top and (top - PANEL_H < SCREEN_PAD) and bottom and (bottom + PANEL_H <= sh - SCREEN_PAD)
        if dir == "LEFT" then
            if alignBottom then p:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -PANEL_GAP, 0)
            else p:SetPoint("TOPRIGHT", f, "TOPLEFT", -PANEL_GAP, 0) end
        else
            if alignBottom then p:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", PANEL_GAP, 0)
            else p:SetPoint("TOPLEFT", f, "TOPRIGHT", PANEL_GAP, 0) end
        end
    end
    self.actualExpandDirection = dir
end

function HUD:ApplyExpandDirection()
    if not self.panel or not self.frame then return end
    self:ClampFrameToScreen(false)
    self:AnchorPanel(self:ResolveExpandDirection())
end

function HUD:GetItems()
    local activities = BJ.Activities and BJ.Activities:GetActive() or {}
    local crafts = BJ.Crafting and BJ.Crafting:GetActiveOrders() or {}
    local items = {}
    for i = 1, #activities do items[#items + 1] = { kind = "ACTIVITY", data = activities[i] } end
    for i = 1, #crafts do items[#items + 1] = { kind = "CRAFT", data = crafts[i] } end
    table.sort(items, function(a, b) return ItemTimestamp(a) > ItemTimestamp(b) end)
    return items, #activities, #crafts
end

function HUD:DetectNewItems(items)
    local current = {}
    local hasNew = false
    for i = 1, #items do
        local key = ItemKey(items[i])
        current[key] = true
        if self.knownItems and not self.knownItems[key] then hasNew = true end
    end
    self.knownItems = current
    if hasNew and not self.initializing then self:Flash() end
end

function HUD:RunFlash(bg, border, duration)
    if not BJ.db.settings.notifications then return end
    if not self.frame or not self.frame:IsShown() then return end
    bg = bg or {0.08, 0.82, 0.38, 0.76}
    border = border or T.accent
    self.flashGroup:Stop()
    self.flashFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.76)
    self.flashFrame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    self.flashFrame:SetAlpha(0)
    self.flashFrame:Show()
    self.flashGroup:Play()
    local token = (self.flashToken or 0) + 1
    self.flashToken = token
    C_Timer.After(duration or 2.0, function()
        if HUD.flashToken ~= token then return end
        HUD.flashGroup:Stop()
        HUD.flashFrame:SetAlpha(0)
        HUD.flashFrame:Hide()
    end)
end

function HUD:Flash()
    self:RunFlash({0.08, 0.82, 0.38, 0.76}, T.accent, 2.0)
end

function HUD:FlashCraftDelivery()
    self:RunFlash({0.58, 0.40, 0.08, 0.82}, T.gold, 2.6)
end

function HUD:SetPanelFilter(filter)
    if filter ~= "GUILD" and filter ~= "CRAFT" then filter = "MINE" end
    self.panelFilter = filter
    self:RefreshPanel()
end

function HUD:RefreshFilterButtons(mineCount, guildCount, craftCount)
    if not self.filterMine then return end
    mineCount = tonumber(mineCount) or 0
    guildCount = tonumber(guildCount) or 0
    craftCount = tonumber(craftCount) or 0
    self.filterMine:SetText("LE MIE  " .. mineCount)
    self.filterGuild:SetText("GILDA  " .. guildCount)
    self.filterCrafts:SetText("CRAFT  " .. craftCount)
    self.filterMine:SetKind(self.panelFilter == "MINE" and "primary" or "default")
    self.filterGuild:SetKind(self.panelFilter == "GUILD" and "primary" or "default")
    self.filterCrafts:SetKind(self.panelFilter == "CRAFT" and "primary" or "default")
end

function HUD:CreateActivityRow(parent, entry, y)
    local category = BJ.Data:GetCategory(entry.category)
    local owned = entry.owner == BJ.player
    local row = W:AddDynamic(parent, W:Card(parent, ROW_W, ACTIVITY_ROW_H, owned))
    row:SetPoint("TOPLEFT", 0, -y)
    if owned then row:SetBackdropBorderColor(T.accentStrong[1], T.accentStrong[2], T.accentStrong[3], 0.60) end

    local strip = row:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMLEFT", 0, 0)
    strip:SetWidth(3)
    strip:SetColorTexture(category.color[1], category.color[2], category.color[3], 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(category.icon)
    icon:SetSize(29, 29)
    icon:SetPoint("TOPLEFT", 12, -11)

    local title = CreateInfoText(row, entry.title or category.label, 10, T.white)
    title:SetPoint("TOPLEFT", 50, -8)
    title:SetWidth(275)

    local who = owned and "MIA" or ("Di: " .. BJ:ShortName(entry.owner))
    local owner = CreateInfoText(row, who .. "  |  " .. (entry.count or 1) .. "/" .. (entry.target or 5) .. "  |  " .. BJ:FormatTimeLeft((entry.expires or 0) - BJ:Now()), 8, owned and T.accent or T.muted)
    owner:SetPoint("TOPLEFT", 50, -27)
    owner:SetWidth(290)

    local message = CreateInfoText(row, "Messaggio: " .. ((entry.description and entry.description ~= "") and entry.description or "Nessun messaggio"), 8, T.text)
    message:SetPoint("TOPLEFT", 50, -45)
    message:SetWidth(305)
    message:SetHeight(28)
    message:SetJustifyV("TOP")

    local meta = entry.category == "MPLUS" and KeyBandLabel(entry.keyBand) or category.label
    local metaText = CreateInfoText(row, meta, 8, T.gold)
    metaText:SetPoint("BOTTOMLEFT", 50, 8)
    metaText:SetWidth(120)

    if owned then
        local participants = BJ.Activities:GetParticipants(entry.id)
        local waiting = BJ.Activities:GetInvitableParticipants(entry.id)
        local candidates = CreateInfoText(row, "Candidati: " .. TruncateNames(participants, 3) .. "  |  da invitare: " .. #waiting, 8, T.muted)
        candidates:SetPoint("BOTTOMLEFT", 174, 8)
        candidates:SetWidth(184)

        local close = W:Button(row, "Chiudi", 66, 28, "danger")
        close:SetPoint("RIGHT", -8, 0)
        close:SetScript("OnClick", function() BJ.Activities:Delete(entry.id) end)
        local invite = W:Button(row, "INV " .. #waiting, 52, 28, "primary")
        invite:SetPoint("RIGHT", close, "LEFT", -5, 0)
        if #waiting == 0 then invite:SetKind("disabled"); invite:Disable() end
        invite:SetScript("OnClick", function() BJ.Activities:InviteParticipants(entry.id) end)
    else
        local joined = BJ.Activities:GetJoinedState(entry.id)
        local state = CreateInfoText(row, joined and "ISCRITTO" or "DISPONIBILE", 8, joined and T.accent or T.muted)
        state:SetPoint("BOTTOMLEFT", 174, 8)
        state:SetWidth(130)
        local action = W:Button(row, joined and "Ritira" or "Ci sono", 88, 28, "primary")
        action:SetPoint("RIGHT", -8, 0)
        action:SetScript("OnClick", function()
            if joined then BJ.Activities:Leave(entry.id) else BJ.Activities:Join(entry.id) end
        end)
    end

    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then HUD:ClosePanel(); BJ.UI:Show("ACTIVITIES") end
    end)
end

function HUD:CreateCraftRow(parent, order, y)
    local row = W:AddDynamic(parent, W:Card(parent, ROW_W, CRAFT_ROW_H))
    row:SetPoint("TOPLEFT", 0, -y)

    local strip = row:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMLEFT", 0, 0)
    strip:SetWidth(3)
    strip:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(BJ.Crafting:GetItemIcon(order))
    icon:SetSize(29, 29)
    icon:SetPoint("LEFT", 12, 0)

    local title = CreateInfoText(row, BJ.Crafting:GetItemName(order), 10, T.white)
    title:SetPoint("TOPLEFT", 50, -9)
    title:SetWidth(250)
    local owner = CreateInfoText(row, "Di: " .. BJ:ShortName(order.owner) .. "  |  " .. BJ.Crafting:GetStateLabel(order), 8, T.muted)
    owner:SetPoint("TOPLEFT", 50, -28)
    owner:SetWidth(250)
    local note = (order.notes and order.notes ~= "") and order.notes or ("Commissione: " .. BJ.Crafting:FormatMoney(order.tipAmount))
    local noteText = CreateInfoText(row, note, 8, T.text)
    noteText:SetPoint("TOPLEFT", 50, -46)
    noteText:SetWidth(285)

    local interested = BJ.Crafting:GetInterestedCount(order.id)
    local meta = tostring(interested) .. " crafter  " .. BJ:FormatTimeLeft(math.max(0, (tonumber(order.expirationTime) or BJ:Now()) - BJ:Now()))
    local metaText = CreateInfoText(row, meta, 8, T.gold)
    metaText:SetPoint("RIGHT", -92, 0)
    metaText:SetWidth(100)

    if order.owner == BJ.player then
        local action = W:Button(row, "Apri", 76, 28, "primary")
        action:SetPoint("RIGHT", -8, 0)
        action:SetScript("OnClick", function() HUD:ClosePanel(); BJ.UI:Show("CRAFTING") end)
    else
        local joined = BJ.Crafting:IsInterested(order.id)
        local action = W:Button(row, joined and "Ritira" or "Posso", 76, 28, "primary")
        action:SetPoint("RIGHT", -8, 0)
        action:SetScript("OnClick", function() BJ.Crafting:ToggleOffer(order.id) end)
    end

    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then HUD:ClosePanel(); BJ.UI:Show("CRAFTING") end
    end)
end

function HUD:RefreshPanel(items, activityCount, craftCount)
    if not self.list then return end
    items = items or select(1, self:GetItems())
    if activityCount == nil or craftCount == nil then
        local _, a, c = self:GetItems()
        activityCount, craftCount = a, c
    end

    local mine, guild, crafts = {}, {}, {}
    local candidateTotal, invitableTotal, joinedTotal = 0, 0, 0
    for i = 1, #items do
        local item = items[i]
        if item.kind == "ACTIVITY" then
            if item.data.owner == BJ.player then
                mine[#mine + 1] = item
                candidateTotal = candidateTotal + #BJ.Activities:GetParticipants(item.data.id)
                invitableTotal = invitableTotal + #BJ.Activities:GetInvitableParticipants(item.data.id)
            else
                guild[#guild + 1] = item
                if BJ.Activities:GetJoinedState(item.data.id) then joinedTotal = joinedTotal + 1 end
            end
        else
            crafts[#crafts + 1] = item
        end
    end

    self:RefreshFilterButtons(#mine, #guild, #crafts)
    W:ClearDynamic(self.list)

    local filtered
    if self.panelFilter == "GUILD" then
        filtered = guild
        self.panelSummary:SetText(#guild .. " tavoli della gilda  |  " .. joinedTotal .. " a cui hai aderito")
        self.panelSummary:SetTextColor(T.muted[1], T.muted[2], T.muted[3], T.muted[4] or 1)
    elseif self.panelFilter == "CRAFT" then
        filtered = crafts
        self.panelSummary:SetText(#crafts .. " ordini craft attivi")
        self.panelSummary:SetTextColor(T.gold[1], T.gold[2], T.gold[3], T.gold[4] or 1)
    else
        filtered = mine
        self.panelSummary:SetText(#mine .. " tavoli tuoi  |  " .. candidateTotal .. " candidati  |  " .. invitableTotal .. " da invitare")
        self.panelSummary:SetTextColor(T.accent[1], T.accent[2], T.accent[3], T.accent[4] or 1)
    end

    if #filtered == 0 then
        local empty = W:AddDynamic(self.list, W:Card(self.list, ROW_W, 78, true))
        empty:SetPoint("TOPLEFT", 0, 0)
        local emptyTitle, emptyDesc
        if self.panelFilter == "GUILD" then
            emptyTitle = "NESSUNA ATTIVITA DELLA GILDA"
            emptyDesc = "Quando un altro membro apre un tavolo comparira qui, separato dalle tue attivita."
        elseif self.panelFilter == "CRAFT" then
            emptyTitle = "NESSUN CRAFT ATTIVO"
            emptyDesc = "Gli ordini di gilda pubblicati dal Companion compariranno qui."
        else
            emptyTitle = "NON HAI ATTIVITA APERTE"
            emptyDesc = "Usa Crea attivita nell'HUD: i tuoi tavoli compariranno sempre in questa scheda."
        end
        local title = W:Text(empty, emptyTitle, 11, T.gold, "OUTLINE")
        title:SetPoint("TOPLEFT", 14, -16)
        local desc = W:Text(empty, emptyDesc, 9, T.muted)
        desc:SetPoint("TOPLEFT", 14, -40)
        desc:SetWidth(440)
        self.list:SetHeight(292)
        return
    end

    local y = 0
    for i = 1, #filtered do
        local item = filtered[i]
        if item.kind == "ACTIVITY" then
            self:CreateActivityRow(self.list, item.data, y)
            y = y + ACTIVITY_ROW_H + 7
        else
            self:CreateCraftRow(self.list, item.data, y)
            y = y + CRAFT_ROW_H + 7
        end
    end
    self.list:SetHeight(math.max(292, y + 2))
end

function HUD:Refresh()
    if not self.frame then return end
    local items, activityCount, craftCount = self:GetItems()
    self:DetectNewItems(items)

    self.activityText:SetText("ATTIVITA " .. activityCount)
    local activityColor = activityCount > 0 and T.accent or T.muted
    self.activityText:SetTextColor(activityColor[1], activityColor[2], activityColor[3], activityColor[4] or 1)
    local pendingDeliveries = BJ.Crafting and BJ.Crafting:GetPendingDeliveryCount() or 0
    if pendingDeliveries > 0 then
        self.craftText:SetText("CRAFT " .. craftCount .. "  |  POSTA " .. pendingDeliveries)
        self.craftText:SetTextColor(T.gold[1], T.gold[2], T.gold[3], 1)
        self.craftBox:SetBackdropColor(0.19, 0.14, 0.035, 0.98)
        self.craftBox:SetBackdropBorderColor(T.gold[1], T.gold[2], T.gold[3], 1)
        self.craftDot:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 1)
    else
        self.craftText:SetText("CRAFT " .. craftCount)
        local craftColor = craftCount > 0 and T.gold or T.muted
        self.craftText:SetTextColor(craftColor[1], craftColor[2], craftColor[3], craftColor[4] or 1)
        self.craftBox:SetBackdropColor(T.bgDeep[1], T.bgDeep[2], T.bgDeep[3], T.bgDeep[4] or 1)
        self.craftBox:SetBackdropBorderColor(T.line[1], T.line[2], T.line[3], T.line[4] or 1)
        self.craftDot:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 1)
    end

    if self.panel:IsShown() then self:RefreshPanel(items, activityCount, craftCount) end
end

function HUD:OpenPanel()
    self:ClampFrameToScreen(true)
    self:ApplyExpandDirection()
    self:RefreshPanel()
    self.panel:Show()
    self.expand:SetText("Chiudi")
    -- SetClampedToScreen is a final safety net after the adaptive anchor has been chosen.
    C_Timer.After(0, function()
        if HUD.panel and HUD.panel:IsShown() then HUD:ApplyExpandDirection() end
    end)
end

function HUD:ClosePanel()
    if self.panel then self.panel:Hide() end
    if self.expand then self.expand:SetText("Apri") end
end

function HUD:TogglePanel()
    if self.panel:IsShown() then self:ClosePanel() else self:OpenPanel() end
end

function HUD:Show(force)
    -- Show can be requested by Access while ADDON_LOADED is still initializing.
    -- Never dereference frame until CreateFrame has actually run.
    if not self.frame then
        self.pendingShow = true
        return false
    end
    if BJ.Access and not BJ.Access:IsAuthorized() then
        self.pendingShow = true
        self.frame:Hide()
        return false
    end

    self.pendingShow = false
    self:Refresh()
    self.frame:Show()
    C_Timer.After(0, function() if HUD.frame and HUD.frame:IsShown() then HUD:ClampFrameToScreen(true) end end)
    return true
end

function HUD:Hide()
    self:ClosePanel()
    if self.frame then self.frame:Hide() end
end
