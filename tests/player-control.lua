-- File map: real player event fixtures and graphical evidence preparation.
-- blueprint: docs/lifecycle.md#verification
local M = {}
local function check(ok, message)
  assert(ok, "NSBC-PLAYER FAIL: " .. message)
  log("NSBC-PLAYER PASS: " .. message)
end
local function metadata(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end

---@param player LuaPlayer
function M.run(player)
  local surface = game.create_surface("nsbc-blueprints", {width = 512, height = 512})
  surface.request_to_generate_chunks({0, 0}, 9)
  surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities()) do if entity.valid then entity.destroy() end end
  local tiles = {}
  -- Include the replacement/GUI lane at y=135 and reach tests at y=180.
  -- Random water outside the blueprint grid must not decide native placement.
  for x = -250, 250 do for y = -140, 200 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
  surface.set_tiles(tiles)
  player.force.chart(surface, {{-250, -140}, {250, 200}})
  player.set_controller{type = defines.controllers.god}
  player.teleport({0, 0}, surface)
  local count = 0
  for _, original in ipairs{0, 4, 8, 12} do
    for _, mirrored in ipairs{false, true} do
      for _, rotation in ipairs{0, 4, 8, 12} do
        for _, flips in ipairs{{false, false}, {true, false}, {false, true}, {true, true}} do
          local position = {x = -225 + (count % 16) * 30, y = -105 + math.floor(count / 16) * 30}
          if player.cursor_stack then player.cursor_stack.clear() end
          check(player.cursor_stack.set_stack{name = "blueprint"}, "blueprint cursor")
          player.cursor_stack.set_blueprint_entities({
            {entity_number = 1, name = "nsbc-copper", position = {0, 0},
              tags = {nsb_orientation = {version = 1, space = "blueprint", direction = original, mirrored = mirrored}}},
            {entity_number = 2, name = "chemical-plant", position = {6, 2}, direction = original, mirror = mirrored}
          }, false)
          -- Every case crosses a real export/import boundary before native placement.
          local encoded = player.cursor_stack.export_stack()
          check(player.cursor_stack.import_stack(encoded) == 0, "blueprint export/import")
          player.build_from_cursor{position = position, direction = rotation,
            flip_horizontal = flips[1], flip_vertical = flips[2]}
          local ghosts = surface.find_entities_filtered{type = "entity-ghost", area = {
            {position.x - 14, position.y - 14}, {position.x + 14, position.y + 14}}}
          local beacon, reference
          for _, ghost in pairs(ghosts) do
            if ghost.ghost_name == "nsbc-copper" then beacon = ghost else reference = ghost end
          end
          check(beacon and reference, "both native blueprint ghosts " .. count)
          local tag = beacon.tags.nsb_orientation
          local context = serpent.line({case = count, original = original, mirror = mirrored,
            rotation = rotation, flips = flips, actual = tag, expected = {reference.direction, reference.mirroring}})
          check(tag and tag.space == "world" and tag.direction == reference.direction and tag.mirrored == reference.mirroring,
            "native transform oracle " .. context)
          local _, real = beacon.revive{raise_revive = true}
          check(real and metadata(real).source.direction == reference.direction and metadata(real).source.mirroring == reference.mirroring,
            "revived world orientation " .. count)
          remote.call("nonstandard-beacons", "set-beacon-orientation", real, 0, false)
          player.build_from_cursor{position = position, direction = rotation,
            flip_horizontal = flips[1], flip_vertical = flips[2]}
          check(metadata(real).source.direction == reference.direction and metadata(real).source.mirroring == reference.mirroring,
            "blueprint over existing orientation " .. count)
          count = count + 1
        end
      end
    end
  end
  player.cursor_stack.clear()
  -- Native player builds exercise pre-build/mined/built ordering and module refunds.
  local replaced = surface.create_entity{name = "nsbc-copper", position = {-30, 135}, force = player.force, raise_built = true}
  metadata(replaced).source.disabled_by_script = true
  metadata(replaced).source.set_fluid(1, {name = "nsbc-nitrogen", amount = 77, temperature = 43})
  remote.call("nonstandard-beacons", "set-beacon-orientation", replaced, 12, true)
  replaced.get_module_inventory().insert{name = "speed-module", count = 4, quality = "rare"}
  for _, target in ipairs{{"nsbc-iron", "rare"}, {"nsbc-copper", "normal"}, {"nsbc-iron", "normal"}, {"nsbc-copper", "normal"}} do
    player.cursor_stack.set_stack{name = target[1], quality = target[2], count = 1}
    player.build_from_cursor{position = replaced.position}
    check(not replaced.valid, "player native fast replacement " .. target[1] .. " " .. target[2])
    replaced = surface.find_entities_filtered{name = target[1], position = {-30, 135}}[1]
    local record = metadata(replaced)
    check(record and record.phase == "attached", "player source handoff")
    check(record.source.get_fluid(1).amount == 77 and record.source.direction == 12 and record.source.mirroring, "player state conserved")
    check(replaced.get_module_inventory().get_item_count{name = "speed-module", quality = "rare"} == 4, "player real modules conserved")
  end
  player.cursor_stack.clear()
  local retained_source = metadata(replaced).source
  player.cursor_stack.set_stack{name = "nsbc-burner", count = 1}
  check(not player.can_build_from_cursor{position = replaced.position}, "incompatible replacement placement refused")
  player.build_from_cursor{position = replaced.position}
  check(replaced.valid and metadata(replaced).source == retained_source and retained_source.get_fluid(1).amount == 77,
    "failed placement leaves predecessor resources intact")
  player.cursor_stack.clear()
  player.cursor_stack.set_stack{name = "blueprint"}
  local mapping = player.cursor_stack.create_blueprint{surface = surface, force = player.force, area = {{-33, 132}, {-27, 138}}}
  remote.call("nsbc-qc", "capture", player.cursor_stack, mapping)
  local captured = player.cursor_stack.get_blueprint_entities()[1].tags.nsb_orientation
  check(captured.space == "blueprint" and captured.direction == 12 and captured.mirrored, "native blueprint mapping capture handler")
  player.add_to_clipboard(player.cursor_stack)
  player.cursor_stack.clear()
  player.set_controller{type = defines.controllers.remote, surface = surface, position = {30, 135}}
  player.activate_paste()
  player.build_from_cursor{position = {30, 135}, direction = 4, flip_horizontal = true}
  local pasted = surface.find_entities_filtered{type = "entity-ghost", ghost_name = "nsbc-copper", area = {{20, 125}, {40, 145}}}[1]
  check(pasted and pasted.tags.nsb_orientation.space == "world" and pasted.tags.nsb_orientation.direction == 8 and not pasted.tags.nsb_orientation.mirrored,
    "remote clipboard placement transforms once")
  player.clear_cursor()
  player.set_controller{type = defines.controllers.god}
  local beacon = surface.create_entity{name = "nsbc-copper", position = {0, 135}, force = player.force, raise_built = true}
  beacon.get_module_inventory().insert{name = "speed-module", count = 1}
  metadata(beacon).source.set_fluid(1, {name = "nsbc-nitrogen", amount = 50, temperature = 25})
  player.teleport({0, 135})
  player.selected = beacon
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(metadata(beacon).source.direction == 4, "selected entity clockwise rotation handler")
  remote.call("nsbc-qc", "rotate", player.index, true, false)
  check(metadata(beacon).source.direction == 0, "selected entity reverse rotation handler")
  remote.call("nsbc-qc", "rotate", player.index, false, true)
  check(metadata(beacon).source.direction == 0, "GUI input leaves world orientation alone")
  player.cursor_stack.set_stack{name = "blueprint"}
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(metadata(beacon).source.direction == 0, "held blueprint rotation leaves world orientation alone")
  player.cursor_stack.clear()
  local old_group = player.permission_group
  local denied = game.permissions.create_group("nsbc-no-rotation")
  denied.set_allows_action(defines.input_action.rotate_entity, false)
  player.permission_group = denied
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(metadata(beacon).source.direction == 0, "rotation permission respected")
  player.permission_group = old_group
  local character = surface.create_entity{name = "character", position = {0, 180}, force = player.force}
  player.set_controller{type = defines.controllers.character, character = character}
  check(not player.can_reach_entity(beacon), "fixture is outside native reach")
  player.selected = beacon
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(metadata(beacon).source.direction == 0, "normal rotation obeys reach")
  player.teleport({0, 138})
  check(player.can_reach_entity(beacon), "fixture is inside native reach")
  player.selected = beacon
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(metadata(beacon).source.direction == 4, "normal nearby rotation allowed")
  remote.call("nsbc-qc", "rotate", player.index, true, false)
  local physical_surface = game.surfaces[1]
  player.teleport({0, 20}, physical_surface)
  player.set_controller{type = defines.controllers.remote, surface = surface, position = beacon.position}
  player.selected = beacon
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(metadata(beacon).source.direction == 4, "remote rotation without nearby character")
  check(character.surface == physical_surface, "remote rotation uses viewed surface rather than character surface")
  player.set_controller{type = defines.controllers.editor}
  player.selected = beacon
  remote.call("nsbc-qc", "rotate", player.index, true, false)
  check(metadata(beacon).source.direction == 0, "editor reverse rotation without character")
  player.set_controller{type = defines.controllers.god}
  local ghost = surface.create_entity{name = "entity-ghost", inner_name = "nsbc-copper", position = {15, 135}, force = player.force,
    tags = {nsb_orientation = {version = 1, space = "world", direction = 12, mirrored = true}}}
  player.teleport({15, 138}, surface)
  check(remote.call("nonstandard-beacons", "set-beacon-orientation", ghost, 12, true), "ghost orientation adapter")
  player.selected = ghost
  remote.call("nsbc-qc", "rotate", player.index, false, false)
  check(ghost.tags.nsb_orientation.direction == 0 and ghost.tags.nsb_orientation.mirrored, "placed ghost rotation preserves mirror tag")
  beacon.copy_settings(ghost, player)
  check(metadata(beacon).source.direction == 0 and metadata(beacon).source.mirroring, "ghost to real settings paste")
  remote.call("nonstandard-beacons", "set-beacon-orientation", beacon, 8, false)
  ghost.copy_settings(beacon, player)
  check(ghost.tags.nsb_orientation.direction == 8 and not ghost.tags.nsb_orientation.mirrored, "real to ghost settings paste")
  player.selected = nil
  player.opened = beacon
  storage.ui_beacon, storage.ui_player = beacon, player.index
  storage.ui_tick, storage.ui_phase = game.tick + 20, 1
  helpers.write_file("nsbc-player-result.json", helpers.table_to_json({passed = true, transforms = count}), false)
  game.auto_save("nsbc-player-fixture")
  log("NSBC-PLAYER COMPLETE " .. count)
