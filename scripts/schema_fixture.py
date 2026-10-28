"""Exercise structured schema-1 development state, same-version loading and reload."""
import argparse, hashlib, json, os, shutil, subprocess
from pathlib import Path
from qc_support import stage_dependencies
p = argparse.ArgumentParser(description=__doc__)
for key in ("engine", "output", "perel", "things"):
    p.add_argument("--" + key, type=Path, required=True)
p.add_argument('--checkpoint-runner', type=Path, default=Path(__file__).with_name('save_checkpoint.py'))
p.add_argument('--baseline', type=Path, help='Optional structured schema-1 implementation; default uses an explicit synthetic schema-1 fixture')
a = p.parse_args()
source = Path(__file__).resolve().parents[1]
root = a.output.absolute(); root.mkdir(parents=True, exist_ok=True)
engine = a.engine.absolute()
assert "Version: 2.1.23 " in subprocess.check_output([str(engine), "--version"], text=True)
assert json.loads((engine.parents[2]/"data/base/info.json").read_text())["version"] == "2.1.23"
stages = {}
for phase, code in [("donor", a.baseline or source), ("candidate", source)]:
    stage = root/phase; mods = stage/"mods"; mods.mkdir(parents=True)
    target = mods/"zzz-nonstandard-beacons"
    shutil.copytree(code, target, ignore=shutil.ignore_patterns(".git", ".qc", "dist", "tests", "__pycache__"))
    with (target/"control.lua").open("a", encoding="utf-8") as stream:
        stream.write("\n" + (source/"tests/schema-hooks.lua").read_text(encoding="utf-8"))
    fixture = mods/"nsbc-schema-fixture"; fixture.mkdir()
    (fixture/"info.json").write_text(json.dumps({"name":"nsbc-schema-fixture", "version":"0.0.1",
        "factorio_version":"2.1", "title":"Private NSBC schema acceptance", "author":"ESIR QC",
        "dependencies":["base", "quality", "zzz-nonstandard-beacons"]}))
    shutil.copy2(source/"tests/data.lua", fixture/"data.lua")
    shutil.copy2(source/"tests/schema-control.lua", fixture/"control.lua")
    stage_dependencies(a.perel,a.things,mods)
    (mods/"mod-list.json").write_text(json.dumps({"mods":[{"name":name,"enabled":True} for name in
        ["base","quality","perel","0-things","zzz-nonstandard-beacons","nsbc-schema-fixture"]]}))
    (stage/"config.ini").write_text("[path]\nread-data="+(engine.parents[2]/"data").as_posix()+
        "\nwrite-data="+stage.as_posix()+"\n[general]\ncheck-updates=false\n")
    stages[phase] = stage
donor = stages["donor"]
command = [str(engine), "--config", str(donor/"config.ini"), "--mod-directory", str(donor/"mods"),
           "--disable-audio", "--create", str(donor/"seed.zip")]
with (donor/"create.log").open("w") as log:
    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
save = donor/"seed.zip"
receipts = []
for phase, stage, name in [("donor",donor,"schema-donor"),
                          ("conversion",stages["candidate"],"schema-bootstrap-donor"),
                          ("on-load",stages["candidate"],"schema-accepted"),
                          ("reload",stages["candidate"],"schema-reloaded")]:
    command = [os.sys.executable,"-B",str(a.checkpoint_runner),"--engine",str(engine),"--run",str(stage),
        "--save",str(save),"--checkpoint",name+".zip","--phase",phase,"--receipt",name+".json"]
    if phase != "donor": command += ["--pass-key","passed"]
    subprocess.run(command, check=True)
    save = stage/"saves"/(name+".zip")
    receipts.append(json.loads((stage/(phase+".checkpoint.json")).read_text()))
(root/"result.json").write_text(json.dumps({"passed":True,"engine_version":"2.1.23","synthetic_schema1":a.baseline is None,"receipts":receipts},indent=2))
