-- flock
-- an experiment in ABM
-- for Norns.
--

engine.name = 'PolyPerc'


local met
birds = {}

WIDTH = 64
HEIGHT = 64

NUM_AGENTS = 25

FEAR = 2
SIGHT = 8

MAX_TURN_ALIGN = 2.0 -- 2.0
MAX_TURN_COHERE = 1.5-- 3.0
MAX_TURN_AVOID = 1.5 -- 1.5
MAX_TURN_AVOID_POINT = 3.0
MAX_TURN_TARGET = 2.0

tick = 0

function should_print(bird)
  return bird.id == 1 and tick % 10 == 0 --and bird.avoiding == 2
end

--- draw functions
function draw_bird(bird)
  screen.level(10)
  screen.pixel(bird.px, math.floor(HEIGHT - bird.py))
  screen.fill()
end

function init()
  met = metro.init()
  met.event = run
  
  for i = 1, NUM_AGENTS do
    local h = 2 * math.pi * math.random(1000) / 1000
    birds[i] = {
      id = i,
      px = math.random(64),
      py = math.random(64),
      heading = h,
      next_heading = 0.0,
      rand = math.random(2) - 1,
      energy = 0.0,
      avoiding = 0
    }
  end
  
  redraw()
  run()
  
  met:start(1 / 60)
end

function crow_init()
  for i = 1, 3 do
    crow.output[i].slew = 0.1
  end
  crow.output[4].slew = 0.0
end


function enforce_heading(bird)
  if bird.next_heading > (2 * math.pi) then
    bird.next_heading = bird.next_heading - math.pi * 2
  elseif bird.next_heading < 0 then
    bird.next_heading = bird.next_heading + math.pi * 2
  end
end

function adjust_heading(bird, change)
  bird.next_heading = bird.next_heading + change
  enforce_heading(bird)
end

function square(x)
  return x * x
end

-- todo: check this
function bound_dist(x1, x2)
  x1 = bound_point(x1)
  x2 = bound_point(x2)
  local s = x1 - x2
  if s < -32 then
    s = s + 64
  elseif s > 32 then
    s = s - 64
  end
  return s
end

function distance(b1, b2)
  local y = bound_dist(b1.py, b2.py)--math.abs(b1.py - b2.py)
  local x = bound_dist(b1.px, b2.px) --math.abs(b1.px - b2.px)
  
  --[[
  if y > 32 then
    y = y - 32
  end
  if x > 32 then 
    x = x - 32
  end
  --]]
  return math.sqrt(square(y) + square(x))
end


function closest_agent(a, as) -- agent, agentset
  m = 64
  ii = 0
  for i = 1, NUM_AGENTS do
    if as[i].id ~= a.id then
      local dist = distance(as[i], a)
      if dist < m then
        m = dist
        ii = i
      end
    end
  end
  return as[ii]
end

function flockmates(bird, birds, radius)
  l = {}
  l["n"] = 0
  for i = 1, NUM_AGENTS do
    local b = birds[i]
    if b.id ~= bird.id then
      local dist = distance(bird, b)
      if dist < radius then
        l["n"] = l["n"] + 1
        l[l["n"]] = b
      end
    end
  end
  return l
end


function diff_angles(a1, a2)
  local diff = a2 - a1
  while (diff < -math.pi) do
    diff = diff + math.pi * 2
  end
  while diff > math.pi do
    diff = diff - math.pi * 2
  end
  return diff
end

function turn_at_most(bird, t, max_turn)
  local mt = max_turn * 0.0174533
  if math.abs(t) > mt then
    if t > 0 then
      adjust_heading(bird, mt)
    else
      adjust_heading(bird, -mt)
    end
  else
    adjust_heading(bird, t)
  end
end

function out_of_bounds(x, y)
  if x > 64 or x < 0 or y < 0 or y > 64 then
    return true
  end
  return false
end


function bird_angle_to_point_relative(bird, sx, sy)
  local s = math.atan2(sy, sx)
  --s = s - math.pi
  if s < 0 then
    s = s + math.pi * 2
  end
  return s
end

function bird_angle_to_point(bird, px, py)
  local sx = bound_dist(px, bird.px)
  local sy = bound_dist(py, bird.py)
  local s = bird_angle_to_point_relative(bird, sx, sy)
  return s
end

function bird_target_point(bird, px, py)
  local s = bird_angle_to_point(bird, px, py)
  local adj = diff_angles(bird.heading, s)
  turn_at_most(bird, adj, MAX_TURN_TARGET)
end



function bird_avoid(bird, point_x, point_y, ma)
  local s = bird_angle_to_point(bird, point_x, point_y)
  s = s - math.pi
  -- flip! we want to avoid
  if s < 0 then
    s = s + 2 * math.pi
  end
  local adj = diff_angles(bird.heading, s)
  turn_at_most(bird, adj, ma)
end

function bird_avoid_birds(bird, flock)
    if flock["n"] < 1 then
    return
  end
  local sx = 0.0
  local sy = 0.0
  for i = 1, flock["n"] do
    sx = sx + (flock[i].px - bird.px) / flock["n"]
    sy = sy + (flock[i].py - bird.py) / flock["n"]
  end
  bird_avoid(bird, sx, sy, MAX_TURN_AVOID)
