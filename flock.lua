-- flock
-- an experiment in ABM for Norns.
--
engine.name = "PolySub"

local met
patches = {}
agents = {}
next_headings = {}

NUM_AGENTS = 35
SPEED = 0.3
MAX_SEP_TURN = 1.5
MAX_COHERE_TURN = 2.0
MAX_ALIGN_TURN = 3.0

VISION = 4
MIN_SEP = 0.4
blink = 0
avoiding = 0

function init()
  -- params
  params:add_number("speed", "speed", 2, 10, 3)
  
  
  --local patches = {}
  for i = 1, 65 do
    patches[i] = math.random(5) + 10
  end
  print(patches)
  
  for i = 1, NUM_AGENTS do
    agents[i] = {
      id = i,
      heading = math.random(1000) / 100,
      px = math.random(64) + 0.001,
      py = math.random(64) + 0.001,
    }
  end
  
  for i = 1, 3 do
    crow.output[i].slew = 0.1
  end
  crow.output[4].slew = 0.0
  
  met = metro.init()
  met.event = run
  met:start(1 / 50)
  
  --redraw()
  run()
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
  
  if y > 32 then
    y = y - 32
  end
  if x > 32 then 
    x = x - 32
  end
  
  
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


function calc_agent(a)
  avoiding = 0
  local closest = closest_agent(a, agents)

  if distance(closest, a) <= MIN_SEP then
    avoiding = 1
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
  
  a.px = a.px + math.cos(a.heading) * SPEED
  a.py = a.py + math.sin(a.heading) * SPEED
  
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
end

function crow_volts(x)
  return 5.0 * (x - math.pi) / math.pi
end


function redraw()
  screen.clear()
  screen.move(0, 0)
  for x = 0, 7 do
    for y = 0, 7 do
      screen.rect(x * 8, y * 8, 8, 8)
      local lvl = patches[x * 8 + y + 1]
      screen.level(lvl)
      screen.fill()
    end
  end
  
  screen.level(15 * blink)
  screen.pixel(math.floor(agents[1].px), math.floor(64 - agents[1].py))
  screen.fill()
  blink = math.abs(blink - 1)
  
  for i = 2, NUM_AGENTS do
    local a = agents[i]
    screen.level(0)
    screen.pixel(math.floor(a.px), math.floor(64 - a.py))
    screen.fill()
  end
  
  screen.move(70, 10)
  screen.level(10)
  screen.font_face(1)
  screen.font_size(8)
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
  screen.update()
  --print("update")
end



function enc(n, d)
  redraw()
end