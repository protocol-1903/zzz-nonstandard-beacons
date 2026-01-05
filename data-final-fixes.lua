local uses_module_effects = false
local event_filter, deconstruction_filter, modded_beacons = {}, {}, {}

local function extract_power(energy)
  local mult = not tonumber(energy:sub(1, -2)) and energy:sub(-2, -2) or nil
  return (mult and energy:sub(1, -3) or energy:sub(1, -2)) * (energy:sub(-1) == "J" and 60 or 1) * 10^(
    mult == "k" and 3 or mult == "M" and 6 or
    mult == "G" and 9 or mult == "T" and 12 or
    mult == "P" and 15 or mult == "E" and 18 or
    mult == "Z" and 21 or mult == "Y" and 24 or
    mult == "R" and 27 or mult == "Q" and 30 or 1
  )
end

local function calculate_power(energy)
  local mult = 0
  while energy >= 1000 do
    energy = energy / 1000
    mult = mult + 1
  end
  -- convert to 000 or 00.0 or 0.0
  if energy >= 100 then
    energy = math.floor(energy)
  else
    energy = math.floor(energy * 10) / 10
  end
  return energy,
    mult == 1 and "k" or mult == 2 and "M" or
    mult == 3 and "G" or mult == 4 and "T" or
    mult == 5 and "P" or mult == 6 and "E" or
    mult == 7 and "Z" or mult == 8 and "Y" or
    mult == 9 and "R" or mult == 10 and "Q" or ""
end

