-- ============================================================================
-- QuestPanel: 任务委托面板 UI（2 行 × 3 列卡片布局）
-- ============================================================================
-- 参考图：卡片式布局，顶部标题，鱼图标，数量，奖励，提交按钮。
-- ctx 字段：quests, caughtList, QuestSystem, fishSheet, islandName
-- ============================================================================

local RodShop = require "RodShop"

local QuestPanel = {}

-- ── 内部状态 ────────────────────────────────────────────────────────────────
local cursor = 1          -- 当前选中卡片 (1~6)
local _hitboxes = {}      -- 每帧 Draw 时填充：{ {type,idx,x,y,w,h}, ... }

-- 按钮点击缩放动画（帧驱动）
local btnPressIdx_   = 0       -- 当前按下的卡片索引（0=无）
local btnAnimFrame_  = 0       -- 当前动画已播放帧数
local BTN_ANIM_FRAMES = 15    -- 动画总帧数（~0.25秒@60fps）

-- ── 直接售卖系统 ─────────────────────────────────────────────────────────────
local SELL_MAX = 6                -- 售卖区最多显示6条鱼（2列×3行）
local sellQueue_ = {}             -- { {fish=, price=, canReturn=true/false}, ... }
local bagCursors_ = {}            -- 多选集合 { [idx]=true, ... }

-- ── 鱼类精灵图映射（与 Inventory.lua 保持一致）──────────────────────────────
-- sheet=1: fish_01.png,   512×96,  每格 32×32
-- sheet=2: fish_02ui.png, 128×128, 每格 32×32
-- sheet=3: fish_03ui.png, 160×32,  每格 32×32 (5列×1行)
-- sheet=4: fish_04ui.png, 128×96,  每格 32×32 (4列×3行)
local FISH_SPRITE_MAP = {}
do
    local layout1 = {
        { 56, 58, 32, 30, 29, 37, 61, 59, 51, 45, 25, 43, 19, 65, 57, 49 },
        { 26, 31, 39, 52, 41, 48, 42, 63, 62, 47, 33, 55, 64, 53, 36, 50 },
        { 40, 54, 22, 44, 60 },
    }
    for row = 1, #layout1 do
        for col = 1, #layout1[row] do
            FISH_SPRITE_MAP[layout1[row][col]] = { col = col-1, row = row-1, sheet = 1 }
        end
    end
    local layout2 = {
        {  3, 27,  9,  8 },
        {  5, 17, 23, 28 },
        { 35, 66, 38, 67 },
        { 46, 20 },
    }
    for row = 1, #layout2 do
        for col = 1, #layout2[row] do
            FISH_SPRITE_MAP[layout2[row][col]] = { col = col-1, row = row-1, sheet = 2 }
        end
    end
    local layout3 = {
        { 10, 1, 4, 7, 2 },
    }
    for row = 1, #layout3 do
        for col = 1, #layout3[row] do
            FISH_SPRITE_MAP[layout3[row][col]] = { col = col-1, row = row-1, sheet = 3 }
        end
    end
    local layout4 = {
        { 21, 13, 11, 34 },
        { 12, 14,  6, 16 },
        { 18, 15, 24 },
    }
    for row = 1, #layout4 do
        for col = 1, #layout4[row] do
            FISH_SPRITE_MAP[layout4[row][col]] = { col = col-1, row = row-1, sheet = 4 }
        end
    end
end

local SHEET_INFO = {
    [1] = { w = 512, h =  96 },   -- fish_01.png
    [2] = { w = 128, h = 128 },   -- fish_02ui.png
    [3] = { w = 160, h =  32 },   -- fish_03ui.png
    [4] = { w = 128, h =  96 },   -- fish_04ui.png
}

