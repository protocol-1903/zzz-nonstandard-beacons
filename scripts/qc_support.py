"""Small, explicit dependency staging helpers for private Factorio fixtures.

Inputs are supplied by the caller. This module never reads account profiles,
downloads dependencies, or changes the installed game's mod selections.
"""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile


def stage_dependency(path, mods, expected_name, minimum):
    path, mods = Path(path), Path(mods)
    if path.is_dir():
        info = json.loads((path / 'info.json').read_text(encoding='utf-8-sig'))
        archive_hash = None
    else:
        with zipfile.ZipFile(path) as archive:
            entries = [n for n in archive.namelist() if n.endswith('/info.json') and n.count('/') == 1]
            assert len(entries) == 1, 'Expected one mod root: ' + str(path)
            info = json.loads(archive.read(entries[0]).decode('utf-8-sig'))
        archive_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    assert info['name'] == expected_name, info
    assert tuple(map(int, info['version'].split('.'))) >= minimum, info
    target = mods / (info['name'] + '_' + info['version'])
    if path.is_dir():
        shutil.copytree(path, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    else:
        with zipfile.ZipFile(path) as archive:
            prefix = entries[0].removesuffix('info.json')
            for item in archive.infolist():
                assert item.filename.startswith(prefix), item.filename
                relative = Path(item.filename[len(prefix):])
                assert not relative.is_absolute() and '..' not in relative.parts
                if item.is_dir():
                    continue
                output = target / relative
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(archive.read(item))
    return dict(name=info['name'], version=info['version'], input=str(path.absolute()), archive_sha256=archive_hash)


def stage_dependencies(perel, things, mods):
    return [stage_dependency(perel, mods, 'perel', (1, 2, 3)),
            stage_dependency(things, mods, '0-things', (0, 6, 1))]


def identity(source):
    info = json.loads((Path(source) / 'info.json').read_text(encoding='utf-8-sig'))
    return info['name'], info['version'], info['name'] + '_' + info['version']
