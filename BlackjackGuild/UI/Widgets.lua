local _, BJ = ...

BJ.Widgets = {}
local W = BJ.Widgets
local T = BJ.Theme

local function unpackColor(c) return c[1], c[2], c[3], c[4] or 1 end

function W:Backdrop(frame, bg, border, edge)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edge or 1,
    })
    frame:SetBackdropColor(unpackColor(bg or T.surface))
    frame:SetBackdropBorderColor(unpackColor(border or T.line))
end

function W:Text(parent, text, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
    fs:SetTextColor(unpackColor(color or T.text))
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetText(text or "")
    return fs
end

function W:Button(parent, text, width, height, kind)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 110, height or 30)

    local function colors(buttonKind)
        if buttonKind == "primary" then
            return {0.10,0.26,0.17,1}, T.accentStrong, T.white
        elseif buttonKind == "danger" then
            return T.surfaceSoft, T.red, T.text
        elseif buttonKind == "disabled" then
            return {0.055,0.075,0.068,1}, T.line, T.muted
        end
        return T.surfaceSoft, T.lineStrong, T.text
    end

    b.label = self:Text(b, text or "", 11, T.text)
    b.label:SetPoint("CENTER")

    b.SetText = function(self, value) self.label:SetText(value or "") end
    b.SetTextColor = function(self, color) self.label:SetTextColor(unpackColor(color)) end
    b.SetKind = function(self, newKind)
        self.kind = newKind or "default"
        local bg, border, textColor = colors(self.kind)
        W:Backdrop(self, bg, border)
        self.label:SetTextColor(unpackColor(textColor))
    end

    b:SetScript("OnEnter", function(self)
        if self.kind == "disabled" or not self:IsEnabled() then return end
        self:SetBackdropBorderColor(unpackColor(self.kind == "danger" and T.red or T.accent))
    end)
    b:SetScript("OnLeave", function(self)
        local _, border = colors(self.kind)
        self:SetBackdropBorderColor(unpackColor(border))
    end)

    b:SetKind(kind or "default")
    return b
end

function W:Card(parent, width, height, strong)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width or 100, height or 100)
    self:Backdrop(f, strong and T.surfaceStrong or T.surface, T.line)
    return f
end

function W:EditBox(parent, width, height, maxLetters, multiline)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 200, height or 30)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(8, 8, 5, 5)
    box:SetMaxLetters(maxLetters or 100)
    box:SetMultiLine(multiline and true or false)
    box:SetJustifyV(multiline and "TOP" or "MIDDLE")
    self:Backdrop(box, T.bgDeep, T.lineStrong)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if not multiline then box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) end
    return box
end

function W:SearchBox(parent, width, placeholder, onChanged)
    local box = self:EditBox(parent, width or 220, 30, 120, false)
    box.placeholder = self:Text(box, placeholder or "Cerca...", 10, T.muted)
    box.placeholder:SetPoint("LEFT", 9, 0)
    box.placeholder:SetPoint("RIGHT", -8, 0)
    box.placeholder:SetJustifyH("LEFT")

    local function RefreshPlaceholder(self)
        self.placeholder:SetShown((self:GetText() or "") == "" and not self:HasFocus())
    end

    box:HookScript("OnTextChanged", function(self)
        RefreshPlaceholder(self)
        if onChanged then onChanged(self:GetText() or "") end
    end)
    box:HookScript("OnEditFocusGained", function(self) RefreshPlaceholder(self) end)
    box:HookScript("OnEditFocusLost", function(self) RefreshPlaceholder(self) end)
    RefreshPlaceholder(box)
    return box
end

function W:SectionLabel(parent, text)
    return self:Text(parent, string.upper(text or ""), 10, T.gold)
end

function W:Toggle(parent, label, getter, setter, width)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f:SetSize(width or 320, 40)
    self:Backdrop(f, T.surface, T.line)
    local text = self:Text(f, label, 12, T.text)
    text:SetPoint("LEFT", 12, 0)
    local state = self:Text(f, "", 11, T.muted, "OUTLINE")
    state:SetPoint("RIGHT", -12, 0)
    f.label, f.state = text, state
    f.Refresh = function(self)
        local enabled = getter()
        self.state:SetText(enabled and "ON" or "OFF")
        self.state:SetTextColor(unpackColor(enabled and T.accent or T.muted))
    end
    f:SetScript("OnClick", function(self)
        setter(not getter())
        self:Refresh()
    end)
    f:Refresh()
    return f
end

function W:Dropdown(parent, width, items, value, onChanged)
    local b = self:Button(parent, "", width or 180, 30)
    b.items = items or {}
    b.value = value
    b.onChanged = onChanged

    function b:FindLabel(id)
        for i = 1, #self.items do
            if tostring(self.items[i].id) == tostring(id) then return self.items[i].label end
        end
        return self.items[1] and self.items[1].label or "-"
    end

    function b:SetItems(newItems)
        self.items = newItems or {}
        local found = false
        for i = 1, #self.items do
            if tostring(self.items[i].id) == tostring(self.value) then
                found = true
                break
            end
        end
        if not found and self.items[1] then self.value = self.items[1].id end
        self:SetText(self:FindLabel(self.value) .. "  v")
    end

    function b:SetValue(newValue, silent)
        self.value = newValue
        self:SetText(self:FindLabel(newValue) .. "  v")
        if not silent and self.onChanged then self.onChanged(newValue) end
    end

    function b:GetValue()
        return self.value
    end

    b:SetItems(b.items)
    b:SetValue(value or (b.items[1] and b.items[1].id), true)
    b:SetScript("OnClick", function(self)
        if BJ.UI then
            BJ.UI:OpenDropdown(self, self.items, self.value, function(v)
                self:SetValue(v, false)
            end)
        end
    end)
    return b
end

function W:ScrollArea(parent, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(math.max(1, width - 28), 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 44)))
    end)
    return scroll, child
end

function W:ClearDynamic(container)
    if not container._dynamic then
        container._dynamic = {}
        return
    end
    for i = 1, #container._dynamic do
        local child = container._dynamic[i]
        child:Hide()
        child:SetParent(nil)
    end
    wipe(container._dynamic)
end

function W:AddDynamic(container, child)
    container._dynamic = container._dynamic or {}
    container._dynamic[#container._dynamic + 1] = child
    return child
end
