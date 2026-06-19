-- [[
-- This is an example of using LuaJIT to create a custom animation in Ly, in this case
-- bouncing squares that change colors.
--
-- You are given the following `ly` table:
-- {
--	height: number -- The height of the terminal
--	width: number -- The width of the terminal
--	putCell(byte, fg, bg, x, y) -- Draw a cell. 
--      All arguments to this function are integers, and 
--      must be in the unsigned 32-bit integer range: 0 to 2^32-1.
--      If an argument cannot be converted to this range, it will throw
--      an error.
--
--      For reference, the XY coordinates (0,0) draw a cell on the top-left 
--      of the terminal, where the positive-X axis moves right and the
--      positive-Y axis moves down.
--
--      For arguments fg and bg: they are colors in the format
--      0xSSRRGGBB, where SS is for styling. See your
--      config.ini for more details.
--
--      For the byte argument, you may use string.byte to fill this argument.
--
--	putCell(byte, fg, bg, x, y, w, h) -- Draw a rectangle. 
--		Arguments are the same as putCell except for w and h, which are also
--		unsigned integers. The rectangle will be drawn from the top-left, with
--		argument w extending it to the right and argument h extending downwards.
--
--
--  putLabel(str, fg, bg, x, y) -- Draw text in argument str. See putCell()
--  	for info on the rest of the arguments.
--
--  clock() -- The time, in microseconds.
-- }
--
-- A function named `draw()` must be declared in the script. This is ran every
-- frame.
--
-- In addition to the base library, you are also given the following standard
-- libraries:
-- 	bit (A library exclusive to LuaJIT, see https://bitop.luajit.org/api.html)
--	math
--	string
--	table
--
--	The std libraries io and debug are NOT included.
-- 
-- ]]

-- You should probably copy FPS and FPS_COUNT into any future LuaJIT animations
-- you create.
local FPS_COUNT = 40
local function FPS()
	return (1/FPS_COUNT)*1000000
end


local SQUARE_WIDTH = 10
local SQUARE_HEIGHT = 5

local SQUARE_COUNT = 25

local squares = {}

for i = 1, SQUARE_COUNT do
	local vx = 1
	local vy = 1
	if math.random(1, 2) == 2 then vx = -vx end
	if math.random(1, 2) == 2 then vy = -vy end
	squares[#squares+1] = {
		x = math.random(1, ly.width - SQUARE_WIDTH),
		y = math.random(1, ly.height - SQUARE_HEIGHT),
		vx = vx,
		vy = vy,
		color = math.random(0xFFFFFF)
	}
end

local timer = ly.clock()
local perf = ly.clock()

function draw()
	-- Rather than progressing the animation by frame, do it based on
	-- seconds, via ly.clock(). In this timeframe, you can update the animation
	-- state.
	-- DO NOT DRAW CELLS IN THIS TIMEFRAME. You will get flickering.

	-- if this check passes, we can update the animation
	if timer + FPS() < ly.clock() then 
		for i, v in ipairs(squares) do
			v.x = v.x + v.vx
			v.y = v.y + v.vy
			if v.x == 0 then 
				v.vx = 1; v.color = math.random(0xFFFFFF)
			end
			if v.x + SQUARE_WIDTH >= ly.width-1 then
				v.vx = -1; v.color = math.random(0xFFFFFF)
			end
			if v.y == 0 then 
				v.vy = 1; v.color = math.random(0xFFFFFF)
			end
			if v.y + SQUARE_HEIGHT >= ly.height-1 then
				v.vy = -1; v.color = math.random(0xFFFFFF) 
			end
		end
		timer = ly.clock()
	end


	for i, v in ipairs(squares) do
		ly.putRect(string.byte(' '), 0, v.color, v.x, v.y, SQUARE_WIDTH, SQUARE_HEIGHT)
	end

	local new_perf = ly.clock()
	local str = "FT: "..((new_perf - perf) / 1000).."ms"
	ly.putLabel(str , 0x00FFFFFF, 0, (ly.width/2) - (string.len(str)/2), ly.height-1)
	perf = new_perf
end
