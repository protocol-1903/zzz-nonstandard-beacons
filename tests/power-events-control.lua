-- Native power/module transitions and a stable workload for paired benchmarks.
local function record(entity) return remote.call("nonstandard-beacons", "get-beacon-data", entity.unit_number) end
local function counts(reset) return remote.call("nsbc-events-qc", "counts", reset) end
local function check(ok, message) assert(ok, "NSBC-EVENTS " .. message) end
script.on_init(function()
  storage.bodies, storage.samples = {}, {}
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 5); surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles+1] = {name="grass-1",position={x,y}} end end
  surface.set_tiles(tiles)
  for _, entity in pairs(surface.find_entities_filtered{area={{-80,-80},{80,80}}, type={"tree","simple-entity"}}) do entity.destroy() end
  local names = {"nsbc-copper", "nsbc-burner", "nsbc-heat", "nsbc-electric", "nsbc-process"}
  for i = 1, 200 do
    local name = names[(i-1)%#names+1]
    local body = assert(surface.create_entity{name=name,position={-70+((i-1)%20)*7,-70+math.floor((i-1)/20)*7},force="player",raise_built=true})
    local source = record(body).source
    if name == "nsbc-copper" then source.set_fluid(1,{name="nsbc-nitrogen",amount=100,temperature=25}) end
    if source.burner then source.get_fuel_inventory().insert{name="coal",count=50} end
    if name == "nsbc-heat" then source.temperature=900 end
    if name == "nsbc-process" then source.get_inventory(defines.inventory.crafter_input).insert{name="iron-plate",count=20} end
    storage.bodies[#storage.bodies+1] = body
  end
end)
script.on_event(defines.events.on_tick,function(event)
  local tick=event.tick
  if tick==100 then counts(true)
  elseif tick==200 then
    local sample=counts(true); storage.samples.operating=sample
    check(sample.updates==0 and sample.events==0,"stable operating controllers kept waking Lua")
    for _,body in ipairs(storage.bodies) do
      if body.name=="nsbc-copper" then record(body).source.clear_fluid(1) end
    end
  elseif tick==240 then
    for _,body in ipairs(storage.bodies) do if body.name=="nsbc-copper" then check(body.disabled_by_script,"depleted fluid beacon still enabled") end end
    counts(true)
  elseif tick==280 then
    local sample=counts(true);storage.samples.depleted=sample
    check(sample.updates==0 and sample.events==0,"stable depletion kept waking Lua")
    for _,body in ipairs(storage.bodies) do
      if body.name=="nsbc-copper" then record(body).source.set_fluid(1,{name="nsbc-nitrogen",amount=100,temperature=25}) end
      if body.name=="nsbc-burner" then body.get_module_inventory().insert{name="speed-module",quality="rare",count=1} end
    end
  elseif tick==330 then
    for _,body in ipairs(storage.bodies) do
      if body.name=="nsbc-copper" then check(not body.disabled_by_script,"refuelled fluid beacon stayed disabled") end
      if body.name=="nsbc-burner" then check(record(body).source.get_module_inventory().get_item_count{name="speed-module",quality="rare"}==1,"module mirror did not update") end
    end
    counts(true)
  elseif tick==380 then
    local sample=counts(true);storage.samples.modules=sample
    check(sample.updates==0 and sample.events==0,"module-change controllers did not settle")
    log("NSBC-EVENTS TRANSITIONS COMPLETE")
    check(remote.call("nsbc-events-qc","stale",storage.bodies[1],storage.bodies[2]),"stale event guard")
    record(storage.bodies[2]).source.destroy()
  elseif tick==400 then
    storage.retired_manager=record(storage.bodies[3]).manager
    storage.retired_manager.destroy()
  elseif tick==410 then
    local recovered=record(storage.bodies[3])
    check(recovered.phase=="protected" and recovered.source.valid,"destroyed manager did not protect source")
    check(remote.call("nonstandard-beacons","adopt-beacon",storage.bodies[3]),"explicit controller repair failed")
    recovered=record(storage.bodies[3]) -- Remote records are copied tables.
    check(recovered.phase=="attached" and recovered.manager.valid
      and recovered.manager~=storage.retired_manager,"destroyed manager did not rebuild")
    local broken=record(storage.bodies[2])
    check(broken.phase=="protected","destroyed source did not protect beacon")
    if counts(false).native then check(broken.manager.disabled_by_script,"protected manager remained enabled") end
  elseif tick==430 then
    -- Allow the explicitly rebuilt controller to propagate its circuit state.
    counts(true)
  elseif tick==460 then
    local sample=counts(true);storage.samples.protected=sample
    check(sample.updates==0 and sample.events==0,"protected controller emitted continuous events")
    check(remote.call("nsbc-events-qc","missing_definition",storage.bodies[1]),"removed-definition preservation")
  elseif tick==480 then
    check(remote.call("nsbc-events-qc","missing_lookup",storage.bodies[3]),"missing schema-2 lookup recovery")
  elseif tick==520 then
    storage.samples.native=counts(false).native
    local modules=storage.bodies[7].get_module_inventory()
    modules.clear()
    modules.insert{name="speed-module",quality="normal",count=1}
  elseif tick==550 then
    local mirror=record(storage.bodies[7]).source.get_module_inventory()
    check(mirror.get_item_count{name="speed-module",quality="normal"}==1
      and mirror.get_item_count{name="speed-module",quality="rare"}==0,"module quality change did not propagate")
    storage.bodies[7].get_module_inventory().clear()
  elseif tick==590 then
    check(record(storage.bodies[7]).source.get_module_inventory().is_empty(),"module removal did not propagate")
    storage.samples.module_quality_and_removal=true
    helpers.write_file("power-events.json",helpers.table_to_json{passed=true,population=#storage.bodies,samples=storage.samples},false)
    log("NSBC-EVENTS COMPLETE")
  end
end)
