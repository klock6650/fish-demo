-- ============================================================================
-- IslandMenu: 岛屿商店 UI 模块
-- ============================================================================
-- 停靠岛屿后的交易面板：卖鱼换钱、补充燃油。
-- 由 main.lua 传入上下文，返回操作结果。
-- ============================================================================

local IslandMenu = {}

-- ── feature → 标签页映射 ─────────────────────────────────────────────────────
-- 每个 feature key 对应一个标签页的显示名和绘制/按键处理函数名
local FEATURE_META = {
    sell_fish = { label = "卖鱼",  drawFn = "_DrawSellTab",   keyFn = "_HandleSellKey"   },
    refuel    = { label = "补给",  drawFn = "_DrawSupplyTab",  keyFn = "_HandleSupplyKey"  },
    -- 未来扩展示例:
    -- repair    = { label = "修船",  drawFn = "_DrawRepairTab",  keyFn = "_HandleRepairKey"  },
    -- upgrade   = { label = "升级",  drawFn = "_DrawUpgradeTab", keyFn = "_HandleUpgradeKey" },
    -- quest     = { label = "任务",  drawFn = "_DrawQuestTab",   keyFn = "_HandleQuestKey"   },
}

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local tab = 1              -- 当前标签页索引
local tabs = {}            -- 当前岛屿的可用标签页列表 { { key, label, drawFn, keyFn }, ... }
local cursor = 1           -- 卖鱼列表当前选中行
local scrollOffset = 0     -- 列表滚动偏移
local ROW_H = 28           -- 每行高度
local MAX_VISIBLE = 8      -- 可见行数

-- ── 定价 ────────────────────────────────────────────────────────────────────
local PRICE_PER_KG_PER_DIFF = 4   -- 每kg每难度等级的价格
local FUEL_COST_PER_UNIT    = 1   -- 每单位燃油价格

-- ── 颜色常量（与 Inventory 同色系）────────────────────────────────────────
local C_BG        = { 12, 22, 45, 220 }
local C_BORDER    = { 80, 160, 240, 160 }
local C_OVERLAY   = { 0, 0, 0, 140 }
local C_TITLE     = { 200, 220, 255, 255 }
local C_TAB_ON    = { 100, 200, 255, 255 }
local C_TAB_OFF   = { 120, 130, 150, 180 }
local C_TAB_BG_ON = { 40, 80, 140, 160 }
local C_LABEL     = { 180, 195, 220, 220 }
local C_VALUE     = { 230, 240, 255, 255 }
local C_DIM       = { 130, 140, 160, 180 }
local C_GOLD      = { 255, 220, 80, 240 }
local C_HEADER    = { 140, 160, 190, 200 }
local C_SUM_LINE  = { 80, 100, 140, 120 }
local C_SUM_TEXT  = { 200, 220, 255, 240 }
local C_STARS     = { 255, 200, 50, 255 }
local C_SCROLL    = { 80, 120, 180, 120 }
local C_SEL_BG    = { 40, 120, 80, 100 }     -- 选中行高亮
local C_PRICE     = { 255, 220, 80, 240 }     -- 价格金色
local C_AFFORD    = { 100, 255, 150, 240 }    -- 买得起
local C_NO_AFFORD = { 255, 100, 100, 200 }    -- 买不起
local C_FUEL_OK   = { 80, 220, 160, 220 }     -- 油量充足
local C_EMPTY_MSG = { 140, 155, 180, 180 }    -- 空列表提示

-- ── 辅助 ────────────────────────────────────────────────────────────────────
local function rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4])
end

--- 计算单条鱼的售价
function IslandMenu.CalcFishPrice(fish)
    local basePerKg = fish.type.diff * PRICE_PER_KG_PER_DIFF
    local price = math.floor(fish.weight * basePerKg + 0.5)
    return math.max(1, price)
end

