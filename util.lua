_G.xutil = xutil or {}

local mult_lookup = {
  int2str = {
    [0] = "",
    "k",
    "M",
    "G",
    "T",
    "P",
    "E",
    "Z",
    "Y",
    "R",
    "Q"
  },
  str2int = {
    ["k"] = 3,
    ["M"] = 6,
    ["G"] = 9,
    ["T"] = 12,
    ["P"] = 15,
    ["E"] = 18,
    ["Z"] = 21,
    ["Y"] = 24,
    ["R"] = 27,
    ["Q"] = 30
  }
}

xutil.calculate_power = function(energy)
  local exp = ("%e"):format(energy)
  local mult = tonumber(exp:sub(-2))
  local power = tonumber(exp:sub(1, -5)) * (10 ^ (mult % 3))
  local long = power >= 100
  return (long and "%d %sW" or "%.1f %sW"):format(power, mult_lookup.int2str[(mult - mult % 3) / 3])
end

xutil.parse_power = function(energy)
  local mult = not tonumber(energy:sub(1, -2)) and energy:sub(-2, -2) or nil
  return (mult and energy:sub(1, -3) or energy:sub(1, -2)) *
    (energy:sub(-1) == "J" and 60 or 1) *
    10 ^ (mult_lookup.str2int[mult] or 0)
end

return xutil