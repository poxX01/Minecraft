local component = require ("component")
local computer = require ("computer")
local term = require ("term")
local event = require ("event")

local programName, version = "TinkerManager", "v0.1"
local sides = {{5, "+x", "east"}, {4, "-x", "west"}, {1, "+y", "up"}, {0, "-y", "down"}, {3, "+z", "south"}, {2, "-z", "north",}}
local gpu, screen = component.gpu, component.screen
local tsmelt, ttank, tp, bufferCastTankStats, rsIO
local tsmeltSide, ttankSide, castSide
--local rsBlockCast1, rsBlockCast2, rsIngotCast, rsNuggetCast
local allowConfirm = false
local rsCastSides = {} --- just an array, but index order is rsBlockCast1, rsBlockCast2, rsIngotCast, rsNuggetCast and values stored are the assigned sides
local rsInitializeFields = {}
local rsInitializeColorTable = {0x00B6C0, 0x0049C0, 0xFFB600, 0xFF4900}
local globalColors = {inactiveGrey = 0x3C3C3C, inactiveGreyHeader = 0x4B4B4B, borderGrey = 0xA5A5A5, foregroundGrey = 0xC3C3C3 }
local currentRSIOconfig = {} --will have to be read from a file in the future, check out IO and filesystem liberaries
local alloyDictionary = {
    {output={"Aluminum Brass", 2},      ingredient1={"Aluminum", 3},    ingredient2={"Copper", 1}},
    {output={"Brass", 2},               ingredient1={"Copper", 2},      ingredient2={"Zinc", 1}},
    {output={"Bronze", 2},              ingredient1={"Copper", 3},      ingredient2={"Tin", 1}},
    {output={"Constantan", 2},          ingredient1={"Copper", 1},      ingredient2={"Nickel", 1}},
    {output={"Electrum", 2},            ingredient1={"Gold", 3},        ingredient2={"Silver", 1}},
    {output={"Fluxed Electrum", 144},   ingredient1={"Electrum", 144},  ingredient2={"Dest. Redstone", 500}},
    {output={"Invar", 3},               ingredient1={"Iron", 2},        ingredient2={"Nickel", 1}},
    {output={"Manyullyn", 2},           ingredient1={"Cobalt", 2},      ingredient2={"Ardite", 2}},
    {output={"Obsidian", 36},           ingredient1={"Water", 125},     ingredient2={"Lava", 125}},
    {output={"Osmiridium", 2},          ingredient1={"Osmium", 1},      ingredient2={"Iridium", 1}},
    {output={"Redmetal", 144},          ingredient1={"Iron", 144},      ingredient2={"Dest. Redstone", 400}},
    {output={"Alumite", 3},             ingredient1={"Aluminum", 5},    ingredient2={"Iron", 2},                ingredient3={"Obsidian", 2}},
    {output={"Clay", 144},              ingredient1={"Water", 250},     ingredient2={"Liquid Dirt", 144},       ingredient3={"Seared Stone", 72}},
    {output={"Enderium", 144},          ingredient1={"Lead", 108},      ingredient2={"Platinum", 36},           ingredient3={"Resonant Ender", 250}},
    {output={"Knightslime", 72},        ingredient1={"Iron", 72},       ingredient2={"L. Purple Slime", 125},   ingredient3={"Seared Stone", 144}},
    {output={"Lumium", 144},            ingredient1={"Tin", 108},       ingredient2={"Silver", 36},             ingredient3={"Energ. Glowstone", 250}},
    {output={"Osgloglas", 1},           ingredient1={"Osmium", 1},      ingredient2={"Ref. Obsidian", 1},       ingredient3={"Ref. Glowstone", 1}},
    {output={"Pigiron", 144},           ingredient1={"Iron", 144},      ingredient2={"Blood", 40},              ingredient3={"Clay", 72}},
    {output={"Signalum", 144},          ingredient1={"Copper", 108},    ingredient2={"Silver", 36},             ingredient3={"Dest. Redstone", 250}}}
