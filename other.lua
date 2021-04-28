
function bird_match(bird, birds)
  local match_x = 0.0
  local match_y = 0.0
  for i = 1, birds["n"] do
    local b = birds[i]
    match_x = match_x + (b.vx / birds["n"])
    match_y = match_y + (b.vy / birds["n"])
  end
  return match_x, match_y
end

function bird_cohere(bird, birds)
  local x = 0.0
  local y = 0.0
  for i = 1, birds["n"] do
    local b = birds[i]
    x = x + b.px - bird.px
    y = y + b.py - bird.py
  end
  return x / birds["n"], y / birds["n"]
end

function bird_avoid(bird, birds)
  local x = 0.0
  local y = 0.0
  local count = 0
  for i = 1, birds["n"] do
    local b = birds[i]
    if distance(bird, b) < FEAR then
      x = x - b.px + bird.px
      y = y - b.py + bird.py
      count = count + 1
    end
  end
  if count == 0 then
    return 0.0, 0.0
  else
    return x / count, y / count
  end
end

function normalize(x, y)
  local norm = math.sqrt(square(x) + square(y))
  return x / norm, y / norm
end


--[[
  
  local match_x, match_y = bird_match(bird, flock)
  local coh_x, coh_y = bird_cohere(bird, flock)
  local sep_x, sep_y = bird_avoid(bird, flock)
  local match_factor = 0.5
  local separate_factor = 0.25
  local cohere_factor = 0.25
  bird.vx = (
    bird.vx + 
    match_x * match_factor +
    coh_x * cohere_factor +
    sep_x * separate_factor
    ) / 2
  bird.vy = (
    bird.vy + 
    match_y * match_factor +
    coh_y * cohere_factor +
    sep_y * separate_factor
    ) / 2
  bird.vx, bird.vy = normalize(bird.vx, bird.vy)
  --]]