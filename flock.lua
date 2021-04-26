-- flock
-- an experiment in ABM for Norns.
--
engine.name = "PolySub"

g = grid.connect()


local met
patches = {}
agents = {}
next_headings = {}

ticks = 0

NUM_AGENTS = 35
SPEED = 0.3

MAX_AVOID_TURN = 5.0
MAX_SEP_TURN = 1.5
MAX_COHERE_TURN = 2.0
MAX_ALIGN_TURN = 3.0
MAX_TURN_TARGET = 100.0

VISION = 6
WALL_VISION = 12

MIN_SEP = 1.0
blink = 0
avoiding = 0

function init()
  -- params
  params:add_number("speed", "speed", 2, 10, 3)
  
  
  --local patches = {}
  for i = 1, 65 do
    patches[i] = math.random(2)
  end
  print(patches)
  
  for i = 1, NUM_AGENTS do
    agents[i] = {
      id = i,
      heading = math.random(1000) / 100,
      px = math.random(64) + 0.001,
      py = math.random(64) + 0.001,
      rand = math.random(2) - 1,
      energy = 0.0
    }
  end
  
  for i = 1, 3 do
    crow.output[i].slew = 0.1
  end
  crow.output[4].slew = 0.0
  
  met = metro.init()
  met.event = run
 
  
  redraw()
  run()
  
  met:start(1 / 10)
end

run = function()
  
  move()
  redraw()
  
  SPEED = params:get("speed") / 10
  --print(SPEED)
  
  crow.output[1].volts = crow_volts(agents[1].heading)
  crow.output[2].volts = agents[1].px / 64
  crow.output[3].volts = agents[1].py / 64
  crow.output[4].volts = avoiding * 5
  --local nn = closest_agent(agents[1], agents)
  --print(distance(agents[1], nn))
end
  

function square(x)
  return x * x
end

function distance(a1, a2)
  local y = math.abs(a1.py - a2.py)
  local x = math.abs(a1.px - a2.px)
  
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
  m = 10000000000000
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


function flockmates(a, as, r)
  l = {}
  l["n"] = 0
  for i = 1, NUM_AGENTS do
    if as[i].id ~= a.id then
      local dist = distance(as[i], a)
      if dist < r then
        l["n"] = l["n"] + 1
        l[l["n"]] = as[i]
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

function turn_at_most(a, turn, max_turn)
  local d_angle = diff_angles(next_headings[a], turn)
  if math.abs(d_angle) > max_turn then
    if d_angle > 0 then
      next_headings[a] = next_headings[a] + max_turn
    else
      next_headings[a] = next_headings[a] - max_turn
    end
  else
    next_headings[a] = next_headings[a] + d_angle
  end
  if a == 1 then
    --print(next_headings[a] - agents[1].heading, d_angle)
  end
end

function out_of_bounds(x, y)
  if x > 64 or x < 0 or y < 0 or y > 64 then
    return true
  end
  return false
end

function patch_at(x, y)
  local xx = math.floor(x / 8)
  local yy = math.floor(y / 8)
  return yy * 8 + xx + 1
end

function patch_pos(p)
  local x = ((p - 1) % 8) * 8
  local y = math.floor(p / 8) * 8
  return x, y
end



function patch_vn_neighbors(p)
  local l = {}
  l["n"] = 0
  -- look right
  if (p % 8) ~= 0 then
    l["n"] = l["n"] + 1
    l[l["n"]] = p + 1
  end
  -- look left
  if (p % 8) ~= 1 then
    l["n"] = l["n"] + 1
    l[l["n"]] = p - 1
  end
  -- look down
  if p > 8 then
    l["n"] = l["n"] + 1
    l[l["n"]] = p - 8
  end
  if p < (64 - 8) then
    l["n"] = l["n"] + 1
    l[l["n"]] = p + 8
  end
  return l
end

function angle_trick(x, y)
  local s = math.atan2(x, y)
  s = s - math.pi
  if s < 0 then
    s = s + math.pi * 2
  end
  return s
end

