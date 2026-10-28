-- Real baseline-save -> same-version candidate -> candidate reload acceptance.
local loaded = false
local function metadata(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end
script.on_init(function()
  storage.configuration_changes = 0
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 3); surface.force_generate_chunk_requests()
  local names = {"nsbc-copper", "nsbc-iron", "nsbc-burner", "nsbc-heat", "nsbc-electric", "nsbc-process", "nsbc-fluid-process"}
  for i, name in ipairs(names) do
    local body = assert(surface.create_entity{name = name, position = {i * 7, 0}, force = "player", quality = "rare", raise_built = true})
    body.get_module_inventory().insert{name = "speed-module", quality = "uncommon", count = 1}
    local source = metadata(body).source
    source.direction, source.mirroring = defines.direction.east, true
    if source.burner then source.get_fuel_inventory().insert{name = "coal", quality = "rare", count = 9} end
    if name == "nsbc-heat" then source.temperature = 637.5 end
    if name == "nsbc-process" then source.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", count = 9} end
    for index = 1, source.fluids_count do
      local filter = source.get_fluid_filter(index)
      if filter then source.set_fluid(index, {name = filter.name, amount = 31.25, temperature = filter.name == "steam" and 200 or 48}) end
    end
  end
end)
script.on_load(function() loaded = true end)
script.on_configuration_changed(function() storage.configuration_changes = storage.configuration_changes + 1 end)
script.on_event(defines.events.on_tick, function(event)
  if not storage.seeded and event.tick == 5 then
    -- Let native quality/module-dependent burner capacities settle before taking
    -- custody. Otherwise the donor itself loses its transient excess next tick.
    for _, body in pairs(game.surfaces[1].find_entities_filtered{type = "beacon"}) do
      metadata(body).source.disabled_by_script = true
    end
  elseif not storage.seeded and event.tick == 25 then
    local report = remote.call("nsbc-schema-qc", "seed")
    storage.seeded, storage.seed_configuration_changes = true, storage.configuration_changes
    loaded = false
    game.server_save("schema-donor")
    helpers.write_file("schema-donor.json", helpers.table_to_json(report), false)
  elseif loaded and storage.seeded then
    loaded = false
    local reload = storage.converted == "bootstrap"
    if storage.converted then
      assert(storage.configuration_changes == storage.seed_configuration_changes, "Bootstrap/reload unexpectedly ran configuration migration")
    end
    local report = remote.call("nsbc-schema-qc", "verify", reload)
    report.passed, report.same_version_on_load = true, storage.converted ~= nil
    report.configuration_changes = storage.configuration_changes
    local name
    if not storage.converted then
      name = "schema-bootstrap-donor"
      remote.call("nsbc-schema-qc", "bootstrap_donor")
      storage.converted = "historical"
      storage.seed_configuration_changes = storage.configuration_changes
      report.reconstructed_lookup_for_next_stage = true
    else
      name = reload and "schema-reloaded" or "schema-accepted"
      storage.converted = "bootstrap"
    end
    game.server_save(name)
    helpers.write_file(name .. ".json", helpers.table_to_json(report), false)
  end
end)
