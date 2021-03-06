-- flock
-- an experiment in ABM
-- for Norns.
--

engine.name = 'Glut'


local met

local g = grid.connect(1)

VOICES = 4

local positions = {}
local gates = {}
local voice_levels = {}

for i=1, VOICES do
  positions[i] = -1
  gates[i] = 0
  voice_levels[i] = 0
end


birds = {}

WIDTH = 64
HEIGHT = 64

NUM_AGENTS = 20

FEAR = 2
SIGHT = 8

MAX_TURN_ALIGN = 2.0 -- 2.0
MAX_TURN_COHERE = 1.5-- 3.0
MAX_TURN_AVOID = 1.5 -- 1.5
MAX_TURN_AVOID_POINT = 3.0
MAX_TURN_TARGET = 2.0

tick = 0
p_index = 1
target_x = 0
target_y = 0

function should_print(bird)
  return bird.id == 1 and tick % 10 == 0 --and bird.avoiding == 2
end

--- draw functions
function draw_bird(bird, lvl)
  screen.level(lvl)
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
  
  params:add_separator("params")
  params:add{
    type="number", id="align", min=0, max=500, default=200,
    action=function(x) MAX_TURN_ALIGN = x / 100 end
  }
  params:add{
    type="number", id="cohere", min=0, max=500, default=300,
    action=function(x) MAX_TURN_COHERE = x / 100 end
  }
  params:add{
    type="number", id="avoid", min=0, max=500, default=150,
    action=function(x) MAX_TURN_AVOID = x / 100 end
  }
  params:add{
    type="number", id="avoid_point", min=0, max=500, default=300,
    action=function(x) MAX_TURN_AVOID_POINT = x / 100 end
  }
  params:add{
    type="number", id="target", min=0, max=500, default=200,
    action=function(x) MAX_TURN_TARGET = x / 100 end
  }
  
  params:add{
    type="number", id="target_x", min=1, max=64, default=32,
    action=function(x) target_x = x end
  }
  
  params:add{
    type="number", id="target_y", min=1, max=64, default=32,
    action=function(x) target_y = x end
  }
  
  params:add_separator("load samples")
  local sep = ":"
  for i = 1, VOICES do
    params:add_file(i .. "sample", i .. sep .. "sample")
    params:set_action(i .. "sample", function(file) engine.read(i, file) end)
  end
  
  redraw()
  run()
  
  met:start(1 / 60)
end

function crow_init()
  for i = 1, 3 do
    crow.output[i].slew = 0.1
  end
  crow.output[4].slew = 0.01
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
    bird_target_point(bird, target_x, target_y)
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

function ansible_update()
  for i = 1, 4 do
    crow.ii.ansible.trigger(i, birds[i].avoiding)
    local cv = 5.0 * math.abs(birds[i].heading - math.pi) / math.pi
    crow.ii.ansible.cv(i, cv)
  end
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
  ansible_update()
  redraw()
  
  for i = 1, VOICES do
    if birds[i].avoiding == 1 then
      start_voice(i, birds[i].heading / (2 * math.pi))
      --engine.hz(220 + birds[1].py)
    elseif birds[i].avoiding == 0 then
      stop_voice(i)
    end
  end
  
  tick = tick + 1
end

function redraw()
  screen.clear()
  for i = 1, NUM_AGENTS do
    local lvl = 3
    if i <= VOICES then
      lvl = 15
    end
    draw_bird(birds[i], lvl)
  end
  
  screen.move(birds[1].px, HEIGHT - birds[1].py)
  local xx = birds[1].px +  math.cos(birds[1].heading) * 5.0
  local yy = HEIGHT - (birds[1].py +math.sin(birds[1].heading) * 5.0)
  screen.line(xx, yy)
  screen.stroke()
  
  screen.move(70, 10)
  screen.text("avoid " .. params:get("avoid"))
  
  screen.move(70, 20)
  screen.text("align " .. params:get("align"))
  
  screen.move(70, 30)
  screen.text("cohere " .. params:get("cohere"))
  
  screen.move(70, 40)
  screen.text("target " .. params:get("target"))
  
  screen.move(70, 50)
  screen.text("t_x " .. params:get("target_x"))
  
  screen.move(70, 60)
  screen.text("t_y " .. params:get("target_y"))
  
  screen.rect(66, -3 + 10 * p_index, 2, 2)
  
  screen.update()
end

function enc(n, d)
  --print(n, d)
  local opts = 6
  if n == 2 then
    p_index = p_index + d
    if p_index > opts then
      p_index = p_index - opts
    elseif p_index < 1 then
      p_index = p_index + opts
    end
  end
  
  if n == 3 then
    if p_index == 1 then
      params:delta("avoid", d)
    elseif p_index == 2 then
      params:delta("align", d)
    elseif p_index == 3 then
      params:delta("cohere", d)
    elseif p_index == 4 then
      params:delta("target", d)
    elseif p_index == 5 then
      params:delta("target_x", d)
    elseif p_index == 6 then
      params:delta("target_y", d)
    end
  end
  
end


---- Engine stuff
function start_voice(voice, pos)
  engine.seek(voice, pos)
  engine.gate(voice, 1)
  gates[voice] = 1
end


function stop_voice(voice)
  gates[voice] = 0
  engine.gate(voice, 0)
end

-- ansible stuff. 
crow.ii.ansible.event = function( e, data )
  print("ansible event:", e, data)
end

