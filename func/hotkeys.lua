local reframework = reframework

-- Mouse buttons
LBUTTON = 0x01
RBUTTON = 0x02
MBUTTON = 0x04
XBUTTON1 = 0x05
XBUTTON2 = 0x06

-- Control keys
CANCEL = 0x03
BACK = 0x08
TAB = 0x09
CLEAR = 0x0C
RETURN = 0x0D
SHIFT = 0x10
CONTROL = 0x11
MENU = 0x12
PAUSE = 0x13
CAPITAL = 0x14
ESCAPE = 0x1B
SPACE = 0x20

-- Navigation keys
PRIOR = 0x21
NEXT = 0x22
END = 0x23
HOME = 0x24
LEFT = 0x25
UP = 0x26
RIGHT = 0x27
DOWN = 0x28

-- Additional keys
SELECT = 0x29
PRINT = 0x2A
EXECUTE = 0x2B
SNAPSHOT = 0x2C
INSERT = 0x2D
DELETE = 0x2E
HELP = 0x2F

-- Number keys
NUM_0 = 0x30
NUM_1 = 0x31
NUM_2 = 0x32
NUM_3 = 0x33
NUM_4 = 0x34
NUM_5 = 0x35
NUM_6 = 0x36
NUM_7 = 0x37
NUM_8 = 0x38
NUM_9 = 0x39

-- Letter keys
A = 0x41
B = 0x42
C = 0x43
D = 0x44
E = 0x45
F = 0x46
G = 0x47
H = 0x48
I = 0x49
J = 0x4A
K = 0x4B
L = 0x4C
M = 0x4D
N = 0x4E
O = 0x4F
P = 0x50
Q = 0x51
R = 0x52
S = 0x53
T = 0x54
U = 0x55
V = 0x56
W = 0x57
X = 0x58
Y = 0x59
Z = 0x5A

-- Windows keys
LWIN = 0x5B
RWIN = 0x5C
APPS = 0x5D
SLEEP = 0x5F

-- Numpad keys
NUMPAD0 = 0x60
NUMPAD1 = 0x61
NUMPAD2 = 0x62
NUMPAD3 = 0x63
NUMPAD4 = 0x64
NUMPAD5 = 0x65
NUMPAD6 = 0x66
NUMPAD7 = 0x67
NUMPAD8 = 0x68
NUMPAD9 = 0x69
MULTIPLY = 0x6A
ADD = 0x6B
SEPARATOR = 0x6C
SUBTRACT = 0x6D
DECIMAL = 0x6E
DIVIDE = 0x6F

-- Function keys
F1 = 0x70
F2 = 0x71
F3 = 0x72
F4 = 0x73
F5 = 0x74
F6 = 0x75
F7 = 0x76
F8 = 0x77
F9 = 0x78
F10 = 0x79
F11 = 0x7A
F12 = 0x7B
F13 = 0x7C
F14 = 0x7D
F15 = 0x7E
F16 = 0x7F
F17 = 0x80
F18 = 0x81
F19 = 0x82
F20 = 0x83
F21 = 0x84
F22 = 0x85
F23 = 0x86
F24 = 0x87

-- Lock keys
NUMLOCK = 0x90
SCROLL = 0x91

-- Shift keys
LSHIFT = 0xA0
RSHIFT = 0xA1
LCONTROL = 0xA2
RCONTROL = 0xA3
LMENU = 0xA4
RMENU = 0xA5

-- Browser keys
BROWSER_BACK = 0xA6
BROWSER_FORWARD = 0xA7
BROWSER_REFRESH = 0xA8
BROWSER_STOP = 0xA9
BROWSER_SEARCH = 0xAA
BROWSER_FAVORITES = 0xAB
BROWSER_HOME = 0xAC

-- Volume keys
VOLUME_MUTE = 0xAD
VOLUME_DOWN = 0xAE
VOLUME_UP = 0xAF

-- Media keys
MEDIA_NEXT_TRACK = 0xB0
MEDIA_PREV_TRACK = 0xB1
MEDIA_STOP = 0xB2
MEDIA_PLAY_PAUSE = 0xB3

