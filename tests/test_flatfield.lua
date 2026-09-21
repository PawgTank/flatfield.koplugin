-- Run from the plugin directory: luajit tests/test_flatfield.lua
local function class(base)
    local c = {}
    c.__index = c
    setmetatable(c, { __index = base })
    function c:extend(fields)
        local child = class(self)
        for k, v in pairs(fields or {}) do child[k] = v end
        return child
    end
    function c:new(fields)
        local o = setmetatable(fields or {}, self)
        if o.init then o:init() end
        return o
    end
    return c
end

local draws, refreshes, brightness, shown, closed
local night_changes, opening_modes
local standby = 0
local scale = 1
local colors = { COLOR_WHITE = "white", COLOR_BLACK = "black" }
local bb = {}
for _, method in ipairs{ "paintRect", "paintRoundedRect", "paintCircle", "fill" } do
    bb[method] = function(_, ...)
        draws[#draws + 1] = { method = method, ... }
    end
end
local screen = { bb = bb, night_mode = false }
function screen:getWidth() return 600 * scale end
function screen:getHeight() return 800 * scale end
function screen:scaleBySize(v) return v * scale end
function screen:refreshFull()
    opening_modes[#opening_modes + 1] = self.night_mode
end
function screen:toggleNightMode()
    self.night_mode = not self.night_mode
    night_changes[#night_changes + 1] = self.night_mode
end
local power = { fl_min = 0, fl_max = 24 }
function power:frontlightIntensity() return 12 end
function power:setIntensity(v) brightness[#brightness + 1] = v end
local device = { screen = screen }
function device:getPowerDevice() return power end
function device:hasFrontlight() return true end
local manager = {}
function manager:show(widget) shown = widget end
function manager:setDirty(widget, mode, region)
    refreshes[#refreshes + 1] = { widget = widget, mode = mode, region = region }
end
function manager:forceRePaint() end
function manager:preventStandby() standby = standby + 1 end
function manager:allowStandby() standby = standby - 1 end
function manager:close(widget, mode)
    closed = { widget = widget, mode = mode }
    widget:onCloseWidget()
end
local text = class()
function text:setText(value) self.text = value end
function text:getSize() return { w = #self.text * 10, h = 20 } end
function text:paintTo() end
function text:free() self.freed = true end
local modules = {
    ["ffi/blitbuffer"] = colors,
    device = device,
    ["ui/font"] = { getFace = function() return {} end },
    ["ui/geometry"] = class(),
    ["ui/gesturerange"] = class(),
    ["ui/widget/infomessage"] = class(),
    ["ui/widget/container/inputcontainer"] = class(),
    ["ui/widget/textwidget"] = text,
    ["ui/uimanager"] = manager,
    ["ui/widget/container/widgetcontainer"] = class(),
    gettext = function(s) return s end,
}
for name, module in pairs(modules) do package.loaded[name] = module end
local Plugin = dofile("main.lua")
local plugin = Plugin:new{ ui = { menu = { registerToMainMenu = function() end } } }
local function panel(night_mode)
    draws, refreshes, brightness = {}, {}, {}
    night_changes, opening_modes = {}, {}
    screen.night_mode = night_mode or false
    standby = 0
    plugin:openFlatField()
    draws, refreshes = {}, {}
    return shown
end
local function pos(p, fraction, y)
    return { x = p.slider_x1 + fraction * (p.slider_x2 - p.slider_x1), y = y or p.slider_y }
end
local function last(t) return t[#t] end
local function test(name, fn)
    fn()
    print("PASS " .. name)
end

test("touch immediately updates brightness using only a fast toolbar refresh", function()
    local p = panel()
    p:onTouch(nil, { pos = pos(p, 0.75) })
    assert(last(brightness) == 18)
    assert(last(refreshes).mode == "fast" and last(refreshes).widget == nil)
    assert(last(refreshes).region.h == p.toolbar_h)
    assert(draws[1].method == "paintRect" and draws[1][4] == p.toolbar_h)
end)

test("drag tracks outside toolbar and commits release endpoint", function()
    local p = panel()
    p:onTouch(nil, { pos = pos(p, 0.5) })
    p:onPan(nil, { pos = pos(p, 0.75, 150) })
    assert(last(brightness) == 18)
    p:onPanRelease(nil, { pos = pos(p, 1, 200) })
    assert(last(brightness) == 24 and not p.dragging)
    assert(last(refreshes).mode == "ui")
end)

test("swipe uses lift position instead of jumping back to touch position", function()
    local p = panel()
    local start = pos(p, 0.25)
    p:onTouch(nil, { pos = start })
    p:onPan(nil, { pos = pos(p, 0.5) })
    p:onSwipe(nil, { pos = start, end_pos = pos(p, 1, 100) })
    assert(last(brightness) == 24 and not p.dragging)
    assert(last(refreshes).mode == "ui")
end)

test("quick swipe and multiswipe work without intermediate pan events", function()
    local p = panel()
    p:onSwipe(nil, { pos = pos(p, 0.5), end_pos = pos(p, 0) })
    assert(last(brightness) == 0)
    p:onTouch(nil, { pos = pos(p, 0.25) })
    p:onMultiSwipe(nil, { pos = pos(p, 0.25), end_pos = pos(p, 0.75) })
    assert(last(brightness) == 18 and not p.dragging)
end)

test("older swipe events retain the last pan position", function()
    local p = panel()
    local start = pos(p, 0.25)
    p:onTouch(nil, { pos = start })
    p:onPan(nil, { pos = pos(p, 0.75) })
    p:onSwipe(nil, { pos = start, direction = "east", distance = 100 })
    assert(last(brightness) == 18 and not p.dragging)
end)

test("hold then drag and release cleans up even with an unchanged value", function()
    local p = panel()
    p:onTouch(nil, { pos = pos(p, 0.5) })
    p:onHold(nil, { pos = pos(p, 0.5) })
    p:onHoldPan(nil, { pos = pos(p, 0.75, 150) })
    local count = #brightness
    p:onHoldRelease(nil, { pos = pos(p, 0.75, 150) })
    assert(#brightness == count and not p.dragging)
    assert(last(refreshes).mode == "ui")
end)

test("gestures originating in the white area do not take over the slider", function()
    local p = panel()
    local start = pos(p, 0.25, 300)
    local finish = pos(p, 0.75)
    p:onTouch(nil, { pos = start })
    p:onPan(nil, { pos = finish, start_pos = start })
    p:onSwipe(nil, { pos = start, end_pos = finish })
    assert(#brightness == 0)
    p:onPan(nil, { pos = finish, relative = { x = finish.x - start.x, y = finish.y - start.y } })
    assert(#brightness == 0)
end)

test("endpoints clamp to hardware range, including a nonzero minimum", function()
    power.fl_min = 2
    local p = panel()
    p:onTouch(nil, { pos = pos(p, 0.5) })
    p:onPan(nil, { pos = pos(p, -1) })
    assert(last(brightness) == 2 and p:_percentText() == "0%")
    p:onPanRelease(nil, { pos = pos(p, 2) })
    assert(last(brightness) == 24 and p:_percentText() == "100%")
    power.fl_min = 0
end)

test("Exit restores brightness and standby, and requests a full refresh", function()
    local p = panel()
    p:onTap(nil, { pos = pos(p, 1) })
    p:onTap(nil, { pos = { x = p.exit_rect.x + 1, y = p.exit_rect.y + 1 } })
    assert(last(brightness) == 12 and standby == 0)
    assert(closed.widget == p and closed.mode == "full")
    assert(p.exit_text.freed and p.percent_text.freed)
end)

test("toolbar footprint and rounded controls scale with the screen", function()
    for _, factor in ipairs{ 1, 2 } do
        scale = factor
        local p = panel()
        assert(p.toolbar_h == 64 * factor)
        assert(p.exit_rect.w == 110 * factor and p.exit_rect.h == 42 * factor)
        assert(p.exit_text.fgcolor == colors.COLOR_WHITE)
        p:paintTo(bb, 0, 0)
        assert(draws[1][4] == screen:getHeight())
        assert(draws[3].method == "paintRoundedRect")
        assert(draws[3][6] == p.control_h / 2)
        assert(last(draws).method == "paintCircle")
        assert(p.slider_touch_rect.x > p.exit_rect.x + p.exit_rect.w)
    end
    scale = 1
end)

test("night mode is disabled before the opening refresh and restored on Exit", function()
    local p = panel(true)
    assert(screen.night_mode == false)
    assert(#opening_modes == 1 and opening_modes[1] == false)
    assert(#night_changes == 1 and night_changes[1] == false)
    p:onTouch(nil, { pos = pos(p, 0.75) })
    assert(screen.night_mode == false)
    p:onPanRelease(nil, { pos = pos(p, 0.75) })
    p:onTap(nil, { pos = { x = p.exit_rect.x + 1, y = p.exit_rect.y + 1 } })
    assert(screen.night_mode == true and #night_changes == 2)
    assert(last(brightness) == 12 and standby == 0)
    assert(closed.mode == "full")
    p:_restoreState()
    assert(#night_changes == 2, "cleanup must not toggle night mode twice")
end)

test("day mode stays unchanged on open and close", function()
    local p = panel(false)
    assert(screen.night_mode == false and #night_changes == 0)
    p:onClose()
    assert(screen.night_mode == false and #night_changes == 0)
    assert(closed.mode == "full")
end)

test("external widget closure restores night mode and requests a full refresh", function()
    local p = panel(true)
    manager:close(p)
    assert(screen.night_mode == true and #night_changes == 2)
    assert(last(refreshes).mode == "full" and last(refreshes).region == nil)
    assert(last(brightness) == 12 and standby == 0)
end)

print("All Flat Field checks passed.")
