if settings.startup["nsb-include-example-beacons"].value then
  data:extend{
    {
      name = "burner-beacon",
      type = "beacon",
      icon = "__base__/graphics/icons/beacon.png",
      flags = {"placeable-player", "player-creation"},
      minable = {mining_time = 0.5, result = "burner-beacon"},
      collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
      selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
      drawing_box_vertical_extension = 0.7,
      allowed_effects = {"consumption", "speed", "pollution"},
      graphics_set = require("__base__.prototypes.entity.beacon-animations"),
      energy_usage = "480kW",
      energy_source = {
        type = "burner",
        fuel_categories = {"chemical"},
        effectivity = 1,
        fuel_inventory_size = 1,
        emissions_per_minute = { pollution = 30 },
        smoke = {{
          name = "smoke",
          position = {0, 0},
          frequency = 15,
          starting_vertical_speed = 0.0,
          starting_frame_deviation = 60
        }}
      },
      radius_visualisation_picture = {
        filename = "__base__/graphics/entity/beacon/beacon-radius-visualization.png",
        priority = "extra-high-no-scale",
        width = 10,
        height = 10
      },
      supply_area_distance = 3,
      distribution_effectivity = 1.5,
      module_slots = 2,
      icons_positioning = {{inventory_index = defines.inventory.beacon_modules, shift = {0, 0}, multi_row_initial_height_modifier = -0.3, max_icons_per_row = 2}}
    },
    {
      name = "fluid-beacon",
      type = "beacon",
      icon = "__base__/graphics/icons/beacon.png",
      flags = {"placeable-player", "player-creation"},
      minable = {mining_time = 0.5, result = "fluid-beacon"},
      collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
      selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
      drawing_box_vertical_extension = 0.7,
      allowed_effects = {"consumption", "speed", "pollution"},
      graphics_set = require("__base__.prototypes.entity.beacon-animations"),
      energy_usage = "480kW",
      energy_source = {
        type = "fluid",
        effectivity = 1,
        maximum_temperature = 500,
        fluid_box = {
          volume = 200,
          pipe_covers = pipecoverspictures(),
          pipe_connections = {
            { flow_direction = "input-output", direction = defines.direction.north, position = {0, -1} },
            { flow_direction = "input-output", direction = defines.direction.east, position = {1, 0} },
            { flow_direction = "input-output", direction = defines.direction.south, position = {0, 1} },
            { flow_direction = "input-output", direction = defines.direction.west, position = {-1, 0} }
          },
          production_type = "input",
          filter = "steam"
        },
        smoke = {{
          name = "smoke",
          position = {0, 0},
          frequency = 15,
          starting_vertical_speed = 0.0,
          starting_frame_deviation = 60
        }}
      },
      radius_visualisation_picture = {
        filename = "__base__/graphics/entity/beacon/beacon-radius-visualization.png",
        priority = "extra-high-no-scale",
        width = 10,
        height = 10
      },
      supply_area_distance = 3,
      distribution_effectivity = 1.5,
      module_slots = 2,
      icons_positioning = {{inventory_index = defines.inventory.beacon_modules, shift = {0, 0}, multi_row_initial_height_modifier = -0.3, max_icons_per_row = 2}}
    },
    {
      name = "heat-beacon",
      type = "beacon",
      icon = "__base__/graphics/icons/beacon.png",
      flags = {"placeable-player", "player-creation"},
      minable = {mining_time = 0.5, result = "heat-beacon"},
      collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
      selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
      drawing_box_vertical_extension = 0.7,
      allowed_effects = {"consumption", "speed", "pollution"},
      graphics_set = require("__base__.prototypes.entity.beacon-animations"),
      energy_usage = "480kW",
      energy_source = {
        type = "heat",
        max_temperature = 1000,
        specific_heat = "1MJ",
        max_transfer = "2GW",
        min_working_temperature = 500,
        minimum_glow_temperature = 350,
        connections = {
          { position = {0, -1}, direction = defines.direction.north },
          { position = {1, 0}, direction = defines.direction.east },
          { position = {0, 1}, direction = defines.direction.south },
          { position = {-1, 0}, direction = defines.direction.west }
        }
      },
      radius_visualisation_picture = {
        filename = "__base__/graphics/entity/beacon/beacon-radius-visualization.png",
        priority = "extra-high-no-scale",
        width = 10,
        height = 10
      },
      supply_area_distance = 3,
      distribution_effectivity = 1.5,
      module_slots = 2,
      icons_positioning = {{inventory_index = defines.inventory.beacon_modules, shift = {0, 0}, multi_row_initial_height_modifier = -0.3, max_icons_per_row = 2}}
    },
    {
      name = "burner-beacon",
      type = "item",
      icon = "__base__/graphics/icons/beacon.png",
      place_result = "burner-beacon",
      stack_size = 20
    },
    {
      name = "fluid-beacon",
      type = "item",
      icon = "__base__/graphics/icons/beacon.png",
      place_result = "fluid-beacon",
      stack_size = 20
    },
    {
      name = "heat-beacon",
      type = "item",
      icon = "__base__/graphics/icons/beacon.png",
      place_result = "heat-beacon",
      stack_size = 20
    },
    {
      type = "recipe",
      name = "burner-beacon",
      enabled = false,
      energy_required = 15,
      ingredients =
      {
        {type = "item", name = "electronic-circuit", amount = 20},
        {type = "item", name = "advanced-circuit", amount = 20},
        {type = "item", name = "steel-plate", amount = 10},
        {type = "item", name = "copper-cable", amount = 10}
      },
      results = {{type = "item", name = "burner-beacon", amount = 1}}
    },
    {
      type = "recipe",
      name = "fluid-beacon",
      enabled = false,
      energy_required = 15,
      ingredients =
      {
        {type = "item", name = "electronic-circuit", amount = 20},
        {type = "item", name = "advanced-circuit", amount = 20},
        {type = "item", name = "steel-plate", amount = 10},
        {type = "item", name = "copper-cable", amount = 10}
      },
      results = {{type = "item", name = "fluid-beacon", amount = 1}}
    },
    {
      type = "recipe",
      name = "heat-beacon",
      enabled = false,
      energy_required = 15,
      ingredients =
      {
        {type = "item", name = "electronic-circuit", amount = 20},
        {type = "item", name = "advanced-circuit", amount = 20},
        {type = "item", name = "steel-plate", amount = 10},
        {type = "item", name = "copper-cable", amount = 10}
      },
      results = {{type = "item", name = "heat-beacon", amount = 1}}
    },
  }

  -- add beacon recipes to beacon tech
  data.raw["technology"]["effect-transmission"].effects = {
    {
      type = "unlock-recipe",
      recipe = "beacon"
    },
    {
      type = "unlock-recipe",
      recipe = "burner-beacon"
    },
    {
      type = "unlock-recipe",
      recipe = "fluid-beacon"
    },
    {
      type = "unlock-recipe",
      recipe = "heat-beacon"
    }
  }
end

-- Wait, that's it?
-- Yup. Just define your beacons as normal (minus the energy_source, of course) before data-final-fixes.lua and this mod will handle the rest!