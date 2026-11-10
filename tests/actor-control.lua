-- File map: real construction-robot and space-platform replacement event oracles.
-- blueprint: docs/lifecycle.md#verification
local M = {}
local function check(ok, message)
  assert(ok, "NSBC-ACTOR FAIL: " .. message)
  log("NSBC-ACTOR PASS: " .. message)
end
local function metadata(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end

local function seed(surface, position)
  local beacon = assert(surface.create_entity{name = "nsbc-copper", position = position, force = "player", raise_built = true})
  beacon.get_module_inventory().insert{name = "speed-module", count = 4, quality = "rare"}
  local source = metadata(beacon).source
  source.set_fluid(1, {name = "nsbc-nitrogen", amount = 77, temperature = 43})
  source.disabled_by_script = true
  check(remote.call("nonstandard-beacons", "set-beacon-orientation", beacon, 12, true), "seed orientation")
  return beacon
end

local function start(tick)
  local surface = game.create_surface("nsbc-actors", {width = 128, height = 128})
  surface.request_to_generate_chunks({0, 0}, 2); surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities()) do entity.destroy() end
  local tiles = {}
  for x = -30, 30 do for y = -30, 30 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
  surface.set_tiles(tiles)
  local force = game.forces.player
  force.unlock_quality("rare")
  local port = surface.create_entity{name = "roboport", position = {0, 0}, force = force}
  surface.create_entity{name = "substation", position = {6, 0}, force = force}
  surface.create_entity{name = "hidden-electric-energy-interface", position = {6, 0}, force = force}
  port.energy = port.electric_buffer_size
  port.get_inventory(defines.inventory.roboport_robot).insert{name = "construction-robot", count = 4}
  local chest = surface.create_entity{name = "storage-chest", position = {6, 3}, force = force}
  local inventory = chest.get_inventory(defines.inventory.chest)
  inventory.insert{name = "nsbc-iron", quality = "rare", count = 1}
  local actor = {kind = "robot", old = seed(surface, {12.5, 0.5}), inventory = inventory, events = {}, port = port, start = tick}
  storage.actors = {actor}
  if script.active_mods["space-age"] then
    local platform = force.create_space_platform{name = "NSBC acceptance", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
    local hub = platform.apply_starter_pack(true)
    platform.paused = true
    hub.request_missing_construction_materials = false
    local foundation = {}
    for x = -15, 15 do for y = -15, 15 do foundation[#foundation + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    platform.surface.set_tiles(foundation)
    local stock = hub.get_inventory(defines.inventory.hub_main)
    stock.insert{name = "nsbc-iron", quality = "rare", count = 1}
    storage.actors[#storage.actors + 1] = {kind = "platform", platform = platform,
      old = seed(platform.surface, {10.5, 0.5}), inventory = stock, events = {}, start = tick}
  end
end

function M.event(event)
  for _, actor in pairs(storage.actors or {}) do
    local entity = event.entity
    if entity and entity.valid and entity.surface == actor.surface and entity.position.x == actor.position.x and entity.position.y == actor.position.y then
      actor.events[#actor.events + 1] = {name = event.name, tick = event.tick, entity = entity.name,
        robot = event.robot and event.robot.valid or false, platform = event.platform and event.platform.index}
      if event.name == defines.events.on_robot_built_entity or event.name == defines.events.on_space_platform_built_entity then
        actor.built = entity
        check(actor.kind == "robot" and event.robot and event.robot.valid or actor.kind == "platform" and event.platform == actor.platform,
          actor.kind .. " native actor confirmed")
      end
    end
  end
end

function M.tick(tick)
  if tick == 200 then start(tick) end
  if not storage.actors or storage.actors_complete then return end
  local done = true
  for _, actor in ipairs(storage.actors) do
    if not actor.ordered then
      actor.surface, actor.position = actor.old.surface, actor.old.position
      check(actor.old.order_upgrade{target = {name = "nsbc-iron", quality = "rare"}, force = actor.old.force}, actor.kind .. " upgrade ordered")
      actor.ordered = true
    end
    if actor.built and not actor.checked then
      local record = metadata(actor.built)
      check(not actor.old.valid and actor.built.name == "nsbc-iron" and actor.built.quality.name == "rare", actor.kind .. " successor identity")
      check(record and record.phase == "attached", actor.kind .. " attached: " .. tostring(record and record.issue))
      check(record.source.disabled_by_script, actor.kind .. " independent pause retained")
      local fluid = record.source.get_fluid(1)
      check(fluid and math.abs(fluid.amount - 77) < 0.0001 and fluid.temperature == 43, actor.kind .. " fluid conserved")
      check(record.source.direction == 12 and record.source.mirroring, actor.kind .. " orientation conserved")
      check(actor.built.get_module_inventory().get_item_count{name = "speed-module", quality = "rare"} == 4, actor.kind .. " real modules conserved")
      check(#actor.surface.find_entities_filtered{name = "nsbc-iron-source", position = actor.position} == 1, actor.kind .. " single source")
      log("NSBC-ACTOR ORDER " .. actor.kind .. " " .. serpent.line(actor.events))
      actor.checked = true
    end
    if actor.checked and not actor.done and actor.inventory.get_item_count("nsbc-copper") == 1 then
      check(actor.inventory.get_item_count{name = "nsbc-iron", quality = "rare"} == 0, actor.kind .. " replacement item consumed")
      actor.done = true
    end
    done = done and actor.done
    if tick - actor.start > 3400 and not actor.done then
      log("NSBC-ACTOR TIMEOUT " .. serpent.line({kind = actor.kind, events = actor.events, stock = actor.inventory.get_contents(),
        port_energy = actor.port and actor.port.energy, network = actor.port and actor.port.logistic_network and actor.port.logistic_network.available_construction_robots}))
      check(false, actor.kind .. " timeout")
    end
  end
  if done then
    storage.actors_complete = true
    helpers.write_file("nsbc-actors-result.json", helpers.table_to_json({passed = true, actors = #storage.actors, tick = tick}), false)
    log("NSBC-ACTOR COMPLETE")
  end
end
return M