-- ── 配色（与 FishAtlas 图册统一的暗色调）─────────────────────────────────
local C_OVERLAY    = {   0,   0,   0, 160 }
local C_PANEL_BG   = {  25,  25,  35, 255 }  -- #191923 面板主背景
local C_PANEL_BDR  = {  37,  38,  44, 255 }  -- #25262c 面板边框
local C_HEADER_BG  = {  37,  38,  44, 255 }  -- #25262c 标题栏背景
local C_CARD_BG    = {  12,  11,  16, 255 }  -- #0c0b10 卡片背景
local C_CARD_BDR   = {  37,  38,  44, 220 }  -- #25262c 卡片边框
local C_CARD_SEL   = { 110, 160, 255, 255 }  -- 选中高亮蓝
local C_CARD_DONE  = {   0,   0,   0, 100 }  -- 已完成蒙层
local C_TITLE_BG   = {  30,  32,  42, 255 }  -- 卡片标题栏背景（略亮）
local C_TITLE_TEXT = { 210, 215, 230, 255 }  -- 卡片标题文字（浅灰白）
local C_QTY_OK     = {  80, 210, 120, 255 }  -- 数量充足（绿）
local C_QTY_NO     = { 230,  90,  75, 255 }  -- 数量不足（红）
local C_QTY_DONE   = { 130, 135, 150, 200 }  -- 已完成（灰）
local C_BADGE_BG   = {  20,  22,  32, 220 }  -- 奖励徽章背景
local C_BADGE_TEXT = { 255, 255, 255, 255 }  -- 奖励白色文字
local C_BTN_OK     = {  45, 160,  80, 255 }  -- 可提交（绿）
local C_BTN_NO     = {  55,  55,  70, 255 }  -- 不可提交（暗灰）
local C_BTN_DONE   = {  40,  42,  52, 180 }  -- 已完成（深灰）
local C_BTN_TEXT   = { 255, 255, 255, 255 }
local C_HINT_TEXT  = { 130, 135, 155, 200 }  -- 提示文字（冷灰）
local C_SEP        = {  37,  38,  44, 180 }  -- 分隔线

-- ── 辅助 ────────────────────────────────────────────────────────────────────
local function rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4])
end

-- 加粗描边文字（与 Inventory 同风格）
local function DrawLabel(vg, x, y, text, size, align, r, g, b, a)
    r, g, b, a = r or 255, g or 255, b or 255, a or 255
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    local offs = { {-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1} }
    for _, d in ipairs(offs) do
        nvgText(vg, x + d[1], y + d[2], text, nil)
    end
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgText(vg, x, y, text, nil)
end

-- 绘制鱼精灵图（带 scissor 裁剪，支持 sheet1/sheet2 双图集）
local function DrawFishSprite(vg, x, y, w, h, fishId, imgSheet1, imgSheet2, imgSheet3, imgSheet4)
    local cell    = FISH_SPRITE_MAP[fishId]
    local sheets  = { imgSheet1, imgSheet2, imgSheet3, imgSheet4 }
    local imgSheet = cell and sheets[cell.sheet]
    if not cell or not imgSheet or imgSheet <= 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, x + w / 2, y + h / 2, math.min(w, h) * 0.4)
        nvgFillColor(vg, nvgRGBA(100, 160, 220, 200))
        nvgFill(vg)
        return
    end
    local si     = SHEET_INFO[cell.sheet]
    local cellPx = 32.0  -- 两张 sheet 均为 32×32/格
    local scaleX = w / cellPx
    local scaleY = h / cellPx
    local ox  = x - cell.col * cellPx * scaleX
    local oy  = y - cell.row * cellPx * scaleY
    local pat = nvgImagePattern(vg, ox, oy, si.w * scaleX, si.h * scaleY, 0, imgSheet, 1.0)
    nvgSave(vg)
    nvgScissor(vg, x, y, w, h)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, pat)
    nvgFill(vg)
    nvgResetScissor(vg)
    nvgRestore(vg)
end

