local _, BJ = ...

BJ.Challenges = {}
local Challenges = BJ.Challenges

function Challenges:Initialize()
    BJ.Progress:EnsureWeek()
end

function Challenges:GetAll()
    return BJ.Data:GetActiveChallenges()
end

function Challenges:GetProgress(challenge)
    if not challenge then return 0, 1 end
    local goal = tonumber(challenge.goal) or 1
    if BJ.TestMode and BJ.TestMode:IsEnabled() and BJ.db.test and BJ.db.test.forceAllChallenges then
        return goal, goal
    end
    if challenge.mode == "stat" then
        return math.min(BJ.Progress:GetStat(challenge.key), goal), goal
    elseif challenge.mode == "set" then
        return math.min(BJ.Progress:GetSetCount(challenge.key), goal), goal
    end
    return 0, goal
end

function Challenges:IsCompleted(challenge)
    local value, goal = self:GetProgress(challenge)
    return value >= goal
end

function Challenges:GetCompletedCount()
    local n = 0
    for _, challenge in ipairs(self:GetAll()) do
        if self:IsCompleted(challenge) then n = n + 1 end
    end
    return n
end

function Challenges:GetClaimableCount()
    local n = 0
    for _, challenge in ipairs(self:GetAll()) do
        if self:IsCompleted(challenge) and not BJ.Rewards:IsClaimed(challenge.id) then n = n + 1 end
    end
    return n
end

function Challenges:GetGroup(group)
    local out = {}
    for _, challenge in ipairs(self:GetAll()) do
        if challenge.group == group then out[#out + 1] = challenge end
    end
    return out
end

function Challenges:Refresh()
    if BJ.UI then
        BJ.UI:RefreshPage("CHALLENGES")
        BJ.UI:RefreshPage("HOME")
    end
end
