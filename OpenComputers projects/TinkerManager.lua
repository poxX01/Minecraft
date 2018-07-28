component = require ("component")
computer = require ("computer")
term = require ("term")
event = require ("event")

local programName = "TinkerManager"
local version = "v0.1"
local sides = {{5, "+x", "east"}, {4, "-x", "west"}, {1, "+y", "up"}, {0, "-y", "down"}, {3, "+z", "south"}, {2, "-z", "north",}}
local gpu = component.gpu
local tsmelt, ttank, tp, bufferCastTankStats, rsIO = false, false, false, false, false
local tsmeltSide, ttankSide, castSide = false, false, false

--prints input:string, number or table. specified table has to contain table in following format: {{string[, color]}, {number[, color]}...}. default color is white(0xFFFFFF
function write(input, newLine)
    if type(input) == "table" then
        local originalColor = gpu.getForeground();
        for v in pairs(input) do
            local color = input[v][2] or 0xFFFFFF
            gpu.setForeground(color);
            term.write(input[v][1]);
        end
        gpu.setForeground(originalColor);
    else
        term.write(input);
    end
    if newLine then term.write("\n") end
end

--shuts down the computer after emitting 3 beeps in descending frequency, asks to reboot if askReboot:bool is true
function shutdown(askReboot)
    local doReboot = false
    if askReboot then
        write({{"\nThe system will now "}, {"shut down", 0xFF0000}, {". Do you wish to "}, {"reboot ", 0x00FF00}, {"instead? ("}, {"Y", 0x00FF00}, {"/"}, {"N", 0xFF0000}, {")"}}, true)
        local input = io.read()
        doReboot = input == "Y" or input == "y"
    end
    computer.beep(1200); computer.beep(1000); computer.beep(800)
    computer.shutdown(doReboot)
end

--detects and assigns components smeltery controller, tank controller and transposer and transposer's connection to component fluid tank entitities, initiates shut down otherwise after printing errors
function boot()
    local unfulfilledEssentialProperties = {}
    local unfulfilledOptionalProperties = {}
    computer.beep(1600); computer.beep(1800); computer.beep(2000)
    write("Booting "..programName.." "..version.." ...", true)
    if component.isAvailable("smeltery") and component.smeltery.getCapacity() ~= 0 then
        tsmelt = component.smeltery
        write({{"Smeltery controller and valid smeltery structure have been detected.", 0x00FF00}}, true)
    else
        write({{"Smeltery controller and valid smeltery structure have not been detected.", 0xFF0000}}, true)
        table.insert(unfulfilledEssentialProperties, "This computer is connected to an adapter neighbouring a smeltery controller that is part of a valid smeltery structure.")
    end
    if component.isAvailable("tinker_tank") and component.tinker_tank.getCapacity() ~= 32000 then --32000 because that's somehow its default (probably a bug)
        ttank = component.tinker_tank
        write({{"Tank controller and valid Tinker tank structure have been detected.", 0x00FF00}}, true)
    else
        write({{"Tank controller and valid Tinker tank structure have not been detected.", 0xFFFF00}}, true)
        table.insert(unfulfilledOptionalProperties, "This computer is connected to a tank controller and valid Tinker tank structure.")
    end
    --Check transposer connection and its access to neighbouring fluid tanks
    if component.isAvailable("transposer") then
        tp = component.transposer
        write({{"Transposer has been detected.", 0x00FF00}}, true)
        if component.isAvailable("smeltery") and component.smeltery.getCapacity() ~= 0 then
            local smelteryCapacity = tsmelt.getCapacity()
            local canConnect = false
            for v in pairs(sides) do
                if tp.getTankCapacity(sides[v][1]) == smelteryCapacity then
                    canConnect = true
                    tsmeltSide = sides[v][1]
                    break
                end
            end
            if canConnect then write({{"Transposer access to smeltery has been detected.", 0x00FF00}}, true)
            else
                write({{"Transposer access to smeltery has not been detected.", 0xFF0000}}, true)
                table.insert(unfulfilledEssentialProperties, "Connected transposer is adjacent to a drain that is part of the valid smeltery structure.")
            end
        end
        if component.isAvailable("tinker_tank") and component.tinker_tank.getCapacity() ~= 32000 then --32k because that's somehow its default (probably a bug)
            local ttankCapacity = ttank.getCapacity()
            local canConnect = false
            for v in pairs(sides) do
                if tp.getTankCapacity(sides[v][1]) == ttankCapacity then
                    canConnect = true
                    ttankSide = sides[v][1]
                    break
                end
            end
            if canConnect then write({{"Transposer access to Tinker tank has been detected.", 0x00FF00}}, true)
            else
                write({{"Transposer access to Tinker tank has not been detected.", 0xFF0000}}, true)
                table.insert(unfulfilledEssentialProperties, "Connected transposer is adjacent to a drain that is part of the valid Tinker tank structure.")
            end
        end
        for v in pairs(sides) do
            local tankName = tp.getInventoryName(sides[v][1])
            local tankCapacity = tp.getTankCapacity(sides[v][1])
            if tankName and tankCapacity ~= 0 then
                bufferCastTankStats = {tankName, tankCapacity }
                castSide = sides[v][1]
            end
        end
        if bufferCastTankStats then write({{"Transposer access to buffer casting tank has been detected. [ID: "..bufferCastTankStats[1].."     Capacity: "..bufferCastTankStats[2].."mb]", 0x00FF00}}, true)
        else
            write({{"Transposer access to buffer casting tank has not been detected.", 0xFF0000}}, true)
            table.insert(unfulfilledEssentialProperties, "A regular fluid tank is neighbouring connected transposer.")
        end
    else
        write({{"Transposer has not been detected.", 0xFF0000}}, true)
        table.insert(unfulfilledEssentialProperties, "This computer is connected to a transposer.")
    end
    if component.isAvailable("redstone") then
        rsIO = component.redstone
        write({{"Redstone I/O component has been detected.", 0x00FF00}}, true)
    else
        write({{"Redstone I/O component has not been detected.", 0xFFFF00}}, true)
        table.insert(unfulfilledOptionalProperties, "This computer is connected to a redstone I/O block.")
    end
    --If essential properties havn't been fulfilled, list them and initiate shutdown
    if #unfulfilledEssentialProperties ~= 0 then
        local essentialPropertyList = ""
        local optionalPropertyList = ""
        for v in pairs(unfulfilledEssentialProperties)  do
            essentialPropertyList = essentialPropertyList.."\n\t- "..unfulfilledEssentialProperties[v]
        end
        for v in pairs(unfulfilledOptionalProperties)  do
            optionalPropertyList = optionalPropertyList.."\n\t- "..unfulfilledOptionalProperties[v]
        end
        write({{"\nBooting has failed. ", 0xFF6D00}, {"Essential ", 0xFF0000}, {"properties havn't been fulfilled:", 0xFF6D00}, {essentialPropertyList, 0xFF0000}, {optionalPropertyList, 0xFFFF00}}, true)
        shutdown(true)
    --If optional properties remain unfulfilled, list them and ask whether to continue or initiate shutdown
    elseif #unfulfilledOptionalProperties ~= 0 then
        local optionalPropertyList = ""
        for v in pairs(unfulfilledOptionalProperties)  do
            optionalPropertyList = optionalPropertyList.."\n\t- "..unfulfilledOptionalProperties[v]
        end
        write({{"\nBooting has succeeded. ", 0x00FF00}, {"However, ", 0xFF6D00}, {"optional ", 0xFFFF00}, {"properties havn't been fulfilled:", 0xFF6D00}, {optionalPropertyList, 0xFFFF00}}, true)
        write({{"\nDo you wish to "}, {"continue", 0x00FF00}, {"? ("}, {"Y", 0x00FF00}, {"/"}, {"N", 0xFF0000}, {")"}}, true)
        local input = io.read()
        if input ~= "y" and input ~= "Y" then shutdown(true) end
    else write({{"\nBooting has succeeded.", 0x00FF00}}, true)
    end
end

--Initializes redstone I/O block (rsIO) via user input
function Initialize()
    write({{"Initializing redstone I/O..."}}, true)
    write({{"Input "}})
end

--Program
term.clear()
boot()
if rsIO then Initialize() end