--- 计算加油费用
local function calcRefuelCost(amount)
    return math.ceil(amount * FUEL_COST_PER_UNIT)
end

-- ── 重置（传入岛屿对象，构建可用标签页）────────────────────────────────────
function IslandMenu.Reset(island)
    tab = 1
    cursor = 1
    scrollOffset = 0

    -- 根据 island.features 构建当前可用标签页
    tabs = {}
    if island and island.features then
        for _, fkey in ipairs(island.features) do
            local meta = FEATURE_META[fkey]
            if meta then
                tabs[#tabs + 1] = {
                    key    = fkey,
                    label  = meta.label,
                    drawFn = meta.drawFn,
                    keyFn  = meta.keyFn,
                }
            end
        end
    end
    -- 保底：如果 features 为空，给一个空 tabs（不会崩溃，只是没功能）
end

-- ── 按键处理 ────────────────────────────────────────────────────────────────
--- @param key number        按键码
--- @param ctx table         { island, caughtList, PlayerData }
--- @return boolean consumed 是否消耗
--- @return table|nil result 操作结果
function IslandMenu.HandleKey(key, ctx)
    local tabCount = #tabs
    if tabCount == 0 then return true, nil end

    -- 标签切换
    if key == KEY_LEFT or key == KEY_RIGHT then
        if key == KEY_LEFT then
            tab = tab > 1 and (tab - 1) or tabCount
        else
            tab = tab < tabCount and (tab + 1) or 1
        end
        scrollOffset = 0
        cursor = 1
        return true, nil
    end

    -- 分发到当前标签页的按键处理函数
    local currentTab = tabs[tab]
    if currentTab and IslandMenu[currentTab.keyFn] then
        return IslandMenu[currentTab.keyFn](key, ctx)
    end
    return true, nil
end

-- ── 卖鱼按键 ────────────────────────────────────────────────────────────────
function IslandMenu._HandleSellKey(key, ctx)
    local list = ctx.caughtList
    local count = #list

    if key == KEY_UP then
        if cursor > 1 then cursor = cursor - 1 end
        -- 滚动跟随光标
        if cursor <= scrollOffset then scrollOffset = cursor - 1 end
        return true, nil
    end

    if key == KEY_DOWN then
        if cursor < count then cursor = cursor + 1 end
        if cursor > scrollOffset + MAX_VISIBLE then
            scrollOffset = cursor - MAX_VISIBLE
        end
        return true, nil
    end

    -- Enter: 卖出选中鱼
    if key == KEY_RETURN or key == KEY_KP_ENTER then
        if count == 0 then return true, nil end
        if cursor < 1 or cursor > count then return true, nil end

        local fish = list[cursor]
        local price = IslandMenu.CalcFishPrice(fish)
        local soldWeight = fish.weight
        local fishName = fish.type.name

        ctx.PlayerData.AddMoney(price)
        table.remove(list, cursor)

        -- 修正光标
        local newCount = #list
        if cursor > newCount and newCount > 0 then cursor = newCount end
        if cursor < 1 then cursor = 1 end
        local maxScroll = math.max(0, newCount - MAX_VISIBLE)
        if scrollOffset > maxScroll then scrollOffset = maxScroll end

        return true, { soldWeight = soldWeight, soldCount = 1, income = price, fishName = fishName }
    end

    -- A: 全部卖出
    if key == KEY_A then
        if count == 0 then return true, nil end

        local totalIncome = 0
        local totalSoldWeight = 0
        for _, fish in ipairs(list) do
            local price = IslandMenu.CalcFishPrice(fish)
            totalIncome = totalIncome + price
            totalSoldWeight = totalSoldWeight + fish.weight
        end
        local soldCount = count

        ctx.PlayerData.AddMoney(totalIncome)

        -- 清空列表（反向移除保持引用）
        for i = count, 1, -1 do
            table.remove(list, i)
        end

        cursor = 1
        scrollOffset = 0

        return true, { soldWeight = totalSoldWeight, soldCount = soldCount, income = totalIncome, fishName = "" }
    end

    return true, nil
