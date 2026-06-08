-- ============================================================================
-- PlayerData: 玩家数值系统
-- ============================================================================
-- 管理玩家的金钱、资源等持久化数据。
-- 后续接入存档系统时，只需序列化/反序列化 PlayerData.data 即可。
-- ============================================================================

local PlayerData = {}

-- ── 数据模型 ────────────────────────────────────────────────────────────────
-- 所有需要持久化的字段都放在这个 table 里
PlayerData.data = {
    money = 0,              -- 金钱
    resources = {
        wood    = 0,        -- 木料
        iron    = 0,        -- 废铁
        rope    = 0,        -- 绳子
        crystal = 0,        -- 深海晶
    },
    ownedRods = {           -- 已解锁的竿型 (1 始终可用，影响钓鱼逻辑)
        [1] = true,
    },
    inventory = {},         -- 背包物品列表：{ {type="rod", rodId=N}, ... }，允许重复
    storage   = {},         -- 仓库物品列表：与 inventory 结构相同
    equippedHook = 3,       -- 当前装备的鱼钩等级 (1=微小 2=小型 3=中型 4=大型 5=巨大)
    equippedBait = 0,       -- 当前装备的鱼饵 (0=无 1-15=对应 BaitSelector.BAIT_TYPES)
    equippedReelId = 2,     -- 当前装备的渔线轮 ID (1=溪钓轮 2=矶钓轮 3=船钓轮 4=重型轮)
    boatLevel = 0,          -- 船只等级 (0=未升级, 1/2/3=已解锁该等级)
    boatTechs = {},         -- 已解锁的科技分支 { "1_storage"=true, "2_engine"=true, ... }
    cabinSlots = {},        -- 船舱装备格 [1~12] = item or nil
}

-- ── 变动回调 ────────────────────────────────────────────────────────────────
-- UI 层可注册回调，在数值变动时刷新显示（观察者模式）
local listeners = {}

--- 注册数值变动监听器
--- @param fn fun(key: string, newVal: number, delta: number)
function PlayerData.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function notify(key, newVal, delta)
    for _, fn in ipairs(listeners) do
        fn(key, newVal, delta)
    end
end

-- ── 金钱操作 ────────────────────────────────────────────────────────────────

--- 获取当前金钱
function PlayerData.GetMoney()
    return PlayerData.data.money
end

--- 增加金钱（正数）
function PlayerData.AddMoney(amount)
    if amount <= 0 then return end
    PlayerData.data.money = PlayerData.data.money + amount
    notify("money", PlayerData.data.money, amount)
end

--- 扣除金钱，余额不足返回 false
function PlayerData.SpendMoney(amount)
    if amount <= 0 then return true end
    if PlayerData.data.money < amount then return false end
    PlayerData.data.money = PlayerData.data.money - amount
    notify("money", PlayerData.data.money, -amount)
    return true
end

--- 判断是否负担得起
function PlayerData.CanAfford(amount)
    return PlayerData.data.money >= amount
end



-- ── 资源操作 ────────────────────────────────────────────────────────────────

--- 获取资源数量
--- @param resName string 资源名 (如 "wood")
function PlayerData.GetResource(resName)
    return PlayerData.data.resources[resName] or 0
end

--- 增加资源
function PlayerData.AddResource(resName, amount)
    if amount <= 0 then return end
    local cur = PlayerData.data.resources[resName] or 0
    PlayerData.data.resources[resName] = cur + amount
    notify("res:" .. resName, PlayerData.data.resources[resName], amount)
end

--- 消耗资源，不足返回 false
function PlayerData.SpendResource(resName, amount)
    if amount <= 0 then return true end
    local cur = PlayerData.data.resources[resName] or 0
    if cur < amount then return false end
    PlayerData.data.resources[resName] = cur - amount
    notify("res:" .. resName, PlayerData.data.resources[resName], -amount)
    return true
end

--- 判断资源是否足够
function PlayerData.HasResource(resName, amount)
    return (PlayerData.data.resources[resName] or 0) >= amount
end

-- ── 背包操作 ─────────────────────────────────────────────────────────────────

