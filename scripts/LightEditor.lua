-- ============================================================================
-- LightEditor.lua  —  可视化灯光编辑器
-- 按 L 键开启/关闭
-- 拖拽灯点移动位置；点击面板字段后直接键盘输入，回车确认，ESC取消
-- 控制台会在每次修改后自动打印完整配置表
-- ============================================================================

local M = {}

-- ── 公共灯光数据（编辑器关闭后仍用于渲染）─────────────────────────────────
-- 每条记录：{ name, entity, dx, dy, color={r,g,b}, size, brightness }
-- entity = "boat" | "island"（岛屿灯光作为模板应用到所有岛）
-- dx, dy 单位：世界像素偏移（screen px / camScale），与缩放无关
M.lights = {}

-- ── 编辑器状态 ───────────────────────────────────────────────────────────────
M.active = false

-- 私有
local vg_          = nil
local screenW_     = 0
local screenH_     = 0
local selected_    = nil   -- 当前选中灯光序号
local dragging_    = false
local dragBaseX_   = 0
local dragBaseY_   = 0
local dragLightDX_ = 0
local dragLightDY_ = 0

-- 输入框
local editField_   = nil   -- "name"|"color"|"size"|"brightness"
local editText_    = ""

-- 布局常量
local PX  = 16     -- 面板 X（运行时由 DrawEditor 重算为右下锚点）
local PY  = 56     -- 面板 Y（同上）
local PW  = 270    -- 面板宽
local RH  = 26     -- 列表行高
local MARGIN = 16  -- 距屏幕边缘间距

-- 外部引用（每帧由 DrawLights/DrawEditor 传入）
local boat_          = nil
local islands_       = nil
local camScale_      = 1
local worldToScreen_ = nil

-- ── 工具函数 ─────────────────────────────────────────────────────────────────
local function hexToRGB(hex)
    hex = hex:gsub("#", "")
    if #hex == 6 then
        return {
            r = tonumber(hex:sub(1,2), 16) or 255,
            g = tonumber(hex:sub(3,4), 16) or 255,
            b = tonumber(hex:sub(5,6), 16) or 255,
        }
    end
    return { r=255, g=255, b=255 }
end

local function rgbToHex(c)
    return string.format("#%02x%02x%02x", c.r, c.g, c.b)
end

-- 获取灯光在屏幕上的位置
local function lightScreenPos(light)
    if light.entity == "boat" and boat_ then
        local bx, by = worldToScreen_(boat_.x, boat_.y)
        return bx + light.dx * camScale_,
               by + light.dy * camScale_
    elseif light.entity == "island" and islands_ then
        -- 取最近的岛屿作为编辑锚点
        local isl = islands_[1]
        if isl then
            local ix, iy = worldToScreen_(isl.x, isl.y)
            return ix + light.dx * camScale_,
                   iy + light.dy * camScale_
        end
    end
    return screenW_ * 0.5, screenH_ * 0.5
end

-- ── 绘制单个光晕 ─────────────────────────────────────────────────────────────
local function drawGlowAt(sx, sy, size, color, brightness)
    local a0 = math.floor(brightness * 255)
    local a1 = math.floor(brightness * 180)
    local a2 = math.floor(brightness * 80)

    -- 核心
    local p = nvgRadialGradient(vg_, sx, sy, 0, size * 0.12,
        nvgRGBA(color.r, color.g, color.b, a0),
        nvgRGBA(color.r, color.g, color.b, 0))
    nvgBeginPath(vg_)
    nvgCircle(vg_, sx, sy, size * 0.12)
    nvgFillPaint(vg_, p)
    nvgFill(vg_)

    -- 中光晕
    p = nvgRadialGradient(vg_, sx, sy, 0, size * 0.38,
        nvgRGBA(color.r, color.g, color.b, a1),
        nvgRGBA(color.r, color.g, color.b, 0))
    nvgBeginPath(vg_)
    nvgCircle(vg_, sx, sy, size * 0.38)
    nvgFillPaint(vg_, p)
    nvgFill(vg_)

    -- 外光晕
    p = nvgRadialGradient(vg_, sx, sy, 0, size,
        nvgRGBA(color.r, color.g, color.b, a2),
        nvgRGBA(color.r, color.g, color.b, 0))
    nvgBeginPath(vg_)
    nvgCircle(vg_, sx, sy, size)
    nvgFillPaint(vg_, p)
    nvgFill(vg_)
end

