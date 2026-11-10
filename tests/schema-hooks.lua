-- Private acceptance adapter appended to both historical and candidate control.
-- Never shipped. Snapshot excludes disposable controllers until conversion commits.
local schema_power = require("scripts.power")
local function custody()
  local result = {records = {}, pending = storage.pending, clone_pending = {},
    reserves = storage.energy_reserves, work = storage.work}
  for id, record in pairs(storage.beacons) do
    local source = record.source
    local entry = {body = record.beacon.unit_number, source = source.unit_number,
      phase = record.phase, issue = record.issue, deadline = record.deadline,
      disabled = source.disabled_by_script, resume_disabled = record.resume_disabled,
      direction = source.direction, mirrored = source.mirroring, energy = source.energy,
      reserve = record.energy_reserve, reserve_capacity = record.reserve_capacity,
      progress = source.crafting_progress, bonus = source.bonus_progress,
      result_quality = source.result_quality and source.result_quality.name, products = source.products_finished,
      fluids = {}, inventories = {}, escrow = {}, transfer = record.transfer_snapshot}
    for i = 1, source.fluids_count do entry.fluids[i] = source.get_fluid(i) end
    for _, i in ipairs{defines.inventory.crafter_input, defines.inventory.crafter_output,
      defines.inventory.fuel, defines.inventory.burnt_result, defines.inventory.crafter_modules} do
      local inventory = source.get_inventory(i)
      if inventory then entry.inventories[i] = inventory.get_contents() end
    end
    for i, inventory in pairs(record.escrow or {}) do entry.escrow[i] = inventory.get_contents() end
    if source.burner then
      local burning = source.burner.currently_burning
      entry.burner = {remaining = source.burner.remaining_burning_fuel, heat = source.burner.heat,
        fuel = burning and burning.name.name, quality = burning and burning.quality.name}
    end
    if source.prototype.heat_energy_source_prototype then entry.temperature = source.temperature end
    result.records[id] = entry
  end
  for id, clone in pairs(storage.clone_pending) do
    result.clone_pending[id] = {entity = clone.entity.unit_number, key = clone.key, deadline = clone.deadline}
  end
  return helpers.table_to_json(result)
end
remote.add_interface("nsbc-schema-qc", {
  seed = function()
    assert(storage.schema == 1 or storage.schema == 2)
    -- Upstream has no released structured schema-1 version. The default runner
    -- deliberately synthesizes that development shape; actual upstream donors
    -- are covered independently by migration.py and legacy_fixture.py.
    storage.schema, storage.manager_owners = 1, nil
    storage.qc_old_managers = {}
    for id, record in pairs(storage.beacons) do
      storage.qc_old_managers[id] = record.manager.unit_number
      record.source.disabled_by_script = true -- Deliberately later than resume_disabled.
      if record.name == "nsbc-burner" then
        record.energy_reserve, record.reserve_capacity = 1234.5, record.source.energy
        storage.energy_reserves[id] = true
      elseif record.name == "nsbc-process" then
        record.escrow = {[defines.inventory.crafter_input] = game.create_inventory(1)}
        record.escrow[defines.inventory.crafter_input].insert{name = "iron-plate", count = 7, quality = "rare"}
        record.transfer_snapshot = {energy = 0, fluids = {}, progress = 0.12345, bonus = 0}
        common.protect(record, "schema fixture: retained unresolved processing")
      elseif record.name == "nsbc-iron" then
        record.phase, record.deadline = "pending", game.tick + 100000
        storage.pending[id] = true
        local q = storage.work; q.tail = q.tail + 1
        local key = "pending:" .. id
        q.items[q.tail], q.seen[key] = {kind = "pending", id = id, key = key}, true
      elseif record.name == "nsbc-heat" then
        storage.clone_pending[id] = {entity = record.beacon, key = "schema-clone", deadline = game.tick + 100000}
        storage.clone_locations["schema-clone"] = id
        local q = storage.work; q.tail = q.tail + 1
        local key = "clone:" .. id
        q.items[q.tail], q.seen[key] = {kind = "clone", id = id, key = key}, true
      end
    end
    storage.qc_custody = custody()
    return {schema = storage.schema, custody = storage.qc_custody}
  end,
  bootstrap_donor = function()
    -- Isolate on_load from the engine's automatic checksum/configuration pass.
    -- The real historical conversion is verified separately before this reset.
    storage.qc_old_managers = {}
    for id, record in pairs(storage.beacons) do
      if common.valid(record.manager) then storage.qc_old_managers[id] = record.manager.unit_number end
      record.manager_unit_number = nil
    end
    storage.schema, storage.manager_owners = 1, nil
    storage.qc_custody = custody()
  end,
  verify = function(reload)
    assert(storage.schema == 2 and storage.manager_owners, "Controller schema was not upgraded")
    local current = custody()
    assert(current == storage.qc_custody, "Resource/transaction custody changed during conversion\n" .. current .. "\n" .. storage.qc_custody)
    local count, managers = 0, {}
    for id, record in pairs(storage.beacons) do
      if record.phase == "attached" then
        assert(record.manager.valid and record.manager.unit_number == record.manager_unit_number)
        assert(record.pointer == record.manager_unit_number, "Upstream pointer alias was not maintained")
        assert(storage.manager_owners[record.manager_unit_number] == id)
        assert(record.manager_unit_number ~= storage.qc_old_managers[id], "Old controller was not converted")
        managers[id] = record.manager_unit_number
        count = count + 1
      else
        assert(not record.manager and not record.monitor and not record.mimic, "Inactive controllers survived conversion")
        local owner = false
        for registration in pairs(record.callbacks) do
          local callback = storage.callbacks[registration]
          if callback and callback.kind == "source" then owner = true end
        end
        assert(owner, "Protected/pending source lost its destruction callback")
      end
    end
    local owners = 0
    for manager_id, id in pairs(storage.manager_owners) do
      assert(managers[id] == manager_id, "Stale or multiply owned controller")
      owners = owners + 1
    end
    assert(owners == count)
    for _, callback in pairs(storage.callbacks) do assert(callback.kind ~= "power", "Legacy power callback survived") end
    if reload then
      assert(helpers.table_to_json(managers) == storage.qc_new_managers, "Candidate reload rebuilt controllers")
      assert(not lifecycle.upgrade_controllers(), "Repeated conversion was not a no-op")
    else storage.qc_new_managers = helpers.table_to_json(managers) end
    return {schema = storage.schema, managers = count, records = table_size(storage.beacons),
      custody_preserved = true, protected_preserved = true, pending_preserved = true, reserve_preserved = true}
  end
})
