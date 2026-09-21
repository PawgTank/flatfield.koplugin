local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local PowerD = Device:getPowerDevice()

local FlatScreen = InputContainer:extend{
    modal = true,
    covers_fullscreen = true,
    disable_double_tap = true,
}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function FlatScreen:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.screen_w,
        h = self.screen_h,
    }

    -- Keep the controls deliberately shallow so nearly the whole panel is usable
    -- as an uninterrupted white flat-field source.
    self.toolbar_h = Screen:scaleBySize(64)
    self.margin = Screen:scaleBySize(14)
    self.exit_w = Screen:scaleBySize(110)
    self.control_h = Screen:scaleBySize(42)
    self.border = math.max(1, Screen:scaleBySize(2))
    self.track_h = math.max(1, Screen:scaleBySize(2))
    self.fill_h = math.max(3, Screen:scaleBySize(6))
    self.knob_radius = math.max(4, Screen:scaleBySize(16))
    self.percent_w = Screen:scaleBySize(86)

    self.exit_rect = Geom:new{
        x = self.margin,
        y = math.floor((self.toolbar_h - self.control_h) / 2),
        w = self.exit_w,
        h = self.control_h,
    }

    self.slider_x1 = self.exit_rect.x + self.exit_rect.w + self.margin * 2
    self.slider_x2 = self.screen_w - self.margin - self.percent_w
    if self.slider_x2 <= self.slider_x1 then
        self.slider_x2 = self.screen_w - self.margin
    end
    self.slider_y = math.floor(self.toolbar_h / 2)
    self.slider_touch_rect = Geom:new{
        x = self.slider_x1 - self.knob_radius,
        y = 0,
        w = (self.slider_x2 - self.slider_x1) + self.knob_radius * 2,
        h = self.toolbar_h,
    }

    self.toolbar_dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.screen_w,
        h = self.toolbar_h,
    }

    self.fl_min = tonumber(PowerD.fl_min) or 0
    self.fl_max = tonumber(PowerD.fl_max) or 100
    if self.fl_max <= self.fl_min then
        self.fl_min = 0
        self.fl_max = 100
    end

    local current = self.fl_min
    if PowerD.frontlightIntensity then
        local ok, intensity = pcall(PowerD.frontlightIntensity, PowerD)
        if ok and type(intensity) == "number" then
            current = intensity
        end
    end
    self.original_intensity = clamp(current, self.fl_min, self.fl_max)
    self.intensity = self.original_intensity
    self.restored = false

    self.exit_text = TextWidget:new{
        text = _("Exit"),
        face = Font:getFace("cfont", 20),
        bold = true,
        padding = 0,
        fgcolor = Blitbuffer.COLOR_WHITE,
    }
    self.percent_text = TextWidget:new{
        text = self:_percentText(),
        face = Font:getFace("cfont", 20),
        padding = 0,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.ges_events = {}
    for event, gesture in pairs{
        Touch = "touch", Tap = "tap", Pan = "pan", PanRelease = "pan_release",
        Hold = "hold", HoldPan = "hold_pan", HoldRelease = "hold_release",
        Swipe = "swipe", MultiSwipe = "multiswipe",
    } do
        self.ges_events[event] = { GestureRange:new{
            ges = gesture,
            range = self.dimen,
        } }
    end

    -- Keep KOReader from entering low-power standby while the flat panel is open.
    if UIManager.preventStandby then
        UIManager:preventStandby()
        self.standby_prevented = true
    end

    -- Override screen inversion only; leave the saved night-mode preference
    -- and theme events alone. This API handles both HW and SW inversion.
    self.original_night_mode = Screen.night_mode
    if Screen.night_mode then
        Screen:toggleNightMode()
    end
end

function FlatScreen:_percentText()
    local span = self.fl_max - self.fl_min
    local pct = span > 0 and math.floor(((self.intensity - self.fl_min) / span) * 100 + 0.5) or 0
    return string.format("%d%%", clamp(pct, 0, 100))
end

function FlatScreen:_knobX()
    local span = self.fl_max - self.fl_min
    local fraction = span > 0 and ((self.intensity - self.fl_min) / span) or 0
    return math.floor(self.slider_x1 + fraction * (self.slider_x2 - self.slider_x1) + 0.5)
end

function FlatScreen:_setIntensityFromX(x)
    local width = self.slider_x2 - self.slider_x1
    if width <= 0 then return end

    local fraction = clamp((x - self.slider_x1) / width, 0, 1)
    local value = math.floor(self.fl_min + fraction * (self.fl_max - self.fl_min) + 0.5)
    value = clamp(value, self.fl_min, self.fl_max)

    if value == self.intensity then return end
    self.intensity = value

    if PowerD.setIntensity then
        pcall(PowerD.setIntensity, PowerD, value)
    end

    self.percent_text:setText(self:_percentText())

    self:_refreshControls(self.dragging and "fast" or "ui")
end

function FlatScreen:_refreshControls(mode)
    if mode == "fast" then
        -- Like ZenOS's brightness slider, repaint the controls directly during
        -- a drag to avoid repainting the full widget tree for each movement.
        self:_paintToolbar(Screen.bb, 0, 0)
        UIManager:setDirty(nil, "fast", self.toolbar_dimen)
    else
        UIManager:setDirty(self, "ui", self.toolbar_dimen)
    end
end

function FlatScreen:_pointIn(rect, pos)
    return pos
        and pos.x >= rect.x and pos.x < rect.x + rect.w
        and pos.y >= rect.y and pos.y < rect.y + rect.h
end

function FlatScreen:onTouch(_, ges)
    local pos = ges and ges.pos
    self.dragging = self:_pointIn(self.slider_touch_rect, pos) or false
    if self.dragging then self:_setIntensityFromX(pos.x) end
    return true
end

function FlatScreen:_finishDrag(pos)
    -- Always clean up fast-refresh artifacts, even if the last value is unchanged.
    if pos then self:_setIntensityFromX(pos.x) end
    self.dragging = false
    self:_refreshControls("ui")
end

function FlatScreen:onTap(_, ges)
    local pos = ges and ges.pos
    if self.dragging then
        self:_finishDrag(pos)
        return true
    end
    if self:_pointIn(self.exit_rect, pos) then
        self:_exit()
        return true
    end

    if self:_pointIn(self.slider_touch_rect, pos) then
        self:_setIntensityFromX(pos.x)
        return true
    end

    -- Swallow taps elsewhere so they cannot reach the reader underneath.
    return true
end

function FlatScreen:onPan(_, ges)
    local pos = ges and ges.pos
    -- Pan positions are current coordinates; only the initial contact needs to
    -- hit the slider. Keep tracking when a finger drifts outside the toolbar.
    local start = ges and ges.start_pos
    if not start and pos and ges.relative then
        start = { x = pos.x - ges.relative.x, y = pos.y - ges.relative.y }
    end
    if not self.dragging and self:_pointIn(self.slider_touch_rect, start or pos) then
        self.dragging = true
    end
    if self.dragging and pos then
        self:_setIntensityFromX(pos.x)
    end
    return true
end

function FlatScreen:onPanRelease(_, ges)
    if self.dragging then self:_finishDrag(ges and ges.pos) end
    return true
end

function FlatScreen:onSwipe(_, ges)
    if ges and (self.dragging or self:_pointIn(self.slider_touch_rect, ges.pos)) then
        -- Unlike a pan, swipe.pos is the START; using it would snap the slider
        -- back on release. KOReader supplies the actual lift point in end_pos.
        local pos = ges.end_pos
        if not pos and not self.dragging and ges.pos then
            -- Older gesture detectors may omit end_pos. Use the horizontal
            -- distance only for straight swipes; otherwise retain the last pan.
            if ges.direction == "east" or ges.direction == "west" then
                local sign = ges.direction == "east" and 1 or -1
                pos = { x = ges.pos.x + sign * (ges.distance or 0) }
            end
        end
        self:_finishDrag(pos)
    end
    return true
end

FlatScreen.onHold = FlatScreen.onPan
FlatScreen.onHoldPan = FlatScreen.onPan
FlatScreen.onHoldRelease = FlatScreen.onPanRelease
FlatScreen.onMultiSwipe = FlatScreen.onSwipe

function FlatScreen:_restoreState()
    if self.restored then return end
    self.restored = true

    if Screen.night_mode ~= self.original_night_mode then
        Screen:toggleNightMode()
        -- Also refresh when KOReader closes the widget outside the Exit path.
        UIManager:setDirty(nil, "full")
    end

    if PowerD.setIntensity and self.original_intensity ~= nil then
        pcall(PowerD.setIntensity, PowerD, self.original_intensity)
    end

    if self.standby_prevented and UIManager.allowStandby then
        UIManager:allowStandby()
        self.standby_prevented = false
    end
end

function FlatScreen:_exit()
    self:_restoreState()
    -- Refresh the entire display after repainting the widgets beneath the panel.
    UIManager:close(self, "full")
end

function FlatScreen:onClose()
    self:_exit()
    return true
end

function FlatScreen:onCloseWidget()
    self:_restoreState()
    if self.exit_text then self.exit_text:free() end
    if self.percent_text then self.percent_text:free() end
end

function FlatScreen:paintTo(bb, x, y)
    -- The entire framebuffer is intentionally pure white except for the tiny
    -- control strip at the top edge.
    bb:paintRect(x, y, self.screen_w, self.screen_h, Blitbuffer.COLOR_WHITE)
    self:_paintToolbar(bb, x, y)
end

function FlatScreen:_paintToolbar(bb, x, y)
    bb:paintRect(x, y, self.screen_w, self.toolbar_h, Blitbuffer.COLOR_WHITE)

    local ex = x + self.exit_rect.x
    local ey = y + self.exit_rect.y
    bb:paintRoundedRect(ex, ey, self.exit_rect.w, self.exit_rect.h,
        Blitbuffer.COLOR_BLACK, math.floor(self.control_h / 2))

    local exit_size = self.exit_text:getSize()
    self.exit_text:paintTo(
        bb,
        ex + math.floor((self.exit_rect.w - exit_size.w) / 2),
        ey + math.floor((self.exit_rect.h - exit_size.h) / 2)
    )

    local track_y = y + self.slider_y - math.floor(self.track_h / 2)
    bb:paintRoundedRect(
        x + self.slider_x1,
        track_y,
        self.slider_x2 - self.slider_x1,
        self.track_h,
        Blitbuffer.COLOR_BLACK,
        math.floor(self.track_h / 2)
    )

    local knob_x = self:_knobX()
    if knob_x > self.slider_x1 then
        bb:paintRoundedRect(x + self.slider_x1,
            y + self.slider_y - math.floor(self.fill_h / 2),
            knob_x - self.slider_x1, self.fill_h, Blitbuffer.COLOR_BLACK,
            math.floor(self.fill_h / 2))
    end
    bb:paintCircle(x + knob_x, y + self.slider_y, self.knob_radius, Blitbuffer.COLOR_WHITE)
    bb:paintCircle(x + knob_x, y + self.slider_y,
        self.knob_radius - self.border, Blitbuffer.COLOR_BLACK)

    local pct_size = self.percent_text:getSize()
    local pct_x = x + self.screen_w - self.margin - pct_size.w
    local pct_y = y + math.floor((self.toolbar_h - pct_size.h) / 2)
    self.percent_text:paintTo(bb, pct_x, pct_y)
end

local FlatField = WidgetContainer:extend{
    name = "flatfield",
    is_doc_only = false,
}

function FlatField:init()
    self.ui.menu:registerToMainMenu(self)
end

function FlatField:addToMainMenu(menu_items)
    menu_items.flatfield = {
        text = _("Flat field panel"),
        sorting_hint = "more_tools",
        callback = function()
            self:openFlatField()
        end,
    }
end

function FlatField:openFlatField()
    if not Device:hasFrontlight() then
        UIManager:show(InfoMessage:new{
            text = _("This device does not report a controllable frontlight."),
        })
        return
    end

    local flat_screen = FlatScreen:new{}

    -- Anti-ghosting pass #1: force every pixel dark and perform a full e-ink refresh.
    -- This follows the same basic black/restore approach KOReader uses for its
    -- optional screensaver anti-ghosting flashes.
    Screen.bb:fill(Blitbuffer.COLOR_BLACK)
    Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

    -- Anti-ghosting pass #2: paint the final white panel and perform a full refresh.
    UIManager:show(flat_screen)
    UIManager:setDirty(flat_screen, "full")
    UIManager:forceRePaint()
end

return FlatField
