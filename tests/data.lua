-- File map: isolated power, replacement, orientation and processing fixtures.
-- blueprint: docs/lifecycle.md#verification
local function beacon(name, energy, watts, family, recipe, modules)
  local prototype = table.deepcopy(data.raw.beacon.beacon)
  prototype.name, prototype.minable = name, {mining_time = 0.1, result = name}
  prototype.localised_name = "NSBC test: " .. name:gsub("nsbc%-", "")
  prototype.fast_replaceable_group = family
  prototype.energy_source, prototype.energy_usage = energy, watts
  prototype.effect_receiver = {uses_module_effects = modules or false}
  prototype.source_recipe = recipe
  prototype.module_slots = name == "nsbc-iron" and 6 or 4
  data:extend{prototype, {type = "item", name = name, icon = "__base__/graphics/icons/beacon.png", stack_size = 50, place_result = name}}
end
data:extend{{type = "fluid", name = "nsbc-nitrogen", icon = "__base__/graphics/icons/fluid/water.png",
  default_temperature = 25, max_temperature = 100, fuel_value = "12J", heat_capacity = "1kJ",
  base_color = {0, 0.5, 1}, flow_color = {0, 0.5, 1}}}
local fluid = {type = "fluid", burns_fluid = true, scale_fluid_usage = true, effectivity = 1,
  fluid_box = {volume = 100, filter = "nsbc-nitrogen", production_type = "input",
    pipe_connections = {{position = {0, -1}, direction = defines.direction.north, flow_direction = "input"}}}}
beacon("nsbc-copper", table.deepcopy(fluid), "60W", "nsbc-nitrogen")
beacon("nsbc-iron", table.deepcopy(fluid), "120W", "nsbc-nitrogen")
data.raw.beacon["nsbc-copper"].next_upgrade = "nsbc-iron"
beacon("nsbc-fractional", table.deepcopy(fluid), "0.6W", "nsbc-fractional")
beacon("nsbc-burner", {type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 2, burnt_inventory_size = 1, effectivity = 1}, "480kW", "nsbc-burner", nil, true)
beacon("nsbc-electric", {type = "electric-2-electric-boogaloo", usage_priority = "secondary-input", drain = "1W"}, "60W", "nsbc-electric", nil, true)
beacon("nsbc-heat", {type = "heat", max_temperature = 1000, specific_heat = "1MJ", max_transfer = "2GW", min_working_temperature = 500, connections = {{position = {0,-1}, direction = defines.direction.north}}}, "1MW", "nsbc-heat", nil, true)
data:extend{{type = "recipe", name = "nsbc-process", categories = {"nsb-filler-category"}, energy_required = 60,
  ingredients = {{type = "item", name = "iron-plate", amount = 1}}, results = {{type = "item", name = "copper-plate", amount = 1}}}}
beacon("nsbc-process", {type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 2, effectivity = 1}, "60W", "nsbc-process", "nsbc-process", true)

data:extend{{type = "item-with-tags", name = "nsbc-tagged-fuel", icon = "__base__/graphics/icons/coal.png",
  stack_size = 50, fuel_categories = {"chemical"}, fuel_value = "4MJ"}}
beacon("nsbc-small-burner", {type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 1, burnt_inventory_size = 1, effectivity = 1}, "480kW", "nsbc-burner", nil, true)
local capped = table.deepcopy(fluid)
capped.fluid_usage_per_tick = 0.05
beacon("nsbc-capped", capped, "60W", "nsbc-capped")
local thermal = table.deepcopy(fluid)
thermal.burns_fluid, thermal.effectivity, thermal.minimum_input_temperature = false, 0.5, 40
beacon("nsbc-thermal", thermal, "50kW", "nsbc-thermal")
beacon("nsbc-efficient", table.deepcopy(fluid), "60W", "nsbc-efficient", nil, true)
data.raw.beacon["nsbc-efficient"].effect_receiver.base_effect = {consumption = -0.5}
data:extend{{type = "recipe", name = "nsbc-fluid-process", categories = {"nsb-filler-category"}, energy_required = 60,
  ingredients = {{type = "fluid", name = "water", amount = 1}}, results = {{type = "fluid", name = "steam", amount = 1, temperature = 200}}}}
local process_energy = table.deepcopy(fluid)
-- The 2.0 migration donor keeps its historical three-box layout.
if mods["zzz-nonstandard-beacons"] and not mods["nsbc-migration"] then
  process_energy.output_fluid_box = {volume = 100, filter = "water", production_type = "output",
    pipe_connections = {{position = {0, 1}, direction = defines.direction.south, flow_direction = "output"}}}
  process_energy.spent_fluid = {name = "water", amount = 0.5, temperature = 25}
end
beacon("nsbc-fluid-process", process_energy, "60W", "nsbc-fluid-process", "nsbc-fluid-process")
data.raw.beacon["nsbc-fluid-process"].source_fluidboxes = {
  {volume = 100, filter = "water", production_type = "input", pipe_connections = {{position = {-1, 0}, direction = defines.direction.west, flow_direction = "input"}}},
  {volume = 100, filter = "steam", production_type = "output", pipe_connections = {{position = {1, 0}, direction = defines.direction.east, flow_direction = "output"}}}}
