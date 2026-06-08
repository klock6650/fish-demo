-- ============================================================================
-- BoatUpgrade: 船只科技树升级模块
-- 3级船只等级，每级4个分支科技（存储、渔网、引擎、鱼钩）
-- ============================================================================

local BoatUpgrade = {}

-- ── 状态 ────────────────────────────────────────────────────────────────────
local open_ = false
local _hits = {}
local imgs_ = {}       -- NanoVG 图片句柄缓存
local loaded_ = false  -- 贴图是否全部加载完毕
local loadingRequested_ = false  -- 是否已发起加载请求

-- ── 弹性点击动画 ────────────────────────────────────────────────────────────
local bounceAnims_ = {}  -- { [id] = { t = 0, duration = 0.25 } }
local BOUNCE_DURATION = 0.2
local BOUNCE_SCALE = 1.15  -- 最大放大倍数

-- ── 科技树配置 ──────────────────────────────────────────────────────────────
-- 船只等级解锁费用
local LEVEL_COSTS = { 500, 1500, 4000 }

-- 分支科技定义: id后缀, 显示名, 图标符号, 每级费用
local BRANCHES = {
    { key = "storage", name = "货仓",   icon = "barrel" },
    { key = "net",     name = "渔网",   icon = "net"    },
    { key = "engine",  name = "引擎",   icon = "prop"   },
    { key = "hook",    name = "钩具",   icon = "hook"   },
}

-- 分支科技每级解锁费用（对应船只等级1/2/3下的分支）
local BRANCH_COSTS = { 300, 800, 2000 }

-- ── 辅助 ────────────────────────────────────────────────────────────────────
local function rgba(r, g, b, a) return nvgRGBA(r, g, b, a or 255) end

