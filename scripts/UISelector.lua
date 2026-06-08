-- UISelector.lua
-- 按 Y 键呼出的 UI 测试选择框
-- 数字键 1~N 或点击选择对应 UI 面板
-- ESC / Y 再次按下 关闭

local M = {}

local open_    = false
local alpha_   = 0
local hovered_ = 0

-- UI 列表（后续可继续添加）
-- { label, open, close, isOpen }
local panels_  = {}

-- ─── 公共接口 ───────────────────────────────────────────────────────────────

function M.Init(panelList)
    panels_ = panelList
end

function M.Toggle()
    if open_ then
        M.Close()
    else
        M.Open()
    end
end

function M.Open()
    open_ = true
end

function M.Close()
    open_ = false
end

function M.IsOpen()
    return open_
end

function M.Update(dt)
    if open_ then
        alpha_ = math.min(1, alpha_ + dt * 8)
    else
        alpha_ = math.max(0, alpha_ - dt * 8)
    end
end

-- 绘制选择框（在 NanoVGRender 内调用）
function M.Draw(vg, screenW, screenH, mx, my)
    if alpha_ <= 0 then return end

    local a   = alpha_
    local ai  = math.floor(255 * a)

    -- 面板尺寸
    local itemH  = 42
    local pw     = 260
    local ph     = 16 + #panels_ * itemH + 16
    local px     = (screenW - pw) * 0.5
    local py     = (screenH - ph) * 0.5

    nvgSave(vg)

    -- 背景遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(80 * a)))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 10)
    nvgFillColor(vg, nvgRGBA(10, 18, 30, math.floor(230 * a)))
    nvgFill(vg)

    -- 面板边框
    nvgStrokeColor(vg, nvgRGBA(80, 140, 200, math.floor(160 * a)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 200, 240, ai))
    nvgText(vg, px + pw * 0.5, py + 12, "UI 测试选择器", nil)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 12, py + 24)
    nvgLineTo(vg, px + pw - 12, py + 24)
    nvgStrokeColor(vg, nvgRGBA(80, 140, 200, math.floor(80 * a)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 每个条目
    hovered_ = 0
    for i, p in ipairs(panels_) do
        local iy    = py + 24 + (i - 1) * itemH
        local isHov = mx >= px and mx <= px + pw and my >= iy and my <= iy + itemH
        if isHov then hovered_ = i end

        -- 高亮
        if isHov then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px + 8, iy + 4, pw - 16, itemH - 8, 6)
            nvgFillColor(vg, nvgRGBA(60, 120, 200, math.floor(60 * a)))
            nvgFill(vg)
        end

        -- 序号
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(120, 180, 240, math.floor(200 * a)))
        nvgText(vg, px + 18, iy + itemH * 0.5, tostring(i), nil)

        -- 标签
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(220, 230, 245, ai))
        nvgText(vg, px + 40, iy + itemH * 0.5, p.label, nil)

        -- 已打开标记
        if p.isOpen and p.isOpen() then
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(100, 220, 120, math.floor(200 * a)))
            nvgText(vg, px + pw - 16, iy + itemH * 0.5, "● 已打开", nil)
        end
    end

    -- 提示
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 120, 140, math.floor(140 * a)))
    nvgText(vg, px + pw * 0.5, py + ph - 4, "数字键选择 / ESC 关闭", nil)

    nvgRestore(vg)
end

-- 按键处理，返回 true 表示已消费
function M.HandleKey(key)
    if not open_ then return false end

    if key == KEY_ESCAPE or key == KEY_Y then
        M.Close()
        return true
    end

    -- 数字键 1-9 选择
    local numKeys = { KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9 }
    for i, k in ipairs(numKeys) do
        if key == k and panels_[i] then
            M._SelectPanel(i)
            return true
        end
    end

    return true  -- 选择器打开时吃掉其他按键
end

-- 鼠标点击处理，返回 true 表示已消费
function M.HandleMouseDown(mx, my)
    if not open_ then return false end
    if hovered_ > 0 and panels_[hovered_] then
        M._SelectPanel(hovered_)
        return true
    end
    -- 点击面板外关闭
    return true
end

-- ─── 内部函数 ───────────────────────────────────────────────────────────────

function M._SelectPanel(idx)
    local p = panels_[idx]
    if not p then return end

    -- 切换开关
    if p.isOpen and p.isOpen() then
        p.close()
    else
        p.open()
    end
    M.Close()
end

return M