-- Application keys
LAUNCH_MAIL = 0xB4
LAUNCH_MEDIA_SELECT = 0xB5
LAUNCH_APP1 = 0xB6
LAUNCH_APP2 = 0xB7

-- OEM keys
OEM_1 = 0xBA      -- ;:
OEM_PLUS = 0xBB   -- =+
OEM_COMMA = 0xBC  -- 
OEM_MINUS = 0xBD  -- -_
OEM_PERIOD = 0xBE -- .>
OEM_2 = 0xBF      -- /?
OEM_3 = 0xC0      -- `~
OEM_4 = 0xDB      -- [{
OEM_5 = 0xDC      -- \|
OEM_6 = 0xDD      -- ]}
OEM_7 = 0xDE      -- '"
OEM_8 = 0xDF
OEM_102 = 0xE2

-- Special keys
PROCESSKEY = 0xE5
PACKET = 0xE7
ATTN = 0xF6
CRSEL = 0xF7
EXSEL = 0xF8
EREOF = 0xF9
PLAY = 0xFA
ZOOM = 0xFB
NONAME = 0xFC
PA1 = 0xFD
OEM_CLEAR = 0xFE

-- D-Pad
PAD_DPAD_UP = 0x5820
PAD_DPAD_DOWN = 0x5821
PAD_DPAD_LEFT = 0x5822
PAD_DPAD_RIGHT = 0x5823

-- Face Buttons
PAD_A = 0x5800
PAD_B = 0x5801
PAD_X = 0x5802
PAD_Y = 0x5803

-- Shoulder Buttons
PAD_LSHOULDER = 0x5804  -- Left bumper
PAD_RSHOULDER = 0x5805  -- Right bumper

-- Triggers
PAD_LTRIGGER = 0x5806
PAD_RTRIGGER = 0x5807

-- Special Buttons
PAD_START = 0x5808
PAD_BACK = 0x5809

-- Thumbstick Buttons
PAD_LTHUMB_PRESS = 0x580A  -- Left stick click
PAD_RTHUMB_PRESS = 0x580B  -- Right stick click

-- Left Thumbstick Directional
PAD_LTHUMB_UP = 0x5810
PAD_LTHUMB_DOWN = 0x5811
PAD_LTHUMB_RIGHT = 0x5812
PAD_LTHUMB_LEFT = 0x5813
PAD_LTHUMB_UPLEFT = 0x5814
PAD_LTHUMB_UPRIGHT = 0x5815
PAD_LTHUMB_DOWNRIGHT = 0x5816
PAD_LTHUMB_DOWNLEFT = 0x5817

-- Right Thumbstick Directional
PAD_RTHUMB_UP = 0x5830
PAD_RTHUMB_DOWN = 0x5831
PAD_RTHUMB_RIGHT = 0x5832
PAD_RTHUMB_LEFT = 0x5833
PAD_RTHUMB_UPLEFT = 0x5834
PAD_RTHUMB_UPRIGHT = 0x5835
PAD_RTHUMB_DOWNRIGHT = 0x5836
PAD_RTHUMB_DOWNLEFT = 0x5837

-- Try to get the REFramework object
local rf = reframework or re

if not rf then
    error("Could not find REFramework object (reframework or re)")
end

if not rf.is_key_down then
    error("REFramework object does not have is_key_down method")
end

local function hotkeys(keys, f, hold_mode)
    if not keys or #keys == 0 then return function() end end
    if type(f) ~= "function" then 
        -- Try to log, but if log is not available, use print
        if log and log.error then
            log.error("hotkey: second argument must be a function")
        else
            print("hotkey error: second argument must be a function")
        end
        return function() end 
    end
    
    local self = {}
    self.keys = keys
    self.f = f
    self.hold_mode = hold_mode or false
    self.was_pressed = false
    
    local function all_keys_pressed()
        for _, key in ipairs(self.keys) do
            if not rf:is_key_down(key) then 
                return false 
            end
        end
        return true
    end
    
    return function()
        local is_pressed = all_keys_pressed()
        
        if self.hold_mode then
            if is_pressed then 
                self.f() 
            end
        else
            if is_pressed and not self.was_pressed then 
                self.f() 
            end
        end
        
        self.was_pressed = is_pressed
    end
end

return hotkeys