local function addHit(id, x, y, w, h)
    _hits[#_hits + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function hitTest(mx, my)
    for i = #_hits, 1, -1 do
        local box = _hits[i]
        if mx >= box.x and mx <= box.x + box.w and
           my >= box.y and my <= box.y + box.h then
            return box.id
        end
    end
    return nil
end

-- ── 贴图映射 ────────────────────────────────────────────────────────────────
-- 科技图标索引: [船等级][分支序号] → 切片编号(未解锁)
-- 分支顺序: 1=storage, 2=net, 3=engine, 4=hook
local TECH_IMG_LOCKED = {
    { 3, 4, 5, 6 },      -- 1级船4个科技（未解锁）
    { 7, 8, 9, 10 },     -- 2级船4个科技（未解锁）
    { 11, 12, 13, 14 },  -- 3级船4个科技（未解锁）
}
local TECH_IMG_UNLOCKED = {
    { 18, 19, 20, 21 },  -- 1级船4个科技（解锁）
    { 22, 23, 24, 25 },  -- 2级船4个科技（解锁）
    { 26, 27, 28, 29 },  -- 3级船4个科技（解锁）
}
-- 船等级图标索引: [船等级] → 切片编号
local SHIP_IMG_LOCKED   = { 15, 16, 17 }   -- 1/2/3级（未解锁）
local SHIP_IMG_UNLOCKED = { 30, 31, 32 }   -- 1/2/3级（解锁）

-- 加载图片辅助
local function loadImg(vg, idx)
    if imgs_[idx] then return imgs_[idx] end
    local path = "ui/ship_class/切片" .. idx .. ".png"
    local handle = nvgCreateImage(vg, path, 0)
    imgs_[idx] = handle
    return handle
end

-- 绘制贴图到指定区域（居中适配）
local function drawImg(vg, imgHandle, cx, cy, drawW, drawH)
    if not imgHandle or imgHandle == 0 then return end
    local x = cx - drawW * 0.5
    local y = cy - drawH * 0.5
    local paint = nvgImagePattern(vg, x, y, drawW, drawH, 0, imgHandle, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, drawW, drawH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- 弹性缓动函数（弹出后回弹）
local function bounceEase(t)
    -- 0→1: 快速放大到BOUNCE_SCALE，然后弹回1.0
    if t < 0.4 then
        -- 放大阶段
        return 1.0 + (BOUNCE_SCALE - 1.0) * (t / 0.4)
    else
        -- 缩回阶段
        local p = (t - 0.4) / 0.6
        return BOUNCE_SCALE + (1.0 - BOUNCE_SCALE) * p * p * (3 - 2 * p)
    end
end

-- 获取某个节点当前的弹性缩放比
local function getBounceScale(id)
    local anim = bounceAnims_[id]
    if not anim then return 1.0 end
    if anim.t >= BOUNCE_DURATION then
        bounceAnims_[id] = nil
        return 1.0
    end
    return bounceEase(anim.t / BOUNCE_DURATION)
end

-- 触发某个节点的弹性动画
local function triggerBounce(id)
    bounceAnims_[id] = { t = 0 }
end

-- ── 接口 ────────────────────────────────────────────────────────────────────
function BoatUpgrade.Init(vg)
    -- Init 不再加载贴图，改为 Open 时统一加载
end

function BoatUpgrade.Open()
    open_ = true
    _hits = {}
    bounceAnims_ = {}
    -- 如果已经加载过，直接显示；否则标记需要加载
    if not loaded_ then
        loadingRequested_ = true
    end
end

function BoatUpgrade.Close()
    open_ = false
    _hits = {}
    bounceAnims_ = {}
end

function BoatUpgrade.IsOpen()
    return open_
end

-- 每帧更新弹性动画
function BoatUpgrade.Update(dt)
    if not open_ then return end
    for id, anim in pairs(bounceAnims_) do
        anim.t = anim.t + dt
        if anim.t >= BOUNCE_DURATION then
            bounceAnims_[id] = nil
        end
    end
end

-- ── 绘制 ────────────────────────────────────────────────────────────────────
function BoatUpgrade.Draw(vg, sw, sh, ctx)
    if not open_ then return end
    _hits = {}

    local S = sh / 1080

    -- 加载贴图（首次打开时统一加载）
    if loadingRequested_ and not loaded_ then
        -- 显示加载界面
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, sw, sh)
        nvgFillColor(vg, rgba(0, 0, 0, 180))
        nvgFill(vg)

        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 36 * S)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, rgba(240, 235, 220, 255))
        nvgText(vg, sw * 0.5, sh * 0.5, "加载中...", nil)

        -- 在这一帧内执行所有图片加载
        for i = 1, 32 do
            loadImg(vg, i)
        end
        loaded_ = true
        loadingRequested_ = false
        return  -- 下一帧再绘制完整界面
    end

    if not loaded_ then return end

    local PlayerData = ctx.PlayerData
    local boatLevel = PlayerData.data.boatLevel or 0
    local boatTechs = PlayerData.data.boatTechs or {}

    -- 面板尺寸
    local PANEL_W = 1400 * S
    local PANEL_H = 750 * S
    local PANEL_X = (sw - PANEL_W) * 0.5
    local PANEL_Y = (sh - PANEL_H) * 0.5 + 20 * S
    local CORNER  = 24 * S

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, rgba(0, 0, 0, 120))
    nvgFill(vg)

    -- 面板背景（贴图）
    local bgImg = loadImg(vg, 2)
    drawImg(vg, bgImg, PANEL_X + PANEL_W * 0.5, PANEL_Y + PANEL_H * 0.5, PANEL_W, PANEL_H)

    local TITLE_H = 60 * S

    -- ── 科技树布局 ──────────────────────────────────────────────────────────
    -- 3列，每列=左侧船等级节点 + 右侧4个分支节点（上下排列）
    local CONTENT_Y = PANEL_Y + TITLE_H + 30 * S
    local CONTENT_H = PANEL_H - TITLE_H - 50 * S
    local COL_W = PANEL_W / 3
    local NODE_SIZE = 107 * S   -- 科技节点贴图宽度（用于连线终点计算）
    local SHIP_SIZE = 147 * S   -- 船等级节点贴图宽度
    local SHIP_OFFSET = -110 * S -- 船节点向左偏移（贴图更宽，加大偏移）
    local BRANCH_OFFSET = 80 * S -- 分支节点向右偏移

    -- 第0轮：先画所有等级间的水平连线（底层，不被船节点遮挡）
    local shipCY = CONTENT_Y + CONTENT_H * 0.5
    for lvl = 1, 2 do
        local colCX = PANEL_X + COL_W * (lvl - 0.5)
        local shipCX = colCX + SHIP_OFFSET
        local nextShipCX = PANEL_X + COL_W * (lvl + 0.5) + SHIP_OFFSET
        local shipUnlocked = boatLevel >= lvl
        nvgBeginPath(vg)
        nvgMoveTo(vg, shipCX + SHIP_SIZE * 0.5, shipCY)
        nvgLineTo(vg, nextShipCX - SHIP_SIZE * 0.5, shipCY)
        if shipUnlocked then
            nvgStrokeColor(vg, rgba(244, 238, 225, 255))
        else
            nvgStrokeColor(vg, rgba(117, 121, 124, 255))
        end
        nvgStrokeWidth(vg, 10 * S)
        nvgStroke(vg)
    end

    for lvl = 1, 3 do
        local colCX = PANEL_X + COL_W * (lvl - 0.5)  -- 列中心X
        local shipCX = colCX + SHIP_OFFSET            -- 船节点X（偏左）
        local branchCX = colCX + BRANCH_OFFSET        -- 分支节点X（偏右）

        -- 船等级节点
        local shipUnlocked = boatLevel >= lvl
        local shipCanBuy = (not shipUnlocked) and (boatLevel >= lvl - 1) and PlayerData.CanAfford(LEVEL_COSTS[lvl])
        local shipNext = (not shipUnlocked) and (boatLevel >= lvl - 1)

        -- 分支节点（4个垂直排列在右侧）
        local branchSpacing = (CONTENT_H - 40*S) / 5  -- 均匀分布

        -- 计算分支位置和状态
        local branchData = {}
        for bi, branch in ipairs(BRANCHES) do
            local bCX = branchCX
            local bCY = CONTENT_Y + 20*S + branchSpacing * (bi)
            local techKey = lvl .. "_" .. branch.key
            local techUnlocked = boatTechs[techKey] == true
            local techCanBuy = (not techUnlocked) and shipUnlocked and PlayerData.CanAfford(BRANCH_COSTS[lvl])
            local techNext = (not techUnlocked) and shipUnlocked
            branchData[bi] = { bCX = bCX, bCY = bCY, techKey = techKey, techUnlocked = techUnlocked, techCanBuy = techCanBuy, techNext = techNext }
        end

        -- 连接线绘制：先画主干（垂直线），再画各分支水平线
        -- 主干：从船节点右侧伸出的垂直线段
        local trunkX = shipCX + SHIP_SIZE * 0.5 + 14*S
        local topBranchY = branchData[1].bCY
        local botBranchY = branchData[4].bCY

        -- 第一轮：画所有未解锁的线（灰色底层）
        local LINE_W = 10 * S  -- 线条宽度
        local STUB_EXTRA = ({ 1*S, 2*S, 0 })[lvl]  -- 每级微调消除缝隙
        -- 水平连接：用填充矩形代替描边线（消除抗锯齿间隙）
        nvgBeginPath(vg)
        nvgRect(vg, shipCX, shipCY - LINE_W * 0.5, trunkX - shipCX + LINE_W * 0.5 + STUB_EXTRA, LINE_W)
        nvgFillColor(vg, rgba(117, 121, 124, 255))
        nvgFill(vg)
        -- 主干垂直线（灰色底）
        nvgBeginPath(vg)
        nvgMoveTo(vg, trunkX, topBranchY)
        nvgLineTo(vg, trunkX, botBranchY)
        nvgStrokeColor(vg, rgba(117, 121, 124, 255))
        nvgStrokeWidth(vg, LINE_W)
        nvgStroke(vg)

        -- 各分支水平线（灰色底）
        for bi = 1, 4 do
            local bd = branchData[bi]
            nvgBeginPath(vg)
            nvgMoveTo(vg, trunkX - 5*S, bd.bCY)
            nvgLineTo(vg, bd.bCX - NODE_SIZE * 0.5 - 2*S, bd.bCY)
            nvgStrokeColor(vg, rgba(117, 121, 124, 255))
            nvgStrokeWidth(vg, 10 * S)
            nvgStroke(vg)
        end

        -- 第二轮：覆盖已解锁的线（亮色顶层）
        if shipUnlocked then
            -- 水平连接用填充矩形覆盖（亮色）
            nvgBeginPath(vg)
            nvgRect(vg, shipCX, shipCY - LINE_W * 0.5, trunkX - shipCX + LINE_W * 0.5 + STUB_EXTRA, LINE_W)
            nvgFillColor(vg, rgba(244, 238, 225, 255))
            nvgFill(vg)
            -- 主干垂直线亮色覆盖
            nvgBeginPath(vg)
            -- 找到已解锁分支的最高和最低位置来决定主干亮色范围
            local hasUnlockedAbove, hasUnlockedBelow = false, false
            for bi = 1, 4 do
                if branchData[bi].techUnlocked then
                    if branchData[bi].bCY < shipCY then hasUnlockedAbove = true end
                    if branchData[bi].bCY > shipCY then hasUnlockedBelow = true end
                end
            end
            if hasUnlockedAbove then
                -- 找最上面的已解锁分支
                for bi = 1, 4 do
                    if branchData[bi].techUnlocked and branchData[bi].bCY < shipCY then
                        nvgMoveTo(vg, trunkX, shipCY)
                        nvgLineTo(vg, trunkX, branchData[bi].bCY)
                        break
                    end
                end
            end
            if hasUnlockedBelow then
                -- 找最下面的已解锁分支
                for bi = 4, 1, -1 do
                    if branchData[bi].techUnlocked and branchData[bi].bCY > shipCY then
                        nvgMoveTo(vg, trunkX, shipCY)
                        nvgLineTo(vg, trunkX, branchData[bi].bCY)
                        break
                    end
                end
            end
            nvgStrokeColor(vg, rgba(244, 238, 225, 255))
            nvgStrokeWidth(vg, 10 * S)
            nvgStroke(vg)

            -- 各已解锁分支水平线用亮色
            for bi = 1, 4 do
                local bd = branchData[bi]
                if bd.techUnlocked then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, trunkX - 5*S, bd.bCY)
                    nvgLineTo(vg, bd.bCX - NODE_SIZE * 0.5 - 2*S, bd.bCY)
                    nvgStrokeColor(vg, rgba(244, 238, 225, 255))
                    nvgStrokeWidth(vg, 10 * S)
                    nvgStroke(vg)
                end
            end
        end

        for bi, branch in ipairs(BRANCHES) do
            local bd = branchData[bi]
            local bCX = bd.bCX
            local bCY = bd.bCY
            local techKey = bd.techKey
            local techUnlocked = bd.techUnlocked
            local techCanBuy = bd.techCanBuy
            local techNext = bd.techNext

            -- 分支科技贴图（根据解锁状态选择对应切片）
            local techImgIdx
            if techUnlocked then
                techImgIdx = TECH_IMG_UNLOCKED[lvl][bi]
            else
                techImgIdx = TECH_IMG_LOCKED[lvl][bi]
            end
            local techImg = loadImg(vg, techImgIdx)
            -- 科技图标原始尺寸约107x60（1080p），按S缩放，应用弹性动画
            local techDrawW = 107 * S
            local techDrawH = 60 * S
            local techBounce = getBounceScale("tech_" .. techKey)
            drawImg(vg, techImg, bCX, bCY, techDrawW * techBounce, techDrawH * techBounce)

            -- 费用标签（未解锁且可解锁时）
            if techNext and not techUnlocked then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 14 * S)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                local costColor = techCanBuy and rgba(120, 220, 80, 200) or rgba(180, 80, 80, 200)
                nvgFillColor(vg, costColor)
                nvgText(vg, bCX, bCY + techDrawH * 0.5 + 4*S, BRANCH_COSTS[lvl].."G", nil)
            end

            -- 点击区域
            addHit("tech_"..techKey, bCX - techDrawW*0.5, bCY - techDrawH*0.5, techDrawW, techDrawH)
        end

        -- 绘制船等级节点（贴图，在分支连接线之上，应用弹性动画）
        local shipImgIdx = shipUnlocked and SHIP_IMG_UNLOCKED[lvl] or SHIP_IMG_LOCKED[lvl]
        local shipImg = loadImg(vg, shipImgIdx)
        -- 船等级图标原始尺寸约147x85（1080p），按S缩放
        local shipDrawW = 147 * S
        local shipDrawH = 85 * S
        local shipBounce = getBounceScale("ship_" .. lvl)
        drawImg(vg, shipImg, shipCX, shipCY, shipDrawW * shipBounce, shipDrawH * shipBounce)

        -- 费用标签（未解锁时显示）
        if not shipUnlocked and shipNext then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16 * S)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local costColor = shipCanBuy and rgba(120, 220, 80, 230) or rgba(220, 80, 80, 230)
            nvgFillColor(vg, costColor)
            nvgText(vg, shipCX, shipCY + shipDrawH * 0.5 + 4*S, LEVEL_COSTS[lvl].." G", nil)
        end

        -- 船点击区域
        addHit("ship_"..lvl, shipCX - shipDrawW*0.5, shipCY - shipDrawH*0.5, shipDrawW, shipDrawH + 30*S)
    end

    -- ── 返回按钮（贴图）────────────────────────────────────────────────────────
    local backImg = loadImg(vg, 1)
    -- 返回按钮原始尺寸105x90（1080p），按S缩放
    local backW = 105 * S
    local backH = 90 * S
    local backCX = PANEL_X + PANEL_W - backW * 0.5 - 16 * S
    local backCY = PANEL_Y + backH * 0.5 + 12 * S
    drawImg(vg, backImg, backCX, backCY, backW, backH)

    addHit("close", backCX - backW*0.5, backCY - backH*0.5, backW, backH)

    -- ── 底部金币显示 ────────────────────────────────────────────────────────
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 24 * S)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, rgba(255, 210, 60, 230))
    local money = PlayerData.GetMoney()
    nvgText(vg, PANEL_X + 30*S, PANEL_Y + PANEL_H - 16*S, "金币: "..money, nil)
