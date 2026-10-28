-- File map: conservation and deliberately interrupted attachment regression fixtures.
-- blueprint: docs/lifecycle.md#verification
local information = require("__zzz-nonstandard-beacons__/scripts/information")
local M = {}
local function check(ok, message) assert(ok, "NSBC-RECOVERY FAIL: " .. message); log("NSBC-RECOVERY PASS: " .. message) end
local function metadata(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end
local function create(name, x)
  return game.surfaces[1].create_entity{name = name, position = {x, 60}, force = "player", raise_built = true}
end
local function row(record, id)
  for _, entry in ipairs(information.rows(record)) do if entry.id == id then return entry.value end end
end
function M.tick(tick)
  if tick == 130 then
    local old = create("nsbc-burner", 0)
    local source = metadata(old).source
    local inventory = source.get_fuel_inventory()
    inventory[1].set_stack{name = "nsbc-tagged-fuel", count = 7, quality = "rare"}
    inventory[1].tags = {fixture = "rich-stack", nested = {answer = 42}}
    inventory[2].set_stack{name = "coal", count = 19, quality = "legendary"}
    source.disabled_by_script = true
    local successor = old.surface.create_entity{name = "nsbc-small-burner", position = old.position, force = old.force,
      fast_replace = true, raise_built = true}
    local record = metadata(successor)
    check(not old.valid and record and record.phase == "protected", "script replacement retains solid overflow")
    check(record.source.disabled_by_script, "incomplete successor remains disabled")
    local refund = game.create_inventory(10)
    local ok, reason = remote.call("nonstandard-beacons", "adopt-beacon", successor, refund)
    check(ok, "idempotent overflow repair: " .. tostring(reason))
    local fuel = metadata(successor).source.get_fuel_inventory()
    local tagged = fuel[1].name == "nsbc-tagged-fuel" and fuel[1] or refund.find_item_stack("nsbc-tagged-fuel")
    check(tagged and tagged.count == 7 and tagged.quality.name == "rare" and tagged.tags.nested.answer == 42, "rich fuel stack conserved")
    check(fuel.get_item_count{name = "coal", quality = "legendary"} + refund.get_item_count{name = "coal", quality = "legendary"} == 19, "overflow quantity and quality conserved")
    check(remote.call("nonstandard-beacons", "adopt-beacon", successor, refund), "repeat repaired adoption")
    storage.recovery_refund = refund

    local remainder = create("nsbc-copper", -12)
    local fluid_source = metadata(remainder).source
    fluid_source.set_fluid(1, {name = "nsbc-nitrogen", amount = 95, temperature = 25})
    remote.call("nsbc-qc", "fault", remainder, "fluid-remainder")
    check(not remote.call("nonstandard-beacons", "adopt-beacon", remainder), "partial fluid repair remains protected")
    check(math.abs(metadata(remainder).transfer_snapshot.remaining_fluids[1].amount - 15) < 0.00001, "only accepted fluid leaves custody")
    check(not remote.call("nonstandard-beacons", "adopt-beacon", remainder), "full buffer repair retry remains protected")
    check(math.abs(metadata(remainder).transfer_snapshot.remaining_fluids[1].amount - 15) < 0.00001, "repeat full-buffer repair cannot duplicate fluid")
    fluid_source.set_fluid(1, {name = "nsbc-nitrogen", amount = 80, temperature = 27.5})
    check(remote.call("nonstandard-beacons", "adopt-beacon", remainder), "remaining fluid repairs after capacity is available")
    check(math.abs(fluid_source.get_fluid(1).amount - 95) < 0.00001, "repair adds only the saved remainder")

    local protected = create("nsbc-copper", 12)
    remote.call("nsbc-qc", "fault", protected, "transfer")
    check(not remote.call("nonstandard-beacons", "adopt-beacon", protected), "unresolved processing snapshot cannot be cleared by repair")
    protected.order_upgrade{target = {name = "nsbc-iron", quality = "normal"}, force = protected.force}
    protected = protected.apply_upgrade()
    check(metadata(protected).phase == "protected" and metadata(protected).transfer_snapshot, "subsequent upgrade cannot bypass unresolved snapshot")

    local repair = create("nsbc-burner", 24)
    metadata(repair).manager.destroy()
    storage.delayed_repair = repair
    local relocated = create("nsbc-burner", 36)
    metadata(relocated).source.teleport({36, 66})
    check(not remote.call("nonstandard-beacons", "adopt-beacon", relocated), "repair rejects misaligned source")
    metadata(relocated).source.teleport(relocated.position)
    check(remote.call("nonstandard-beacons", "adopt-beacon", relocated), "repair succeeds after source alignment restored")
    local cancelled = create("nsbc-copper", 48)
    cancelled.order_upgrade{target = {name = "nsbc-iron", quality = "normal"}, force = cancelled.force}
    cancelled.cancel_upgrade(cancelled.force)
    check(cancelled.valid and metadata(cancelled).phase == "attached", "cancelled upgrade preserves attachment")
    cancelled.order_deconstruction(cancelled.force)
    check(metadata(cancelled).source.disabled_by_script, "deconstruction pauses source")
    cancelled.cancel_deconstruction(cancelled.force)
    check(not metadata(cancelled).source.disabled_by_script, "cancelled deconstruction resumes source")
    metadata(cancelled).source.disabled_by_script = true
    metadata(cancelled).source.set_fluid(1, {name = "nsbc-nitrogen", amount = 40, temperature = 35})
    remote.call("nonstandard-beacons", "set-beacon-orientation", cancelled, 4, true)
    cancelled.surface.clone_area{source_area = {{45, 57}, {51, 63}}, destination_area = {{45, 87}, {51, 93}},
      clone_tiles = false, clone_entities = true, clear_destination_entities = true, clear_destination_decoratives = true}

    local capped = create("nsbc-capped", 60)
    check(row(metadata(capped), "operating-requirement") == "5/s" and row(metadata(capped), "configured-cap") == "3/s", "fluid cap distinct from demand")
    local thermal = create("nsbc-thermal", 72)
    metadata(thermal).source.set_fluid(1, {name = "nsbc-nitrogen", amount = 100, temperature = 75})
    check(row(metadata(thermal), "operating-requirement") == "2/s", "thermal energy and effectivity calculation")
    local efficient = create("nsbc-efficient", 84)
    check(row(metadata(efficient), "operating-requirement") == "2.5/s", "consumption effect calculation")
    check(information.number(0.0001) ~= "0", "positive fractional display")
    check(row(metadata(storage.fixture["nsbc-electric"]), "idle-drain") == "1 W", "electric idle drain separate")
    check(row(metadata(storage.fixture["nsbc-heat"]), "maximum-temperature") == "1000 °C", "heat maximum temperature retained")
    storage.thermal = thermal
    storage.thermal_start = metadata(thermal).source.get_fluid(1).amount
    storage.fluid_process = create("nsbc-fluid-process", 96)
    local process = metadata(storage.fluid_process).source
    local energy_box = process.prototype.fluid_energy_source_prototype.fluid_box
    local energy_index, spent_index
    local input_index, output_index
    for index = 1, process.fluids_count do
      local box = process.get_fluid_box_prototype(index)
      log("NSBC-FLUID ROLE " .. serpent.line({index = index, filter = box.filter and box.filter.name, role = box.production_type, energy = box == energy_box}))
      if box == energy_box then energy_index = index end
      if box == process.prototype.fluid_energy_source_prototype.output_fluid_box then spent_index = index end
      if box.filter and box.filter.name == "water" and box.production_type == "input" then input_index = index end
      if box.filter and box.filter.name == "steam" then output_index = index end
    end
    check(input_index and output_index and energy_index ~= input_index and energy_index ~= output_index, "fuel-fluid role is distinct from recipe fluids")
    process.set_fluid(energy_index, {name = "nsbc-nitrogen", amount = 80, temperature = 35})
    process.set_fluid(input_index, {name = "water", amount = 50, temperature = 25})
    process.set_fluid(output_index, {name = "steam", amount = 10, temperature = 200})
    check(spent_index and spent_index ~= input_index, "same fluid distinguished by energy output and recipe input roles")
    process.set_fluid(spent_index, {name = "water", amount = 15, temperature = 25})
    check(row(metadata(storage.fluid_process), "operating-requirement") == "5/s", "custom recipe demand uses energy-fluid role")
    check(row(metadata(storage.fluid_process), "recipe-fluid-" .. input_index) and row(metadata(storage.fluid_process), "recipe-fluid-" .. output_index), "recipe fluids displayed separately")
    check(row(metadata(storage.fluid_process), "spent-fluid") and not row(metadata(storage.fluid_process), "recipe-fluid-" .. spent_index), "spent energy fluid is not a recipe fluid")
  elseif tick == 141 then
    local copy = game.surfaces[1].find_entities_filtered{name = "nsbc-copper", position = {48, 90}}[1]
    local clone = copy and metadata(copy)
    check(clone and clone.phase == "attached" and clone.source.get_fluid(1).amount == 40, "native area clone preserves source snapshot")
    check(clone.source.direction == 4 and clone.source.mirroring and #copy.surface.find_entities_filtered{name = "nsbc-copper-source", position = copy.position} == 1,
      "native area clone adopts exactly one oriented source")
    local record = metadata(storage.delayed_repair)
    check(record.phase == "protected", "destroyed-controller callback protects source")
    check(remote.call("nonstandard-beacons", "adopt-beacon", storage.delayed_repair), "delayed controller repair succeeds")
    check(not metadata(storage.delayed_repair).source.disabled_by_script, "controller repair restores prior enabled state")
  elseif tick == 190 then
    local old = storage.fluid_process
    local source = metadata(old).source
    local progress, fluids = source.crafting_progress, {}
    for index = 1, source.fluids_count do fluids[index] = source.get_fluid(index) end
    old.order_upgrade{target = {name = old.name, quality = "rare"}, force = old.force}
    local successor = old.apply_upgrade()
    local current = metadata(successor)
    check(current.phase == "attached" and current.source.crafting_progress == progress, "in-flight fluid recipe survives quality upgrade")
    for index, fluid in pairs(fluids) do
      local after = current.source.get_fluid(index)
      check(after.name == fluid.name and math.abs(after.amount - fluid.amount) < 0.00001 and after.temperature == fluid.temperature, "recipe and energy fluid conservation " .. index)
    end
    local used = storage.thermal_start - metadata(storage.thermal).source.get_fluid(1).amount
    check(math.abs(used - 2) < 0.01, "thermal controlled engine depletion " .. used)
    log("NSBC-RECOVERY COMPLETE")
  end
end
return M
