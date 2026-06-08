-- ============================================================================
-- IslandMenu: 岛屿 UI 模块
-- Level 1: 功能选择对话框（黑色圆角矩形，无描边，鼠标点击）
-- ============================================================================

local IslandMenu = {}

-- ── 对话框 UI 图片 ───────────────────────────────────────────────────────────
local imgDialogBg  = -1   -- 切片3: 米白色有机大背景
local imgNameTag   = -1   -- 切片1: 金黄气泡名字框
local imgButton    = -1   -- 切片2: 黑色选项按钮

-- 原始尺寸（SVG viewBox）
local BG_W, BG_H   = 1128, 260
local TAG_W, TAG_H  = 236,  105
local BTN_W, BTN_H  = 294,   64

-- ── NPC 半身绘图片 ────────────────────────────────────────────────────────────
local imgNpcF01 = -1   -- f01 半身绘（岛屿11 巴兰）
local imgNpcF02 = -1   -- f02 半身绘（岛屿2  于勒）
local imgNpcF03 = -1   -- f03 半身绘（岛屿10 塔莎）

-- ── 岛屿 → NPC 定制配置 ──────────────────────────────────────────────────────
-- halfBody: 半身绘图片句柄引用名，imgW/imgH 为图片原始像素尺寸
local ISLAND_NPC_CONFIG = {
    [10] = { name = "塔莎", dialog = "你好 欢迎光临深流渔具店\n这里卖渔具 也卖情报.",    halfBodyRef = "f03", halfBodyW = 561, halfBodyH = 499 },
    [2]  = { name = "于勒", dialog = "珍珠贝里可能藏着珍珠\n怎么样 要不要试试手气?", halfBodyRef = "f02", halfBodyW = 561, halfBodyH = 499 },
    [11] = { name = "巴兰", dialog = "要改装你的船嘛?",                                    halfBodyRef = "f01", halfBodyW = 560, halfBodyH = 499 },
}

function IslandMenu.Init(vg)
    imgDialogBg = nvgCreateImage(vg, "image/ui/dialog_box/dialog_bg.png",  0)
    imgNameTag  = nvgCreateImage(vg, "image/ui/dialog_box/dialog_name_tag.png", 0)
    imgButton   = nvgCreateImage(vg, "image/ui/dialog_box/dialog_button.png",   0)
    if imgDialogBg <= 0 then print("[WARN] dialog_bg not loaded") end
    if imgNameTag  <= 0 then print("[WARN] dialog_name_tag not loaded") end
    if imgButton   <= 0 then print("[WARN] dialog_button not loaded") end

    -- 加载 NPC 半身绘
    imgNpcF01 = nvgCreateImage(vg, "image/npc/f01.png.png", 0)
    imgNpcF02 = nvgCreateImage(vg, "image/npc/f02.png.png", 0)
    imgNpcF03 = nvgCreateImage(vg, "image/npc/f03.png.png", 0)
    if imgNpcF01 <= 0 then print("[WARN] npc f01 not loaded") end
    if imgNpcF02 <= 0 then print("[WARN] npc f02 not loaded") end
    if imgNpcF03 <= 0 then print("[WARN] npc f03 not loaded") end
end

-- ── 获取半身绘图片句柄 ────────────────────────────────────────────────────────
local function getNpcHalfBodyImg(ref)
    if ref == "f01" then return imgNpcF01 end
    if ref == "f02" then return imgNpcF02 end
    if ref == "f03" then return imgNpcF03 end
    return -1
end




-- ── 内部状态 ────────────────────────────────────────────────────────────────
local menuItems_ = {}       -- level 1 选项列表
local _hitboxes  = {}       -- 当前帧可点击区域
local openTime_  = 0        -- Level 1 弹入动画起始时间
local inquiryMode_ = false  -- 是否在"打探消息"子对话中
local inquiryText_ = "去东南方向找巴兰 他能升级你的船 \n西北边住着老于勒 他做些贝壳生意."
local inquiryItems_ = {
    { id = "inquiry_fish", label = "打探鱼类信息" },
    { id = "inquiry_back", label = "返回" },
}

-- ── 辅助 ────────────────────────────────────────────────────────────────────
local function rgba(r,g,b,a) return nvgRGBA(r,g,b,a or 255) end

