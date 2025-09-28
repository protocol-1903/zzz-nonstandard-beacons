[![ko-fi](https://img.shields.io/badge/Ko--fi-Donate%20-hotpink?logo=kofi&logoColor=white&style=for-the-badge)](https://ko-fi.com/protocol1903) [![](https://img.shields.io/badge/dynamic/json?color=orange&label=Factorio&query=downloads_count&suffix=%20downloads&url=https%3A%2F%2Fmods.factorio.com%2Fapi%2Fmods%2Fzzz-nonstandard-beacons&style=for-the-badge)](https://mods.factorio.com/mod/zzz-nonstandard-beacons) [![](https://img.shields.io/badge/Discord-Community-blue?style=for-the-badge)](https://discord.gg/K3fXMGVc4z) [![](https://img.shields.io/badge/Github-Source-green?style=for-the-badge)](https://github.com/protocol-1903/zzz-nonstandard-beacons)

# This mod does not add new beacons unless you use the example mod setting. Another mod must be used to add new beacons.

### NOW WITH NO RUNTIME OVERHEAD! PLAYERS REJOICE WITH UPS FREE BEACONS!
Thanks to quezler, nonstandard beacons now have zero runtime overhead on steady-state (fully powered or no fuel) bases. The only scripting is done when the beacon turns on/off.

## What?
You can now create and run non-electric beacons, and this mod will handle all runtime scripting related to them.

## Use
WHEN ADDING THE MOD AS A REQUIREMENT, MAKE SURE TO MAKE IT NOT LOAD ORDER AFFECTING (i.e. "~ zzz-nonstandard-beacons")

Define your beacon entity like normal, but when setting the energy_source just define it as a fluid, heat, or burner variant (OR custom electric using "electric-2-electric-boogaloo"). Like so:

```
{
  name = "burner-beacon",
  type = "beacon",
  icon = "__base__/graphics/icons/beacon.png",
  flags = {"placeable-player", "player-creation"},
  minable = {mining_time = 0.5, result = "beacon"},
  collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
  selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
  allowed_effects = {"consumption", "speed", "pollution"},
  graphics_set = require("__base__.prototypes.entity.beacon-animations"),
  energy_usage = "480kW",
  energy_source = {
    type = "burner",
    fuel_categories = {"chemical"},
    fuel_inventory_size = 1,
    emissions_per_minute = { pollution = 30 }
  },
  radius_visualisation_picture = {
    filename = "__base__/graphics/entity/beacon/beacon-radius-visualization.png",
    width = 10,
    height = 10
  },
  supply_area_distance = 3,
  distribution_effectivity = 1.5,
  module_slots = 2,
}
```

## Additional features
Nonstandard Beacons includes some new features that you can use on custom beacons, just define them as follows:
- `prototype.effect_reciever = [EffectReciever](https://lua-api.factorio.com/latest/types/EffectReceiver.html)` allows the beacon source to be affected by surface, beacon, or module effects. If the effect category is not explicitly allowed, the beacon will default to ignoring it. `uses_module_effects` and `uses_beacon_effects` cannot both be true, due to implementation reasons. If `uses_beacon_effects` is true, then the beacon's energy draw will be affected by surrounding beacons. If `uses_module_effects` is true, then the beacon's energy draw will be affected by the contained modules.
- Use `remote.call("nonstandard-beacons", "get-beacon-data", beacon_unit_number)` to access any of the internal entities releated to that nonstandard beacon. `source` is the actual power source entity - an assembler, internally. it's the only one that you should need access to, if anything. `manager` is the entity that detects changes in the beacon state, also an assembler. `monitor` and `mimic` only exist if the beacon `uses_module_effects`, and i see no reason why you would need to access either. they only provide information to the circuit network.
- You must use the custom energy source `"electric-2-electric-boogaloo"` to use any of the other additional features on an electrically powered beacon.

## Coming soon, whenever i have time to implement
- Sources with byproducts (like fusion power)
- Secondary source requirements (powered by fluids and items, etc)
- Multi fuel souces (like thrusters)

# Known Issues/Future Features
- There is currently no way to see the fuel inventory. This will eventually be fixed by a custom GUI implementation.
- Most of the previous issues were resolved in version 1.2.0. Yay!

If you have any suggestions for future features or compatability, let me know. Creating a discussion on the shelved issues/features makes it more likely that they will be implemented.

As always, if you have a mod idea, let me know and I can look into it.