-- ── 按键处理 ────────────────────────────────────────────────────────────────
--- @return boolean, table|nil
function QuestPanel.HandleKey(key, ctx)
    -- 关闭
    if key == KEY_ESCAPE or key == KEY_Q or key == KEY_E then
        return false, { close = true }
    end

    -- 光标移动（3列布局）
    if key == KEY_LEFT then
        cursor = cursor > 1 and (cursor - 1) or 6
        return true, nil
    elseif key == KEY_RIGHT then
        cursor = cursor < 6 and (cursor + 1) or 1
        return true, nil
    elseif key == KEY_UP then
        cursor = cursor > 3 and (cursor - 3) or (cursor + 3)
        return true, nil
    elseif key == KEY_DOWN then
        cursor = cursor <= 3 and (cursor + 3) or (cursor - 3)
        return true, nil
    end

    -- 提交
    if key == KEY_RETURN or key == KEY_KP_ENTER then
        local quest = ctx.quests and ctx.quests[cursor]
        if not quest then return true, nil end

        local ok, income, msg = ctx.QuestSystem.TrySubmit(
            quest, ctx.caughtList, ctx.PlayerData)

        return true, { submitted = ok, income = income, message = msg }
    end

    return true, nil
end

function QuestPanel.Reset()
    cursor = 1
    bagCursors_ = {}
    sellQueue_ = {}
end

--- 获取当前背包选中集合（供 RodShop.DrawBagOnly 高亮用）
function QuestPanel.GetBagCursor()
    return bagCursors_
end

