-- Run from addon root: lua Tests/regression.lua
-- TeX Live also provides a Lua runtime: luatex --luaonly Tests/regression.lua
local now, rank, inGuild = 100000, 1, true
local guid = "Player-1-ABC"
local timers = {}
GetServerTime = function() return now end
GetNormalizedRealmName = function() return "Nemesis" end
UnitFullName = function() return "Vice", "Nemesis" end
UnitGUID = function() return guid end
IsInGuild = function() return inGuild end
GetGuildInfo = function() return "Blackjack", "Pit Boss", rank end
C_GuildInfo = { CanEditOfficerNote = function() return true end }
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return {} end }
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
wipe = function(t) for k in pairs(t) do t[k] = nil end end
local BJ = {}
local function load(name) assert(loadfile(name))("BlackjackGuild", BJ) end
load("Core.lua")
BJ.player = BJ:GetPlayerFullName()
load("Storage.lua")
BJ.Storage:Initialize()
load("Data.lua")
BJ.Data:Initialize()
load("Guild.lua")
load("Access.lua")
load("Activities.lua")
load("Comms.lua")
load("TestMode.lua")
load("Raider.lua")
load("Crafting.lua")
BJ.Theme = {}
load("UI/Main.lua")
local checks = 0
local function check(value, label)
    assert(value, label)
    checks = checks + 1
    print("PASS " .. label)
end
local function packet(id, count, revision)
    return { "V5", "ACT", id, "MPLUS", "vault_chill", "ANY", "ANY", "5", tostring(now + 3600), tostring(count or 1), tostring(revision or 0) }
end
local function receive(kind, sender, ...)
    BJ.Comms:OnMessage(false, BJ.prefix, BJ.Comms:Make(kind, ...), "GUILD", sender)