for p, prototype in pairs(data.raw.beacon) do
  if prototype.energy_source.type ~= "void" and prototype.energy_source.type ~= "electric" then
    -- validate optional properties
    if prototype.effect_receiver and (prototype.effect_receiver.uses_beacon_effects or prototype.effect_receiver.uses_surface_effects) and prototype.effect_receiver.uses_module_effects then
      error("Failed to load nonstandard beacon " .. p .. "\neffect_receiver.uses_beacon_effects and effect_receiver.uses_module_effects cannot be used together!")
    end

    -- replace electric boogaloo
    prototype.energy_source.type = prototype.energy_source.type == "electric-2-electric-boogaloo" and "electric" or prototype.energy_source.type
    
    -- copy for ease of use
    local effect_receiver = prototype.effect_receiver

    -- store data for use during scripting
    event_filter[#event_filter+1] = {filter = "name", name = p}
    deconstruction_filter[#deconstruction_filter+1] = p
    modded_beacons[p] = effect_receiver and effect_receiver.uses_module_effects or false

    -- update if the value is used anywhere
    uses_module_effects = uses_module_effects or effect_receiver and effect_receiver.uses_module_effects or false

    -- create energy source entity, storing the 'disabled' localisation to simplify runtime scripting
    data:extend{{
      type = "assembling-machine",
      name = p .. "-source",
      localised_name = prototype.localised_name or {"?", {"item-name." .. p}, {"entity-name." .. p}},
      localised_description = prototype.localised_description or {"?", {"item-description." .. p}, {"entity-description." .. p}},
      icon = prototype.icon,
      minable = prototype.minable,
      icon_size = prototype.icon_size,
      icons = prototype.icons,
      energy_usage = prototype.energy_usage,
      energy_source = prototype.energy_source,
      crafting_categories = {"nsb-filler-category"},
      fixed_recipe = "nsb-filler-recipe",
      crafting_speed = 1,
      create_corpse_on_death = false,
      flags = {
        "placeable-off-grid",
        "not-repairable",
        "not-on-map",
        "not-blueprintable",
        "not-deconstructable",
        "no-copy-paste",
        "not-upgradable",
        "placeable-neutral"
      },
      icon_draw_specification = {scale = 0, scale_for_many = 0},
      icons_positioning = {{inventory_index = defines.inventory.crafter_modules, scale = 0}},
      selectable_in_game = false,
      allow_copy_paste = false,
      effect_receiver = effect_receiver and {
        uses_beacon_effects = effect_receiver.uses_beacon_effects,
        uses_module_effects = effect_receiver.uses_module_effects,
        uses_surface_effects = effect_receiver.uses_surface_effects
      },
      module_slots = effect_receiver and effect_receiver.uses_module_effects and prototype.module_slots or 0, -- only copy if it uses module effects
      allowed_effects = {"consumption", "pollution", "speed", "productivity", "quality"},
      quality_affects_energy_usage = true,
      collision_box = prototype.collision_box,
      collision_mask = { layers = {} },
      selection_box = prototype.selection_box,
      selection_priority = 0,
      hidden = true,
      hidden_in_factoriopedia = true
    }}

    local source = data.raw["assembling-machine"][p .. "-source"]

    -- change the beacon to be non-interactible by inserters if burner powered
    if prototype.energy_source.type == "burner" then
      prototype.flags = prototype.flags or {}
      prototype.flags[#prototype.flags+1] = "no-automated-item-insertion"
      prototype.flags[#prototype.flags+1] = "no-automated-item-removal"
    else -- allow module insertion if not a burner
      source.flags[#source.flags+1] = "no-automated-item-insertion"
      source.flags[#source.flags+1] = "no-automated-item-removal"
    end

    -- override the energy source
    prototype.energy_source = {type = "void"}

    -- clear custom flags
    prototype.effect_receiver = nil

    -- set custom tooltip data
    local fields = {}
    -- module/beacon effectiveness on the beacon
    fields[#fields + 1] = source.module_slots > 0 and {
      name = "",
      value = {"custom-tooltip.affected-by-modules"}
    } or nil
    fields[#fields + 1] = effect_receiver and effect_receiver.uses_beacon_effects and {
      name = "",
      value = {"custom-tooltip.affected-by-beacons"}
    } or nil
    
    -- power calculations for consumption
    local power = extract_power(source.energy_usage) / (source.effectivity or 1)
    local prefix, mult = calculate_power(power)
    local consumption = tostring(prefix) .. " " .. mult .. "W"

    if source.energy_source.type == "electric" then
      fields[#fields + 1] = {
        name = "",
        value = {"custom-tooltip.header", {"", "[img=tooltip-category-electricity]", " ", {"tooltip-category.consumes"}, " ", {"tooltip-category.electricity"}}}
      }
      fields[#fields + 1] = {
        name = {"description.max-energy-consumption"},
        value = consumption
      }
      -- min consumption, only applies to electrics
      fields[#fields + 1] = source.drain and {
        name = {"description.min-energy-consumption"},
        value = source.drain
      } or nil
    elseif source.energy_source.type == "burner" then
      local category = #(source.energy_source.fuel_categories or {}) == 1 and source.energy_source.fuel_categories[1] or nil
      local tooltip_category = category and data.raw.sprite["tooltip-category-" .. category] and "tooltip-category-" .. category or "tooltip-category-consumes"
      fields[#fields + 1] = {
        name = "",
        value = {"custom-tooltip.header", {"", "[img=" .. tooltip_category .. "]", " ", {"tooltip-category.consumes"}, " ", category and {"fuel-category-name." .. category}}}
      }
      fields[#fields + 1] = {
        name = {"description.max-energy-consumption"},
        value = consumption
      }
      -- efficiency, not always appliccable
      fields[#fields + 1] = source.effectivity and {
        name = {"description.effectivity"},
        value = tostring(math.floor(source.effectivity * 1000) / 10) .. "%"
      }
    elseif source.energy_source.type == "fluid" then
      local fluid = source.energy_source.fluid_box.filter
      local tooltip_category = fluid and data.raw.sprite["tooltip-category-" .. fluid] and "tooltip-category-" .. fluid or "tooltip-category-consumes"
      fields[#fields + 1] = {
        name = "",
        value = {"custom-tooltip.header", {"", "[img=" .. tooltip_category .. "]", " ", {"tooltip-category.consumes"}, " ", fluid and {"fluid-name." .. fluid} or {"tooltip-category.fluid"}}}
      }
      fields[#fields + 1] = {
        name = {"description.max-energy-consumption"},
        value = consumption
      }
      -- efficiency, not always appliccable
      fields[#fields + 1] = source.effectivity and {
        name = {"description.effectivity"},
        value = tostring(math.floor(source.effectivity * 1000) / 10) .. "%"
      }
      fields[#fields + 1] = source.energy_source.maximum_temperature and {
        name = {"description.maximum-temperature"},
        value = {"", tostring(source.energy_source.maximum_temperature) .. " ", {"si-unit-degree-celsius"}}
      } or nil
    elseif source.energy_source.type == "heat" then
      fields[#fields + 1] = {
        name = "",
        value = {"custom-tooltip.header", {"", "[img=tooltip-category-heat]", " ", {"tooltip-category.consumes"}, " ", {"tooltip-category.heat"}}}
      }
      fields[#fields + 1] = {
        name = {"description.max-energy-consumption"},
        value = consumption
      }
      -- min and max temp
      fields[#fields + 1] = {
        name = {"description.maximum-temperature"},
        value = {"", tostring(source.energy_source.max_temperature) .. " ", {"si-unit-degree-celsius"}}
      }
      fields[#fields + 1] = source.energy_source.min_working_temperature and {
        name = {"description.minimum-temperature"},
        value = {"", tostring(source.energy_source.min_working_temperature) .. " ", {"si-unit-degree-celsius"}}
      } or nil
    end

    prototype.custom_tooltip_fields = fields
  end
end

-- verify quality if uses_module_effects is active
if uses_module_effects then
  for p, prototype in pairs(data.raw.quality or {}) do
    if (prototype.crafting_machine_module_slots_bonus or 0) < (prototype.beacon_module_slots_bonus or 0) then
      if settings.startup["nsb-override-quality"].value then
        prototype.crafting_machine_module_slots_bonus = prototype.beacon_module_slots_bonus
      else
        error("Failed to load quality " .. p .. ", crafting_machine_module_slots_bonus must not be less than beacon_module_slots_bonus!")
      end
    end
  end
end

data:extend{
  {
    type = "recipe-category",
    name = "nsb-filler-category",
    hidden = true,
    hidden_in_factoriopedia = true
  },
  {
    type = "recipe",
    name = "nsb-filler-recipe",
    icon = util.empty_icon().icon,
    category = "nsb-filler-category",
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden recipe used to check if machine is working
    type = "recipe",
    name = "nsb-internal-recipe",
    icon = util.empty_icon().icon,
    category = "nsb-filler-category",
    ingredients = {{ type = "item", name = "nsb-internal-item", amount = 1, ignored_by_stats = 1}},
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden item for recipe and signals, can use existing item but this one is garunteed to work
    type = "item",
    name = "nsb-internal-item",
    icon = util.empty_icon().icon,
    stack_size = 1,
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden assembling machine to craft the aforementioned recipe
    type = "assembling-machine",
    name = "nsb-internal-manager",
    icon = util.empty_icon().icon,
    collision_mask = {layers = {}},
    flags = {
      "placeable-off-grid",
      "not-repairable",
      "not-on-map",
      "not-blueprintable",
      "not-deconstructable",
      "no-copy-paste",
      "not-upgradable",
      "placeable-neutral",
      "no-automated-item-removal",
      "no-automated-item-insertion"
    },
    allow_copy_paste = false,
    selectable_in_game = false,
    energy_usage = "1W",
    energy_source = {type = "void"},
    crafting_categories = {"nsb-filler-category"},
    fixed_recipe = "nsb-internal-recipe",
    crafting_speed = 60,
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden proxy container to monitor module inventory
    type = "proxy-container",
    name = "nsb-internal-monitor",
    icon = util.empty_icon().icon,
    draw_inventory_content = false,
    collision_mask = {layers = {}},
    flags = {
      "not-rotatable",
      "placeable-neutral",
      "placeable-off-grid",
      "not-repairable",
      "not-on-map",
      "not-deconstructable",
      "not-blueprintable",
      "hide-alt-info",
      "not-upgradable"
    },
    allow_copy_paste = false,
    selectable_in_game = false,
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden combinator to mimic negative of network state
    type = "constant-combinator",
    name = "nsb-internal-mimic",
    icon = util.empty_icon().icon,
    collision_mask = {layers = {}},
    activity_led_light_offsets = {{0, 0}, {0, 0}, {0, 0}, {0, 0}},
    circuit_wire_connection_points = {{wire = {}, shadow = {}}, {wire = {}, shadow = {}}, {wire = {}, shadow = {}}, {wire = {}, shadow = {}}},
    flags = {
      "not-rotatable",
      "placeable-neutral",
      "placeable-off-grid",
      "not-repairable",
      "not-on-map",
      "not-deconstructable",
      "not-blueprintable",
      "hide-alt-info",
      "not-upgradable"
    },
    allow_copy_paste = false,
    selectable_in_game = false,
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- smuggle some simple data to runtime
    type = "mod-data",
    name = "nsb-beacon-data",
    data = {
      event = event_filter,
      decon = deconstruction_filter,
      modded_beacons = modded_beacons
    },
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- custom rotation handler for beacons
    type = "custom-input",
    name = "nsb-beacon-rotate",
    key_sequence = "",
    linked_game_control = "rotate",
    include_selected_prototype = true,
    action = "lua",
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- custom counterrotation handler for beacons
    type = "custom-input",
    name = "nsb-beacon-rotate-reverse",
    key_sequence = "",
    linked_game_control = "reverse-rotate",
    include_selected_prototype = true,
    action = "lua",
    hidden = true,
    hidden_in_factoriopedia = true
  }
}