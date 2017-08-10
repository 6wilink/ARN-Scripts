-- by Qige <qigezhao@gmail.com>
-- 2017.08.10

--local DBG = print
local function DBG(msg) end

local vint = tonumber
local sfmt = string.format

local uhf = {}

--[[
FIXME: 
    1. Suitable for UHF, but wrong in VHF
Tasks: 
    1. frequency to region/channel number
Frequency Formular:
    Region 0: 14 - 473, f = 470 + 6 * (0.5 + ch - 14)
    Region 1: 21 - 474, f = 470 + 8 * (0.5 + ch - 21)
]]--
function uhf.freq_to_channel(region, freq)
    DBG(sfmt("--------> (FIXME) freq_to_channel(UHF r=%s, f=%s)", region or '-', freq or '-'))
    local i, channel
    local f = vint(freq or 0)

    if (region > 0) then
        channel = 21
        for i=474,f+8,8 do
            if (i >= f) then break end
            channel = channel + 1
        end
    else
        channel = 14
        for i=473,f+6,6 do
            if (i >= f) then break end
            channel = channel + 1
        end
    end
    DBG(sfmt("--------+ Calculate channel number (%s)", channel))
    return channel
end

--[[
FIXME: 
    1. Suitable for UHF, but wrong in VHF
Frequency formular
    Region 0: f = 473 + (ch - 14) * 6
    Region 1: f = 474 + (ch - 21) * 8
]]--
function uhf.channel_to_freq(region, channel)
    DBG(sfmt("--------> (FIXME) channel_to_freq(UHF r=%s, c=%s)", region, channel))
    local freq = 470
    if (region > 0) then
        freq = freq + (0.5 + channel - 21) * 8
    else
        freq = freq + (0.5 + channel - 14) * 6
    end
    return freq
end

return uhf
