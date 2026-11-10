"""Exercise original-ID unversioned metadata with unchanged-code on_load and second reload."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
from qc_support import identity, stage_dependencies

p = argparse.ArgumentParser(description=__doc__)
for key in ['engine', 'output', 'perel', 'things']:
    p.add_argument('--' + key, type=Path, required=True)
p.add_argument('--checkpoint-runner', type=Path, default=Path(__file__).with_name('save_checkpoint.py'))
a = p.parse_args()
source = Path(__file__).resolve().parents[1]
root = a.output.absolute(); mods = root / 'mods'; mods.mkdir(parents=True)
engine = a.engine.absolute()
assert 'Version: 2.1.23 ' in subprocess.check_output([str(engine), '--version'], text=True)
assert json.loads((engine.parents[2] / 'data/base/info.json').read_text())['version'] == '2.1.23'
mod_id, _, folder = identity(source)
target = mods / folder
shutil.copytree(source, target, ignore=shutil.ignore_patterns('.git', '.qc', 'dist', 'tests', '__pycache__'))
with (target / 'control.lua').open('a', encoding='utf-8') as stream:
    stream.write('\n' + (source / 'tests/legacy-hooks.lua').read_text(encoding='utf-8'))
fixture = mods / 'nsb-legacy-fixture'; fixture.mkdir()
(fixture / 'info.json').write_text(json.dumps(dict(name='nsb-legacy-fixture', version='0.0.1', factorio_version='2.1',
    title='Private NSB legacy conversion fixture', author='Theorun', dependencies=['base', 'quality', mod_id])))
shutil.copy2(source / 'tests/data.lua', fixture / 'data.lua')
shutil.copy2(source / 'tests/legacy-control.lua', fixture / 'control.lua')
dependencies = stage_dependencies(a.perel, a.things, mods)
(mods / 'mod-list.json').write_text(json.dumps({'mods': [{'name': n, 'enabled': True} for n in
    ['base', 'quality', 'perel', '0-things', mod_id, 'nsb-legacy-fixture']] + [{'name': 'space-age', 'enabled': False}]}))
(root / 'config.ini').write_text('[path]\nread-data=' + (engine.parents[2] / 'data').as_posix() + '\nwrite-data=' + root.as_posix() + '\n[general]\ncheck-updates=false\n')
command = [str(engine), '--config', str(root / 'config.ini'), '--mod-directory', str(mods), '--disable-audio', '--create', str(root / 'seed.zip')]
with (root / 'create.log').open('w') as stream:
    subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=120)
save = root / 'seed.zip'
receipts = []
for phase, name in [('donor', 'legacy-donor'), ('conversion', 'legacy-accepted'), ('reload', 'legacy-reloaded')]:
    command = [sys.executable, '-B', str(a.checkpoint_runner), '--engine', str(engine), '--run', str(root),
        '--save', str(save), '--checkpoint', name + '.zip', '--phase', phase, '--receipt', name + '.json', '--pass-key', 'passed']
    subprocess.run(command, check=True)
    receipts.append(json.loads((root / (phase + '.checkpoint.json')).read_text()))
    save = root / 'saves' / (name + '.zip')
(root / 'result.json').write_text(json.dumps(dict(passed=True, engine_version='2.1.23', dependencies=dependencies, receipts=receipts), indent=2))