-- ── 公共：绘制所有灯光（编辑器开关无关） ─────────────────────────────────────
function M.DrawLights(vg, boat, islands, camScale, worldToScreen, nightIntensity)
    if #M.lights == 0 then return end
    vg_          = vg
    boat_        = boat
    islands_     = islands
    camScale_    = camScale
    worldToScreen_ = worldToScreen

    local ni = nightIntensity or 1.0

    nvgSave(vg)
    for _, light in ipairs(M.lights) do
        if light.entity == "boat" and boat_ then
            local sx, sy = lightScreenPos(light)
            drawGlowAt(sx, sy, light.size, light.color, light.brightness * ni)
        elseif light.entity == "island" and islands_ then
            for _, isl in pairs(islands_) do
                local ix, iy = worldToScreen_(isl.x, isl.y)
                local sx = ix + light.dx * camScale_
                local sy = iy + light.dy * camScale_
                -- 简单视锥剔除
                if sx > -light.size and sx < screenW_ + light.size and
                   sy > -light.size and sy < screenH_ + light.size then
                    drawGlowAt(sx, sy, light.size, light.color, light.brightness * ni)
                end
            end
        end
    end
    nvgRestore(vg)
end

-- ── 公共：绘制编辑器覆盖层 ───────────────────────────────────────────────────
function M.DrawEditor(vg, screenW, screenH)
    vg_      = vg
    screenW_ = screenW
    screenH_ = screenH

    -- 灯光手柄（始终绘制，方便对照；编辑器关闭时只画小圆点）
    nvgSave(vg)

    for i, light in ipairs(M.lights) do
        local sx, sy  = lightScreenPos(light)
        local isSel   = (i == selected_)
        local showFull = M.active

        if showFull then
            -- 外圈
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, isSel and 14 or 9)
            nvgStrokeColor(vg, isSel
                and nvgRGBA(255, 255, 80, 255)
                or  nvgRGBA(255, 255, 255, 140))
            nvgStrokeWidth(vg, isSel and 2.5 or 1.5)
            nvgStroke(vg)

            -- 彩色内点
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, 4)
            nvgFillColor(vg, nvgRGBA(light.color.r, light.color.g, light.color.b, 255))
            nvgFill(vg)

            -- 名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, sx + 16, sy - 5, light.name, nil)

            -- 实时坐标
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(150, 255, 150, 200))
            nvgText(vg, sx + 16, sy + 7,
                string.format("dx=%.1f  dy=%.1f", light.dx, light.dy), nil)
        end
    end

    nvgRestore(vg)

    if not M.active then return end

    -- ── 面板 ────────────────────────────────────────────────────────────────
    nvgSave(vg)
    nvgFontFace(vg, "sans")

    -- 计算面板高度，并锚定到右下角
    local listRows  = #M.lights
    local propRows  = selected_ and 6 or 0   -- name/color/size/brightness/pos/entity
    local panelH    = 18 + 26 + listRows * RH + 8 + propRows * 28 + 14
    PX = screenW - PW - MARGIN
    PY = screenH - panelH - MARGIN

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, PX, PY, PW, panelH, 8)
    nvgFillColor(vg, nvgRGBA(8, 12, 24, 218))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(70, 110, 200, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(140, 190, 255, 255))
    nvgText(vg, PX + 10, PY + 14, "灯光编辑器  [L 关闭]", nil)

    -- + / - 按钮
    local btnY = PY + 20
    nvgBeginPath(vg)
    nvgRoundedRect(vg, PX + 10, btnY, 52, 20, 4)
    nvgFillColor(vg, nvgRGBA(35, 140, 65, 230))
    nvgFill(vg)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, PX + 22, btnY + 14, "+ 新增", nil)

    if selected_ then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, PX + 72, btnY, 52, 20, 4)
        nvgFillColor(vg, nvgRGBA(160, 40, 40, 230))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, PX + 84, btnY + 14, "- 删除", nil)
    end

    -- 灯光列表
    local listY = btnY + 26
    for i, light in ipairs(M.lights) do
        local ry  = listY + (i - 1) * RH
        local sel = (i == selected_)

        if sel then
            nvgBeginPath(vg)
            nvgRect(vg, PX + 4, ry, PW - 8, RH - 1)
            nvgFillColor(vg, nvgRGBA(40, 70, 150, 190))
            nvgFill(vg)
        end

        -- 色块
        nvgBeginPath(vg)
        nvgRect(vg, PX + 10, ry + 6, 12, 12)
        nvgFillColor(vg, nvgRGBA(light.color.r, light.color.g, light.color.b, 255))
        nvgFill(vg)

        -- 名称
        nvgFontSize(vg, 11)
        nvgFillColor(vg, sel and nvgRGBA(255,255,140,255) or nvgRGBA(210,210,210,255))
        nvgText(vg, PX + 28, ry + RH - 7, light.name, nil)

        -- entity 标签
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(100, 170, 255, 200))
        nvgText(vg, PX + 110, ry + RH - 7, light.entity == "boat" and "船" or "岛", nil)

        -- dx dy
        nvgFillColor(vg, nvgRGBA(140, 220, 140, 200))
        nvgText(vg, PX + 132, ry + RH - 7,
            string.format("(%.1f, %.1f)", light.dx, light.dy), nil)

        -- size / brightness
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 160))
        nvgText(vg, PX + 210, ry + RH - 7,
            string.format("r=%d b=%.2f", light.size, light.brightness), nil)
    end

    -- 属性面板（选中时）
    if selected_ then
        local light  = M.lights[selected_]
        local propY  = listY + #M.lights * RH + 12

        -- 分割线
        nvgBeginPath(vg)
        nvgMoveTo(vg, PX + 8, propY - 4)
        nvgLineTo(vg, PX + PW - 8, propY - 4)
        nvgStrokeColor(vg, nvgRGBA(70, 100, 160, 140))
        nvgStroke(vg)

        local function drawField(label, value, fieldName, fy)
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(150, 175, 220, 255))
            nvgText(vg, PX + 10, fy + 14, label, nil)

            local isEd = (editField_ == fieldName)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, PX + 76, fy + 2, 182, 20, 3)
            nvgFillColor(vg, isEd
                and nvgRGBA(25, 45, 90, 248)
                or  nvgRGBA(18, 28, 55, 210))
            nvgFill(vg)
            nvgStrokeColor(vg, isEd
                and nvgRGBA(90, 150, 255, 255)
                or  nvgRGBA(50, 70, 120, 160))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            local disp = isEd and (editText_ .. "|") or tostring(value)
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
            nvgText(vg, PX + 82, fy + 15, disp, nil)
        end

        drawField("名称",   light.name,                          "name",       propY)       propY = propY + 28
        drawField("颜色",   rgbToHex(light.color),               "color",      propY)       propY = propY + 28
        drawField("大小",   tostring(light.size),                 "size",       propY)       propY = propY + 28
        drawField("亮度",   string.format("%.2f", light.brightness), "brightness", propY) propY = propY + 28

        -- 位置（只读，高亮显示）
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(150, 175, 220, 255))
        nvgText(vg, PX + 10, propY + 14, "位置", nil)
        nvgFillColor(vg, nvgRGBA(120, 255, 120, 255))
        nvgFontSize(vg, 12)
        nvgText(vg, PX + 76, propY + 14,
            string.format("dx = %.2f    dy = %.2f", light.dx, light.dy), nil)
        propY = propY + 28

        -- 类型切换
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(150, 175, 220, 255))
        nvgText(vg, PX + 10, propY + 14, "类型", nil)

        local isBoat = (light.entity == "boat")
        nvgBeginPath(vg)
        nvgRoundedRect(vg, PX + 76, propY + 2, 56, 20, 3)
        nvgFillColor(vg, isBoat
            and nvgRGBA(50, 110, 200, 230)
            or  nvgRGBA(25, 35, 65, 180))
        nvgFill(vg)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, PX + 90, propY + 14, "船只", nil)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, PX + 140, propY + 2, 56, 20, 3)
        nvgFillColor(vg, not isBoat
            and nvgRGBA(50, 110, 200, 230)
            or  nvgRGBA(25, 35, 65, 180))
        nvgFill(vg)
        nvgText(vg, PX + 154, propY + 14, "岛屿", nil)
    end

    nvgRestore(vg)
