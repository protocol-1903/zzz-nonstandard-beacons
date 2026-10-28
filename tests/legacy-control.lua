-- Same-code save/load conversion: no configuration-change callback may substitute for on_load.
local loaded = false
local function metadata(body) return remote.call("nonstandard-beacons", "get-beacon-data", body.unit_number) end
script.on_init(function()
  storage.configuration_changes, storage.bodies = 0, {}
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 3); surface.force_generate_chunk_requests()
  for index = 1, 8 do
    local body = assert(surface.create_entity{name = "nsbc-burner", position = {index * 7, 0},
      force = "player", quality = index % 2 == 0 and "rare" or "normal", raise_built = true})
    body.get_module_inventory().insert{name = "speed-module", count = 1, quality = "uncommon"}
    metadata(body).source.get_fuel_inventory().insert{name = "coal", count = 9, quality = "rare"}
    storage.bodies[index] = body
  end
  local body = storage.bodies[3]
  storage.extra = surface.create_entity{name = "nsbc-burner-source", position = body.position, force = body.force, quality = body.quality}
  storage.extra.disabled_by_script, storage.extra.energy = true, 0
  storage.extra.get_fuel_inventory().insert{name = "coal", count = 7, quality = "uncommon"}
  storage.foreign = surface.create_entity{name = "assembling-machine-1", position = {70, 0}, force = "player"}
  storage.tree = surface.create_entity{name = "tree-01", position = {80, 0}}
end)
script.on_load(function() loaded = true end)
script.on_configuration_changed(function() storage.configuration_changes = storage.configuration_changes + 1 end)
script.on_event(defines.events.on_tick, function(event)
  if not storage.seeded and event.tick == 5 then
    for _, body in ipairs(storage.bodies) do metadata(body).source.disabled_by_script = true end
  elseif not storage.seeded and event.tick == 25 then
    remote.call("nsb-legacy-qc", "seed", storage.bodies, storage.extra, storage.foreign, storage.tree)
    storage.seeded, loaded = true, false
    game.server_save("legacy-donor")
    helpers.write_file("legacy-donor.json", helpers.table_to_json({passed = true}), false)
  elseif storage.seeded and loaded then
    loaded = false
    assert(storage.configuration_changes == 0, "Fixture accidentally exercised configuration conversion")
    local report = remote.call("nsb-legacy-qc", "verify", storage.accepted == true)
    local name = storage.accepted and "legacy-reloaded" or "legacy-accepted"
    storage.accepted = true
    game.server_save(name)
    helpers.write_file(name .. ".json", helpers.table_to_json(report), false)
  end
end)
