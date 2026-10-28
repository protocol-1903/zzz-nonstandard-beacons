"""Isolated unchanged upstream2.0.0 diagnostic, donor adoption and save/reload."""
import argparse, hashlib, json, os, shutil, subprocess
from pathlib import Path
p = argparse.ArgumentParser(description=__doc__)
for key in ("engine", "output", "upstream", "upstream-perel", "things", "perel", "donor-save"):
    p.add_argument("--"+key, type=Path, required=True)
a=p.parse_args(); source=Path(__file__).resolve().parents[1]
root=a.output.absolute(); root.mkdir(parents=True,exist_ok=True); engine=a.engine.absolute()
assert "Version: 2.1.23 " in subprocess.check_output([str(engine),"--version"],text=True)
assert json.loads((engine.parents[2]/"data/base/info.json").read_text())["version"]=="2.1.23"
mods=root/"mods"; mods.mkdir()
for folder in (a.upstream,a.upstream_perel):
    name=json.loads((folder/"info.json").read_text())["name"]
    shutil.copytree(folder,mods/name)
shutil.copy2(a.things,mods/a.things.name)
fixture=mods/"nsbc-migration_0.0.1";fixture.mkdir()
(fixture/"info.json").write_text(json.dumps({"name":"nsbc-migration","version":"0.0.1","factorio_version":"2.1",
    "title":"Private upstream migration diagnostic","author":"ESIR QC","dependencies":["base","quality","zzz-nonstandard-beacons"]}))
shutil.copy2(source/"tests/data.lua",fixture/"data.lua")
shutil.copy2(source/"tests/migration-control.lua",fixture/"control.lua")
(fixture/"migration-phase.lua").write_text("return {candidate = false}\n")
(mods/"mod-list.json").write_text(json.dumps({"mods":[{"name":n,"enabled":True} for n in
    ["base","quality","perel","0-things","zzz-nonstandard-beacons","nsbc-migration"]]+[{"name":"space-age","enabled":False}]}))
(root/"config.ini").write_text("[path]\nread-data="+(engine.parents[2]/"data").as_posix()+"\nwrite-data="+root.as_posix()+"\n[general]\ncheck-updates=false\n")
command=[str(engine),"--config",str(root/"config.ini"),"--mod-directory",str(mods),"--disable-audio"]
diagnostic=subprocess.run(command+["--benchmark",str(a.donor_save.absolute()),"--benchmark-ticks","100","--benchmark-runs","1"],capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=120)
text=diagnostic.stdout+diagnostic.stderr;(root/"upstream-142-to-200.log").write_text(text,encoding="utf-8")
assert diagnostic.returncode!=0 and "beacon_pointers" in text, "Expected source finding was not reproduced; inspect diagnostic log"
print("Reproduced upstream migration failure: beacon_pointers",flush=True)
receipt={"upstream_migration_failure_reproduced":True,"exit_code":diagnostic.returncode,
    "donor_sha256":hashlib.sha256(a.donor_save.read_bytes()).hexdigest(),"engine_version":"2.1.23"}
(root/"upstream-failure.json").write_text(json.dumps(receipt,indent=2))
# Create a separate healthy upstream2.0.0 world, without altering upstream code.
with (root/"create.log").open("w") as log:
    subprocess.run(command+["--create",str(root/"fresh.zip")],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
runner=Path(__file__).with_name("save_checkpoint.py")
subprocess.run([os.sys.executable,"-B",str(runner),"--engine",str(engine),"--run",str(root),
    "--save",str(root/"fresh.zip"),"--checkpoint","nsbc-donor.zip","--phase","upstream-donor",
    "--receipt","nsbc-donor-ready.json"],check=True)
donor=root/"saves/nsbc-donor.zip"
subprocess.run([os.sys.executable,"-B",str(source/"scripts/migration.py"),"--engine",str(engine),
    "--output",str(root/"candidate"),"--perel",str(a.perel),"--things",str(a.things),"--donor-save",str(donor),
    "--donor-sha256",hashlib.sha256(donor.read_bytes()).hexdigest(),"--donor-provenance",str(root/"upstream-donor.checkpoint.json")],check=True)
receipt["upstream_200_adoption_and_reload"]=True
(root/"result.json").write_text(json.dumps(receipt,indent=2))
