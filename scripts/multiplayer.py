"""Private localhost server and two isolated graphical clients; no account credentials."""
import argparse, json, pathlib, shutil, subprocess, time
p=argparse.ArgumentParser()
for key in ['engine','output','staged']: p.add_argument('--'+key,type=pathlib.Path,required=True)
p.add_argument('--use-staged-mods',action='store_true',help='Use an already isolated full-consumer fixture without copying its media')
p.add_argument('--wait-seconds',type=int,default=90)
p.add_argument('--graphics-quality',choices=['high','medium'],default='high',help='Isolated client sprite resolution; medium bounds full-consumer atlas memory')
a=p.parse_args(); out=a.output.absolute(); out.mkdir(parents=True,exist_ok=True)
fork=pathlib.Path(__file__).resolve().parents[1]; engine=a.engine.absolute()
mods=(a.staged.absolute()/'mods') if a.use_staged_mods else out/'mods'
if not a.use_staged_mods:
 shutil.copytree(a.staged/'mods',mods,dirs_exist_ok=True)
 shutil.copy2(fork/'tests/multiplayer-control.lua',mods/'nsbc-fixture_0.0.1/control.lua')
assert 'Version: 2.1.23 ' in subprocess.check_output([str(engine),'--version'],text=True)
assert json.loads((engine.parents[2]/'data/base/info.json').read_text())['version']=='2.1.23'
profiles={}
for name in ['server','client-a','client-b']:
 root=out/name; (root/'user/saves').mkdir(parents=True,exist_ok=True)
 (root/'runtime.log').unlink(missing_ok=True)
 config=root/'config.ini'
 config.write_text('[path]\nread-data='+(engine.parents[2]/'data').as_posix()+'\nwrite-data='+(root/'user').as_posix()+'\n[general]\ncheck-updates=false\n[graphics]\nfull-screen=false\nwindow-size=1280x800\nhalt-rendering-when-minimized=false\nmax-sprite-loading-threads=2\nvideo-memory-usage=low\ncache-sprite-atlas=false\ngraphics-quality='+a.graphics_quality+'\n')
 if name != 'server': (root/'user/player-data.json').write_text(json.dumps({'service-username':'NSBC-QC-'+name}))
 profiles[name]=(root,[str(engine),'--config',str(config),'--mod-directory',str(mods),'--disable-audio'])
root,command=profiles['server']; settings=root/'settings.json'
settings.write_text(json.dumps({'name':'Private NSBC acceptance','description':'Isolated localhost acceptance fixture','visibility':{'public':False,'lan':False},'require_user_verification':False,'auto_pause':False,'autosave_interval':0}))
created=subprocess.run(command+['--create',str(root/'seed.zip')],capture_output=True,text=True,encoding='utf-8',errors='replace')
(root/'create.log').write_text(created.stdout+created.stderr,encoding='utf-8'); assert created.returncode == 0
for marker in ['nsbc-mp-disconnect.json','nsbc-mp-rejoin.json','nsbc-mp-result.json']:
 (root/'user/script-output'/marker).unlink(missing_ok=True)
processes=[]; files=[]
def launch(name,arguments):
 root,command=profiles[name]; log=(root/'runtime.log').open('a',encoding='utf-8'); files.append(log)
 startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=0
 process=subprocess.Popen(command+arguments,stdout=log,stderr=subprocess.STDOUT,startupinfo=startup)
 processes.append(process); return process
def wait_marker(marker,seconds=None):
 seconds=seconds or a.wait_seconds
 deadline=time.monotonic()+seconds; path=profiles['server'][0]/'user/script-output'/marker
 while time.monotonic()<deadline:
  if server.poll() is not None: raise RuntimeError('Private fixture server exited')
  for name in profiles:
   log=profiles[name][0]/'runtime.log'
   text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
   if any(marker in text for marker in ['non-recoverable error','Desync','Unexpected error occurred','Error AtlasBuilder.cpp:']):
    raise RuntimeError('Failure in '+str(log))
  if path.exists(): print('Passed',marker,flush=True); return
  time.sleep(.25)
 raise RuntimeError('Timed out waiting for '+marker)
try:
 server=launch('server',['--start-server',str(root/'seed.zip'),'--server-settings',str(settings),'--bind','127.0.0.1','--port','34221'])
 first=launch('client-a',['--mp-connect','127.0.0.1:34221'])
 # Full ESIR sprite loading has a large temporary allocation. Let one real
 # client finish loading before starting the other; their actions still overlap.
 deadline=time.monotonic()+a.wait_seconds
 while time.monotonic()<deadline:
  if server.poll() is not None or first.poll() is not None:
   raise RuntimeError('Server or first client exited before joining')
  text=(profiles['server'][0]/'runtime.log').read_text(encoding='utf-8',errors='replace')
  if '[JOIN] NSBC-QC-client-a joined the game' in text: break
  time.sleep(.25)
 else: raise RuntimeError('First client did not join before its load deadline')
 second=launch('client-b',['--mp-connect','127.0.0.1:34221'])
 wait_marker('nsbc-mp-disconnect.json')
 second.terminate(); second.wait(timeout=10)
 wait_marker('nsbc-mp-rejoin.json',45)
 second=launch('client-b',['--mp-connect','127.0.0.1:34221'])
 wait_marker('nsbc-mp-result.json')
 time.sleep(2)
 (out/'result.json').write_text(json.dumps({'passed':True,'clients':2,'rejoined':True,'network':'127.0.0.1:34221','graphics_quality':a.graphics_quality},indent=2))
finally:
 for process in reversed(processes):
  if process.poll() is None: process.terminate(); process.wait(timeout=10)
 for log in files: log.close()
