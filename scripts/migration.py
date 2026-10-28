"""Run a verified historical donor -> Factorio 2.1.23 candidate -> reload privately."""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, time, zipfile
from qc_support import identity, stage_dependencies
p=argparse.ArgumentParser()
p.add_argument("--engine",type=pathlib.Path,required=True)
p.add_argument("--output",type=pathlib.Path,required=True)
p.add_argument("--perel",type=pathlib.Path,required=True)
p.add_argument("--things",type=pathlib.Path,required=True)
p.add_argument("--old-nsb",type=pathlib.Path,help="Explicit NSB 1.4.2 archive, required for a fresh historical donor")
p.add_argument("--old-perel",type=pathlib.Path,help="Explicit PEREL 1.1.9 archive, required for a fresh historical donor")
p.add_argument("--archive",type=pathlib.Path,help="Load only this candidate shipping ZIP in the target stage")
donor_mode=p.add_mutually_exclusive_group(required=True)
donor_mode.add_argument("--old-engine",type=pathlib.Path,help="Verified Factorio 2.0.77 executable for a fresh donor")
donor_mode.add_argument("--donor-save",type=pathlib.Path,help="Preserved actual upstream1.4.2 donor; never modified")
p.add_argument("--donor-sha256",help="Required recorded hash when using a preserved donor")
p.add_argument("--donor-provenance",type=pathlib.Path,help="Required historical receipt/log when using a preserved donor")
a=p.parse_args()
fork=pathlib.Path(__file__).resolve().parents[1]
if a.donor_save:
 assert a.donor_provenance and a.donor_provenance.is_file(), "Preserved donor needs its provenance receipt/log"
 assert a.donor_sha256 and hashlib.sha256(a.donor_save.read_bytes()).hexdigest()==a.donor_sha256.lower(), "Preserved donor hash differs"
if a.old_engine:
 assert a.old_nsb and a.old_perel, "Fresh donors require explicit --old-nsb and --old-perel archives"
 for path,name,version in [(a.old_nsb,"zzz-nonstandard-beacons","1.4.2"),(a.old_perel,"perel","1.1.9")]:
  with zipfile.ZipFile(path) as archive:
   info=json.loads(archive.read(name+"_"+version+"/info.json"))
   assert info["name"]==name and info["version"]==version, info
out=a.output.resolve(); out.mkdir(parents=True,exist_ok=True)
stages={}
phases=([("donor",a.old_engine.absolute(),"2.0.77","zzz-nonstandard-beacons")] if a.old_engine else [])
phases.append(("adopted",a.engine.absolute(),"2.1.23","zzz-nonstandard-beacons"))
for phase,engine,version,library in phases:
 root=out/phase; mods=root/"mods"; mods.mkdir(parents=True,exist_ok=True)
 (root/"user/saves").mkdir(parents=True,exist_ok=True)
 assert "Version: "+version+" " in subprocess.check_output([str(engine),"--version"],text=True)
 assert json.loads((engine.parents[2]/"data/base/info.json").read_text())["version"]==version
 if phase=="donor":
  shutil.copy2(a.old_nsb,mods/"zzz-nonstandard-beacons_1.4.2.zip")
  shutil.copy2(a.old_perel,mods/"perel_1.1.9.zip")
 else:
  if a.archive:
   with zipfile.ZipFile(a.archive) as archive:
    _, candidate_version, candidate_folder = identity(fork)
    info=json.loads(archive.read(candidate_folder+"/info.json"))
    assert info['name']==library and info['version']==candidate_version and archive.testzip() is None
   shutil.copy2(a.archive,mods/a.archive.name)
  else:
   shutil.copytree(fork,mods/identity(fork)[2],dirs_exist_ok=True,ignore=shutil.ignore_patterns(".git",".qc","dist","tests","__pycache__"))
  stage_dependencies(a.perel,a.things,mods)
 fixture=mods/"nsbc-migration_0.0.1"; fixture.mkdir(exist_ok=True)
 (fixture/"info.json").write_text(json.dumps({"name":"nsbc-migration","version":"0.0.1","factorio_version":version[:3],"title":"NSBC migration fixture","author":"Theorun","dependencies":["base","quality",library]}))
 data=(fork/"tests/data.lua").read_text()
 if phase=="donor":
  data=data.replace('categories = {"nsb-filler-category"}','category = "nsb-filler-category"')
  data=data.replace('stack_size = 50, fuel_categories = {"chemical"}', 'stack_size = 50, fuel_category = "chemical"')
 (fixture/"data.lua").write_text(data,encoding="utf-8")
 shutil.copy2(fork/"tests/migration-control.lua",fixture/"control.lua")
 (fixture/"migration-phase.lua").write_text("return {candidate = " + ("false" if phase=="donor" else "true") + "}\n")
 (mods/"mod-list.json").write_text(json.dumps({"mods":[{"name":name,"enabled":True} for name in ["base","quality","perel",library,"nsbc-migration"]+(["0-things"] if phase!="donor" else [])]+[{"name":"space-age","enabled":False}]}))
 config=root/"config.ini"
 config.write_text("[path]\nread-data="+(engine.parents[2]/"data").as_posix()+"\nwrite-data="+(root/"user").as_posix()+"\n[general]\ncheck-updates=false\n")
 settings=root/"server-settings.json"
 settings.write_text(json.dumps({"name":"Private NSBC fixture","description":"isolated local validation","visibility":{"public":False,"lan":False},"require_user_verification":False,"auto_pause":False,"autosave_interval":0}))
 stages[phase]=(root,[str(engine),"--config",str(config),"--mod-directory",str(mods),"--disable-audio"],settings)
