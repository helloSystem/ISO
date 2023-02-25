local core = require("core")
local screen = require("screen")

KEY_LOWER_V = 118
KEY_UPPER_V = 86
KEY_LOWER_S = 115
KEY_UPPER_S = 83

-- Move the cursor out of view
screen.setcursor(1, 70)

-- Fill whole screen with white, even though
-- we have redefined what white actually means by using bootloader variables
if core.isFramebufferConsole() then
    local width = loader.getenv("screen.width") or 640
    local height = loader.getenv("screen.height") or 480
    loader.fb_drawrect(0, 0, width, height, 1)
end

local shouldboot = true

local endtime = loader.time() + 3
local time
local last

repeat
    time = endtime - loader.time()

    if last == nil or last ~= time then
        last = time
    end

    if io.ischar() then
        local ch = io.getchar()

        if ch == core.KEY_ENTER then
            core.setSingleUser(false)
            core.boot()
            break
        end

        if ch == core.KEY_BACKSPACE or ch == core.KEY_DELETE then
            loader.setenv("beastie_disable", "NO")
            loader.setenv("loader_logo", "none")
            loader.setenv("loader_brand", "none")
            loader.setenv("autoboot_delay", "NO")
            shouldboot = false
            break
        end

        if ch == KEY_LOWER_S or ch == KEY_UPPER_S then
            printc("Single user boot")
            core.setSingleUser(true)
            loader.unsetenv("boot_mute")
            loader.setenv("kern.vt.color.15.rgb", "0,0,0")
            loader.setenv("kern.vt.color.7.rgb", "0,0,0")
            core.boot()
            break
        end

        if ch == KEY_LOWER_V or ch == KEY_UPPER_V then
            printc("Verbose boot")
            loader.unsetenv("boot_mute")
            core.setVerbose(true)
            loader.setenv("kern.vt.color.15.rgb", "0,0,0")
            loader.setenv("kern.vt.color.7.rgb", "0,0,0")
            core.boot()
            break
        end
    end

    loader.delay(50000)
until time <= 0

if shouldboot == true then
    if core.isFramebufferConsole() then
        -- Set fg and bg color to white, because we have painted a white background
        -- on the whole screen earlier. This way the background of the screen
        -- and the background of the text are the same color, even though
        -- we have redefined what white actually means by using bootloader variables
        printc(core.KEYSTR_CSI .. "3" .. "7" .. "m")
        printc(core.KEYSTR_CSI .. "4" .. "7" .. "m")
        -- Make the cursor (black rectangle) invisible
        -- screen.setcursor(70, 70)
    end
    core.boot()
end
