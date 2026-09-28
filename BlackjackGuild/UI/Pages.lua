local _, BJ = ...

local UI = BJ.UI
local W = BJ.Widgets
local T = BJ.Theme

function UI.UnpackColor(c) return c[1], c[2], c[3], c[4] or 1 end

function UI.LabelFor(list, id)
    for i = 1, #list do if tostring(list[i].id) == tostring(id) then return list[i].label end end
    return tostring(id or "")
end

function UI.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return {c.r, c.g, c.b, 1} end
    return T.text
end

function UI:CreatePages()
    self:CreateHomePage()
    self:CreateActivitiesPage()
    self:CreateChallengesPage()
    self:CreateRewardsPage()
    self:CreateTreasuryPage()
    self:CreateRaiderPage()
    self:CreateCraftingPage()
    self:CreateMembersPage()
    self:CreateSettingsPage()
end

