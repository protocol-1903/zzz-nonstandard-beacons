_G.xutil = xutil or {}

xutil.calculate_power = function(energy)
  local mult = 0
  while energy >= 1000 do
    energy = energy / 1000
    mult = mult + 1
  end
  -- convert to 000 or 00.0 or 0.0
  if energy >= 100 then
    energy = math.floor(energy)
  else
    energy = math.floor(energy * 10) / 10
  end
  mult =
    mult == 1 and "k" or mult == 2 and "M" or
    mult == 3 and "G" or mult == 4 and "T" or
    mult == 5 and "P" or mult == 6 and "E" or
    mult == 7 and "Z" or mult == 8 and "Y" or
    mult == 9 and "R" or mult == 10 and "Q" or ""
  return tostring(energy) .. " " .. mult .. "W"
end

xutil.parse_power = function(energy)
  local mult = not tonumber(energy:sub(1, -2)) and energy:sub(-2, -2) or nil
  return (mult and energy:sub(1, -3) or energy:sub(1, -2)) * (energy:sub(-1) == "J" and 60 or 1) * 10^(
    mult == "k" and 3 or mult == "M" and 6 or
    mult == "G" and 9 or mult == "T" and 12 or
    mult == "P" and 15 or mult == "E" and 18 or
    mult == "Z" and 21 or mult == "Y" and 24 or
    mult == "R" and 27 or mult == "Q" and 30 or 1
  )
end

return xutil