--- 向背包中添加一件物品
--- @param item table  如 {type="rod", rodId=2}
function PlayerData.AddInventoryItem(item)
    local inv = PlayerData.data.inventory
    inv[#inv + 1] = item
end

--- 获取背包列表（只读引用）
function PlayerData.GetInventory()
    return PlayerData.data.inventory
end

-- ── 仓库操作 ─────────────────────────────────────────────────────────────────

--- 获取仓库列表（只读引用）
function PlayerData.GetStorage()
    return PlayerData.data.storage
end

--- 向仓库添加物品
function PlayerData.AddStorageItem(item)
    local st = PlayerData.data.storage
    st[#st + 1] = item
end

--- 从仓库移除指定索引的物品，返回被移除的物品
function PlayerData.RemoveStorageItem(idx)
    local st = PlayerData.data.storage
    if idx < 1 or idx > #st then return nil end
    return table.remove(st, idx)
end

--- 从背包移除指定索引的物品，返回被移除的物品
function PlayerData.RemoveInventoryItem(idx)
    local inv = PlayerData.data.inventory
    if idx < 1 or idx > #inv then return nil end
    return table.remove(inv, idx)
end

-- ── 快照（供存档系统使用）────────────────────────────────────────────────────

--- 导出当前数据的深拷贝（存档用）
function PlayerData.Export()
    local d = PlayerData.data
    local rods = {}
    for k, v in pairs(d.ownedRods or {}) do rods[k] = v end
    local inv = {}
    for i, item in ipairs(d.inventory or {}) do
        inv[i] = { type = item.type, rodId = item.rodId, reelId = item.reelId, hookId = item.hookId, baitId = item.baitId }
    end
    local sto = {}
    for i, item in ipairs(d.storage or {}) do
        sto[i] = { type = item.type, rodId = item.rodId, reelId = item.reelId, hookId = item.hookId, baitId = item.baitId }
    end
    local techs = {}
    for k, v in pairs(d.boatTechs or {}) do techs[k] = v end
    local cabin = {}
    for i = 1, 12 do
        if d.cabinSlots and d.cabinSlots[i] then
            local item = d.cabinSlots[i]
            cabin[i] = { type = item.type, rodId = item.rodId, reelId = item.reelId, hookId = item.hookId, baitId = item.baitId }
        end
    end
    return {
        money = d.money,
        resources = {
            wood    = d.resources.wood    or 0,
            iron    = d.resources.iron    or 0,
            rope    = d.resources.rope    or 0,
            crystal = d.resources.crystal or 0,
        },
        ownedRods    = rods,
        inventory    = inv,
        storage      = sto,
        equippedHook   = d.equippedHook   or 3,
        equippedBait   = d.equippedBait   or 0,
        equippedReelId = d.equippedReelId or 2,
        boatLevel      = d.boatLevel      or 0,
        boatTechs      = techs,
        cabinSlots     = cabin,
    }
end

--- 从存档数据导入（读档用）
function PlayerData.Import(saved)
    if not saved then return end
    PlayerData.data.money = saved.money or 0
    if saved.resources then
        for k, v in pairs(saved.resources) do
            PlayerData.data.resources[k] = v
        end
    end
    if saved.ownedRods then
        PlayerData.data.ownedRods = {}
        for k, v in pairs(saved.ownedRods) do
            PlayerData.data.ownedRods[k] = v
        end
    end
    -- 竿型 1 始终可用
    PlayerData.data.ownedRods[1] = true
    -- 背包
    PlayerData.data.inventory = {}
    if saved.inventory then
        for i, item in ipairs(saved.inventory) do
            PlayerData.data.inventory[i] = { type = item.type, rodId = item.rodId, reelId = item.reelId, hookId = item.hookId, baitId = item.baitId }
        end
    end
    -- 仓库
    PlayerData.data.storage = {}
    if saved.storage then
        for i, item in ipairs(saved.storage) do
            PlayerData.data.storage[i] = { type = item.type, rodId = item.rodId, reelId = item.reelId, hookId = item.hookId, baitId = item.baitId }
        end
    end
    -- 鱼钩等级（兼容旧存档默认中型）
    PlayerData.data.equippedHook = saved.equippedHook or 3
    -- 鱼饵（兼容旧存档默认无饵）
    PlayerData.data.equippedBait = saved.equippedBait or 0
    -- 渔线轮（兼容旧存档默认矶钓轮）
    PlayerData.data.equippedReelId = saved.equippedReelId or 2
    -- 船只升级
    PlayerData.data.boatLevel = saved.boatLevel or 0
    PlayerData.data.boatTechs = {}
    if saved.boatTechs then
        for k, v in pairs(saved.boatTechs) do
            PlayerData.data.boatTechs[k] = v
        end
    end
    -- 船舱装备
    PlayerData.data.cabinSlots = {}
    if saved.cabinSlots then
        for i = 1, 12 do
            if saved.cabinSlots[i] then
                local item = saved.cabinSlots[i]
                PlayerData.data.cabinSlots[i] = { type = item.type, rodId = item.rodId, reelId = item.reelId, hookId = item.hookId, baitId = item.baitId }
            end
        end
    end
end

--- 重置为初始状态
function PlayerData.Reset()
    PlayerData.data.money = 0
    PlayerData.data.resources.wood    = 0
    PlayerData.data.resources.iron    = 0
    PlayerData.data.resources.rope    = 0
    PlayerData.data.resources.crystal = 0
    PlayerData.data.ownedRods      = { [1] = true }
    PlayerData.data.equippedHook   = 3
    PlayerData.data.equippedBait   = 0
    PlayerData.data.equippedReelId = 2
    PlayerData.data.boatLevel      = 0
    PlayerData.data.boatTechs      = {}
end

return PlayerData
