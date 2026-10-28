-- File map: two actual network clients, independent viewers and reconnect acceptance.
-- blueprint: docs/lifecycle.md#verification
local function check(ok, message) assert(ok, "NSBC-MP FAIL: " .. message); log("NSBC-MP PASS: " .. message) end
local function metadata() return remote.call("nonstandard-beacons", "get-beacon-data", storage.beacon.unit_number) end
local function open(player)
  player.set_controller{type = defines.controllers.god}
  player.teleport({0, 5}, game.surfaces[1])
  player.selected = nil
  player.opened = storage.beacon
end
script.on_init(function()
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 2); surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities_filtered{area = {{-10, -10}, {10, 10}}}) do entity.destroy() end
  storage.beacon = surface.create_entity{name = "nsbc-copper", position = {0, 0}, force = "player", raise_built = true}
  storage.beacon.get_module_inventory().insert{name = "speed-module", count = 1}
  metadata().source.set_fluid(1, {name = "nsbc-nitrogen", amount = 90, temperature = 35})
  storage.phase = 0
end)
script.on_event(defines.events.on_player_joined_game, function(event)
  open(game.get_player(event.player_index))
  if storage.phase == 5 then storage.phase, storage.due = 6, event.tick + 30 end
end)
script.on_event(defines.events.on_player_left_game, function(event)
  if storage.phase == 4 then
    storage.disconnected = event.player_index
    storage.phase, storage.due = 5, event.tick + 30
  end
end)
script.on_nth_tick(10, function(event)
  if storage.phase == 0 and #game.connected_players == 2 then storage.phase, storage.due = 1, event.tick + 30 end
  if not storage.due or event.tick < storage.due then return end
  if storage.phase <= 3 or storage.phase == 6 then
    check(#game.connected_players == 2, "two real connected clients")
    for _, player in pairs(game.connected_players) do
      check(player.opened == storage.beacon and player.selected == nil, "independent opened viewer " .. player.name)
      check(player.gui.relative["nsbc-source-information"] ~= nil, "relative adapter " .. player.name)
    end
  end
  if storage.phase == 1 then
    metadata().source.clear_fluid(1)
  elseif storage.phase == 2 then
    check(storage.beacon.disabled_by_script, "both clients observe depletion")
    metadata().source.set_fluid(1, {name = "nsbc-nitrogen", amount = 75, temperature = 50})
    local player = game.connected_players[1]
    player.cursor_stack.set_stack{name = "nsbc-iron", count = 1}
    player.build_from_cursor{position = storage.beacon.position}
    storage.beacon = game.surfaces[1].find_entities_filtered{name = "nsbc-iron", position = {0, 0}}[1]
    check(storage.beacon and metadata().phase == "attached", "network player replacement")
  elseif storage.phase == 3 then
    check(not storage.beacon.disabled_by_script, "both clients observe refuelled successor")
    storage.phase, storage.due = 4, nil
    helpers.write_file("nsbc-mp-disconnect.json", helpers.table_to_json({ready = true}), false)
    return
  elseif storage.phase == 5 then
    check(#game.connected_players == 1, "disconnect leaves remaining viewer")
    check(game.get_player(storage.disconnected).gui.relative["nsbc-source-information"] == nil, "disconnected adapter removed")
    storage.due = nil
    helpers.write_file("nsbc-mp-rejoin.json", helpers.table_to_json({ready = true}), false)
    return
  elseif storage.phase == 6 then
    helpers.write_file("nsbc-mp-result.json", helpers.table_to_json({passed = true, clients = 2, rejoined = true, tick = event.tick}), false)
    game.server_save("nsbc-multiplayer")
    log("NSBC-MP COMPLETE")
    storage.phase, storage.due = 7, nil
    return
  end
  storage.phase, storage.due = storage.phase + 1, event.tick + 30
end)