--{output={"Mirion", 1},              ingredient1={"Terrasteel", 18}, ingredient2={"Manasteel", 18},          ingredient3={"Elementium", 18},         ingredient4={"Cobalt", 18}, ingredient5={"Liquid Glass", 125}}

---prints input:string, number or table. specified table has to contain table in following format: {{string[, color]}, {number[, color]}...}. default color is white(0xFFFFFF
function write(input, newLine)
    if type(input) == "table" then
        local originalColor = gpu.getForeground()
        for v in pairs(input) do
            local color = input[v][2] or 0xFFFFFF
            gpu.setForeground(color)
            term.write(input[v][1])
        end
        gpu.setForeground(originalColor)
    else
        term.write(input)
    end
    if newLine then term.write("\n") end
end

---returns evaluated result as bool if boolReturn:boolean is true, otherwise returns input of user input with specified allowedInput: table, repeats until valid input if continuous: boolean is true.
---informs of invalid input if notSilent:boolean is true
function evaluateInput(allowedInput, boolReturn, notSilent, continuous)
    local input = io.read()
    for v in pairs(allowedInput) do
        if input == allowedInput[v] then
            if boolReturn then return true
            else return input end
        end
    end
    if notSilent then write({{"Invalid Input.", 0xFF0000}}) end
    if continuous then
        write({{" Retry.", 0xFF0000}})
        evaluateInput(boolReturn, allowedInput, notSilent, continuous)
    end
end

---shuts down the computer after emitting 3 beeps in descending frequency, asks to reboot if askReboot:bool is true
function shutdown(askReboot)
    local doReboot = false
    if askReboot then
        write({{"\nThe system will now "}, {"shut down", 0xFF0000}, {". Do you wish to "}, {"reboot ", 0x00FF00}, {"instead? ("}, {"Y", 0x00FF00}, {"/"}, {"N", 0xFF0000}, {")"}}, true)
        doReboot = evaluateInput({"Y", "y"}, true)
    end
    computer.beep(1200); computer.beep(1000); computer.beep(800)
    computer.shutdown(doReboot)
end

---compares table:table for duplicate values. returns true if a duplicate has been found, otherwise returns false.
function checkForDuplicates(table)
    for n1=1, #table-1 do
        for n2=n1, #table-1 do
            if table[n1] == table[n2+1] then return true end
        end
    end
    return false
end
---determines color contrast, returns black on bright foreground, otherwise returns white
function contrastForeground(backgroundColor)
    local function tohex(num)
        local charset = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
        local tmp = {}
        repeat
            table.insert(tmp,1,charset[num%16+1])
            num = math.floor(num/16)
        until num==0
        while #tmp < 6 do table.insert(tmp, 1, 0) end
        return table.concat(tmp)
    end
    backgroundColor = tohex(backgroundColor)
    local rgb = {tonumber("0x"..backgroundColor:sub(1,2)), tonumber("0x"..backgroundColor:sub(3,4)), tonumber("0x"..backgroundColor:sub(5,6))}
    for k, v in pairs(rgb) do
        v = v / 255.0
        if v <= 0.03928 then rgb[k] = v/12.92 else rgb[k] = ((v+0.055)/1.055)^2.4 end
    end
    local L = 0.2126 * rgb[1] + 0.7152 * rgb[2] + 0.0722 * rgb[3]
    if L > 0.179 then return 0x000000 else return 0xFFFFFF end
end
---detects and assigns components smeltery controller, tank controller and transposer and transposer's connection to component fluid tank entitities, initiates shut down otherwise after printing errors
function boot()
    term.clear()
    gpu.setResolution(160, 50)
    screen.turnOn()
    screen.setTouchModeInverted(true)
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
    ---Check transposer connection and its access to neighbouring fluid tanks
    if component.isAvailable("transposer") then
        tp = component.transposer
        write({{"Transposer has been detected.", 0x00FF00}}, true)
        if component.isAvailable("smeltery") and component.smeltery.getCapacity() ~= 0 then
            local smelteryCapacity = tsmelt.getCapacity()
            local canConnect = false
            for i in pairs(sides) do
                if tp.getTankCapacity(sides[i][1]) == smelteryCapacity then
                    canConnect = true
                    tsmeltSide = sides[i][1]
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
            for i in pairs(sides) do
                if tp.getTankCapacity(sides[i][1]) == ttankCapacity then
                    canConnect = true
                    ttankSide = sides[i][1]
                    break
                end
            end
            if canConnect then write({{"Transposer access to Tinker tank has been detected.", 0x00FF00}}, true)
            else
                write({{"Transposer access to Tinker tank has not been detected.", 0xFF0000}}, true)
                table.insert(unfulfilledEssentialProperties, "Connected transposer is adjacent to a drain that is part of the valid Tinker tank structure.")
            end
        end
        for i in pairs(sides) do
            local tankName = tp.getInventoryName(sides[i][1])
            local tankCapacity = tp.getTankCapacity(sides[i][1])
            if tankName and tankCapacity ~= 0 then
                bufferCastTankStats = {tankName, tankCapacity }
                castSide = sides[i][1]
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
    ---If essential properties havn't been fulfilled, list them and initiate shutdown
    if #unfulfilledEssentialProperties ~= 0 then
        local essentialPropertyList = ""
        local optionalPropertyList = ""
        for i in pairs(unfulfilledEssentialProperties)  do
            essentialPropertyList = essentialPropertyList.."\n\t- "..unfulfilledEssentialProperties[i]
        end
        for i in pairs(unfulfilledOptionalProperties)  do
            optionalPropertyList = optionalPropertyList.."\n\t- "..unfulfilledOptionalProperties[i]
        end
        write({{"\nBooting has failed. ", 0xFF6D00}, {"Essential ", 0xFF0000}, {"properties havn't been fulfilled:", 0xFF6D00}, {essentialPropertyList, 0xFF0000}, {optionalPropertyList, 0xFFFF00}}, true)
        shutdown(true)
        ---If optional properties remain unfulfilled, list them and ask whether to continue or initiate shutdown
    elseif #unfulfilledOptionalProperties ~= 0 then
        local optionalPropertyList = ""
        for i in pairs(unfulfilledOptionalProperties)  do
            optionalPropertyList = optionalPropertyList.."\n\t- "..unfulfilledOptionalProperties[i]
        end
        write({{"\nBooting has succeeded. ", 0x00FF00}, {"However, ", 0xFF6D00}, {"optional ", 0xFFFF00}, {"properties havn't been fulfilled:", 0xFF6D00}, {optionalPropertyList, 0xFFFF00}}, true)
        write({{"\nDo you wish to "}, {"continue", 0x00FF00}, {"? ("}, {"Y", 0x00FF00}, {"/"}, {"N", 0xFF0000}, {")"}}, true)
        if not evaluateInput({"Y", "y"}, true) then shutdown(true) end
    else write({{"\nBooting has succeeded.", 0x00FF00}}, true)
    end
end

---returns point at which str:string should start given the startX:int coordinate to be formatted into the middle of width:int
function centerString(str, startX, width)
    local starterX = startX + math.floor((width - string.len(str)) / 2)
    return starterX
end
---returns input x:integer rounded to the nearest natural number (1 decimal precision)
function round(x)
    local out
    if x%1 < 0.5 then out = math.floor(x); return out end
    out = math.ceil(x); return out
end

---if addEvent:boolean is true, adds a rectangle with all of its corner points (minX:int, maxX:int ...) and the related action:function to the table registeredTouchZones, otherwise clears the entire table
local registeredTouchZones = {}
function touchZoneConstructor(reset, minX, maxX, minY, maxY, action, ...)
    if not reset then table.insert(registeredTouchZones, {minX=minX, maxX=maxX, minY=minY, maxY=maxY, action=action, args={...}})
    else registeredTouchZones = {} end
end

---handles passed touch event by the listener by comparing clicked x and y coordinates to be within anything clickable specified by table registeredTouchZones
function touchEventHandler(type, _, x, y)
    if type == "touch" then
        for v in pairs(registeredTouchZones) do
            if x >= registeredTouchZones[v].minX and x <= registeredTouchZones[v].maxX and y >= registeredTouchZones[v].minY and y <= registeredTouchZones[v].maxY then
                registeredTouchZones[v].action(table.unpack(registeredTouchZones[v].args))
                break
            end
        end
    end
end
drawLibrary = {
    ---draws button architecture at start location x:int, y:int with width:int, and fills out the middle part with the header:string. registers button area as an action:function with params ... as long as inactive:boolean is false, will otherwise grey out
    ---the button
    drawButton = function(x, y, width, header, inactive, action, ...)
        local colors
        if inactive then colors = {globalColors.inactiveGrey, globalColors.inactiveGrey, globalColors.inactiveGreyHeader, 0x000000}
        else colors = {0xA5A5A5, 0xC3C3C3, 0xFFFFFF, 0x3C3C3C} end
        if action then touchZoneConstructor(false, x, x+width-1, y, y+2, action, ...) end
        gpu.setForeground(colors[1])
        gpu.fill(x, y, width, 1, "▄")
        gpu.set(x, y+1, "█")
        gpu.fill(x, y+2, width, 1, "▀")
        gpu.setForeground(colors[2])
        gpu.fill(x+width-3, y, 3, 1, "▄")
        gpu.set(x+width-1, y+1, "█")
        gpu.setForeground(colors[3])
        gpu.setBackground(colors[4])
        gpu.fill(x+1, y+1, width-2, 1, " ")
        gpu.set(centerString(header, x+1, width-1), y+1, header)
    end,
    ---draws underlined headline:str at x, y and if inactive, greys out whole text [[deprecated for now]]
    drawHeader = function(x, y, str, inactive)
        if inactive then gpu.setForeground(globalColors.inactiveGreyHeader) end
        gpu.set(x, y, str)
        gpu.set(x, y+1, string.rep("¯", #str))
    end,
    ---draws border at x, y with width, height in [color]
    drawBorder = function(x, y, width, height, color)
        if color then gpu.setForeground(color) end
        gpu.set(x, y, string.rep("▄", width))
        gpu.set(x, y+1, string.rep("█", height-2), true)
        gpu.set(x+width-1, y+1, string.rep("█", height-2), true)
        gpu.set(x, y+height-1, string.rep("▀", width))
    end,
    ---draws a vertical fraction at x,y, with width and puts unit:string at the end of both numbers
    drawVerticalFraction = function(x, y, width, unit)
        gpu.set(x+width, y, unit)
        gpu.set(x, y+1, string.rep("─", width+#unit))
        gpu.set(x+width, y+2, unit)
    end,
    drawParentBox = function(x, y, width, stepsUntilNextCross)
        local verticalStr = ""
        local currentY = y
        for v in pairs(stepsUntilNextCross) do
            verticalStr = verticalStr .. string.rep("║", stepsUntilNextCross[v]) .. "╟"
            currentY = currentY + stepsUntilNextCross[v] + 1
            gpu.set(x+1, currentY, string.rep("─", width-2))
        end
        local verticalStrInv = verticalStr:gsub("╟", "╢")
        gpu.set(x, y, "╔"..string.rep("═", width-2).."╗")
        gpu.set(x, y+1, verticalStr, true)
        gpu.set(x+width-1, y+1, verticalStrInv, true)
        gpu.set(x, currentY, "╚"..string.rep("═", width-2).."╝")
    end,
    ---draws 21 width progress bar of value:int to valueMax:int at x,y in a gradient from red to green (or green to red if invertColors:bool is true) if monocolor is nil, otherwise draws whole progress bar in singular specified color
    drawPercentageBar = function(x,y, valueCurrent, valueMax, invertColors, monocolor)
        local percentage = tostring(math.abs(round(valueCurrent / valueMax * 100))).."%"
        local bars = math.floor(round(valueCurrent / valueMax * 100)/5) + 1
        local colors = {0xFF0000, 0xFF6D00, 0xFF9200, 0xFFB600, 0xFFDB00, 0xFFFF00, 0xCCFF00, 0x99FF00, 0x66FF00, 0x33FF00, 0x00FF00 }
        local color = monocolor
        if not monocolor then
            if not invertColors then color = colors[math.ceil(bars/2)]
            else color = colors[12-math.ceil(bars/2)] end
        end
        gpu.fill(x, y, 21, 1, " ")
        gpu.setForeground(color)
        gpu.set(x, y, string.rep("█", bars))
        local strTable = {}
        for i = 1, #percentage, 1 do table.insert(strTable, percentage:sub(i, i)) end
        gpu.setForeground(0xD2D2D2)
        for i = 1, #strTable, 1 do
            if bars-centerString(percentage, x, 21)+x-i+1 >= 0 then gpu.setBackground(color)
            else gpu.setBackground(0x000000) end
            gpu.set(centerString(percentage, x, 21)+i-1, y, strTable[i])
        end
    end,
    ---fills screen space x,y,width,height with colorBackground. sets header:string in the middle of width and height with optional colorForeground, otherwise using globalColors.foregroundGrey
    drawBackgroundHeader= function(x, y, width, height, header, colorBackground, colorForeground)
        if not colorForeground then colorForeground = contrastForeground(colorBackground) end
        gpu.setForeground(colorForeground)
        gpu.setBackground(colorBackground)
        gpu.fill(x, y, width, height, " ")
        local whitespace1, whitespace2 = string.rep(" ", math.floor((width-#header)/2)), string.rep(" ", math.ceil((width-#header)/2))
        local str = whitespace1..header..whitespace2
        gpu.set(x, y+math.ceil(height/2)-1, str)
    end,
}
---draws item:function with parameters ... and then resets foreground and background colors to previous
function draw(item, x, y, ...)
    local originalForeground, originalBackground = gpu.getForeground(), gpu.getBackground()
    if type(item) == "function" then item(x, y, ...)
    elseif type(item) == "table" then
        local colors = {...}
        local currentX = x
        for i, v in  ipairs(item) do
            gpu.setForeground(colors[i])
            gpu.set(currentX, y, v)
            currentX = currentX + #v
        end
    else
        if ... then gpu.setForeground(...) end
        gpu.set(x, y, item)
    end
    gpu.setForeground(originalForeground); gpu.setBackground(originalBackground)
end

local startX, startY, width, height
pages = {
    mainMenu = function()
        startX, startY, width = 2, 1, 38
        local tsmeltCapacity = tostring(tsmelt.getCapacity()):sub(1, #tostring(tsmelt.getCapacity())-2)
        local tsmeltFuelMax = tostring(tsmelt.getFuelInfo().maxCap):sub(1, #tostring(tsmelt.getFuelInfo().maxCap)-2)
        local computerMaxEnergy = tostring(computer.maxEnergy()):sub(1, #tostring(computer.maxEnergy())-2)
        local ttankCapacity
        gpu.setResolution(2*width+4, 31)
        draw(drawLibrary.drawParentBox, startX, startY, width, {1, 4, 4, 2})
        gpu.set(centerString("SMELTERY", startX+1, width-2), startY+1, "SMELTERY")
        gpu.set(startX+1, startY+3, "Fill status")
        draw(drawLibrary.drawBorder, startX+1, startY+4, 23, 3, globalColors.borderGrey)
        draw(drawLibrary.drawVerticalFraction, startX+25, startY+4, #tsmeltCapacity, "mb")
        gpu.set(startX+25,startY+6, tsmeltCapacity)
        gpu.set(startX+1, startY+8, "Fuel remaining")
        draw(drawLibrary.drawBorder, startX+1, startY+9, 23, 3, globalColors.borderGrey)
        draw(drawLibrary.drawVerticalFraction, startX+25, startY+9, #tsmeltFuelMax, "mb")
        gpu.set(startX+25, startY+11, tsmeltFuelMax)
        gpu.set(startX+1, startY+13, "Operational status")
        draw(drawLibrary.drawButton, startX, startY+16, width, "Display alloy dictionary", false, actions.transitionPage, pages.alloyDictionary)
        startX = startX + width + 2
        draw(drawLibrary.drawParentBox, startX, startY, width, {1, 4})
        gpu.set(centerString("SYSTEM", startX+1, width-2), startY+1, "SYSTEM")
        gpu.set(startX+1, startY+3, "Energy status")
        draw(drawLibrary.drawBorder, startX+1, startY+4, 23, 3, globalColors.borderGrey)
        draw(drawLibrary.drawVerticalFraction, startX+25, startY+4, #computerMaxEnergy, "RF")
        gpu.set(startX+25, startY+6, computerMaxEnergy)
        draw(drawLibrary.drawButton, startX, startY+8, width, "Enter idle mode", false, actions.transitionPage, pages.idleScreen)
        draw(drawLibrary.drawButton, startX, startY+11, width, "Reinitialize Redstone I/O", not rsIO, actions.transitionPage, pages.initializeRS)
        startY = startY + 14
        local fractionWidth = 8
        local color = globalColors.borderGrey
        if not ttank then gpu.setForeground(globalColors.inactiveGrey); color = globalColors.inactiveGrey
        else ttankCapacity, fractionWidth = tostring(ttank.getCapacity()):sub(1, #tostring(ttank.getCapacity()-2)), #ttankCapacity end
        draw(drawLibrary.drawParentBox, startX, startY, width, {1, 4, 2})
        gpu.set(centerString("TINKER TANK", startX+1, width-2), startY+1, "TINKER TANK")
        gpu.set(startX+1, startY+3, "Fill status")
        draw(drawLibrary.drawBorder, startX+1, startY+4, 23, 3, color)
        draw(drawLibrary.drawVerticalFraction, startX+25, startY+4, fractionWidth, "mb")
        if ttank then gpu.set(startX+25, startY+6, tostring(ttank.getCapacity())) end
        gpu.set(startX+1, startY+8, "Operational status")
        gpu.setForeground(0xFFFFFF)
        draw(drawLibrary.drawButton, 2, startY+14, width, "Display/cast fluids", false, actions.transitionPage, pages.displayCastFluids)
        draw(drawLibrary.drawButton, startX, startY+14, width, "Forge alloys", not ttank, actions.transitionPage, pages.forgeAlloys)
        engageUpdateRoutine(updateRoutines.mainMenu)
    end,
    idleScreen = function()
        gpu.setResolution(40, 1)
        gpu.set(centerString("TOUCH TO RETURN TO MAIN MENU", 1, 40), 1, "TOUCH TO RETURN TO MAIN MENU")
        engageUpdateRoutine(updateRoutines.idleScreen, 2.5, 1)
    end,
    initializeRS = function(firstTime)
        startX, startY, width, height = 2, 1, 16, 6
        local resX = width*3+10
        local header
        ---draws a rectangle split in two using unicode characters. color:color determines foreground color for the first value of table:table. int1:int and int2:int are for denoting the side number assigned to the respective touch zone
        local function fabricateBox(fbstartX, fbstartY, fbwidth, table, string, color, int1, int2)
            draw(table, centerString(string, fbstartX, fbwidth), fbstartY, color, 0xFFFFFF)
            draw(drawLibrary.drawParentBox, fbstartX, fbstartY+1, fbwidth, {height, height})
            rsInitializeFields[int1+1] = {int1, fbstartX+1, fbstartY+2, fbwidth-2, height}
            rsInitializeFields[int2+1] = {int2, fbstartX+1, fbstartY+9, fbwidth-2, height}
            touchZoneConstructor(false, fbstartX+1, fbstartX+fbwidth-2, fbstartY+2, fbstartY+2+height, actions.initializeRS.fillField, false, int1+1, true)
            touchZoneConstructor(false, fbstartX+1, fbstartX+fbwidth-2, fbstartY+9, fbstartY+9+height, actions.initializeRS.fillField, false, int2+1, true)
        end
        gpu.setResolution(resX, 24)
        fabricateBox(startX, startY, width, {"x", "-axis"}, "x-axis", 0xFF0000, 5, 4)
        fabricateBox(startX+width+4, startY, width, {"y", "-axis"}, "y-axis", 0x00FF00, 1, 0)
        fabricateBox(startX+(width+4)*2, startY, width, {"z", "-axis"}, "z-axis", 0x0000FF, 3, 2)
        if firstTime then header = "Skip" else header = "Home" end
        if #rsCastSides == 0 then
            actions.initializeRS.fillField(true)
        else
            for k1 in pairs(rsInitializeFields) do
                for k2, v2 in pairs(rsCastSides) do
                    if rsInitializeFields[k1][1] == v2 then rsInitializeFields[k1][6] = k2; break end
                end
                actions.initializeRS.fillField(false, k1)
            end
        end
        gpu.set(startX, startY+17, "Casting row legend:")
        draw(drawLibrary.drawBackgroundHeader, startX, startY+18, math.floor(resX/2)-2, 1, "Block row 1-8", rsInitializeColorTable[1])
        draw(drawLibrary.drawBackgroundHeader, startX, startY+19, math.floor(resX/2)-2, 1, "Block row 9-16", rsInitializeColorTable[2])
        draw(drawLibrary.drawBackgroundHeader, startX+math.floor(resX/2), startY+18, math.floor(resX/2)-2, 1, "Ingot row", rsInitializeColorTable[3])
        draw(drawLibrary.drawBackgroundHeader, startX+math.floor(resX/2), startY+19, math.floor(resX/2)-2, 1, "Nugget row", rsInitializeColorTable[4])
        draw(drawLibrary.drawButton, startX, startY+21, width, "Reset", false, actions.initializeRS.fillField, true)
        draw(drawLibrary.drawButton, startX+width+4, startY+21, width, header, false, actions.transitionPage, pages.mainMenu)
        draw(drawLibrary.drawButton, startX+width*2+8, startY+21, width, "Confirm", true, actions.initializeRS.confirm)
        allowConfirm = false
        engageUpdateRoutine()
    end,
    alloyDictionary = function()
    
    end,
    displayCastFluids = function()
    
    end,
    forgeAlloys = function()
    
    end
}

updateRoutines = {
    mainMenu = function()
        local startX, startY, width = 2, 1, 38
        local tsmeltFill, tsmeltFillCap, tsmeltFuel, tsmeltFuelCap, compEnergy = tsmelt.getFillLevel() or 0, tsmelt.getCapacity(), tsmelt.getFuelLevel() or 0, 4000, round(computer.energy())
        draw(drawLibrary.drawPercentageBar, startX+2, startY+5, tsmeltFill, tsmeltFillCap, true)
        gpu.set(startX+25, startY+4, tostring(tsmeltFill))
        draw(drawLibrary.drawPercentageBar, startX+2, startY+10, tsmeltFuel, tsmeltFuelCap, false, 0xFF4900)
        gpu.set(startX+25, startY+9, tostring(tsmeltFuel))
        local status, color
        ---advanced featureset scrapped for now due to performance reasons and multiple inconsistencies (such as aluminum ore smelting without fuel, hasFuel() returning true even if fuel tanks are empty)
        if tsmeltFillCap == 0 then status, color = "INOPERABLE", 0xFF0000
        else status, color = "OPERABLE", 0x00FF00 end
        draw(drawLibrary.drawBackgroundHeader, startX+1, startY+14, width-2, 1, status, color)
        startX = startX + width + 2
        draw(drawLibrary.drawPercentageBar, startX+2, startY+5, compEnergy, computer.maxEnergy())
        gpu.set(startX+25, startY+4, tostring(compEnergy))
        if ttank then
            startY = startY + 14
            draw(drawLibrary.drawPercentageBar, startX+2, startY+5, ttank.getFillLevel() or 0, ttank.getCapacity(), true)
            if ttank.getCapacity() ~= 0 then status, color = "INOPERABLE", 0xFF0000
            else status, color = "OPERABLE", 0x00FF00 end
            draw(drawLibrary.drawBackgroundHeader, startX+1, startY+9, width-2, 1, status, color)
        end
    end,
    idleScreen = function()
        screen.turnOff()
        touchZoneConstructor(false, 1, 40, 1, 1, actions.transitionPage, pages.mainMenu)
    end,
}

local timerID
function engageUpdateRoutine(routine, interval, reruns)
    local i, r
    if interval and reruns then i, r = interval, reruns else i, r  = 0.5, math.huge end
    if routine then
        routine()
        timerID = event.timer(i, routine, r)
    end
    event.pullFiltered(touchEventHandler)
end

actions = {
    transitionPage = function(page, ...)
        touchZoneConstructor(true)
        if timerID then event.cancel(timerID) end
        term.clear()
        screen.turnOn()
        page(...)
    end,
    initializeRS = {
        fillField = function(reset, field, advance)
            local header
            if reset then
                for n=1, 6 do
                    if rsInitializeFields[n][1] % 2 == 0 then header = "negative" else header = "positive" end
                    draw(drawLibrary.drawBackgroundHeader, rsInitializeFields[n][2], rsInitializeFields[n][3], rsInitializeFields[n][4], rsInitializeFields[n][5], header, 0x000000)
                    table.remove(rsInitializeFields[n], 6)
                end
            else
                if advance then
                    if not rsInitializeFields[field][6] then rsInitializeFields[field][6] = 1
                    else
                        if rsInitializeFields[field][6] == 4 then table.remove(rsInitializeFields[field], 6)
                        else
                            rsInitializeFields[field][6] = rsInitializeFields[field][6]+1
                        end
                    end
                end
                if rsInitializeFields[field][6] then
                    draw(drawLibrary.drawBackgroundHeader, rsInitializeFields[field][2], rsInitializeFields[field][3], rsInitializeFields[field][4], rsInitializeFields[field][5], "", rsInitializeColorTable[rsInitializeFields[field][6]])
                else
                    if rsInitializeFields[field][1] % 2 == 0 then header = "negative" else header = "positive" end
                    draw(drawLibrary.drawBackgroundHeader, rsInitializeFields[field][2], rsInitializeFields[field][3], rsInitializeFields[field][4], rsInitializeFields[field][5], header, 0x000000)
                end
            end
            local t = {}
            for k in pairs(rsInitializeFields) do
                if rsInitializeFields[k][6] then table.insert(t, rsInitializeFields[k][6]) end
            end
            local duplicates = checkForDuplicates(t)
            if not allowConfirm and not duplicates and #t > 0 then
                allowConfirm = true
                draw(drawLibrary.drawButton, startX+width*2+8, startY+21, width, "Confirm", false)
            elseif allowConfirm and (duplicates or #t == 0) then
                allowConfirm = false
                draw(drawLibrary.drawButton, startX+width*2+8, startY+21, width, "Confirm", true)
            end
        end,
        confirm = function()
            if allowConfirm then
                for k in pairs(rsInitializeFields) do
                    if rsInitializeFields[k][6] then rsCastSides[rsInitializeFields[k][6]] = rsInitializeFields[k][1] end
                end
                actions.transitionPage(pages.mainMenu)
            end
        end
    }
}
--Program
boot()
if rsIO and #rsCastSides == 0 then actions.transitionPage(pages.initializeRS, true) ---need to read from and save configuration to external file, if that is empty or doesn't exist: do this first time initializeRS
else actions.transitionPage(pages.mainMenu) end
--[[necessary GUI elements: always have a confirm, cancel & back button
                            filler character: █,▌,▐,▀,▄,─
    should probably establish an event listener to listen for component removal/adding
]]
