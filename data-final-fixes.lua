for p, prototype in pairs(data.raw.beacon) do
  if prototype.energy_source.type ~= "void" and prototype.energy_source.type ~= "electric" then
    -- validate optional properties
    if prototype.allowed_effects and not prototype.effect_receiver then
      error("Failed to load nonstandard beacon " .. p .. "\nprototype.allowed_effects was defined but prototype.effect_receiver was not")
    end

    local effects = prototype.allowed_effects or {"consumption", "pollution"}
    prototype.allowed_effects = {}
    for _, effect in pairs(effects) do
      if effect == "consumption" or effect == "pollution" then
        prototype.allowed_effects[#prototype.allowed_effects+1] = effect
      end
    end
    
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
        "not-deconstructable",
        "no-copy-paste",
        "not-upgradable",
        "placeable-neutral"
      },
      selectable_in_game = false,
      allow_copy_paste = false,
      effect_receiver = prototype.effect_receiver and {
        uses_beacon_effects = prototype.effect_receiver.uses_beacon_effects,
        uses_module_effects = prototype.effect_receiver.uses_module_effects,
        uses_surface_effects = prototype.effect_receiver.uses_surface_effects
      },
      allowed_effects = prototype.allowed_effects,
      collision_box = prototype.collision_box,
      collision_mask = { layers = {} },
      selection_box = prototype.selection_box,
      selection_priority = 0,
      hidden = true,
      hidden_in_factoriopedia = true
    }}

    -- change the beacon to be non-interactible by inserters if burner powered
    if prototype.energy_source.type == "burner" then
      prototype.flags = prototype.flags or {}
      prototype.flags[#prototype.flags+1] = "no-automated-item-insertion"
      prototype.flags[#prototype.flags+1] = "no-automated-item-removal"
    else -- allow module insertion if not a burner
      data.raw["assembling-machine"][p .. "-source"].flags[#data.raw["assembling-machine"][p .. "-source"].flags+1] = "no-automated-item-insertion"
      data.raw["assembling-machine"][p .. "-source"].flags[#data.raw["assembling-machine"][p .. "-source"].flags+1] = "no-automated-item-removal"
    end

    -- override the energy source
    prototype.energy_source = {type = "void"}

    -- clear custom flags
    prototype.effect_receiver = nil
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
  }
}