end
local mine = BJ.Activities:Create({})
local id = mine.id
BJ.Activities:HandleRemoteActivity("Other-Nemesis", packet(id))
check(mine.owner == BJ.player and #BJ.Activities:GetOwned() == 1, "ID collision cannot steal local ownership")
BJ.Activities:HandleRemoteActivity("Vice-nemesis", packet(id))
check(mine.localOwned, "self echo preserves local activity")
local id2 = BJ.Activities:NewID()
guid = "Player-1-DEF"
local otherID = BJ.Activities:NewID()
check(id ~= id2 and id2 ~= otherID, "IDs unique within one second and between players")
receive("ACTDEL", "Other-Nemesis", id)
receive("COUNT", "Other-Nemesis", id, 99, 99)
check(BJ.db.network.activities[id] == mine and mine.count == 1, "foreign deletion and count rejected")
BJ.Activities:HandleJoin(id, "Other-Nemesis")
BJ.Activities:HandleJoin(id, "Other-Nemesis")
check(mine.count == 2 and mine.revision == 2, "duplicate JOIN is idempotent")
BJ.Activities:HandleLeave(id, BJ.player)
check(mine.count == 2, "owner cannot leave own participant set")
BJ.Activities:HandleLeave(id, "Other-Nemesis")
check(mine.count == 1 and mine.revision == 3, "LEAVE updates revision")
BJ.Activities:HandleRemoteActivity("Other-Nemesis", packet("remote", 2, 2))
BJ.Activities:HandleCount("remote", 3, "Other-Nemesis", 3)
BJ.Activities:HandleRemoteActivity("Other-Nemesis", packet("remote", 2, 2))
check(BJ.db.network.activities.remote.count == 3, "stale activity snapshot cannot roll back count")
BJ.Activities:HandleCount("remote", 20, "Stranger-Nemesis", 100)
check(BJ.db.network.activities.remote.count == 3, "only owner updates remote count")
receive("ACTDEL", "Other-Nemesis", "remote")
BJ.Activities:HandleRemoteActivity("Other-Nemesis", packet("remote", 3, 3))
check(not BJ.db.network.activities.remote, "deleted activity cannot resurrect")
receive("ACTDEL", "Other-Nemesis", "early")
BJ.Activities:HandleRemoteActivity("Other-Nemesis", packet("early"))
check(not BJ.db.network.activities.early, "delete before creation is remembered")
BJ.Activities:HandleRemoteActivity("Real-Nemesis", packet("early"))
check(BJ.db.network.activities.early.owner == "Real-Nemesis", "foreign tombstone cannot suppress owner")
local invalid = packet("invalid")
invalid[9] = "inf"
check(not BJ.Activities:HandleRemoteActivity("Other-Nemesis", invalid), "invalid expiry rejected")
BJ.Comms:OnMessage(true, BJ.prefix, "ACTTXT text Early description", "GUILD", "Other-Nemesis")
receive("ACT", "Other-Nemesis", "text", "MPLUS", "vault_chill", "ANY", "ANY", 5, now + 3600, 1)
check(BJ.db.network.activities.text.description == "Early description", "text before metadata reconciles")
BJ.Comms:StoreActivityText("pending", "Other-Nemesis", nil, "expired")
now = now + 301
BJ.Comms:Cleanup()
check(next(BJ.Comms.pendingActivityText) == nil, "orphan text expires")
BJ.Comms:OnMessage(false, BJ.prefix, BJ.Comms:Make("ACTDEL", id), "RAID", "Other-Nemesis")
check(BJ.db.network.activities[id] == mine, "unexpected transport rejected")
BJ.Comms.queue = {}
BJ.Comms:SendSystem("AREQ", "GUILD")
BJ.Comms:SendSystem("AREQ", "GUILD")
check(#BJ.Comms.queue == 1, "identical queued requests coalesce")
for i = 1, 1100 do BJ.Comms:SendSystem("COUNT", "GUILD", nil, "q" .. i, 1) end
check(#BJ.Comms.queue == 1024, "outgoing queue bounded")
inGuild = false
BJ.Comms:FlushOne()
check(#BJ.Comms.queue == 0, "guild departure clears unsent messages")
inGuild = true
BJ.Comms.queue = {}
timers = {}
receive("AREQ", "Other-Nemesis")
receive("AREQ", "Other-Nemesis")
check(#timers == 1, "repeated requests do not amplify replies")
BJ.Comms.queue = {}
BJ.Comms:SendSystem("COUNT", "GUILD", nil, "retry", 1)
local attempts = 0
C_ChatInfo = { SendAddonMessage = function()
    attempts = attempts + 1
    return attempts < 3 and 3 or 0
end }
BJ.Comms:FlushOne()
BJ.Comms:FlushOne()
check(#BJ.Comms.queue == 1, "throttled transmission remains queued")
BJ.Comms:FlushOne()
check(#BJ.Comms.queue == 0 and attempts == 3, "transmission completes after retry")
BJ.Comms:SendSystem("COUNT", "GUILD", nil, "retry", 1)
C_ChatInfo.SendAddonMessage = function() return 3 end
for i = 1, 8 do BJ.Comms:FlushOne() end
check(#BJ.Comms.queue == 0, "failed transmission has bounded retries")
BJ.Comms:ApplyProfileMeta("Other-Nemesis", 10, 3, "starter", "")
receive("PCLEAR", "Other-Nemesis", 9)
check(BJ.db.network.profiles["Other-Nemesis"], "stale privacy packet cannot erase newer profile")
receive("PCLEAR", "Other-Nemesis", 10)
BJ.Comms:ApplyProfileField("Other-Nemesis", 10, "LIKES", "late")
check(not BJ.db.network.profiles["Other-Nemesis"], "delayed profile field cannot undo privacy clear")
BJ.Comms:ApplyProfileField("Other-Nemesis", 11, "LIKES", "shared again")
check(BJ.db.network.profiles["Other-Nemesis"].likes == "shared again", "newer revision can share profile again")
BJ.Guild.members["Other-Nemesis"] = { rankIndex = 1 }
check(not BJ.Guild:ResolveMember("Other-AnotherRealm"), "explicit foreign realm cannot inherit member permissions")
check(BJ.Guild:IsOfficer() and BJ.Guild:IsOfficerName("Other-Nemesis"), "vice GM local and remote permissions agree")
check(BJ.UI:CanAccessPage("CASSA") and BJ.Raider:CanManage(), "vice GM can manage both modules")
BJ.TestMode:SetEnabled(true)
check(BJ.TestMode:IsEnabled(), "vice GM can enable test mode")
rank = 2
check(not BJ.Guild:IsOfficer() and not BJ.UI:CanAccessPage("CASSA") and not BJ.Raider:CanManage(), "officer-note permission does not grant GM access")
check(not BJ.TestMode:IsEnabled(), "demotion disables test mode immediately")
BJ.TestMode:SetEnabled(true)
check(not BJ.TestMode:IsEnabled(), "member cannot activate test mode")
rank = 0
check(BJ.Guild:IsOfficer(), "GM access")
-- Test actual page transition, including the nested navigation refresh.
local function frame()
    return { shown = true, SetShown = function(self, v) self.shown = v end,
        IsShown = function(self) return self.shown end }
end
BJ.UI.navFrame = {}
BJ.UI.pages = { HOME = frame(), CASSA = frame() }
BJ.db.ui.lastPage = "CASSA"
rank = 2
BJ.UI:RefreshNavAccess()
check(BJ.db.ui.lastPage == "HOME" and not BJ.UI.pages.CASSA.shown, "demotion closes an already open restricted page")
BJ.UI.pages = {}
BJ.UI.navFrame = nil
BJ.Comms.queue = {}
BJ.Activities:Join("text")
BJ.Activities:Leave("text")
BJ.Comms.queue = {} -- simulate a lost LEAVE
BJ.Comms:BroadcastActivities("GUILD")
local sawLeave = false
for _, item in ipairs(BJ.Comms.queue) do
    if item.message == BJ.Comms:Make("LEAVE", "text") then sawLeave = true end
end
check(sawLeave, "lost LEAVE recovered by periodic broadcast")
BJ.Activities:Join("text")
check(not BJ.db.activityLeaves[BJ.player].text, "rejoining cancels departure recovery")
BJ.db.crafting.owned.localOrder = { id = "localOrder", owner = BJ.player, orderState = 1, expirationTime = now + 300 }
BJ.db.network.craftingHistory.finished = { id = "finished", closeReason = "COMPLETATO", closedAt = now }
BJ.Storage:ResetNetworkCache()
check(BJ.db.network.activities[id] == mine, "cache reset preserves own activity and participants")
check(BJ.db.network.craftingOrders.localOrder and BJ.db.network.craftingHistory.finished, "cache reset preserves owned crafting and completion recovery")
check(BJ.Activities:IsDeleted("remote", "Other-Nemesis"), "cache reset preserves deletion guards")
local previous = BJ.player
BJ.db.joinedActivities.subscription = true
BJ.player = "Alt-Nemesis"
BJ.Storage:Initialize()
check(not BJ.db.joinedActivities.subscription, "subscriptions isolated on character switch")
BJ.player = previous
BJ.Storage:Initialize()
check(BJ.db.joinedActivities.subscription, "subscriptions restored on original character")
local order = { owner = BJ.player, id = "123" }
BJ.db.network.craftingOrders["123"] = order
BJ.Crafting:HandleRemoteOrder("Other-Nemesis", { "V5", "CRAFT", "123", "1", "1", "1", "0", tostring(now + 300), "0", "0", "1" })
check(order.owner == BJ.player, "crafting announcements cannot transfer ownership")
BJ.Activities:Delete(id)
BJ.Comms.queue = {}
BJ.Comms:BroadcastActivities("GUILD")
check(#BJ.Comms.queue > 0 and BJ.Comms.queue[1].message:find("ACTDEL", 1, true), "deletions rebroadcast when no owned activity remains")
-- Syntax-check every shipped Lua source, without executing UI/game APIs.
for line in io.lines("BlackjackGuild.toc") do
    if line:match("%.lua%s*$") then assert(loadfile((line:gsub("\\", "/"):gsub("%s+$", "")))) end
end
print("PASS all TOC Lua files parse")
print(tostring(checks) .. " regression checks passed")
