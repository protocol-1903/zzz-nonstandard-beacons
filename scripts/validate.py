"""Isolated Factorio acceptance runner. Never modifies the user's installed mods."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from qc_support import identity, stage_dependencies

parser = argparse.ArgumentParser()
parser.add_argument("--engine", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--perel", type=Path, required=True)
parser.add_argument("--things", type=Path, required=True)
parser.add_argument("--ticks", type=int, default=195)
parser.add_argument("--space-age", action="store_true")
parser.add_argument("--examples", action="store_true")
parser.add_argument("--add-to-existing", action="store_true", help="Create without NSB, then add it and its fixture to that existing save")
args = parser.parse_args()
source = Path(__file__).resolve().parents[1]
mod_id, mod_version, mod_folder = identity(source)
engine = args.engine.absolute() # Retain a short task-owned junction for Windows asset path limits.
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
version = subprocess.run([str(engine), "--version"], capture_output=True, text=True, check=True).stdout
assert "Version: 2.1.23 " in version, version
data = engine.parents[2] / "data"
assert json.loads((data / "base/info.json").read_text())["version"] == "2.1.23"
mods = output / "mods"
mods.mkdir(exist_ok=True)
shutil.copytree(source, mods / mod_folder,
                dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git", ".qc", "dist", "tests", "__pycache__"))
shutil.copytree(source / "tests", mods / "nsbc-fixture_0.0.1", dirs_exist_ok=True)
example_settings = mods / "nsbc-fixture_0.0.1/settings-updates.lua"
if args.examples:
    example_settings.write_text('data.raw["bool-setting"]["nsb-include-example-beacons"].default_value = true\n')
else:
    example_settings.unlink(missing_ok=True)
staged_control = mods / mod_folder / "control.lua"
staged_control.write_text((source / "control.lua").read_text(encoding="utf-8") +
                          (source / "tests/hooks.lua").read_text(encoding="utf-8"), encoding="utf-8")
dependencies = stage_dependencies(args.perel, args.things, mods)
(mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": name, "enabled": True}
  for name in ["base", "quality", "perel", "0-things", mod_id, "nsbc-fixture"]] + [{"name": "space-age", "enabled": args.space_age}]}))
config = output / "config.ini"
config.write_text("[path]\nread-data=" + data.as_posix() + "\nwrite-data=" + (output / "user").as_posix() + "\n[general]\ncheck-updates=false\n[graphics]\nfull-screen=false\nwindow-size=1600x1000\n")
common = [str(engine), "--config", str(config), "--mod-directory", str(mods), "--disable-audio"]
results = []
for name, arguments in [("create", ["--create", str(output / "fixture.zip")]),
                        ("runtime", ["--benchmark", str(output / "fixture.zip"), "--benchmark-ticks", str(args.ticks), "--benchmark-runs", "1"])]:
    if args.add_to_existing:
        selection = json.loads((mods / "mod-list.json").read_text())
        for row in selection["mods"]:
            if row["name"] in (mod_id, "nsbc-fixture"): row["enabled"] = name != "create"
        (mods / "mod-list.json").write_text(json.dumps(selection))
    completed = subprocess.run(common + arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", timeout=180)
    (output / (name + ".log")).write_text(completed.stdout, encoding="utf-8")
    required = (["NSBC-QC COMPLETE"] + (["NSBC-RECOVERY COMPLETE"] if args.ticks >= 190 else []) +
                (["NSBC-ACTOR COMPLETE"] if args.space_age and args.ticks >= 3600 else [])) if name == "runtime" else []
    accepted = completed.returncode == 0 and all(marker in completed.stdout for marker in required)
    results.append({"name": name, "exit_code": completed.returncode, "accepted": accepted, "required_markers": required})
    print(completed.stdout[-7000:])
    if not accepted: break
(output / "run.json").write_text(json.dumps({"engine": version.strip(), "mod_id": mod_id, "mod_version": mod_version, "dependencies": dependencies, "add_to_existing": args.add_to_existing, "results": results}, indent=2))
raise SystemExit(0 if len(results) == 2 and all(r["accepted"] for r in results) else 1)
