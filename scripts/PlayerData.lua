-- ============================================================================
-- PlayerData: 玩家数值系统
-- ============================================================================
-- 管理玩家的金钱、资源等持久化数据。
-- 后续接入存档系统时，只需序列化/反序列化 PlayerData.data 即可。
-- ============================================================================

local PlayerData = {}

-- ── 数据模型 ────────────────────────────────────────────────────────────────
-- 所有需要持久化的字段都放在这个 table 里
PlayerData.FUEL_MAX = 300       -- 燃油上限

PlayerData.data = {
    money = 0,              -- 金钱
    fuel = 300,             -- 燃油（初始满）
    resources = {
        wood = 0,           -- 木料
    },
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

-- ── 燃油操作 ────────────────────────────────────────────────────────────────

function PlayerData.GetFuel()
    return PlayerData.data.fuel
end

function PlayerData.GetFuelMax()
    return PlayerData.FUEL_MAX
end

--- 消耗燃油（每帧调用，amount 可以是小数）
function PlayerData.ConsumeFuel(amount)
    if amount <= 0 then return end
    PlayerData.data.fuel = math.max(0, PlayerData.data.fuel - amount)
end

--- 补充燃油
function PlayerData.AddFuel(amount)
    if amount <= 0 then return end
    PlayerData.data.fuel = math.min(PlayerData.FUEL_MAX, PlayerData.data.fuel + amount)
    notify("fuel", PlayerData.data.fuel, amount)
end

function PlayerData.HasFuel()
    return PlayerData.data.fuel > 0
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

-- ── 快照（供存档系统使用）────────────────────────────────────────────────────

--- 导出当前数据的深拷贝（存档用）
function PlayerData.Export()
    local d = PlayerData.data
    return {
        money = d.money,
        fuel = d.fuel,
        resources = {
            wood = d.resources.wood or 0,
        },
    }
end

--- 从存档数据导入（读档用）
function PlayerData.Import(saved)
    if not saved then return end
    PlayerData.data.money = saved.money or 0
    PlayerData.data.fuel = saved.fuel or PlayerData.FUEL_MAX
    if saved.resources then
        for k, v in pairs(saved.resources) do
            PlayerData.data.resources[k] = v
        end
    end
end

--- 重置为初始状态
function PlayerData.Reset()
    PlayerData.data.money = 0
    PlayerData.data.fuel = PlayerData.FUEL_MAX
    PlayerData.data.resources.wood = 0
end

return PlayerData