end

-- ── 补给按键 ────────────────────────────────────────────────────────────────
function IslandMenu._HandleSupplyKey(key, ctx)
    local PD = ctx.PlayerData
    local currentFuel = PD.GetFuel()
    local maxFuel = PD.GetFuelMax()

    local function tryRefuel(amount)
        local need = math.min(amount, maxFuel - currentFuel)
        if need <= 0 then return true, nil end
        local cost = calcRefuelCost(need)
        if not PD.CanAfford(cost) then return true, nil end
        PD.SpendMoney(cost)
        PD.AddFuel(need)
        return true, { fuelAdded = need, cost = cost }
    end

    -- Enter: 加满
    if key == KEY_RETURN or key == KEY_KP_ENTER then
        return tryRefuel(maxFuel)
    end

    -- 1: +10
    if key == KEY_1 then
        return tryRefuel(10)
    end

    -- 2: +30
    if key == KEY_2 then
        return tryRefuel(30)
    end

    return true, nil
end

-- ── 主绘制 ──────────────────────────────────────────────────────────────────
function IslandMenu.Draw(vg, sw, sh, ctx)
    local pw = math.min(460, sw - 40)
    local ph = math.min(420, sh - 40)
    local px = math.floor((sw - pw) / 2)
    local py = math.floor((sh - ph) / 2)

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, rgba(C_OVERLAY))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 10)
    nvgFillColor(vg, rgba(C_BG))
    nvgFill(vg)
    nvgStrokeColor(vg, rgba(C_BORDER))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题栏（显示岛屿名称）
    local titleH = 38
    local island = ctx.island
    local titleText = island and island.name or "岛屿"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_TITLE))
    nvgText(vg, px + 16, py + titleH * 0.5, titleText, nil)

    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_DIM))
    nvgText(vg, px + pw - 12, py + titleH * 0.5, "[E] 关闭", nil)

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 10, py + titleH)
    nvgLineTo(vg, px + pw - 10, py + titleH)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标签栏（动态生成）
    local tabY = py + titleH + 4
    local tabH = 28
    local tabW = 70
    local tabCount = #tabs
    for i, tabDef in ipairs(tabs) do
        local tx = px + 12 + (i - 1) * (tabW + 8)
        local isOn = (i == tab)
        if isOn then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx, tabY, tabW, tabH, 6)
            nvgFillColor(vg, rgba(C_TAB_BG_ON))
            nvgFill(vg)
        end
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, rgba(isOn and C_TAB_ON or C_TAB_OFF))
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, tabDef.label, nil)
    end

    if tabCount > 1 then
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, rgba(C_DIM))
        nvgText(vg, px + pw - 12, tabY + tabH / 2, "← → 切换", nil)
    end

    -- 内容区（分发到当前标签页的绘制函数）
    local contentY = tabY + tabH + 8
    local contentH = py + ph - contentY - 10

    local currentTab = tabs[tab]
    if currentTab and IslandMenu[currentTab.drawFn] then
        IslandMenu[currentTab.drawFn](vg, px, contentY, pw, contentH, ctx)
    else
        -- 无可用标签页时显示提示
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, rgba(C_EMPTY_MSG))
        nvgText(vg, px + pw / 2, contentY + contentH / 2, "此岛屿暂无可用服务", nil)
    end
end