if a.old_engine:
 root,command,settings=stages["donor"]
 created=subprocess.run(command+["--create",str(root/"seed.zip")],capture_output=True,text=True,encoding="utf-8",errors="replace")
 (root/"create.log").write_text(created.stdout+created.stderr,encoding="utf-8")
 assert created.returncode==0, created.stdout[-3000:]
def server(phase,save,marker,saved=None):
 root,command,settings=stages["adopted" if phase=="reload" else phase]
 ready=root/"user/script-output"/marker
 ready.unlink(missing_ok=True)
 if saved: (root/"user/saves"/saved).unlink(missing_ok=True)
 with (root/(phase+".log")).open("w",encoding="utf-8") as log:
  process=subprocess.Popen(command+["--start-server",str(save),"--server-settings",str(settings),"--bind","127.0.0.1","--port","34219"],stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
  try:
   deadline=time.monotonic()+60
   while time.monotonic()<deadline:
    if process.poll() is not None: raise RuntimeError("server failed: "+str(root/(phase+".log")))
    if "non-recoverable error" in (root/(phase+".log")).read_text(encoding="utf-8",errors="replace"):
     raise RuntimeError("fixture failed: "+str(root/(phase+".log")))
    if ready.exists() and (saved is None or (root/"user/saves"/saved).exists()):
     time.sleep(1)
     print("Passed",phase,flush=True)
     return root/"user/saves"/saved if saved else None
    time.sleep(0.2)
   raise RuntimeError("server timed out: "+str(root/(phase+".log")))
  finally:
   process.terminate(); process.wait(timeout=10)
if a.donor_save:
 donor=out/"preserved-donor.zip"
 shutil.copy2(a.donor_save,donor)
 shutil.copy2(a.donor_provenance,out/("donor-provenance"+a.donor_provenance.suffix))
else:
 donor=server("donor",root/"seed.zip","nsbc-donor-ready.json","nsbc-donor.zip")
adopted=server("adopted",donor,"nsbc-adopted-ready.json","nsbc-adopted.zip")
server("reload",adopted,"nsbc-reload-ready.json")
(out/"result.json").write_text(json.dumps({"passed":True,"donor":str(donor),"adopted":str(adopted),
 "donor_sha256":hashlib.sha256(donor.read_bytes()).hexdigest(),"reused_historical_donor":bool(a.donor_save),
 "engine":str(a.engine.absolute()),"engine_version":"2.1.23"},indent=2))
