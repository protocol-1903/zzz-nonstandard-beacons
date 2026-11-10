"""Deterministic shipping allowlist and an isolated test of the actual dry-run ZIP."""
import argparse, hashlib, json, pathlib, shutil, subprocess, zipfile
from qc_support import identity, stage_dependencies
p=argparse.ArgumentParser()
for key in ['engine','output','perel','things']: p.add_argument('--'+key,type=pathlib.Path,required=True)
a=p.parse_args(); source=pathlib.Path(__file__).resolve().parents[1]; out=a.output.resolve(); out.mkdir(parents=True,exist_ok=True)
sha=lambda data:hashlib.sha256(data).hexdigest()
names=['info.json','control.lua','data.lua','data-final-fixes.lua','settings.lua','thumbnail.png','LICENSE','README.md','changelog.txt']
names += [p.relative_to(source).as_posix() for folder,pattern in [('scripts','*.lua'),('locale','*.cfg'),('migrations','*.lua')] for p in (source/folder).rglob(pattern)]
names=sorted(names); mod_id,mod_version,root=identity(source)
archive=out/(root+'.zip'); inventory=[]
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for name in names:
  data=(source/name).read_bytes(); inventory.append({'path':name,'size_bytes':len(data),'sha256':sha(data)})
  entry=zipfile.ZipInfo(root+'/'+name,date_time=(2026,10,24,0,0,0)); entry.compress_type=zipfile.ZIP_DEFLATED
  z.writestr(entry,data)
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 assert set(z.namelist()) == {root+'/'+name for name in names}
 assert b'nsbc-qc' not in z.read(root+'/control.lua')
engine=a.engine.absolute(); version=subprocess.check_output([str(engine),'--version'],text=True); assert 'Version: 2.1.23 ' in version
assert json.loads((engine.parents[2]/'data/base/info.json').read_text())['version']=='2.1.23'
mods=out/'mods'; mods.mkdir(exist_ok=True); shutil.copy2(archive,mods/archive.name)
dependencies=stage_dependencies(a.perel,a.things,mods)
shutil.copytree(source/'tests',mods/'nsbc-fixture_0.0.1',dirs_exist_ok=True)
(mods/'mod-list.json').write_text(json.dumps({'mods':[{'name':n,'enabled':True} for n in ['base','quality','perel','0-things',mod_id,'nsbc-fixture']]+[{'name':'space-age','enabled':False}]}))
config=out/'config.ini'; config.write_text('[path]\nread-data='+(engine.parents[2]/'data').as_posix()+'\nwrite-data='+(out/'user').as_posix()+'\n[general]\ncheck-updates=false\n')
common=[str(engine),'--config',str(config),'--mod-directory',str(mods),'--disable-audio']; results=[]
for name,args in [('create',['--create',str(out/'fixture.zip')]),('runtime',['--benchmark',str(out/'fixture.zip'),'--benchmark-ticks','125','--benchmark-runs','1'])]:
 run=subprocess.run(common+args,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
 (out/(name+'.log')).write_text(run.stdout+run.stderr,encoding='utf-8'); results.append({'phase':name,'exit_code':run.returncode})
 assert run.returncode==0,(name,run.stdout[-3000:])
 if name=='runtime': assert 'NSBC-QC COMPLETE' in run.stdout
receipt={'mod_id':mod_id,'version':mod_version,'dependencies':dependencies,'zip':str(archive),'sha256':sha(archive.read_bytes()),
 'files':inventory,'file_inventory_sha256':sha(json.dumps(inventory,sort_keys=True,separators=(',',':')).encode()),
 'engine':version.strip(),'results':results,'published':False,'installed_to_active_game':False}
(out/'manifest.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('Package dry run passed:',archive); print('SHA256:',receipt['sha256'])