local function addHit(id, x, y, w, h)
    _hitboxes[#_hitboxes + 1] = { id=id, x=x, y=y, w=w, h=h }
end

local function hitTest(mx, my)
    for _, box in ipairs(_hitboxes) do
        if mx >= box.x and mx <= box.x + box.w and
           my >= box.y and my <= box.y + box.h then
            return box.id
        end
    end
    return nil
end

-- ── 加粗白字（黑色四方向描边）────────────────────────────────────────────────
local function BoldText(vg, x, y, text, size, align, r, g, b, a)
    r, g, b, a = r or 255, g or 255, b or 255, a or 255
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align)
    nvgFillColor(vg, rgba(0, 0, 0, 190))
    nvgText(vg, x-1, y,   text, nil)
    nvgText(vg, x+1, y,   text, nil)
    nvgText(vg, x,   y-1, text, nil)
    nvgText(vg, x,   y+1, text, nil)
    nvgFillColor(vg, rgba(r, g, b, a))
    nvgText(vg, x, y, text, nil)
end







-- ── Reset ─────────────────────────────────────────────────────────────────────
function IslandMenu.Reset(island)
    _hitboxes  = {}
    openTime_  = time:GetElapsedTime()   -- 记录弹入动画起点
    inquiryMode_ = false                 -- 重置打探消息子对话状态

    menuItems_ = {}
    -- 鱼铺：始终可用
    menuItems_[#menuItems_ + 1] = { id = "quest",     label = "鱼铺" }
    -- 商店：始终可用
    menuItems_[#menuItems_ + 1] = { id = "rod_shop",  label = "商店" }
    -- 仓库：所有岛屿可用
    menuItems_[#menuItems_ + 1] = { id = "warehouse", label = "仓库" }
    -- 升级船只：所有岛屿可用
    menuItems_[#menuItems_ + 1] = { id = "boat_upgrade", label = "升级船只" }
    -- 打探消息：始终可用
    menuItems_[#menuItems_ + 1] = { id = "inquiry",   label = "打探消息" }
end

-- ── 鼠标点击处理 ─────────────────────────────────────────────────────────────
--- @return table|nil result  { openQuest=true } / { close=true } / nil
function IslandMenu.HandleMouseClick(mx, my, ctx)
    local id = hitTest(mx, my)
    if not id then return nil end

    -- 打探消息子对话模式
    if inquiryMode_ then
        if id == "inquiry_back" then
            inquiryMode_ = false
            openTime_ = time:GetElapsedTime()  -- 重新触发弹入动画
            return nil  -- 返回主菜单，不关闭整个对话
        elseif id == "inquiry_fish" then
            return { openInquiryFish = true }
        elseif id == "close" then
            return { close = true }
        end
        return nil
    end

    -- 主菜单模式
    if id == "quest" then
        return { openQuest = true }
    elseif id == "rod_shop" then
        return { openRodShop = true }
    elseif id == "warehouse" then
        return { openWarehouse = true }
    elseif id == "boat_upgrade" then
        return { openBoatUpgrade = true }
    elseif id == "inquiry" then
        inquiryMode_ = true
        openTime_ = time:GetElapsedTime()  -- 重新触发弹入动画
        return nil  -- 留在对话中，切换内容
    elseif id == "close" then
        return { close = true }
    end
    return nil
end

-- ── 按键处理 ─────────────────────────────────────────────────────────────────
function IslandMenu.HandleKey(key, ctx)
    if key == KEY_ESCAPE then
        if inquiryMode_ then
            -- 从打探消息子对话返回主菜单
            inquiryMode_ = false
            openTime_ = time:GetElapsedTime()
            return true, nil
        end
        return true, { close = true }
    end
    if key == KEY_Q      then return true, { openQuest = true } end
    return true, nil
end





-- ============================================================================
-- 绘制
-- ============================================================================

function IslandMenu.Draw(vg, sw, sh, ctx, mx, my)
    _hitboxes = {}
    mx = mx or 0
    my = my or 0
    IslandMenu._DrawLobby(vg, sw, sh, ctx, mx, my)
end

-- ── Level 1: 对话框 + 右侧选项（新 UI 图片版，1080p 基准缩放）────────────────
function IslandMenu._DrawLobby(vg, sw, sh, ctx, mx, my)
    local island = ctx.island

    -- ── UI 缩放：以 1080p 高度为基准 ────────────────────────────────────────
    local S = sh / 1080   -- 所有 1080p 下的像素值 × S 得到实际像素

    -- ── 弹入动画（Back Ease Out）────────────────────────────────────────────
    local ANIM_DUR = 0.38
    local elapsed  = time:GetElapsedTime() - openTime_
    local t        = math.min(1.0, elapsed / ANIM_DUR)
    local c1    = 1.70158
    local c3    = c1 + 1
    local tm1   = t - 1
    local animScale = 1.0 + c3 * tm1 * tm1 * tm1 + c1 * tm1 * tm1

    local pivotX = sw * 0.5
    local pivotY = sh
    nvgSave(vg)
    nvgTranslate(vg, pivotX, pivotY)
    nvgScale(vg, animScale, animScale)
    nvgTranslate(vg, -pivotX, -pivotY)

    -- ── 布局：底部对话框（1080p 原始尺寸 × S）──────────────────────────────
    local DIAL_W   = BG_W * S
    local DIAL_H   = BG_H * S
    local DIAL_X   = math.floor((sw - DIAL_W) / 2)          -- 水平居中
    local DIAL_Y   = math.floor(sh - DIAL_H - 20 * S)       -- 距屏幕底部 20px(1080p)

    -- ── 岛屿 NPC 配置（仅特定岛屿生效）─────────────────────────────────────────
    local islandId  = island and island.id
    local npcConfig = islandId and ISLAND_NPC_CONFIG[islandId] or nil

    -- ── NPC 半身绘（绘制在对话框背景之前，即对话框后方）──────────────────────
    if npcConfig and npcConfig.halfBodyRef then
        local hbImg = getNpcHalfBodyImg(npcConfig.halfBodyRef)
        if hbImg and hbImg > 0 then
            -- 半身绘高度 = 对话框高度的 2.0/1.2 倍，宽度按原始比例缩放
            local HB_SCALE_H = 2.0 / 1.2
            local hbH = DIAL_H * HB_SCALE_H
            local hbW = hbH * (npcConfig.halfBodyW / npcConfig.halfBodyH)
            -- 水平：与名字标签对齐，贴紧对话框左侧
            local hbX = DIAL_X - hbW * 0.05 - 40 * S
            -- 垂直：底部与对话框底部对齐，再上移 200px(1080p)
            local hbY = DIAL_Y + DIAL_H - hbH - 200 * S
            local hbPat = nvgImagePattern(vg, hbX, hbY, hbW, hbH, 0, hbImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, hbX, hbY, hbW, hbH)
            nvgFillPaint(vg, hbPat)
            nvgFill(vg)
        end
    end

    -- 对话框背景图
    if imgDialogBg > 0 then
        local bgPat = nvgImagePattern(vg, DIAL_X, DIAL_Y, DIAL_W, DIAL_H, 0, imgDialogBg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, DIAL_X, DIAL_Y, DIAL_W, DIAL_H)
        nvgFillPaint(vg, bgPat)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, DIAL_X, DIAL_Y, DIAL_W, DIAL_H, 12)
        nvgFillColor(vg, rgba(244, 239, 227, 240))
        nvgFill(vg)
    end

    -- ── NPC 名字标签（1080p 原始尺寸 × S，叠在对话框左上角）────────────────
    local TAG_W_D = TAG_W * S
    local TAG_H_D = TAG_H * S
    local tagX    = DIAL_X + 40 * S
    local tagY    = DIAL_Y - TAG_H_D * 0.5   -- 叠入对话框顶部一半

    if imgNameTag > 0 then
        local tagPat = nvgImagePattern(vg, tagX, tagY, TAG_W_D, TAG_H_D, 0, imgNameTag, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, tagX, tagY, TAG_W_D, TAG_H_D)
        nvgFillPaint(vg, tagPat)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tagX, tagY, TAG_W_D, TAG_H_D, 8)
        nvgFillColor(vg, rgba(254, 198, 95, 240))
        nvgFill(vg)
    end
    -- 名字：NPC配置优先，回退到岛屿名
    local npcName = (npcConfig and npcConfig.name) or (island and island.name) or "岛屿"
    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, 42 * S)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(80, 45, 10, 230))
    nvgText(vg, tagX + TAG_W_D / 2, tagY + TAG_H_D / 2, npcName, nil)

    -- ── 对话文字：50pt 加粗，上下居中，左对齐 ────────────────────────────────
    -- 文字区：对话框左半部分，水平留边
    local TEXT_PAD_L = 60 * S    -- 左侧内边距
    local TEXT_PAD_R = 20 * S    -- 文字区右侧与选项区的间隔
    local TEXT_AREA_W = DIAL_W * 0.48   -- 左半留给文字
    local textX = DIAL_X + TEXT_PAD_L
    local textW = TEXT_AREA_W - TEXT_PAD_L - TEXT_PAD_R
    -- 打探消息模式使用专属文本，否则使用 NPC 对话
    local dialogMsg = inquiryMode_ and inquiryText_
        or ((npcConfig and npcConfig.dialog) or "要做些什么呢？")
    local fontSize50 = 50 * S
    local lineH = fontSize50 * 1.3

    -- 拆分换行，计算总文字块高度后垂直居中
    local lines = {}
    for line in (dialogMsg .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local totalTextH = #lines * lineH
    local textBlockY = DIAL_Y + (DIAL_H - totalTextH) / 2

    nvgFontFace(vg, "sans-bold")
    nvgFontSize(vg, fontSize50)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, rgba(60, 35, 10, 230))
    for i, line in ipairs(lines) do
        nvgText(vg, textX, textBlockY + (i - 0.5) * lineH, line, nil)
    end

    -- Esc 提示（对话框右下角）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18 * S)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, rgba(120, 90, 40, 160))
    nvgText(vg, DIAL_X + DIAL_W - 78 * S, DIAL_Y + DIAL_H - 19 * S, "[Esc] 离开", nil)

    -- ── 选项按钮（1080p 原始尺寸 × S，底部锚点对齐）──────────────────────────
    local OPT_W        = BTN_W * S
    local OPT_H        = BTN_H * S
    local OPT_GAP      = 20 * S          -- 1080p 下按钮间距 20px
    local OPT_MARGIN_R = 60 * S          -- 距对话框右边缘（1080p）
    -- 打探消息模式使用专属选项列表
    local currentItems = inquiryMode_ and inquiryItems_ or menuItems_
    local n            = #currentItems
    local optsH        = n * OPT_H + (n - 1) * OPT_GAP
    -- 锚点：以对话框垂直中心为基准，上移 220px、右移 300px（1080p 坐标）
    -- 最下方按钮的底部固定在此锚点，按钮组向上堆叠
    local ANCHOR_BOTTOM_Y = DIAL_Y + DIAL_H / 2
    local OPT_X           = DIAL_X + DIAL_W - OPT_W - OPT_MARGIN_R + 300 * S
    local OPT_TOP         = ANCHOR_BOTTOM_Y - optsH

    for i, item in ipairs(currentItems) do
        local bx  = OPT_X
        local by  = OPT_TOP + (i - 1) * (OPT_H + OPT_GAP)
        local hov = mx >= bx and mx <= bx + OPT_W and my >= by and my <= by + OPT_H

        -- hover 时微放大
        local drawX, drawY, drawW, drawH = bx, by, OPT_W, OPT_H
        if hov then
            local ex = 6 * S
            local ey = ex * BTN_H / BTN_W
            drawX, drawY = bx - ex, by - ey
            drawW, drawH = OPT_W + ex * 2, OPT_H + ey * 2
        end

        if imgButton > 0 then
            local btnPat = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, imgButton, hov and 1.0 or 0.9)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillPaint(vg, btnPat)
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, OPT_W, OPT_H, 8)
            nvgFillColor(vg, rgba(33, 33, 33, hov and 255 or 210))
            nvgFill(vg)
        end

        -- 按钮文字：42pt 加粗，居中
        nvgFontFace(vg, "sans-bold")
        nvgFontSize(vg, 42 * S)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, hov and rgba(255, 230, 120, 255) or rgba(230, 220, 200, 255))
        nvgText(vg, bx + OPT_W / 2, by + OPT_H / 2, item.label, nil)

        addHit(item.id, bx, by, OPT_W, OPT_H)
    end

    -- 关闭热区（对话框左侧空白）
    addHit("close", 0, 0, DIAL_X - 1, sh)

    nvgRestore(vg)
end

return IslandMenu
