for p, prototype in pairs(data.raw.beacon) do
  if prototype.energy_source.type ~= "void" and prototype.energy_source.type ~= "electric" then
    -- create energy source entity, storing the 'disabled' localisation to simplify runtime scripting
    data:extend{{
      type = "assembling-machine",
      name = p .. "-source",
      localised_description = "entity-status." .. (
        prototype.energy_source.type == "burner" and "no-fuel" or
        prototype.energy_source.type == "fluid" and "no-input-fluid" or "low-temperature"),
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
        "no-copy-paste",
        "not-selectable-in-game",
        "not-upgradable",
        "placeable-neutral",
        "player-creation"
      },
      effect_receiver = {
        uses_beacon_effects = false,
        uses_module_effects = false,
        uses_surface_effects = false
      },
      collision_box = prototype.collision_box,
      collision_mask = { layers = {} },
      selection_box = prototype.selection_box,
      selection_priority = 1,
      hidden = true,
      hidden_in_factoriopedia = true,
      allowed_effects = prototype.allowed_effects,
      module_slots = prototype.module_slots,
      icon_draw_specification = prototype.icon_draw_specification,
      circuit_wire_max_distance = 1
    }}

    -- change the beacon to be non-interactible by inserters
    prototype.flags = prototype.flags or {}
    prototype.flags[#prototype.flags+1] = "no-automated-item-insertion"
    prototype.flags[#prototype.flags+1] = "no-automated-item-removal"
    prototype.flags[#prototype.flags+1] = "not-deconstructable"

    -- have the beacon point to the source when deconstructed
    prototype.deconstruction_alternative = p .. "-source"
    
    -- override the energy source
    prototype.energy_source = {type = "void"}
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
    category = "nsb-filler-category"
  },
  {
    type = "recipe",
    name = "nsb-internal-recipe",
    icon = util.empty_icon().icon,
    category = "nsb-filler-category",
    ingredients = {{ type = "item", name = "nsb-internal-item", amount = 1}}
  },
  {
    type = "item",
    name = "nsb-internal-item",
    icon = util.empty_icon().icon,
    stack_size = 1
  },
  {
    type = "assembling-machine",
    name = "nsb-internal-manager",
    icon = util.empty_icon().icon,
    energy_usage = "1W",
    energy_source = {type = "void"},
    crafting_categories = {"nsb-filler-category"},
    fixed_recipe = "nsb-internal-recipe",
    crafting_speed = 60,
    hidden = true,
    hidden_in_factoriopedia = true,
    circuit_wire_max_distance = 1
  }
}