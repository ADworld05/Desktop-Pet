"""Build the portable Windows application using existing tools; never downloads."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
VERSION='1.0.0-rc.7'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True,help='Godot4.7.2 Standard executable');p.add_argument('--cc',default='gcc',help='64-bit MinGW-w64 GCC');p.add_argument('--templates',help='Directory containing the matching Windows export templates');p.add_argument('--installer',action='store_true',help='Also build and verify the standalone setup');p.add_argument('--windres',help='MinGW-w64 resource compiler (default: beside GCC)');a=p.parse_args()
 if os.name!='nt':raise SystemExit('This build entry point requires Windows.')
 godot=Path(shutil.which(a.godot) or a.godot).resolve();cc=Path(shutil.which(a.cc) or a.cc).resolve()
 if not godot.is_file() or not cc.is_file():raise SystemExit('Select existing Godot and MinGW-w64 tools; nothing is downloaded.')
 version=subprocess.check_output([str(godot),'--version'],text=True).strip()
 machine=subprocess.check_output([str(cc),'-dumpmachine'],text=True).strip()
 if not version.startswith('4.7.2.') or not machine.startswith('x86_64-'):raise SystemExit('Requires Godot4.7.2 and x86_64 MinGW-w64 GCC.')
 temp=ROOT/'.build';out=ROOT/'dist'/VERSION/'DesktopPet';logs=temp/'logs'
 for folder in [temp,out,logs]:folder.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy()
 for key,leaf in [('APPDATA','Roaming'),('LOCALAPPDATA','Local')]:
  folder=temp/'Profile'/leaf;folder.mkdir(parents=True,exist_ok=True);env[key]=str(folder)
 if a.templates:
  templates=Path(a.templates).resolve()
  if not (templates/'windows_release_x86_64.exe').is_file():raise SystemExit('Select the matching export-template directory, not its parent.')
  target=Path(env['APPDATA'])/'Godot/export_templates'/('4.7.2.stable')
  target.mkdir(parents=True,exist_ok=True)
  for name in ['windows_release_x86_64.exe','version.txt']:
   if (templates/name).is_file() and (templates/name).resolve()!=(target/name).resolve():shutil.copy2(templates/name,target/name)
 def run(label,args):
  for attempt in range(2):
   path=logs/(label+('.attempt1' if attempt==0 else '.attempt2')+'.log')
   with path.open('w',encoding='utf-8') as log:
    result=subprocess.run([str(x) for x in args],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
   text=path.read_text(encoding='utf-8',errors='replace')
   shutil.copy2(path,logs/(label+'.log'))
   if attempt==0 and label in {'godot_import','setup_import'} and result.returncode in {3221225477,-1073741819} and 'SCRIPT ERROR' not in text:
    print(label+': Godot cache-initialization access violation; retrying once (first log retained).',flush=True)
    continue
   if result.returncode or 'SCRIPT ERROR' in text:raise SystemExit(f'{label} failed (exit {result.returncode}); inspect {path.relative_to(ROOT)}')
   break
  print(label+' passed',flush=True)
 src=ROOT/'Source/Native';native=ROOT/'Source/Godot/native'
 common=[cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-cast-function-type','-shared','-static-libgcc']
 targets=[('fox_window',['user32','advapi32','wtsapi32']),('fox_chat_window',[]),('fox_glass',['user32','gdi32']),('fox_path_boundary',['advapi32','user32','shlwapi','wintrust','crypt32'])]
 for name,libs in targets:
  run(name,[*common,src/(name+'.c'),'-o',native/(name+'.dll'),*['-l'+x for x in libs]])
  shutil.copy2(native/(name+'.dll'),out/(name+'.dll'))
 for name,source,flags,libs in [('DesktopPet','fox_release_launcher',['-mwindows'],[]),('DesktopFoxStartup','fox_release_startup',[],['ole32','shell32','uuid'])]:
  run(name,[cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-municode','-static-libgcc',*flags,src/(source+'.c'),'-o',out/(name+'.exe'),*['-l'+x for x in libs]])
 project=ROOT/'Source/Godot'
 run('godot_import',[godot,'--headless','--path',project,'--editor','--import'])
 run('godot_export',[godot,'--headless','--path',project,'--export-release','Windows Portable Release',out/'DesktopFox.exe'])
 shutil.copytree(ROOT/'Notices',out/'Notices',dirs_exist_ok=True)
 shutil.copytree(ROOT/'docs/images',out/'docs/images',dirs_exist_ok=True)
 for name in ['README.md','LICENSE','AUTHORS.md','THIRD_PARTY_NOTICES.md']:shutil.copy2(ROOT/name,out/name)
 sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
 inventory={f.relative_to(out).as_posix():{'bytes':f.stat().st_size,'sha256':sha(f)} for f in out.rglob('*') if f.is_file() and f.name not in ['release.json','SHA256SUMS.txt']}
 (out/'release.json').write_text(json.dumps({'version':VERSION,'product':'Desktop Pet','build':'local-source-review','godot':version,'compiler_target':machine,'unsigned':True,'files':inventory},indent=2)+'\n',encoding='utf-8')
 (out/'SHA256SUMS.txt').write_text(''.join(sha(f)+'  '+f.relative_to(out).as_posix()+'\n' for f in sorted(out.rglob('*')) if f.is_file() and f.name!='SHA256SUMS.txt'),encoding='utf-8')
 archive=out.parent/'DesktopPet_Portable.zip'
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for f in sorted(out.rglob('*')):
   if f.is_file():z.write(f,'DesktopPet/'+f.relative_to(out).as_posix())
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  assert not any(n.startswith('DesktopPet/Source/') or '/.godot/' in n for n in z.namelist())
 result={'version':VERSION,'portable_zip':str(archive),'sha256':sha(archive),'bytes':archive.stat().st_size,'runtime_files':8,'installer_built':False}
 if a.installer:
  from build_installer import build_installer
  result.update(build_installer(ROOT,out,VERSION,godot,cc,Path(a.windres).resolve() if a.windres else cc.with_name('windres.exe'),env,run))
 (temp/'build_result.json').write_text(json.dumps(result,indent=2)+'\n')
 print('Local review build complete. Run '+str(out/'DesktopPet.exe'))
if __name__=='__main__':main()