end

-- ── 点击处理 ────────────────────────────────────────────────────────────────
function BoatUpgrade.HandleMouseClick(mx, my, ctx)
    if not open_ then return false, nil end

    local id = hitTest(mx, my)
    if not id then return true, nil end  -- 消耗点击，不穿透

    local PlayerData = ctx.PlayerData

    if id == "close" then
        triggerBounce("close")
        return true, { close = true }
    end

    -- 触发弹性点击动画
    triggerBounce(id)

    -- 船等级解锁
    local shipLvl = id:match("^ship_(%d+)$")
    if shipLvl then
        shipLvl = tonumber(shipLvl)
        local curLevel = PlayerData.data.boatLevel or 0
        if curLevel >= shipLvl then
            -- 已解锁
            return true, { message = "等级 "..shipLvl.." 已解锁" }
        end
        if curLevel < shipLvl - 1 then
            -- 需要先解锁前一级
            return true, { message = "需要先解锁等级 "..(shipLvl-1) }
        end
        local cost = LEVEL_COSTS[shipLvl]
        if not PlayerData.CanAfford(cost) then
            return true, { message = "金币不足 (需要 "..cost..")" }
        end
        PlayerData.SpendMoney(cost)
        PlayerData.data.boatLevel = shipLvl
        return true, { message = "船只升级到等级 "..shipLvl.."!" }
    end

    -- 分支科技解锁
    local techKey = id:match("^tech_(.+)$")
    if techKey then
        local lvlStr, branchKey = techKey:match("^(%d+)_(.+)$")
        local lvl = tonumber(lvlStr)
        if not lvl then return true, nil end

        local boatTechs = PlayerData.data.boatTechs or {}
        if boatTechs[techKey] then
            return true, { message = "科技已解锁" }
        end

        local curLevel = PlayerData.data.boatLevel or 0
        if curLevel < lvl then
            return true, { message = "需要先解锁船只等级 "..lvl }
        end

        local cost = BRANCH_COSTS[lvl]
        if not PlayerData.CanAfford(cost) then
            return true, { message = "金币不足 (需要 "..cost..")" }
        end

        PlayerData.SpendMoney(cost)
        PlayerData.data.boatTechs[techKey] = true
        return true, { message = "科技解锁成功!" }
    end

    return true, nil
end

-- ── 按键处理 ────────────────────────────────────────────────────────────────
function BoatUpgrade.HandleKey(key)
    if key == KEY_ESCAPE then
        return true, { close = true }
    end
    return true, nil
end

return BoatUpgrade