--- 鼠标点击处理（由 main.lua HandleMouseButtonDown 调用）
--- 逻辑：单击未选中卡片 → 选中；单击已选中卡片 → 尝试提交；单击关闭区域 → 关闭
--- @return boolean consumed, table|nil result
function QuestPanel.HandleMouseClick(mx, my, ctx)
    -- 反向变换鼠标坐标以匹配缩放后的 hitbox
    local sh = graphics:GetHeight()
    local S  = sh / 1080
    local pw = 1018.1 * S
    local ph = 693.4 * S
    local px = 127.2 * S
    local py = 211.2 * S
    local dpr = graphics:GetDPR()
    local isMob = (dpr >= 2.0) or (sh < 800)
    local pScale = isMob and 1.20 or 1.0
    if isMob then py = (sh - ph) / 2 end  -- 手机端垂直居中
    local lmx, lmy = mx, my
    if pScale ~= 1.0 then
        local cx = px + pw * 0.5
        local cy = py + ph * 0.5
        lmx = (mx - cx) / pScale + cx
        lmy = (my - cy) / pScale + cy
    end

    -- 背包格子 hitbox（屏幕空间，用原始 mx,my）— 多选 toggle
    for _, bh in ipairs(RodShop.bagSlotHits) do
        if mx >= bh.x and mx <= bh.x + bh.w and my >= bh.y and my <= bh.y + bh.h then
            local idx = bh.fishIdx
            if bagCursors_[idx] then
                bagCursors_[idx] = nil
            else
                bagCursors_[idx] = true
            end
            return true, nil
        end
    end

    for _, hb in ipairs(_hitboxes) do
        if lmx >= hb.x and lmx <= hb.x + hb.w and lmy >= hb.y and lmy <= hb.y + hb.h then
            if hb.type == "close" then
                return true, { close = true }
            elseif hb.type == "card" then
                local idx = hb.idx
                if cursor == idx then
                    -- 已选中 → 尝试提交
                    local quest = ctx.quests and ctx.quests[idx]
                    if not quest then return true, nil end
                    if quest.completed then return true, nil end  -- 已完成，忽略点击
                    -- 触发按钮动画
                    btnPressIdx_  = idx
                    btnAnimFrame_ = 0
                    local ok, income, msg = ctx.QuestSystem.TrySubmit(
                        quest, ctx.caughtList, ctx.PlayerData)
                    return true, { submitted = ok, income = income, message = msg }
                else
                    -- 未选中 → 选中
                    cursor = idx
                    return true, nil
                end
            elseif hb.type == "bagSlot" then
                -- 点击背包格子 → 多选 toggle
                local idx = hb.idx
                if bagCursors_[idx] then
                    bagCursors_[idx] = nil
                else
                    bagCursors_[idx] = true
                end
                return true, nil
            elseif hb.type == "sellBtn" then
                -- 点击售卖按钮 → 将所有选中鱼转入售卖区
                local list = ctx.caughtList
                -- 收集有效选中索引，从大到小排序以安全删除
                local selected = {}
                for idx in pairs(bagCursors_) do
                    if idx >= 1 and idx <= #list and list[idx] then
                        selected[#selected + 1] = idx
                    end
                end
                if #selected == 0 then return true, nil end
                table.sort(selected, function(a, b) return a > b end)
                local totalPrice = 0
                local soldCount = 0
                local lastName = ""
                for _, si in ipairs(selected) do
                    local fish = list[si]
                    local price = ctx.QuestSystem.CalcSellPrice
                        and ctx.QuestSystem.CalcSellPrice(fish)
                        or math.max(1, math.floor(fish.weight * (fish.type.diff or 1) * 8 + 0.5))
                    -- 加入售卖队列
                    if #sellQueue_ >= SELL_MAX then
                        table.remove(sellQueue_, 1)
                    end
                    sellQueue_[#sellQueue_ + 1] = { fish = fish, price = price, canReturn = true }
                    table.remove(list, si)
                    ctx.PlayerData.AddMoney(price)
                    totalPrice = totalPrice + price
                    soldCount = soldCount + 1
                    lastName = fish.type.name
                end
                bagCursors_ = {}
                local fishName = soldCount == 1 and lastName or (soldCount .. "条鱼")
                return true, { sold = true, price = totalPrice, fishName = fishName }
            elseif hb.type == "sellSlot" then
                -- 点击售卖区鱼 → 退回到背包
                local idx = hb.idx
                local entry = sellQueue_[idx]
                if not entry then return true, nil end
                if not entry.canReturn then return true, nil end  -- 已被清除，不可退回
                -- 扣除金币
                if not ctx.PlayerData.SpendMoney(entry.price) then
                    return true, { refundFail = true }  -- 余额不足
                end
                -- 鱼放回背包
                local list = ctx.caughtList
                list[#list + 1] = entry.fish
                table.remove(sellQueue_, idx)
                return true, { returned = true, fishName = entry.fish.type.name }
            end
        end
    end
    -- 点在面板外 → 不消耗（允许关闭等其他逻辑）
    return false, nil
end

-- ── 单张卡片绘制 ─────────────────────────────────────────────────────────────
local function DrawCard(vg, cx, cy, cw, ch, quest, isSelected, holdCount, imgSheet1, imgSheet2, imgSheet3, imgSheet4, cardR, cardIdx)
    local r = cardR or 8

    -- 选中时整体放大 5%（从中心扩大）
    if isSelected then
        local scale = 1.05
        local dw = cw * (scale - 1)
        local dh = ch * (scale - 1)
        cx = cx - dw / 2
        cy = cy - dh / 2
        cw = cw + dw
        ch = ch + dh
        r  = math.floor(r * scale)
    end

    -- 卡片底色（从下 #95ABFA 渐变到上 #735AFF）
    local bgPaint = nvgLinearGradient(vg, cx, cy + ch, cx, cy,
        nvgRGBA(0x95, 0xAB, 0xFA, 255), nvgRGBA(0x73, 0x5A, 0xFF, 255))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx, cy, cw, ch, r)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- ── 标题栏（142.2×41.6，上直下圆，#95806E）────────────────────────────
    local S_ = ch / 264.8  -- 卡片内部缩放因子
    local titleW = math.floor(142.2 * S_)
    local titleH = math.floor(41.6 * S_)
    local titleR = math.floor(41.6 * 0.30 * S_)  -- 30% 圆角（按短边）
    local titleX = cx + math.floor((cw - titleW) / 2)  -- 水平居中
    nvgBeginPath(vg)
    nvgRoundedRectVarying(vg, titleX, cy, titleW, titleH, 0, 0, titleR, titleR)
    nvgFillColor(vg, nvgRGBA(0x95, 0x80, 0x6E, 255))
    nvgFill(vg)

    local fishName = quest.fishType.name
    local titleStr = fishName

    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 24 * S_)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_TITLE_TEXT))
    nvgText(vg, cx + cw / 2, cy + titleH / 2, titleStr, nil)

    -- ── 鱼图标（居中，等比缩放）─────────────────────────────────────────────
    local iconAreaH = math.floor(108 * S_)
    local sprSize   = math.floor(96 * S_)
    local iconCX    = cx + cw / 2
    local iconCY    = cy + titleH + iconAreaH / 2
    local sprX = math.floor(iconCX - sprSize / 2)
    local sprY = math.floor(iconCY - sprSize / 2)

    DrawFishSprite(vg, sprX, sprY, sprSize, sprSize, quest.fishType.id, imgSheet1, imgSheet2, imgSheet3, imgSheet4)

    -- ── 数量文字 "(have/need)" ───────────────────────────────────────────────
    local qtyY = cy + titleH + iconAreaH + math.floor(2 * S_)
    local canSubmit = (not quest.completed) and (holdCount >= quest.required)
    local qtyC = quest.completed and C_QTY_DONE
                   or (canSubmit and C_CARD_SEL or { 255, 255, 255, 230 })
    local qtyStr = quest.completed
        and "✓ 已完成"
        or string.format("(%d / %d)", holdCount, quest.required)

    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 17 * S_)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(qtyC))
    nvgText(vg, cx + cw / 2, qtyY + math.floor(8 * S_), qtyStr, nil)

    -- ── 奖励（金币图标 + 数字）─────────────────────────────────────────────
    local badgeY = qtyY + math.floor(22 * S_)
    local badgeCY = badgeY + math.floor(8 * S_)
    local rewardStr = tostring(quest.reward)
    local coinH = 17 * S_
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 17 * S_)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textW = nvgTextBounds(vg, 0, 0, rewardStr)
    local coinW = coinH * (59 / 56)  -- W[3]/H[3] 比例
    local gap = 4 * S_
    local totalW = coinW + gap + textW
    local startX = cx + cw / 2 - totalW / 2
    RodShop.DrawCoinIcon(vg, startX, badgeCY - coinH / 2, coinH)
    nvgFillColor(vg, rgba(C_BADGE_TEXT))
    nvgText(vg, startX + coinW + gap, badgeCY, rewardStr, nil)

    -- ── 提交按钮 ────────────────────────────────────────────────────────────
    local btnH  = math.floor(34 * S_)
    local btnPad = math.floor(8 * S_)
    local btnX  = cx + btnPad
    local btnY  = cy + ch - btnH - btnPad
    local btnW  = cw - btnPad * 2
    local btnR  = math.floor(6 * S_)
    local btnC  = { 0x25, 0x28, 0x29, 255 }  -- #252829

    -- 按钮点击缩放动画（帧驱动）
    local btnScale = 1.0
    if cardIdx and btnPressIdx_ == cardIdx then
        btnAnimFrame_ = btnAnimFrame_ + 1
        if btnAnimFrame_ >= BTN_ANIM_FRAMES then
            btnPressIdx_ = 0  -- 动画结束
            btnScale = 1.0
        else
            local t = btnAnimFrame_ / BTN_ANIM_FRAMES  -- 0~1
            -- 弹性回弹：先缩小到 0.80，再弹回并有轻微过冲
            local ease = 1.0 - (1.0 - t) * (1.0 - t)  -- easeOutQuad
            local overshoot = 1.0 + 0.12 * math.sin(ease * math.pi)
            btnScale = 0.80 + (overshoot - 0.80) * ease
        end
    end

    nvgSave(vg)
    if btnScale ~= 1.0 then
        local bcx = btnX + btnW / 2
        local bcy = btnY + btnH / 2
        nvgTranslate(vg, bcx, bcy)
        nvgScale(vg, btnScale, btnScale)
        nvgTranslate(vg, -bcx, -bcy)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, btnR)
    nvgFillColor(vg, rgba(btnC))
    nvgFill(vg)

    -- 按钮上高光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, btnX + btnPad, btnY + math.floor(3 * S_))
    nvgLineTo(vg, btnX + btnW - btnPad, btnY + math.floor(3 * S_))
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local btnLabel = quest.completed and "已完成"
                       or (canSubmit and "提  交" or "提  交")
    DrawLabel(vg, btnX + btnW / 2, btnY + btnH / 2, btnLabel, 24 * S_,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        C_BTN_TEXT[1], C_BTN_TEXT[2], C_BTN_TEXT[3])

    nvgRestore(vg)

    -- ── 已完成遮罩（覆盖整张卡片，动画期间延迟显示）──────────────────────────
    local animPlaying = (cardIdx and btnPressIdx_ == cardIdx)
    if quest.completed and not animPlaying then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cy, cw, ch, r)
        nvgFillColor(vg, rgba(C_CARD_DONE))
        nvgFill(vg)
    end