end


function bird_align(bird, flock)
  if flock["n"] < 1 then
    return
  end
  local h = 0.0
  local sx = 0.0
  local sy = 0.0
  for i = 1, flock["n"] do
    sx = sx + math.cos(flock[i].heading)
    sy = sy + math.sin(flock[i].heading)
  end
  sx = sx / flock["n"]
  sy = sy / flock["n"]
  local s = math.atan(sy / sx)
  if sy < 0 then
    s = s + math.pi
  elseif sy < 0 and sx > 0 then
    s = s + 2 * math.pi
  end
  local adj = diff_angles(bird.heading, s)
  turn_at_most(bird, adj, MAX_TURN_ALIGN)
end

function bird_cohere(bird, flock)
  if flock["n"] < 1 then
    return
  end
  local sx = 0.0
  local sy = 0.0
  for i = 1, flock["n"] do
    sx = sx + flock[i].px
    sy = sy + flock[i].py
  end
  sx = (sx / flock["n"]) - bird.px
  sy = (sy / flock["n"]) - bird.px
  --
  --local s = math.atan2(sx, sy)
  local s = math.atan2(sy, sx)
  local adj = diff_angles(bird.heading, s)
  turn_at_most(bird, adj, MAX_TURN_COHERE)
end


function calculate(bird)
  --local neighbor = closest_agent(bird, birds)
  local flock = flockmates(bird, birds, SIGHT)
  local too_close = flockmates(bird, birds, FEAR)
  -- avoid?
  bird.avoiding = 0
  local future_x = bird.px + math.cos(bird.heading) * SIGHT
  local future_y = bird.py + math.sin(bird.heading) * SIGHT
  if out_of_bounds(future_x, future_y) then
    bird.avoiding = 2
    local fx = bound_point_ceil(future_x)
    local fy = bound_point_ceil(future_y)
    turn_at_most(bird, -MAX_TURN_AVOID_POINT, MAX_TURN_AVOID_POINT)
    --bird_avoid(bird, fx, fy, MAX_TURN_AVOID_POINT)
  elseif too_close["n"] > 0 then
    bird.avoiding = 1
    bird_avoid_birds(bird, too_close)
  elseif flock["n"] > 0 then
    bird_target_point(bird, 32.0, 32.0)
    bird_align(bird, flock)
    bird_cohere(bird, flock)
  end
end

function bounce(x, y)
  if x > 64 then
    x = 128 - x
  elseif x < 0 then
    x = -x
  end
  if y > 64 then
    y = 128 - y
  elseif y < 0 then
    y = -y
  end
  return x, y
end

function bound_point(p)
  if p > 64 then
    p = 64 - p
  elseif p < 0 then
    p = 60 + p
  end
  return p
end

function bound_point_ceil(p)
  if p > 64 then
    p = 64
  elseif p < 0 then
    p = 0
  end
  return p
end


function enforce_walls(bird)
  bird.px = bound_point(bird.px)
  bird.py = bound_point(bird.py)
end

function move(bird)
  local my_speed = 0.1
  bird.px = bird.px + math.cos(bird.heading) * my_speed
  bird.py = bird.py + math.sin(bird.heading) * my_speed
  
  enforce_walls(bird)
  enforce_heading(bird)
end

function crow_update()
  crow.output[1].volts = 5.0 * math.abs(birds[1].heading - math.pi) / math.pi
  crow.output[2].volts = 5.0 * birds[1].px / 64
  crow.output[3].volts = 5.0 * birds[1].py / 64
  crow.output[4].volts = 5.0 * birds[1].avoiding
end


function run()
  for i = 1, NUM_AGENTS do
    calculate(birds[i])
  end
  
  for i = 1, NUM_AGENTS do
    birds[i].heading = birds[i].next_heading
  end
  
  for i = 1, NUM_AGENTS do
    move(birds[i])
  end
  
  crow_update()
  redraw()
  
  if birds[1].avoiding == 1 then
    engine.hz(220 + birds[1].py)
  end
  
  tick = tick + 1
end

function redraw()
  screen.clear()
  for i = 1, NUM_AGENTS do
    draw_bird(birds[i])
  end
  
  screen.move(birds[1].px, HEIGHT - birds[1].py)
  local xx = birds[1].px +  math.cos(birds[1].heading) * 5.0
  local yy = HEIGHT - (birds[1].py +math.sin(birds[1].heading) * 5.0)
  screen.line(xx, yy)
  screen.stroke()
  
  -- bird 1 update
  screen.move(70, 10)
  screen.level(10)
  
  screen.text("px " .. birds[1].px)
  screen.move(70, 20)
  screen.text("py " .. birds[1].py)
  screen.move(70, 30)
  screen.text("hd " .. birds[1].heading)
  screen.move(70, 40)
  screen.text("av " .. birds[1].avoiding)
  screen.move(70, 50)
  local n = flockmates(birds[1], birds, SIGHT)
  screen.text("n " .. n["n"])
  
  screen.update()
end

function enc(n, d)
  print(n, d)
end
