[![ko-fi](https://img.shields.io/badge/Ko--fi-Donate%20-hotpink?logo=kofi&logoColor=white&style=for-the-badge)](https://ko-fi.com/protocol1903) [![](https://img.shields.io/badge/dynamic/json?color=orange&label=Factorio&query=downloads_count&suffix=%20downloads&url=https%3A%2F%2Fmods.factorio.com%2Fapi%2Fmods%2Fno-pipe-touching&style=for-the-badge)](https://mods.factorio.com/mod/zzz-nonstandard-beacons) [![](https://img.shields.io/badge/Discord-Community-blue?style=for-the-badge)](https://discord.gg/K3fXMGVc4z) [![](https://img.shields.io/badge/Github-Source-green?style=for-the-badge)](https://github.com/protocol-1903/zzz-nonstandard-beacons)

# This mod does not add new beacons unless you use the example mod setting. Another mod must be used to add new beacons.

## What?
You can now create and run non-electric beacons, and this mod will handle all runtime scripting related to them.

## Use
Define your beacon entity like normal, but when setting the energy_source just define it as a fluid, heat, or burner variant. Like so:

```
{
  name = "heat-beacon",
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
    priority = "extra-high-no-scale",
    width = 10,
    height = 10
  },
  supply_area_distance = 3,
  distribution_effectivity = 1.5,
  module_slots = 2,
}
```

## Wait... That's it?
Yup. Just define your beacons as normal (minus the energy_source, of course) before data-final-fixes.lua and this mod will handle the rest!

# Known Issues/Future Features
- There is currently no way to see the fuel inventory. This will eventually be fixed by a custom GUI implementation.
- There is no way to rotate asymmetric fluid/burner connections. This is not a pressing issue, but will be looked into if enough people request it.
- Beacons can show 'Working' even if they don't have any modules. This is a minor graphical issue, and probably won't be resolved. The current runtime code is dirt simple, and adding any new features might have drastic effects on UPS.
- When marked for deconstruction, the beacon's module icons will shift and the modules in the beacon graphics will disappear. This is a natural result of the deconstruction code to allow for better robot and space platform integration. The first issue might be fixed, the latter probably won't.

If you have any suggestions for future features or compatability, let me know. Creating a discussion on the shelved issues/features makes it more likely that they will be implemented.

As always, if you have a mod idea, let me know and I can look into it.