end

---@param tick MapTick
function M.tick(tick)
  if not storage.player_tests and tick >= 150 and #game.connected_players > 0 then
    storage.player_tests = true
    M.run(game.connected_players[1])
  elseif storage.ui_action_tick and tick >= storage.ui_action_tick then
    local player = game.get_player(storage.ui_player)
    local phase = storage.ui_phase
    storage.ui_action_tick = nil
    if phase == 1 then
      metadata(storage.ui_beacon).source.clear_fluid(1)
    elseif phase == 2 then
      check(metadata(storage.ui_beacon).source.get_fluid(1) == nil, "opened source depleted")
      metadata(storage.ui_beacon).source.set_fluid(1, {name = "nsbc-nitrogen", amount = 80, temperature = 40})
    elseif phase == 3 then
      player.opened = nil
      check(player.gui.relative["nsbc-source-information"] == nil, "closed information adapter removed immediately")
      player.opened = storage.ui_beacon
    elseif phase == 4 then
      local old = storage.ui_beacon
      old.order_upgrade{target = {name = "nsbc-iron", quality = "normal"}, force = old.force}
      storage.ui_beacon = old.apply_upgrade()
      check(player.opened == storage.ui_beacon, "native opened window follows replacement")
    elseif phase == 5 then
      player.opened = nil
      player.selected = storage.ui_beacon
    elseif phase >= 6 and phase <= 9 then
      local names = {[6] = "nsbc-burner", [7] = "nsbc-heat", [8] = "nsbc-electric", [9] = "nsbc-fluid-process"}
      local beacon = player.surface.create_entity{name = names[phase], position = {90 + phase * 6, 135},
        force = player.force, raise_built = true}
      beacon.get_module_inventory().insert{name = "speed-module", count = 1}
      local source = metadata(beacon).source
      if source.burner then source.get_fuel_inventory().insert{name = "coal", quality = "rare", count = 1} end
      if phase == 7 then source.temperature = 637.5 end
      if phase == 9 then
        for index = 1, source.fluids_count do
          local box = source.get_fluid_box_prototype(index)
          source.set_fluid(index, {name = box.filter.name, amount = 50, temperature = box.filter.name == "steam" and 200 or 35})
        end
      end
      storage.ui_beacon = beacon
      player.selected = nil
      player.opened = beacon
    else
      storage.ui_tick = nil
      helpers.write_file("nsbc-ui-result.json", helpers.table_to_json({passed = true, scale = player.display_scale, locale = player.locale, resolution = player.display_resolution}), false)
      game.auto_save("nsbc-player-accepted")
      game.tick_paused = true
      return
    end
    storage.ui_phase, storage.ui_tick = phase + 1, tick + 20
  elseif storage.ui_tick and tick >= storage.ui_tick then
    local player = game.get_player(storage.ui_player)
    if storage.ui_phase ~= 6 then
      check(player.opened == storage.ui_beacon and player.selected == nil, "opened viewer independent of world hover")
      check(player.gui.relative["nsbc-source-information"] ~= nil, "opened information adapter present")
      if storage.ui_phase == 7 then
        local source = metadata(storage.ui_beacon).source
        check(source.burner.currently_burning and source.get_fuel_inventory().is_empty(), "rendered burner has burning fuel but empty queue")
      end
    else
      player.selected = storage.ui_beacon
      check(player.opened == nil and player.gui.relative["nsbc-source-information"] == nil, "hover independent of opened window")
    end
    check(#storage.ui_beacon.get_tooltip_fields() > 0, "viewed runtime information populated")
    game.take_screenshot{player = player, by_player = player, show_gui = true, resolution = player.display_resolution,
      path = "nsbc/opened-phase-" .. storage.ui_phase .. ".png", force_render = true}
    -- Screenshots render after this callback; mutate on a later tick so the
    -- evidence records the asserted state, not the following test phase.
    storage.ui_tick, storage.ui_action_tick = nil, tick + 2
  end
end
return M