-- ── 卖鱼标签 ────────────────────────────────────────────────────────────────
function IslandMenu._DrawSellTab(vg, px, cy, pw, ch, ctx)
    local list = ctx.caughtList
    local count = #list
    local y = cy + 4

    -- 表头
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_HEADER))
    nvgText(vg, px + 20, y, "#", nil)
    nvgText(vg, px + 46, y, "鱼种", nil)
    nvgText(vg, px + 150, y, "重量", nil)
    nvgText(vg, px + 230, y, "单价", nil)
    nvgText(vg, px + 310, y, "小计", nil)
    y = y + 20

    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 16, y)
    nvgLineTo(vg, px + pw - 16, y)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    y = y + 4

    -- 空列表
    if count == 0 then
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, rgba(C_EMPTY_MSG))
        nvgText(vg, px + pw / 2, y + 30, "暂无渔获，先去钓鱼吧！", nil)
        return
    end

    -- 保证光标范围合法
    if cursor > count then cursor = count end
    if cursor < 1 then cursor = 1 end

    -- 可见行计算
    local listAreaH = ch - (y - cy) - 50
    local visibleRows = math.max(1, math.floor(listAreaH / ROW_H))
    local maxScroll = math.max(0, count - visibleRows)
    if scrollOffset > maxScroll then scrollOffset = maxScroll end

    local startIdx = scrollOffset + 1
    local endIdx = math.min(count, scrollOffset + visibleRows)

    -- 累计总价
    local grandTotal = 0

    for i = startIdx, endIdx do
        local fish = list[i]
        local ft = fish.type
        local fy = y + (i - startIdx) * ROW_H
        local price = IslandMenu.CalcFishPrice(fish)
        local unitPrice = ft.diff * PRICE_PER_KG_PER_DIFF
        grandTotal = grandTotal + price

        -- 选中行高亮
        if i == cursor then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px + 12, fy - 2, pw - 24, ROW_H - 2, 4)
            nvgFillColor(vg, rgba(C_SEL_BG))
            nvgFill(vg)
        end

        nvgFontSize(vg, 13)

        -- 序号
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, rgba(C_DIM))
        nvgText(vg, px + 38, fy, tostring(i), nil)

        -- 鱼名
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local fc = ft.color or {180, 200, 220}
        nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], 240))
        nvgText(vg, px + 46, fy, ft.name, nil)

        -- 重量
        nvgFillColor(vg, rgba(C_VALUE))
        nvgText(vg, px + 150, fy, FormatWeight(fish.weight), nil)

        -- 单价
        nvgFillColor(vg, rgba(C_DIM))
        nvgText(vg, px + 230, fy, string.format("%d/kg", unitPrice), nil)

        -- 小计
        nvgFillColor(vg, rgba(C_PRICE))
        nvgText(vg, px + 310, fy, string.format("%d 💰", price), nil)
    end

    -- 计算所有鱼的总价（包括不可见的）
    grandTotal = 0
    for _, fish in ipairs(list) do
        grandTotal = grandTotal + IslandMenu.CalcFishPrice(fish)
    end

    -- 滚动条
    if count > visibleRows then
        local barX = px + pw - 14
        local barAreaY = y
        local barAreaH = visibleRows * ROW_H
        local thumbH = math.max(20, barAreaH * (visibleRows / count))
        local scrollRatio = maxScroll > 0 and (scrollOffset / maxScroll) or 0
        local thumbY = barAreaY + (barAreaH - thumbH) * scrollRatio
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, 4, thumbH, 2)
        nvgFillColor(vg, rgba(C_SCROLL))
        nvgFill(vg)
    end

    -- 底部合计 + 操作提示
    local sumY = cy + ch - 44
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 16, sumY)
    nvgLineTo(vg, px + pw - 16, sumY)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_SUM_TEXT))
    nvgText(vg, px + 20, sumY + 8,
        string.format("合计: %d 条  总价: %d 💰", count, grandTotal), nil)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_DIM))
    nvgText(vg, px + pw - 16, sumY + 8, "[Enter] 卖出", nil)
    nvgText(vg, px + pw - 16, sumY + 22, "[A] 全部卖出  ↑↓ 选择", nil)
end

