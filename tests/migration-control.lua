-- File map: real upstream1.4.2 donor creation and continuation adoption/reload assertions.
-- blueprint: docs/lifecycle.md#verification
-- Both donor and candidate use upstream's original mod ID. The private runner
-- supplies the phase explicitly; identity cannot prove which code is loaded.
local continued = require("migration-phase").candidate
local modern_fluids = script.active_mods.base:match("^2%.1%.") ~= nil
local loaded = false
local names = {"nsbc-copper", "nsbc-iron", "nsbc-fractional", "nsbc-burner", "nsbc-electric", "nsbc-heat", "nsbc-process", "nsbc-fluid-process"}
local function metadata(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end
local function snapshot(source)
  local result = {name = source.name, quality = source.quality.name, direction = source.direction,
    mirrored = source.mirroring, energy = source.energy, progress = source.crafting_progress,
    bonus = source.bonus_progress, products = source.products_finished, fluids = {}, inventories = {}}
  for index = 1, modern_fluids and source.fluids_count or #source.fluidbox do
    result.fluids[index] = modern_fluids and source.get_fluid(index) or source.fluidbox[index]
  end
  for _, index in ipairs{defines.inventory.crafter_input, defines.inventory.crafter_output,
    defines.inventory.fuel, defines.inventory.burnt_result, defines.inventory.crafter_modules} do
    local inventory = source.get_inventory(index)
    if inventory then result.inventories[index] = inventory.get_contents() end
  end
  if source.burner then
    local fuel = source.burner.currently_burning
    result.burner = {burning = fuel and fuel.name.name, quality = fuel and fuel.quality.name,
      remaining = source.burner.remaining_burning_fuel, heat = source.burner.heat}
  end
  if source.prototype.heat_energy_source_prototype then result.temperature = source.temperature end
  return result
end
local function compare()
  for _, test in pairs(storage.cases) do
    local record = metadata(test.beacon)
    assert(record and record.source == test.source and test.source.valid, "NSBC-MIGRATION source identity " .. test.beacon.name)
    local current = snapshot(record.source)
    assert(helpers.table_to_json(current) == helpers.table_to_json(test.snapshot),
      "NSBC-MIGRATION state differs " .. test.beacon.name .. "\n" .. serpent.line(current) .. "\n" .. serpent.line(test.snapshot))
    assert(record.manager and record.manager.valid, "NSBC-MIGRATION controller missing")
    assert(math.abs((record.energy_reserve or 0) - (test.reserve or 0)) < 0.00001,
      "NSBC-MIGRATION saved energy reserve differs: " .. tostring(record.energy_reserve) .. " / " .. tostring(test.reserve))
    if test.beacon.name == "nsbc-burner" then assert(record.monitor and record.monitor.valid, "NSBC-MIGRATION module monitor missing") end
    log("NSBC-MIGRATION PASS: " .. test.beacon.name .. " " .. test.beacon.quality.name)
  end
end
script.on_init(function()
  assert(not continued, "Donor must be created under actual upstream NSB")
  storage.cases = {}
  remote.call("nonstandard-beacons", "force_migrations", true)
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0,0}, 3)
  surface.force_generate_chunk_requests()
  for i, name in ipairs(names) do
    for j, quality in ipairs{"normal", "rare"} do
      local beacon = surface.create_entity{name = name, position = {i*6, j*6}, force = "player", quality = quality, raise_built = true}
      beacon.get_module_inventory().insert{name = "speed-module", quality = "uncommon", count = 1}
      local source = metadata(beacon).source
      source.direction = defines.direction.east
      source.mirroring = true
      if source.prototype.fluid_energy_source_prototype then
        for index = 1, modern_fluids and source.fluids_count or #source.fluidbox do
          local filter = modern_fluids and source.get_fluid_filter(index) or source.fluidbox.get_filter(index)
          local name = filter and filter.name
          if name then
            local fluid = {name = name, amount = 37.25, temperature = name == "steam" and 200 or 48}
            if modern_fluids then source.set_fluid(index, fluid) else source.fluidbox[index] = fluid end
          end
        end
      end
      if source.burner then source.get_fuel_inventory().insert{name = "coal", quality = "rare", count = 11} end
      if name == "nsbc-heat" then source.temperature = 637.5 end
      if name == "nsbc-process" then source.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", quality = "normal", count = 7} end
      storage.cases[#storage.cases+1] = {beacon = beacon, source = source}
    end
  end
end)
script.on_load(function() loaded = true end)
script.on_configuration_changed(function()
  if continued then
    compare()
    -- A paused quality upgrade deliberately leaves surplus across the save boundary.
    for _, test in pairs(storage.cases) do
      if test.beacon.name == "nsbc-burner" and test.beacon.quality.name == "normal" then
        test.source.energy = 1000000000
        local total = test.source.energy
        assert(test.beacon.order_upgrade{target = {name = test.beacon.name, quality = "legendary"}, force = test.beacon.force})
        test.beacon = assert(test.beacon.apply_upgrade())
        local record = metadata(test.beacon)
        test.source, test.reserve = record.source, record.energy_reserve
        assert(test.reserve and test.reserve > 0, "NSBC-MIGRATION reserve not created")
        assert(math.abs(test.source.energy + test.reserve - total) < 0.00001, "NSBC-MIGRATION reserve energy differs")
        test.snapshot = snapshot(test.source)
        storage.reserve_case = test
        log("NSBC-RESERVE initial " .. serpent.line({energy = test.source.energy, heat = test.source.burner.heat, reserve = test.reserve,
          usage = test.source.prototype.get_max_energy_usage(test.source.quality), bonus = test.source.consumption_bonus, disabled = test.source.disabled_by_script}))
        break
      end
    end
    storage.migrated = true
    storage.save_at = game.tick + 2
    loaded = false
  end
end)
script.on_event(defines.events.on_tick, function(event)
  if not continued and modern_fluids and not storage.seeded and event.tick == 5 then
    for _, test in pairs(storage.cases) do test.source.disabled_by_script = true end
  end
  if continued and storage.reserve_case then
    local test = storage.reserve_case
    log("NSBC-RESERVE tick " .. event.tick .. " " .. serpent.line({energy = test.source.energy, heat = test.source.burner.heat,
      reserve = metadata(test.beacon).energy_reserve, disabled = test.source.disabled_by_script, bonus = test.source.consumption_bonus}))
  end
  if not continued and not storage.seeded and event.tick >= (modern_fluids and 25 or 5) then
    for _, test in pairs(storage.cases) do
      test.source.disabled_by_script = true
      test.snapshot = snapshot(test.source)
    end
    storage.seeded = true
    game.server_save("nsbc-donor")
    helpers.write_file("nsbc-donor-ready.json", helpers.table_to_json({tick = event.tick}), false)
  elseif continued and storage.save_at and event.tick >= storage.save_at then
    storage.save_at = nil
    compare()
    game.server_save("nsbc-adopted")
    helpers.write_file("nsbc-adopted-ready.json", helpers.table_to_json({tick = event.tick}), false)
  elseif continued and loaded and storage.migrated then
    loaded = false
    compare()
    helpers.write_file("nsbc-reload-ready.json", helpers.table_to_json({tick = event.tick}), false)
  end
end)
