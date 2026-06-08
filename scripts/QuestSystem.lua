-- ============================================================================
-- QuestSystem: 任务系统数据层
-- ============================================================================
-- 负责任务生成、进度追踪、提交结算。
-- 纯数据层，不涉及渲染。
-- ============================================================================

local QuestSystem = {}

-- 每个岛屿的任务缓存 (islandId → quests[6])
local islandQuests = {}

-- ── 奖励公式 ────────────────────────────────────────────────────────────────
-- 基础奖励 = diff * 80 + 平均体重 * diff * 0.8
-- 数量加成：required 越多总奖励越高（略有溢价）
local function calcReward(ft, required)
    local avgW   = (ft.wMin + ft.wMax) * 0.5
    local base   = ft.diff * 80 + avgW * ft.diff * 0.8
    local jitter = 0.85 + math.random() * 0.3   -- ±15% 随机
    return math.max(50, math.floor(base * required * jitter))
end

-- ── 生成任务 ────────────────────────────────────────────────────────────────
--- 为指定岛屿生成 6 个任务（首次调用生成，后续复用缓存）
--- @param islandId  any        岛屿 ID
--- @param fishTypes table      FISH_TYPES 数组（1-based）
--- @return table               quests[1..6]
function QuestSystem.GenerateQuests(islandId, fishTypes)
    if islandQuests[islandId] then
        return islandQuests[islandId]
    end

    -- 构建可选鱼种池（排除最后的测试鱼）
    local pool = {}
    for i = 1, #fishTypes - 1 do
        pool[#pool + 1] = i
    end

    -- Fisher-Yates 随机打乱
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    local quests = {}
    for k = 1, 6 do
        local idx      = pool[k]
        local ft       = fishTypes[idx]
        local required = math.random(1, 5)
        quests[k] = {
            fishTypeIdx = idx,
            fishType    = ft,
            required    = required,
            reward      = calcReward(ft, required),
            completed   = false,
        }
    end

    islandQuests[islandId] = quests
    return quests
end

-- ── 辅助查询 ────────────────────────────────────────────────────────────────
--- 返回背包中某鱼种的数量
function QuestSystem.GetHoldCount(fishTypeIdx, caughtList)
    local n = 0
    for _, fish in ipairs(caughtList) do
        if fish.type.id == fishTypeIdx then n = n + 1 end
    end
    return n
end

-- ── 提交任务 ────────────────────────────────────────────────────────────────
--- 尝试完成指定任务
--- @return boolean, number, string
function QuestSystem.TrySubmit(quest, caughtList, playerData)
    if quest.completed then
        return false, 0, "任务已完成"
    end

    local have = QuestSystem.GetHoldCount(quest.fishTypeIdx, caughtList)
    if have < quest.required then
        return false, 0, string.format(
            "需要 %d 条%s，背包只有 %d 条",
            quest.required, quest.fishType.name, have)
    end

    -- 从背包移除对应数量的鱼（倒序，避免索引错位）
    local removed = 0
    for i = #caughtList, 1, -1 do
        if removed >= quest.required then break end
        if caughtList[i].type.id == quest.fishTypeIdx then
            table.remove(caughtList, i)
            removed = removed + 1
        end
    end

    playerData.AddMoney(quest.reward)
    quest.completed = true

    return true, quest.reward, string.format("完成！获得 %d 💰", quest.reward)
end

-- ── 刷新 ────────────────────────────────────────────────────────────────────
--- 清除某岛屿的任务缓存（下次打开时重新生成）
function QuestSystem.RefreshIsland(islandId)
    islandQuests[islandId] = nil
end

return QuestSystem