end

-- ── 打印配置到控制台 ─────────────────────────────────────────────────────────
function M.PrintConfig()
    print("---------- LightEditor 当前配置 ----------")
    print("M.lights = {")
    for _, l in ipairs(M.lights) do
        print(string.format(
            '  { name="%s", entity="%s", dx=%.2f, dy=%.2f,'
            ..' color={r=%d,g=%d,b=%d}, size=%d, brightness=%.2f },',
            l.name, l.entity, l.dx, l.dy,
            l.color.r, l.color.g, l.color.b,
            l.size, l.brightness))
    end
    print("}")
    print("-------------------------------------------")
end

-- ── 提交当前输入框 ───────────────────────────────────────────────────────────
local function commitEdit()
    if not selected_ or not editField_ then return end
    local l = M.lights[selected_]
    if     editField_ == "name"       then l.name       = editText_
    elseif editField_ == "color"      then l.color      = hexToRGB(editText_)
    elseif editField_ == "size"       then l.size       = math.max(1, tonumber(editText_) or l.size)
    elseif editField_ == "brightness" then l.brightness = math.max(0, math.min(1, tonumber(editText_) or l.brightness))
    end
    editField_ = nil
    editText_  = ""
    M.PrintConfig()
end

-- ── 事件处理 ─────────────────────────────────────────────────────────────────
function M.OnKeyDown(key)
    -- L 键切换编辑器
    if key == KEY_L then
        M.active = not M.active
        if M.active then
            print("[LightEditor] 编辑器已开启 —— 拖拽灯点移动位置，点击字段输入数值")
        end
        return true   -- 已消费
    end

    if not M.active then return false end

    if editField_ then
        if key == KEY_RETURN or key == KEY_KP_ENTER then
            commitEdit()
        elseif key == KEY_ESCAPE then
            editField_ = nil
            editText_  = ""
        elseif key == KEY_BACKSPACE then
            if #editText_ > 0 then
                editText_ = editText_:sub(1, -2)
            end
        end
        return true
    end
    return false
