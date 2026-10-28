-- Private original-ID migration fault adapter. Appended only in an isolated test copy.
local function legacy_snapshot(entities)
  local result = {}
  for _, entity in ipairs(entities) do
    assert(entity.valid)
    local row = {id = entity.unit_number, name = entity.name, direction = entity.direction,
      mirror = entity.mirroring, energy = entity.energy, progress = entity.crafting_progress,
      bonus = entity.bonus_progress, inventories = {}, fluids = {}}
    for _, index in ipairs{defines.inventory.fuel, defines.inventory.burnt_result, defines.inventory.crafter_modules} do
      local inventory = entity.get_inventory(index)
      if inventory then row.inventories[index] = inventory.get_contents() end
    end
    for index = 1, entity.fluids_count do row.fluids[index] = entity.get_fluid(index) end
    if entity.burner then
      local fuel = entity.burner.currently_burning
      row.burning = {name = fuel and fuel.name.name, quality = fuel and fuel.quality.name,
        remaining = entity.burner.remaining_burning_fuel, heat = entity.burner.heat}
    end
    result[#result + 1] = row
  end
  return helpers.table_to_json(result)
end
remote.add_interface("nsb-legacy-qc", {
  seed = function(bodies, extra_source, foreign, tree)
    local old, resources, records = storage.beacons, {}, {}
    for _, body in ipairs(bodies) do
      local current = old[body.unit_number]
      resources[#resources + 1] = current.source
      records[#records + 1] = {beacon = body, source = current.source, manager = current.manager,
        monitor = current.monitor, mimic = current.mimic, pointer = current.manager_unit_number}
      body.custom_status = {diode = defines.entity_status_diode.yellow, label = "legacy status"}
    end
    resources[#resources + 1] = extra_source
    storage.qc_legacy = {bodies = bodies, sources = resources, foreign = foreign, tree = tree,
      foreign_helper = records[5].manager, snapshot = legacy_snapshot(resources)}
    local map = {}
    -- Rekey through a separate map: these two valid records deliberately exchange keys.
    map[bodies[2].unit_number], map[bodies[1].unit_number] = records[1], records[2]
    for index = 3, #bodies do map[bodies[index].unit_number] = records[index] end
    map[9000001] = {beacon = bodies[3], source = extra_source}
    records[4].manager = records[5].manager -- Correct helper prototype, wrong location/owner.
    records[6].source = foreign -- Must never pause/destroy an unrelated machine.
    records[7].phase, records[7].issue = "protected", "retained partial-record diagnostic"
    records[7].resume_disabled, records[7].energy_reserve = false, 1234.5
    records[7].escrow = {[defines.inventory.crafter_input] = game.create_inventory(1)}
    records[7].escrow[defines.inventory.crafter_input].insert{name = "iron-plate", quality = "rare", count = 7}
    records[8].phase, records[8].deadline = "pending", nil
    storage.pending[bodies[8].unit_number] = true
    map[9000002], map[9000003] = 17, tree -- Neither is a plain record table.
    storage.beacons, storage.callbacks = map, {}
    storage.deathrattles = {[1234567] = records[1]}
    storage.beacon_pointers = {[records[1].pointer] = bodies[1].unit_number}
    storage.watched_beacons = {[1] = bodies[1]}
    storage.schema, storage.manager_owners = nil, nil
  end,
  verify = function(reload)
    local q = storage.qc_legacy
    for _, version in ipairs{"1.4.2", "2.0.0"} do legacy.require_supported_version(version) end
    legacy.require_supported_version(nil)
    for _, version in ipairs{"0.9.0", "1.3.5", "1.4.0", "1.4.1"} do
      assert(not pcall(legacy.require_supported_version, version), "Unsupported donor passed version guard")
    end
    lifecycle.expire(game.tick)
    assert(storage.schema == 2 and storage.manager_owners)
    assert(storage.deathrattles == nil and storage.beacon_pointers == nil and storage.watched_beacons == nil)
    assert(legacy_snapshot(q.sources) == q.snapshot, "Legacy conversion changed source resource state")
    for _, index in ipairs{1, 2} do
      local body = q.bodies[index]
      local record = assert(storage.beacons[body.unit_number], "Rekey lost a record")
      assert(record.beacon == body and record.phase == "attached")
      assert(record.source == q.sources[index] and record.source.disabled_by_script)
      assert(record.manager.valid and record.pointer == record.manager_unit_number)
      assert(storage.manager_owners[record.pointer] == record.id)
      assert(record.monitor.valid and record.mimic.valid)
    end
    for _, index in ipairs{3, 4, 5, 6, 7, 8} do
      assert(storage.beacons[q.bodies[index].unit_number].phase == "protected", "Ambiguous record was enabled")
    end
    local partial = storage.beacons[q.bodies[7].unit_number]
    assert(not storage.pending[q.bodies[8].unit_number], "Partial transaction kept invalid scheduling")
    assert(partial.issue == "retained partial-record diagnostic" and partial.resume_disabled == false)
    local escrow_stack = partial.escrow[defines.inventory.crafter_input][1]
    assert(partial.energy_reserve == 1234.5 and escrow_stack.valid_for_read
      and escrow_stack.name == "iron-plate" and escrow_stack.quality.name == "rare" and escrow_stack.count == 7)
    assert(q.foreign.valid and not q.foreign.disabled_by_script and q.tree.valid, "Foreign entity was mutated")
    assert(q.foreign_helper.valid, "Unverified helper ownership authorized destruction")
    assert(#storage.legacy_orphans == 3, "Conflicting/malformed records were lost")
    for attempt = 1, 2 do
      local ok, reason = lifecycle.attach(q.bodies[3], game.tick, {adopting = true})
      assert(not ok and reason, "Explicit repair waived unresolved source ownership")
      assert(storage.beacons[q.bodies[3].unit_number].phase == "protected")
      assert(not lifecycle.upgrade_controllers(), "Repeated conversion was not idempotent")
    end
    assert(legacy_snapshot(q.sources) == q.snapshot and #storage.legacy_orphans == 3)
    local managers = {}
    for id, record in pairs(storage.beacons) do managers[id] = record.manager_unit_number or false end
    local current = helpers.table_to_json(managers)
    if reload then assert(current == q.managers, "Reload rebuilt settled controllers") else q.managers = current end
    return {passed = true, records = table_size(storage.beacons), quarantined = #storage.legacy_orphans,
      same_code_on_load = true, source_custody = true, malformed_values = true, swapped_keys = true,
      duplicate_ids = true, foreign_ownership = true, repeated_repair = true, pointer_alias = true,
      partial_protected_state = true, partial_pending_state = true, reload = reload}
  end
})
