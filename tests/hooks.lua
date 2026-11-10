
-- Appended only to the staged test copy, never to shipping control.lua.
-- Named custom-input events cannot be raised through the public engine API.
remote.add_interface("nsbc-qc", {
  rotate = function(player_index, reverse, in_gui)
    orientation.rotate({player_index = player_index, tick = game.tick, in_gui = in_gui or false}, reverse)
  end,
  capture = function(stack, mapping)
    orientation.setup_blueprint{stack = stack, mapping = {get = function() return mapping end}}
  end,
  fault = function(entity, kind)
    local record = storage.beacons[entity.unit_number]
    if kind == "refund" then
      record.refund = game.create_inventory(1)
      record.refund.insert{name = "iron-plate", count = 1}
    elseif kind == "transfer" then record.transfer_snapshot = {energy = 0, fluids = {}, progress = 0.12345, bonus = 0}
    elseif kind == "fluid-remainder" then
      record.transfer_snapshot = {energy = record.source.energy, fluids = {},
        remaining_fluids = {[1] = {name = "nsbc-nitrogen", amount = 20, temperature = 75}},
        progress = record.source.crafting_progress, bonus = record.source.bonus_progress, result_quality = record.source.result_quality}
    end
    common.protect(record, "injected fixture " .. kind)
  end
})
