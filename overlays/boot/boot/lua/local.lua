local core = require("core")
local screen = require("screen")

-- loader.* functions are not part of normal lua, where are they documented?
-- Just look at the other lua files for "documentation"

screen.clear()
screen.defcursor()

KEY_LOWER_V = 118
KEY_UPPER_V = 86
KEY_LOWER_S = 115
KEY_UPPER_S = 83

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
    -- Set black font so that we don't see the messages while the kernel is being loaded
    printc(core.KEYSTR_CSI .. "3" .. "0" .. "m")
    core.boot()
end