end

function M.OnTextInput(char)
    if not M.active or not editField_ then return end
    editText_ = editText_ .. char
end

function M.OnMouseDown(mx, my)
    if not M.active then return false end

    -- 先看是否命中某个灯点（12px 半径内）
    for i, light in ipairs(M.lights) do
        local sx, sy = lightScreenPos(light)
        if (mx - sx)^2 + (my - sy)^2 < 144 then
            selected_    = i
            dragging_    = true
            dragBaseX_   = mx
            dragBaseY_   = my
            dragLightDX_ = light.dx
            dragLightDY_ = light.dy
            editField_   = nil
            return true
        end
    end

    -- 计算面板命中区域
    local listRows = #M.lights
    local panelH   = 18 + 26 + listRows * RH + 8 + (selected_ and 6 or 0) * 28 + 14
    local inPanel  = mx >= PX and mx <= PX + PW and my >= PY and my <= PY + panelH

    if not inPanel then
        -- 点击面板外，取消选中
        selected_  = nil
        editField_ = nil
        return false
    end

    -- + 新增按钮
    local btnY = PY + 20
    if mx >= PX+10 and mx <= PX+62 and my >= btnY and my <= btnY+20 then
        local n = #M.lights + 1
        table.insert(M.lights, {
            name       = "灯" .. n,
            entity     = "boat",
            dx         = 0,
            dy         = 0,
            color      = { r=255, g=200, b=100 },
            size       = 60,
            brightness = 0.8,
        })
        selected_  = #M.lights
        editField_ = nil
        return true
    end

    -- - 删除按钮
    if selected_ and mx >= PX+72 and mx <= PX+124 and my >= btnY and my <= btnY+20 then
        table.remove(M.lights, selected_)
        selected_ = #M.lights > 0 and math.min(selected_, #M.lights) or nil
        editField_ = nil
        M.PrintConfig()
        return true
    end

    -- 列表行选中
    local listY = btnY + 26
    for i = 1, #M.lights do
        local ry = listY + (i - 1) * RH
        if mx >= PX+4 and mx <= PX+PW-4 and my >= ry and my <= ry + RH then
            selected_  = i
            editField_ = nil
            return true
        end
    end

    -- 属性字段点击
    if selected_ then
        local propY = listY + #M.lights * RH + 12
        local fields = { "name", "color", "size", "brightness" }
        for _, fn in ipairs(fields) do
            if mx >= PX+76 and mx <= PX+258 and my >= propY+2 and my <= propY+22 then
                local l = M.lights[selected_]
                editField_ = fn
                if     fn == "name"       then editText_ = l.name
                elseif fn == "color"      then editText_ = rgbToHex(l.color)
                elseif fn == "size"       then editText_ = tostring(l.size)
                elseif fn == "brightness" then editText_ = string.format("%.2f", l.brightness)
                end
                return true
            end
            propY = propY + 28
        end
        -- 跳过位置行（只读）
        propY = propY + 28

        -- 类型按钮（船只）
        if mx >= PX+76 and mx <= PX+132 and my >= propY+2 and my <= propY+22 then
            M.lights[selected_].entity = "boat"
            M.PrintConfig()
            return true
        end
        -- 类型按钮（岛屿）
        if mx >= PX+140 and mx <= PX+196 and my >= propY+2 and my <= propY+22 then
            M.lights[selected_].entity = "island"
            M.PrintConfig()
            return true
        end
    end

    return true  -- 消费点击，防止穿透
end

function M.OnMouseUp(button)
    if button == MOUSEB_LEFT and dragging_ then
        dragging_ = false
        M.PrintConfig()
    end
end

function M.OnMouseMove(mx, my)
    if not M.active or not dragging_ or not selected_ then return end
    local l = M.lights[selected_]
    l.dx = dragLightDX_ + (mx - dragBaseX_) / camScale_
    l.dy = dragLightDY_ + (my - dragBaseY_) / camScale_
end

return M
