-- Private paired baseline/candidate instrumentation; never packaged.
local qc_power = require("scripts.power")
local qc_counts = {updates = 0, events = 0}
local qc_totals = {updates = 0, events = 0}
local qc_update = qc_power.update
qc_power.update = function(record)
  qc_counts.updates = qc_counts.updates + 1
  qc_totals.updates = qc_totals.updates + 1
  return qc_update(record)
end
local qc_event = prototypes.recipe["nsb-internal-recipe"].on_crafted_event
if qc_event then
  local original = script.get_event_handler(qc_event)
  script.on_event(qc_event, function(event)
    qc_counts.events = qc_counts.events + 1
    qc_totals.events = qc_totals.events + 1
    original(event)
  end)
else
  local original = script.get_event_handler(defines.events.on_object_destroyed)
  script.on_event(defines.events.on_object_destroyed, function(event)
    local callback = storage.callbacks[event.registration_number]
    if callback and callback.kind == "power" then
      qc_counts.events = qc_counts.events + 1
      qc_totals.events = qc_totals.events + 1
    end
    original(event)
  end)
end
remote.add_interface("nsbc-events-qc", {
  counts = function(reset)
    local result = {updates = qc_counts.updates, events = qc_counts.events, native = qc_event ~= nil,
      total_updates = qc_totals.updates, total_events = qc_totals.events}
    if reset then qc_counts = {updates = 0, events = 0} end
    return result
  end,
  stale = function(first, second)
    if not qc_event then return true end
    local a, b = storage.beacons[first.unit_number], storage.beacons[second.unit_number]
    local manager = a.manager
    storage.manager_owners[manager.unit_number] = b.id
    local before = qc_counts.updates
    qc_power.crafted{entity = manager, recipe = "nsb-internal-recipe", tick = game.tick}
    assert(qc_counts.updates == before, "Mismatched manager event reached another record")
    storage.manager_owners[manager.unit_number] = a.id
    return true
  end,
  missing_definition = function(entity)
    if not qc_event then return true end
    local record = storage.beacons[entity.unit_number]
    local source, definition = record.source, common.definitions[entity.name]
    common.definitions[entity.name] = nil
    storage.schema = 1
    assert(lifecycle.upgrade_controllers())
    assert(record.phase == "protected" and record.source == source and source.valid and entity.valid)
    assert(not record.manager and source.disabled_by_script)
    common.definitions[entity.name] = definition
    return true
  end,
  missing_lookup = function(entity)
    if not qc_event then return true end
    local record = storage.beacons[entity.unit_number]
    local source, manager = record.source, record.manager
    local paused = source.disabled_by_script
    storage.manager_owners = nil
    assert(storage.schema == 2 and lifecycle.upgrade_controllers())
    assert(record.source == source and source.disabled_by_script == paused)
    assert(record.manager ~= manager and not manager.valid)
    assert(storage.manager_owners[record.manager_unit_number] == record.id)
    local before = qc_counts.updates
    qc_power.crafted{entity = manager, recipe = "nsb-internal-recipe", tick = game.tick}
    assert(qc_counts.updates == before, "Retired manager event reached its successor")
    assert(not lifecycle.upgrade_controllers(), "Repeated conversion rebuilt controllers")
    return true
  end
})
