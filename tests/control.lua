-- File map: engine assertions and structured evidence for isolated NSBC behavior.
-- blueprint: docs/lifecycle.md#verification
local information = require("__zzz-nonstandard-beacons__/scripts/information")
local player_fixture = require("player-control")
local actor_fixture = require("actor-control")
local recovery_fixture = require("recovery-control")
local function check(condition, message)
  if not condition then error("NSBC-QC FAIL: " .. message) end
  log("NSBC-QC PASS: " .. message)
end
local function metadata(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end
script.on_init(function()
  storage.fixture = {}
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 2)
  surface.force_generate_chunk_requests()
  local names = {"nsbc-copper", "nsbc-iron", "nsbc-fractional", "nsbc-burner", "nsbc-electric", "nsbc-heat", "nsbc-process"}
  if settings.startup["nsb-include-example-beacons"].value then
    for index, name in ipairs{"electric-beacon", "burner-beacon", "fluid-beacon", "heat-beacon"} do
      local entity = surface.create_entity{name = name, position = {index * 6, -24}, force = "player", raise_built = true}
      check(entity and metadata(entity).manager.valid, "optional example attaches " .. name)
      check(prototypes.recipe[name] and game.forces.player.recipes[name], "optional example recipe " .. name)
    end
  end
  for i, name in ipairs(names) do
    local entity = surface.create_entity{name = name, position = {i * 6, 0}, force = "player", raise_built = true}
    check(entity ~= nil, "created " .. name)
    entity.get_module_inventory().insert{name = "speed-module", count = 1}
    local record = metadata(entity)
    check(record and record.source and record.source.valid, "attached " .. name)
    check(record.manager and record.manager.valid, "manager " .. name)
    storage.fixture[name] = entity
    local source = record.source
    if source.prototype.fluid_energy_source_prototype then source.set_fluid(source.prototype.fluid_energy_source_prototype.fluid_box.index, {name = "nsbc-nitrogen", amount = 100, temperature = 25}) end
    if source.burner then source.get_fuel_inventory().insert{name = "coal", count = 10} end
    if name == "nsbc-heat" then source.temperature = 700 end
    if name == "nsbc-process" then source.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", count = 5} end
  end
  check(metadata(storage.fixture["nsbc-copper"]).source.prototype.get_max_energy_usage() == 1, "60 W is 1 J/tick")
  storage.quality = surface.create_entity{name = "nsbc-copper", position = {6, 36}, force = "player", quality = "rare", raise_built = true}
  metadata(storage.quality).source.set_fluid(1, {name = "nsbc-nitrogen", amount = 100, temperature = 25})
  local ok, reason = remote.call("nonstandard-beacons", "set-beacon-orientation", storage.fixture["nsbc-copper"], defines.direction.east, true)
  check(ok, "orientation adapter " .. tostring(reason))
end)
script.on_event(defines.events.on_tick, function(event)
  player_fixture.tick(event.tick)
  actor_fixture.tick(event.tick)
  recovery_fixture.tick(event.tick)
  if event.tick == 10 then
    local copper = metadata(storage.fixture["nsbc-copper"])
    local iron = metadata(storage.fixture["nsbc-iron"])
    storage.start = {tick = event.tick, copper = copper.source.get_fluid(1).amount, iron = iron.source.get_fluid(1).amount}
    storage.start.quality = metadata(storage.quality).source.get_fluid(1).amount
    check(copper.source.direction == defines.direction.east, "source direction retained")
    check(copper.source.mirroring, "source mirroring retained")
    check(metadata(storage.fixture["nsbc-burner"]).monitor ~= nil, "fresh optional module monitor")
  elseif event.tick == 70 then
    local quality_source = metadata(storage.quality).source
    log("NSBC-QC quality energy " .. serpent.line({rate = storage.start.quality - quality_source.get_fluid(1).amount,
      maximum = quality_source.prototype.get_max_energy_usage(quality_source.quality),
      multiplier = quality_source.quality.crafting_machine_energy_usage_multiplier,
      affects = quality_source.prototype.quality_affects_energy_usage,
      usage = quality_source.prototype.energy_usage, factors = quality_source.prototype.energy_usage_quality_multiplier}))
    local original = metadata(storage.fixture["nsbc-process"]).source
    local probe = original.clone{position = {70, 0}}
    local progress, bonus, quality = probe.crafting_progress, probe.bonus_progress, probe.result_quality
    local inputs = probe.get_inventory(defines.inventory.crafter_input).get_contents()
    local replacement = probe.surface.create_entity{name = probe.name, position = probe.position,
      force = probe.force, quality = "uncommon", fast_replace = true, spill = true}
    log("NSBC-QC native craft probe " .. serpent.line({old_invalid = not probe.valid, before = {progress, bonus, quality and quality.name, inputs},
      after = {replacement.crafting_progress, replacement.bonus_progress, replacement.result_quality and replacement.result_quality.name,
      replacement.get_inventory(defines.inventory.crafter_input).get_contents()}}))
    for _, pair in ipairs{{"nsbc-copper", "copper", 5}, {"nsbc-iron", "iron", 10}} do
      local source = metadata(storage.fixture[pair[1]]).source
      local depletion = storage.start[pair[2]] - source.get_fluid(1).amount
      check(math.abs(depletion - pair[3]) < 0.01, pair[1] .. " controlled depletion " .. depletion .. "/s")
    end
    local old = storage.fixture["nsbc-copper"]
    local before = metadata(old)
    local quantity = before.source.get_fluid(1).amount
    old.order_upgrade{target = {name = "nsbc-iron", quality = "normal"}, force = old.force}
    local successor = old.apply_upgrade()
    check(successor ~= nil and not old.valid, "visible native replacement")
    local after = metadata(successor)
    check(after.phase == "attached", "source native replacement: " .. tostring(after.issue))
    check(math.abs(after.source.get_fluid(1).amount - quantity) < 0.01, "replacement conserves nitrogen")
    check(after.source.direction == defines.direction.east and after.source.mirroring, "replacement preserves orientation")
    storage.fixture["nsbc-copper"] = successor
    local function upgrade(entity, name, quality)
      local old_record = metadata(entity)
      local fluid = old_record.source.prototype.fluid_energy_source_prototype and old_record.source.get_fluid(1)
      local energy = old_record.source.energy + (old_record.energy_reserve or 0)
      local burner = old_record.source.burner
      local remaining = burner and burner.remaining_burning_fuel
      local progress, bonus, result_quality = old_record.source.crafting_progress, old_record.source.bonus_progress, old_record.source.result_quality
      check(entity.order_upgrade{target = {name = name, quality = quality}, force = entity.force}, "mark " .. name .. " " .. quality)
      local result = entity.apply_upgrade()
      check(result and not entity.valid, "native " .. name .. " " .. quality)
      local record = metadata(result)
      check(record and record.phase == "attached", "attachment " .. name .. " " .. quality .. ": " .. tostring(record and record.issue))
      check(record.source.quality.name == quality, "source quality " .. name .. " " .. quality)
      if fluid then check(math.abs(record.source.get_fluid(1).amount - fluid.amount) < 0.0001, "fluid conserved " .. name .. " " .. quality) end
      if remaining then check(record.source.burner.remaining_burning_fuel == remaining, "burning remainder conserved " .. name) end
      check(math.abs(record.source.energy + (record.energy_reserve or 0) - energy) < 0.00001, "buffer plus reserve conserves energy " .. name)
      if name == "nsbc-process" then
        check(record.source.crafting_progress == progress and record.source.bonus_progress == bonus and record.source.result_quality == result_quality, "processing state conserved")
      end
      return result
    end
    successor = upgrade(successor, "nsbc-copper", "normal")
    successor = upgrade(successor, "nsbc-copper", "rare")
    successor = upgrade(successor, "nsbc-copper", "normal")
    storage.fixture["nsbc-copper"] = successor
    storage.fixture["nsbc-burner"] = upgrade(storage.fixture["nsbc-burner"], "nsbc-burner", "rare")
    local process_source = metadata(storage.fixture["nsbc-process"]).source
    process_source.disabled_by_script = true
    process_source.crafting_progress, process_source.bonus_progress, process_source.result_quality = 0.4, 0.37, "rare"
    storage.fixture["nsbc-process"] = upgrade(storage.fixture["nsbc-process"], "nsbc-process", "rare")
    local process_refund = game.create_inventory(10)
    check(metadata(storage.fixture["nsbc-process"]).source.mine{inventory = process_refund, force = true}, "native processing source can be mined after upgrade")
    check(process_refund.get_item_count("iron-plate") == 5, "queued and consumed recipe ingredients refunded exactly once")
    process_refund.destroy()
    storage.fixture["nsbc-heat"] = upgrade(storage.fixture["nsbc-heat"], "nsbc-heat", "rare")
    storage.fixture["nsbc-electric"] = upgrade(storage.fixture["nsbc-electric"], "nsbc-electric", "rare")
    for _, expected in ipairs{{"nsbc-copper", "5/s"}, {"nsbc-iron", "10/s"}, {"nsbc-fractional", "0.05/s"}} do
      local found
      for _, row in ipairs(information.rows(metadata(storage.fixture[expected[1]]))) do
        if row.id == "operating-requirement" then found = row.value end
      end
      check(found == expected[2], expected[1] .. " calculated operating requirement " .. tostring(found))
    end
    local burner_record = metadata(storage.fixture["nsbc-burner"])
    burner_record.source.get_fuel_inventory().clear()
    local burning
    for _, row in ipairs(information.rows(burner_record)) do if row.id == "burning" then burning = row.value end end
    check(type(burning) == "table" and burning[1] == "" and burning[2]:find("coal", 1, true), "currently burning displayed with empty fuel inventory")
    local manager = burner_record.manager
    manager.destroy()
    local repaired = remote.call("nonstandard-beacons", "adopt-beacon", storage.fixture["nsbc-burner"])
    check(repaired and metadata(storage.fixture["nsbc-burner"]).manager.valid, "idempotent controller repair")
    local source_id = metadata(storage.fixture["nsbc-burner"]).source.unit_number
    check(remote.call("nonstandard-beacons", "adopt-beacon", storage.fixture["nsbc-burner"]), "repeat adoption")
    check(metadata(storage.fixture["nsbc-burner"]).source.unit_number == source_id, "repeat adoption retains source")
    local field = successor.set_tooltip_field{name = "Other mod", value = "kept"}
    local view = metadata(successor)
    information.refresh(view)
    local count = #successor.get_tooltip_fields()
    information.refresh(view)
    check(#successor.get_tooltip_fields() == count, "tooltip refresh reuses owned IDs")
    information.clear(view)
    check(#successor.get_tooltip_fields() == 1 and successor.get_tooltip_fields()[1].id == field, "tooltip cleanup retains other mod fields")
    storage.clone = storage.fixture["nsbc-copper"].clone{position = {6, 18}}
    local remote_surface = game.create_surface("nsbc-remote", {width = 128, height = 128})
    remote_surface.request_to_generate_chunks({0, 0}, 1)
    remote_surface.force_generate_chunk_requests()
    check(successor.teleport({6, 6}, nil, true), "same-surface visible teleport")
    check(metadata(successor).source.position.y == successor.position.y and metadata(successor).source.position.x == successor.position.x, "same-surface helper teleport")
    storage.crossclone = successor.clone{position = {6, 6}, surface = remote_surface}
    burner_record.source.burner.remaining_burning_fuel = 0
    burner_record.source.burner.heat = 0
    burner_record.source.energy = 0
    storage.reserve_before = burner_record.energy_reserve
  elseif event.tick == 81 then
    local clone = metadata(storage.clone)
    check(clone and clone.phase == "attached" and clone.source.valid, "visible-only clone attachment")
    check(clone.source.direction == defines.direction.east and clone.source.mirroring, "clone orientation")
    local cross = metadata(storage.crossclone)
    check(cross and cross.source.surface == storage.crossclone.surface and cross.source.direction == defines.direction.east and cross.source.mirroring, "cross-surface clone preserves orientation")
    local record = metadata(storage.fixture["nsbc-burner"])
    check(storage.reserve_before and storage.reserve_before > 0 and not record.energy_reserve, "saved reserve becomes usable source energy")
  elseif event.tick == 100 then
    local record = metadata(storage.fixture["nsbc-burner"])
    log("NSBC-QC exhausted diagnostics " .. serpent.line({status = record.source.status, energy = record.source.energy,
      remaining = record.source.burner.remaining_burning_fuel, heat = record.source.burner.heat,
      manager = record.manager.status, disabled = record.source.disabled_by_script, progress = record.source.crafting_progress,
      fuel = record.source.get_fuel_inventory().get_contents(), phase = record.phase}))
    check(storage.fixture["nsbc-burner"].disabled_by_script, "exhausted burner disables visible beacon")
    metadata(storage.fixture["nsbc-burner"]).source.get_fuel_inventory().insert{name = "coal", count = 1}
  elseif event.tick == 120 then
    check(not storage.fixture["nsbc-burner"].disabled_by_script, "refueling wakes visible beacon")
    log("NSBC-QC COMPLETE")
    helpers.write_file("nsbc-result.json", helpers.table_to_json({passed = true, tick = event.tick}), false)
  end
end)
script.on_event({defines.events.on_robot_pre_mined, defines.events.on_robot_mined_entity,
  defines.events.on_robot_built_entity, defines.events.on_space_platform_pre_mined,
  defines.events.on_space_platform_mined_entity, defines.events.on_space_platform_built_entity}, actor_fixture.event)