function calc_agent(a)
  --if a.id == 1 then
    -- unreleastic views for now
    local c_p = patch_at(a.px, a.py)
    local nn = patch_vn_neighbors(c_p)
    nn["n"] = nn["n"] + 1
    nn[nn["n"]] = c_p
    local m_energy = 0
    local best_patch = 0
     local dn = a.heading
     
    for i = 1, nn["n"] do
      local m = nn[i]
      local m_patch = patches[m]
     
      if m_patch > m_energy then
        -- TODO
        -- can we see this?
        local x_t, y_t = patch_pos(m)
        local s = angle_trick(x_t - a.px + 4, y_t - a.py + 4)
        local d = diff_angles(a.heading, s)
        if a.id == 1 then
          --print(d, a.heading, s)
        end
        if math.abs(d) < math.pi then
          m_energy = m_patch
          best_patch = m
          dn = d
        end
      end
    end
    
    turn_at_most(a.id, dn, MAX_TURN_TARGET * 0.0174533)
    
    --local bp_x = 8 * 
    --local x_t, y_t = patch_pos(best_patch)

    --local s = angle_trick(x_t - a.px + 4, y_t - a.py + 4)
    
    if a.id == 1 then
      --print(a.px, a.py, x_t, y_t, m_energy)
      --print("s " .. s)
    end
    
    --print(nn["n"], c_p, best_patch, x_t, y_t)
  --end
  
  
  
  avoiding = 0
  local closest = closest_agent(a, agents)
  --a.px = a.px + math.cos(a.heading) * SPEED
  --a.py = a.py + math.sin(a.heading) * SPEED
  local future_x = a.px + math.cos(a.heading) * WALL_VISION
  local future_y = a.py + math.sin(a.heading) * WALL_VISION
  if out_of_bounds(future_x, future_y) then
    avoiding = 1
    ---turn_at_most(a.id, a.heading + math.pi, MAX_AVOID_TURN * 0.0174533)
    local tr = math.floor(ticks / 250)
    -- ^ keeps from having two flocks 
    if a.rand == 1 then
      turn_at_most(a.id, a.heading + 1.0, MAX_AVOID_TURN * 0.0174533)
    else
      turn_at_most(a.id, a.heading - 1.0, MAX_AVOID_TURN * 0.0174533)
    end
  elseif distance(closest, a) <= MIN_SEP then
    avoiding = 1
    a.rand = math.random(2) - 1
    local flock = flockmates(a, agents, MIN_SEP)
    
    local sx = 0.0
    local sy = 0.0
    -- cohere
    -- TODO: This part is tricky. Check it carefully.
    for i = 1, flock["n"] do
      sx = sx + flock[i].px
      sy = sy + flock[i].py
      --s = s + math.atan2(flock[i].px - a.px, flock[i].py - a.py)
    end
    sx = sx / flock["n"]
    sy = sy / flock["n"]
    local s = math.atan2(sx - a.px, sy - a.py)
    s = s - math.pi
    if s < 0 then
      s = s + math.pi * 2
    end
    turn_at_most(a.id, s, MAX_SEP_TURN * 0.0174533)
    
    
    
    local turn = diff_angles(closest.heading, a.heading) + a.heading
    --local turn = a.heading - closest.heading
    --local turn = (closest.heading + math.pi) -- - a.heading
    
    --print(a.id, turn)
    -- turn_at_most(a.id, turn, MAX_SEP_TURN * 0.0174533)
  else
    local flock = flockmates(a, agents, VISION)
    if flock["n"] >= 1 then
      -- align
      local ss = 0.0
      local sc = 0.0
      for i = 1, flock["n"] do
        ss = ss + math.sin(flock[i].heading)
        sc = sc + math.cos(flock[i].heading)
      end
      ss = ss / flock["n"]
      sc = sc / flock["n"]
      local s = math.atan(ss / sc)
      if sc < 0 then
        s = s + math.pi
      elseif ss < 0 and sc > 0 then
        s = s + 2 * math.pi
      end
      turn_at_most(a.id, s, MAX_ALIGN_TURN * 0.0174533)
      
      local sx = 0.0
      local sy = 0.0
      -- cohere
      -- TODO: This part is tricky. Check it carefully.
      for i = 1, flock["n"] do
        sx = sx + flock[i].px
        sy = sy + flock[i].py
        --s = s + math.atan2(flock[i].px - a.px, flock[i].py - a.py)
      end
      sx = sx / flock["n"]
      sy = sy / flock["n"]
      local s = math.atan2(sx - a.px, sy - a.py)
      turn_at_most(a.id, s, MAX_COHERE_TURN * 0.0174533)
    end
  end
