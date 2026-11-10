-- The runtime lifecycle converter now owns this transition, including complete
-- source-preserving record normalization and controller lookup construction.
-- Keep this historical migration filename so existing 2.0.0 saves remain valid.
-- It intentionally performs no destructive work: on_configuration_changed (or
-- the first game-available event for a same-version development load) converts
-- the complete saved graph before legacy helpers can be retired.
local previous = storage.previous_version
if type(previous) == "string" then
  local major, minor, patch = previous:match("^(%d+)%.(%d+)%.(%d+)$")
  major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
  if major and (major < 1 or (major == 1 and (minor < 4 or (minor == 4 and patch < 2)))) then
    error("Please upgrade this save to Nonstandard Beacons 1.4.2 under Factorio 2.0 before loading this contribution.")
  end
end
