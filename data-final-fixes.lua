local uses_module_effects = false
local event_filter, deconstruction_filter, modded_beacons = {}, {}, {}

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
      localised_description = "entity-status." .. (
        prototype.energy_source.type == "burner" and "no-fuel" or
        prototype.energy_source.type == "fluid" and "no-input-fluid" or
        prototype.energy_source.type == "heat" and "low-temperature" or
        prototype.energy_source.type == "electric" and "low-power"),
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
      selectable_in_game = false,
      allow_copy_paste = false,
      effect_receiver = effect_receiver and {
        uses_beacon_effects = effect_receiver.uses_beacon_effects,
        uses_module_effects = effect_receiver.uses_module_effects,
        uses_surface_effects = effect_receiver.uses_surface_effects
      },
      module_slots = effect_receiver and effect_receiver.uses_module_effects and prototype.module_slots or 0, -- only copy if it uses module effects
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
  end
end

-- verify quality if uses_module_effects is active
if uses_module_effects then
  for p, prototype in pairs(data.raw.quality or {}) do
    if (prototype.crafting_machine_module_slots_bonus or 0) < (prototype.beacon_module_slots_bonus or 0) then
      error("Failed to load quality " .. p .. ", crafting_machine_module_slots_bonus must not be less than beacon_module_slots_bonus!")
    end
    if (prototype.crafting_machine_energy_usage_multiplier or 0) ~= (prototype.beacon_power_usage_multiplier or 0) then
      error("Failed to load quality " .. p .. ", crafting_machine_energy_usage_multiplier must equal beacon_power_usage_multiplier!")
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
  }
}