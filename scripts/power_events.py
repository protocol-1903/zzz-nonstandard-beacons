"""Paired baseline/candidate native transition tests with five identical engine runs."""
import argparse, hashlib, json, os, re, shutil, subprocess
from pathlib import Path
from qc_support import stage_dependencies
p=argparse.ArgumentParser(description=__doc__)
for key in ("engine","output","perel","things"): p.add_argument("--"+key,type=Path,required=True)
p.add_argument('--baseline',type=Path,help='Optional compatible structured implementation; not unmodified upstream 2.0.0')
a=p.parse_args(); source=Path(__file__).resolve().parents[1]; root=a.output.absolute();root.mkdir(parents=True,exist_ok=True)
engine=a.engine.absolute(); assert 'Version: 2.1.23 ' in subprocess.check_output([str(engine),'--version'],text=True)
assert json.loads((engine.parents[2]/'data/base/info.json').read_text())['version']=='2.1.23'
reports={}
for phase,code in ([('baseline',a.baseline)] if a.baseline else []) + [('candidate',source)]:
 stage=root/phase;mods=stage/'mods';mods.mkdir(parents=True)
 target=mods/'zzz-nonstandard-beacons';shutil.copytree(code,target,ignore=shutil.ignore_patterns('.git','.qc','dist','tests','__pycache__'))
 with (target/'control.lua').open('a',encoding='utf-8') as f:f.write('\n'+(source/'tests/power-events-hooks.lua').read_text())
 fixture=mods/'nsbc-events-fixture';fixture.mkdir()
 (fixture/'info.json').write_text(json.dumps({'name':'nsbc-events-fixture','version':'0.0.1','factorio_version':'2.1','title':'Private NSBC event acceptance','author':'ESIR QC','dependencies':['base','quality','zzz-nonstandard-beacons']}))
 shutil.copy2(source/'tests/data.lua',fixture/'data.lua');shutil.copy2(source/'tests/power-events-control.lua',fixture/'control.lua')
 stage_dependencies(a.perel,a.things,mods)
 (mods/'mod-list.json').write_text(json.dumps({'mods':[{'name':n,'enabled':True} for n in ['base','quality','perel','0-things','zzz-nonstandard-beacons','nsbc-events-fixture']]+[{'name':'space-age','enabled':False}]}))
 (stage/'config.ini').write_text('[path]\nread-data='+(engine.parents[2]/'data').as_posix()+'\nwrite-data='+stage.as_posix()+'\n[general]\ncheck-updates=false\n')
 command=[str(engine),'--config',str(stage/'config.ini'),'--mod-directory',str(mods),'--disable-audio']
 (stage/'map-gen.json').write_text(json.dumps({'seed':1903}))
 for name,args in [('create',['--create',str(stage/'seed.zip'),'--map-gen-settings',str(stage/'map-gen.json')]),('runtime',['--benchmark',str(stage/'seed.zip'),'--benchmark-ticks','600','--benchmark-runs','5'])]:
  run=subprocess.run(command+args,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
  text=run.stdout+run.stderr;(stage/(name+'.log')).write_text(text,encoding='utf-8')
  assert run.returncode==0,text[-4500:]
  if name=='runtime':assert text.count('NSBC-EVENTS COMPLETE')==5,text[-4500:]
 fixture_report=json.loads((stage/'script-output/power-events.json').read_text())
 assert fixture_report['passed']
 reports[phase]={'fixture':fixture_report,'benchmark_ms':[float(v) for v in re.findall(r'Performed 600 updates in ([\d.]+) ms',text)],
  'source_sha256':{p.relative_to(target).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*.lua')}}
 # Time only the shared transition workload. The later candidate-only missing-
 # definition conversion deliberately does extra work and is not a fair benchmark.
 run=subprocess.run(command+['--benchmark',str(stage/'seed.zip'),'--benchmark-ticks','381','--benchmark-runs','5'],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
 text=run.stdout+run.stderr;(stage/'paired-benchmark.log').write_text(text,encoding='utf-8')
 assert run.returncode==0 and text.count('NSBC-EVENTS TRANSITIONS COMPLETE')==5,text[-3000:]
 reports[phase]['paired_benchmark_ms']=[float(v) for v in re.findall(r'Performed 381 updates in ([\d.]+) ms',text)]
(root/'result.json').write_text(json.dumps({'passed':True,'engine':'2.1.23','reports':reports},indent=2))
print(json.dumps({phase:{'fixture':r['fixture'],'paired_benchmark_ms':r['paired_benchmark_ms']} for phase,r in reports.items()}))