end

function move_agents(a)
  a.heading = next_headings[a.id]
  
  if a.heading > math.pi * 2 then
    a.heading = a.heading - math.pi * 2
  end
  if a.heading < 0 then
    a.heading = a.heading + math.pi * 2
  end
  
  local my_speed = SPEED
  local patch_index = patch_at(a.px, a.py)
  
  --if patches[patch_index] > 4 then
  --  my_speed = my_speed * 1.5
  --end
  
  if a.energy > 0.1 then
    my_speed = my_speed * 1.5
    a.energy = a.energy - 0.1
  end
  
  -- get some energy
  if patches[patch_index] ~= nil then
    if patches[patch_index] > 0.1 then
    a.energy = a.energy + 0.1
    patches[patch_index] = patches[patch_index] - 0.1
    end
  end

  
  
  a.px = a.px + math.cos(a.heading) * my_speed
  a.py = a.py + math.sin(a.heading) * my_speed
  
  if a.px > 64 then
    a.px = 128 - a.px
  elseif a.px < 0 then
    a.px = -a.px
  end
  
  if a.py > 64 then
    a.py = 128 - a.py -- 64
  elseif a.py < 0 then
    a.py = -a.py
  end
  
  --[[
  if a.px > 64 then
    a.px = a.px - 64
  elseif a.px < 0 then
    a.px = a.px + 64
  end
  
  if a.py > 64 then
    a.py = a.py - 64
  elseif a.py < 0 then
    a.py = a.py + 64
  end
  --]]
end

function move()
  for i = 1, NUM_AGENTS do
    local id = agents[i].id
    next_headings[id] = agents[i].heading
  end
  
  for i = 1, NUM_AGENTS do
    calc_agent(agents[i])
  end
  
  for i = 1, NUM_AGENTS do
    move_agents(agents[i])
  end
  
  ticks = ticks + 1
  if ticks > 1000 then 
    ticks = 0
  end
  
  for i = 1, 65 do
    if math.random(10) > 7 then
      patches[i] = patches[i] + 0.1
    end
  end
end

function crow_volts(x)
  return 5.0 * (x - math.pi) / math.pi
end


function redraw()
  screen.clear()
  screen.move(0, 0)
  screen.font_face(1)
  screen.font_size(6)
  
  
  for y = 0, 7 do
    for x = 0, 7 do
      screen.rect(y * 8, x * 8, 8, 8)
      local lvl = math.floor(patches[x * 8 + y + 1] + 7)
      screen.level(lvl)
      screen.fill()
      screen.level(0)
      screen.move(y * 8, x * 8 + 7)
      --screen.text(x * 8 + y + 1)
    end
  end
  
  screen.font_size(8)
  
  screen.level(15 * blink)
  screen.pixel(math.floor(agents[1].px), math.floor(agents[1].py))
  screen.fill()
  blink = math.abs(blink - 1)
  
  for i = 2, NUM_AGENTS do
    local a = agents[i]
    screen.level(0)
    screen.pixel(math.floor(a.px), math.floor(a.py))
    screen.fill()
  end
  
  screen.move(70, 10)
  screen.level(10)
  
  screen.text("px " .. agents[1].px)
  screen.move(70, 20)
  screen.text("py " .. agents[1].py)
  screen.move(70, 30)
  screen.text("hd " .. agents[1].heading)
  screen.move(70, 40)
  screen.text("av " .. avoiding)
  screen.move(70, 50)
  local n = flockmates(agents[1], agents, VISION)
  screen.text("n " .. n["n"])
  
  screen.move(70, 60)
  local cp = patch_at(agents[1].py, agents[1].py)
  screen.text("e " .. patches[cp])
  screen.update()
  --print("update")
  
  -- grid
  g:all(0)
  for x = 0, 7 do
    for y = 0, 7 do
      local index = x * 8 + y + 1
      local lvl = math.min(math.floor(patches[index]), 15)
      g:led(y + 1, x + 1, lvl)
    end
  end
  g:refresh()
end

g.key = function(x, y, z)
  if x <= 8 then
    if z == 1 then
      patches[(y - 1) * 8 + x] = patches[(y - 1) * 8 + x] + 1.0
    end
  end
end


function enc(n, d)
  redraw()
end