-- ── 补给标签 ────────────────────────────────────────────────────────────────
function IslandMenu._DrawSupplyTab(vg, px, cy, pw, ch, ctx)
    local PD = ctx.PlayerData
    local fuel = PD.GetFuel()
    local fuelMax = PD.GetFuelMax()
    local money = PD.GetMoney()

    local y = cy + 16

    -- 燃油标题
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 160, 60, 240))
    nvgText(vg, px + 20, y, "⛽  燃油补给", nil)
    y = y + 30

    -- 燃油进度条
    local barX = px + 24
    local barW = pw - 48
    local barH = 18

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, y, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(20, 20, 30, 200))
    nvgFill(vg)

    -- 填充
    local pct = math.max(0, math.min(1, fuel / fuelMax))
    local fillW = barW * pct
    local r, g, b
    if pct > 0.5 then
        local t = (pct - 0.5) / 0.5
        r = math.floor(255 * (1 - t))
        g = 220
        b = math.floor(60 * (1 - t))
    else
        local t = pct / 0.5
        r = 255
        g = math.floor(220 * t)
        b = 0
    end
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, y, fillW, barH, 6)
        nvgFillColor(vg, nvgRGBA(r, g, b, 220))
        nvgFill(vg)
    end

    -- 数值
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, barX + barW / 2, y + barH / 2,
        string.format("%d / %d", math.ceil(fuel), fuelMax), nil)
    y = y + barH + 20

    -- 加满费用
    local need = math.max(0, fuelMax - fuel)
    local fullCost = calcRefuelCost(need)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    if need <= 0 then
        nvgFillColor(vg, rgba(C_FUEL_OK))
        nvgText(vg, px + 24, y, "油箱已满！", nil)
        y = y + 28
    else
        nvgFillColor(vg, rgba(C_LABEL))
        nvgText(vg, px + 24, y,
            string.format("加满需要: %d 单位 = %d 💰", math.ceil(need), fullCost), nil)
        y = y + 28
    end

    -- 当前金钱
    nvgFillColor(vg, rgba(C_LABEL))
    nvgText(vg, px + 24, y, "当前金钱: ", nil)
    local canAffordFull = money >= fullCost
    nvgFillColor(vg, rgba(canAffordFull and C_AFFORD or C_GOLD))
    nvgText(vg, px + 110, y, string.format("%d 💰", money), nil)
    y = y + 36

    -- 操作区分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 20, y)
    nvgLineTo(vg, px + pw - 20, y)
    nvgStrokeColor(vg, rgba(C_SUM_LINE))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    y = y + 14

    -- 操作按钮提示
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    if need > 0 then
        -- 加满
        local canFull = PD.CanAfford(fullCost)
        nvgFillColor(vg, rgba(canFull and C_AFFORD or C_NO_AFFORD))
        nvgText(vg, px + 24, y,
            string.format("[Enter]  加满  (%d 💰)", fullCost), nil)
        y = y + 24

        -- +10
        local need10 = math.min(10, need)
        local cost10 = calcRefuelCost(need10)
        local can10 = PD.CanAfford(cost10)
        nvgFillColor(vg, rgba(can10 and C_AFFORD or C_NO_AFFORD))
        nvgText(vg, px + 24, y,
            string.format("[1]  +%d 燃油  (%d 💰)", math.ceil(need10), cost10), nil)
        y = y + 24

        -- +30
        local need30 = math.min(30, need)
        local cost30 = calcRefuelCost(need30)
        local can30 = PD.CanAfford(cost30)
        nvgFillColor(vg, rgba(can30 and C_AFFORD or C_NO_AFFORD))
        nvgText(vg, px + 24, y,
            string.format("[2]  +%d 燃油  (%d 💰)", math.ceil(need30), cost30), nil)
        y = y + 30
    end

    -- 底部提示
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, rgba(C_DIM))
    nvgText(vg, px + pw / 2, cy + ch - 20, "燃油不足时船只无法加速", nil)
end

return IslandMenu
