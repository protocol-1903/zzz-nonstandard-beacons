-- NSB FILE MAP
-- owns: consumer definitions and powered source/controller prototypes
-- loaded_by: Factorio data-final-fixes stage
-- cadence: prototype loading only
-- forwarded_events: none
-- storage_roots: nsb-beacon-data prototype mod-data
-- gui_ids: static tooltip fields on consumer beacons
-- remote_interfaces: none
-- rebuild_on: prototype reload
-- blueprint: docs/lifecycle.md#contract
local util = require("util")
local perel = require("__perel__.util.general")
---@type table<string, NSBDefinition>
local definitions = {}

---@class (partial) data.BeaconPrototype
---@field effect_receiver data.EffectReceiver?
---@field source_recipe string?
---@field source_fluidboxes data.FluidBox[]?

---@class CustomBeaconConfiguration
---@field uses_module_effects boolean
---@type table<string, CustomBeaconConfiguration>
local custom_beacon_prototypes = {}

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
    local effect_receiver = prototype.effect_receiver or {}
    local recipe = prototype.source_recipe
    prototype.source_recipe = nil
    local source_fluidboxes = prototype.source_fluidboxes
    prototype.source_fluidboxes = nil

    -- store data for use during scripting
    event_filter[#event_filter+1] = {filter = "name", name = p}
    deconstruction_filter[#deconstruction_filter+1] = p
    modded_beacons[p] = effect_receiver.uses_module_effects or false
    custom_beacon_prototypes[p] = {uses_module_effects = effect_receiver.uses_module_effects or false}

    -- update if the value is used anywhere
    uses_module_effects = uses_module_effects or effect_receiver.uses_module_effects or false

    definitions[p] = {
      kind = prototype.energy_source.type,
      modules = effect_receiver.uses_module_effects or false,
      family = prototype.fast_replaceable_group,
      recipe = recipe or "nsb-filler-recipe",
      fluid_layout = util.table.deepcopy(source_fluidboxes or {}),
      energy_fluid = util.table.deepcopy(prototype.energy_source.fluid_box),
      spent_fluid = util.table.deepcopy(prototype.energy_source.output_fluid_box),
      min_temperature = prototype.energy_source.min_working_temperature,
      max_temperature = prototype.energy_source.max_temperature or prototype.energy_source.maximum_temperature
    }

    -- create energy source entity, storing the 'disabled' localisation to simplify runtime scripting
    data:extend{{
      type = "assembling-machine",
      name = p .. "-source",
      localised_name = prototype.localised_name or {"?", {"item-name." .. p}, {"entity-name." .. p}},
      localised_description = prototype.localised_description or {"?", {"item-description." .. p}, {"entity-description." .. p}},
      icon = prototype.icon,
      -- Native helper replacement must not mint a second visible chassis.
      minable = {mining_time = 0.01, results = {}},
      fast_replaceable_group = "nsbc-source-" .. prototype.energy_source.type .. "-" .. (prototype.fast_replaceable_group or p),
      icon_size = prototype.icon_size,
      icons = prototype.icons,
      energy_usage = prototype.energy_usage,
      energy_source = util.table.deepcopy(prototype.energy_source),
      crafting_categories = {"nsb-filler-category"},
      fixed_recipe = recipe or "nsb-filler-recipe",
      fluid_boxes = util.table.deepcopy(source_fluidboxes),
      crafting_speed = 1,
      create_corpse_on_death = false,
      flags = {
        "placeable-off-grid",
        "not-repairable",
        "not-on-map",
        "not-blueprintable",
        "not-deconstructable",
        "no-copy-paste",
        "placeable-neutral"
      },
      icon_draw_specification = {scale = 0, scale_for_many = 0},
      icons_positioning = {{inventory_index = defines.inventory.crafter_modules, scale = 0}},
      selectable_in_game = false,
      allow_copy_paste = false,
      effect_receiver = {
        uses_beacon_effects = effect_receiver.uses_beacon_effects or false,
        uses_module_effects = effect_receiver.uses_module_effects or false,
        uses_surface_effects = effect_receiver.uses_surface_effects or false,
        base_effect = effect_receiver.base_effect,
        consumption_limits = effect_receiver.consumption_limits
      },
      module_slots = effect_receiver.uses_module_effects and prototype.module_slots or 0, -- only copy if it uses module effects
      allowed_effects = {"consumption", "pollution", "speed", "productivity", "quality"},
      quality_affects_energy_usage = true,
      collision_box = prototype.collision_box,
      collision_mask = { layers = {} },
      selection_box = prototype.selection_box,
      selection_priority = (prototype.selection_priority or 50) - 1,
      hidden = true,
      hidden_in_factoriopedia = true
    }}

    local source = data.raw["assembling-machine"][p .. "-source"]
    source.effect_receiver = util.table.deepcopy(effect_receiver)
    source.effect_receiver.uses_beacon_effects = effect_receiver.uses_beacon_effects or false
    source.effect_receiver.uses_module_effects = effect_receiver.uses_module_effects or false
    source.effect_receiver.uses_surface_effects = effect_receiver.uses_surface_effects or false

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
    local fields = prototype.custom_tooltip_fields or {}
    -- module/beacon effectiveness on the beacon
    fields[#fields + 1] = source.module_slots > 0 and {
      name = "",
      value = {"custom-tooltip.affected-by-modules"}
    } or nil
    fields[#fields + 1] = effect_receiver and effect_receiver.uses_beacon_effects and {
      name = "",
      value = {"custom-tooltip.affected-by-beacons"}
    } or nil

    prototype.custom_tooltip_fields = #fields ~= 0 and fields or nil


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
    categories = {"nsb-filler-category"},
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden recipe used to check if machine is working
    type = "recipe",
    name = "nsb-internal-recipe",
    icon = util.empty_icon().icon,
    categories = {"nsb-filler-category"},
    -- At manager speed 60, one craft per tick avoids duplicate same-tick events.
    -- The old ingredient implicitly limited throughput; native events need a cap.
    energy_required = 1,
    raise_on_crafted = true,
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- hidden circuit signal; retained so existing source/controller wires keep their identity
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
  { -- Preserve upstream 2.0.0's extensible mod-data handle for existing consumers.
    type = "mod-data",
    name = "zzz-nonstandard-beacons",
    data = {
      event_filter = event_filter,
      deconstruction_filter = deconstruction_filter,
      custom_beacon_prototypes = custom_beacon_prototypes,
      tooltip_fields = {}, -- Runtime tooltip IDs are owned per entity, never globally.
      definitions = definitions
    },
    hidden = true,
    hidden_in_factoriopedia = true
  },
  { -- Internal structured definition alias retained from the tested continuation.
    type = "mod-data",
    name = "nsb-beacon-data",
    data = {
      event = event_filter,
      decon = deconstruction_filter,
      modded_beacons = modded_beacons,
      definitions = definitions
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