end

-- ── 主绘制 ──────────────────────────────────────────────────────────────────
function QuestPanel.Draw(vg, sw, sh, ctx)
    local quests    = ctx.quests
    local QS        = ctx.QuestSystem
    local imgSheet  = ctx.fishSheet
    local imgSheet2 = ctx.fishSheet2
    local imgSheet3 = ctx.fishSheet3
    local imgSheet4 = ctx.fishSheet4
    local islandName = ctx.islandName or "未知岛屿"
    _hitboxes = {}   -- 每帧重置

    -- 面板尺寸（1080p 设计坐标）
    local S  = sh / 1080
    local pw = math.floor(1018.1 * S)
    local ph = math.floor(693.4 * S)
    local px = math.floor(127.2 * S)
    local py = math.floor(211.2 * S)
    local pr = math.floor(693.4 * 0.06 * S)  -- 圆角 6%（按短边）

    -- 手机端整体放大
    local dpr = graphics:GetDPR()
    local isMobile = (dpr >= 2.0) or (sh < 800)
    local PANEL_SCALE = isMobile and 1.20 or 1.0
    if isMobile then py = math.floor((sh - ph) / 2) end  -- 手机端垂直居中
    if PANEL_SCALE ~= 1.0 then
        local cx = px + pw * 0.5
        local cy = py + ph * 0.5
        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgScale(vg, PANEL_SCALE, PANEL_SCALE)
        nvgTranslate(vg, -cx, -cy)
    end



    -- 面板阴影
    local shadowBlur = math.floor(24 * S)
    local shadowOfs  = math.floor(6 * S)
    local shadowPaint = nvgBoxGradient(vg, px, py + shadowOfs, pw, ph, pr, shadowBlur,
        nvgRGBA(0, 0, 0, 90), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, px - shadowBlur, py - shadowBlur, pw + shadowBlur * 2, ph + shadowBlur * 2 + shadowOfs)
    nvgRoundedRect(vg, px, py, pw, ph, pr)
    nvgPathWinding(vg, NVG_HOLE)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, pr)
    nvgFillColor(vg, nvgRGBA(0xF2, 0xED, 0xE1, 255))
    nvgFill(vg)

    -- ── 标题栏（106px 高，#252829）───────────────────────────────────────────
    local hdrH = math.floor(106 * S)
    nvgBeginPath(vg)
    nvgRoundedRectVarying(vg, px, py, pw, hdrH, pr, pr, 0, 0)
    nvgFillColor(vg, nvgRGBA(0x25, 0x28, 0x29, 255))
    nvgFill(vg)

    -- 标题文字（46.5pt 加粗 #F2EDE1）
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 46.5 * S)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xF2, 0xED, 0xE1, 255))
    nvgText(vg, px + 30 * S, py + hdrH / 2, islandName .. "  ·  任务委托", nil)

    -- 关闭按钮（标题栏右侧）
    local closeBtnW = math.floor(100 * S)
    local closeBtnX = px + pw - closeBtnW
    _hitboxes[#_hitboxes + 1] = { type = "close", x = closeBtnX, y = py, w = closeBtnW, h = hdrH }
    nvgFontSize(vg, 24 * S)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xF2, 0xED, 0xE1, 180))
    nvgText(vg, px + pw - 20 * S, py + hdrH / 2, "✕", nil)

    -- ── 卡片区域（3列 × 2行，左上对齐）─────────────────────────────────────
    local cardW   = math.floor(222.9 * S)
    local cardH   = math.floor(264.8 * S)
    local cardGap = math.floor(14 * S)
    local cardR   = math.floor(222.9 * 0.07 * S)  -- 7% 圆角（按短边）

    -- 左上对齐：左边距 14px，顶部紧挨标题栏下方 14px
    local gridX = px + math.floor(14 * S)
    local gridY = py + hdrH + math.floor(14 * S)

    for idx = 1, 6 do
        local col = (idx - 1) % 3         -- 0,1,2
        local row = math.floor((idx - 1) / 3)  -- 0,1
        local cx  = gridX + col * (cardW + cardGap)
        local cy  = gridY + row * (cardH + cardGap)

        local quest = quests and quests[idx]
        if quest then
            local hold = QS.GetHoldCount(quest.fishTypeIdx, ctx.caughtList)
            DrawCard(vg, cx, cy, cardW, cardH, quest,
                (idx == cursor), hold, imgSheet, imgSheet2, imgSheet3, imgSheet4, cardR, idx)
            -- 记录整张卡片点击区域
            _hitboxes[#_hitboxes + 1] = { type = "card", idx = idx, x = cx, y = cy, w = cardW, h = cardH }
        end
    end

    -- ── 右侧售卖区域 ─────────────────────────────────────────────────────────
    local rightAreaX = gridX + 3 * (cardW + cardGap)
    local rightAreaW = px + pw - rightAreaX - math.floor(14 * S)

    local r1W = math.floor(279.2 * S)
    local r1H = math.floor(417.7 * S)
    local r1X = rightAreaX + math.floor((rightAreaW - r1W) / 2)
    local r1Y = gridY  -- 上边界与第一行卡片对齐
    local rr  = math.floor(8 * S)

    -- 大矩形背景（已售卖鱼区域）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, r1X, r1Y, r1W, r1H, rr)
    nvgFillColor(vg, nvgRGBA(0xC9, 0xC5, 0xBE, 255))
    nvgFill(vg)

    -- 标题
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, math.floor(16 * S))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(0x40, 0x38, 0x28, 255))
    nvgText(vg, r1X + r1W / 2, r1Y + math.floor(8 * S), "已售出", nil)

    -- 2列×3行网格绘制已售鱼类
    local sellCols = 2
    local sellRows = 3
    local sellPad  = math.floor(10 * S)
    local sellTopY = r1Y + math.floor(32 * S)  -- 标题下方
    local sellCellW = math.floor((r1W - sellPad * 3) / sellCols)
    local sellCellH = math.floor((r1H - sellTopY + r1Y - sellPad * 4) / sellRows)

    for i = 1, SELL_MAX do
        local col = (i - 1) % sellCols
        local row = math.floor((i - 1) / sellCols)
        local cellX = r1X + sellPad + col * (sellCellW + sellPad)
        local cellY = sellTopY + sellPad + row * (sellCellH + sellPad)

        -- 格子底色
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cellX, cellY, sellCellW, sellCellH, math.floor(4 * S))
        local entry = sellQueue_[i]
        if entry then
            if entry.canReturn then
                nvgFillColor(vg, nvgRGBA(0xE8, 0xE2, 0xD4, 255))
            else
                nvgFillColor(vg, nvgRGBA(0xA0, 0x9A, 0x90, 120))
            end
        else
            nvgFillColor(vg, nvgRGBA(0xB8, 0xB3, 0xA8, 100))
        end
        nvgFill(vg)

        if entry then
            -- 绘制鱼精灵
            local fishId = entry.fish.type and entry.fish.type.id
            local sprSz = math.min(sellCellW, sellCellH) * 0.6
            local sprX = cellX + (sellCellW - sprSz) / 2
            local sprY = cellY + (sellCellH - sprSz) / 2 - math.floor(6 * S)
            DrawFishSprite(vg, sprX, sprY, sprSz, sprSz, fishId, imgSheet, imgSheet2, imgSheet3, imgSheet4)

            -- 金额文字
            nvgFontFace(vg, "sans-bold")
            nvgFontSize(vg, math.floor(12 * S))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            if entry.canReturn then
                nvgFillColor(vg, nvgRGBA(0xD3, 0xA7, 0x5A, 255))
            else
                nvgFillColor(vg, nvgRGBA(0x80, 0x78, 0x68, 200))
            end
            nvgText(vg, cellX + sellCellW / 2, cellY + sellCellH - math.floor(4 * S),
                string.format("%d$", entry.price), nil)

            -- 可退回标记
            if entry.canReturn then
                _hitboxes[#_hitboxes + 1] = {
                    type = "sellSlot", idx = i,
                    x = cellX, y = cellY, w = sellCellW, h = sellCellH
                }
            end
        end
    end

    -- 小矩形：直接售卖按钮
    local r2W = math.floor(279.2 * S)
    local r2H = math.floor(76.5 * S)
    local r2X = r1X
    local r2Y = r1Y + r1H + math.floor(20 * S)

    -- 按钮颜色：有选中鱼时金色，否则灰色
    local sellBtnActive = (next(bagCursors_) ~= nil)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, r2X, r2Y, r2W, r2H, rr)
    if sellBtnActive then
        nvgFillColor(vg, nvgRGBA(0xD3, 0xA7, 0x5A, 255))
    else
        nvgFillColor(vg, nvgRGBA(0x9A, 0x94, 0x88, 255))
    end
    nvgFill(vg)

    -- 按钮文字
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, math.floor(22 * S))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0xFF, 0xFF, 0xFF, 255))
    nvgText(vg, r2X + r2W / 2, r2Y + r2H / 2, "直接售卖", nil)

    -- 注册按钮 hitbox
    _hitboxes[#_hitboxes + 1] = {
        type = "sellBtn",
        x = r2X, y = r2Y, w = r2W, h = r2H
    }

    -- ── 底部操作提示 ─────────────────────────────────────────────────────────
    local hintY = py + ph - math.floor(26 * S)
    local hintCenterX = px + pw / 2

    -- 完成数统计
    local doneCount = 0
    if quests then
        for _, q in ipairs(quests) do
            if q.completed then doneCount = doneCount + 1 end
        end
    end

    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, math.floor(12 * S))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_HINT_TEXT))
    nvgText(vg, px + math.floor(16 * S), hintY,
        string.format("进度: %d / 6", doneCount), nil)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(C_HINT_TEXT))
    nvgText(vg, hintCenterX, hintY,
        "单击卡片选中  再次单击提交  [Q/E] 关闭", nil)

    -- 恢复手机端缩放变换
    if PANEL_SCALE ~= 1.0 then
        nvgRestore(vg)
    end
end

return QuestPanel
