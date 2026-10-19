"""Review tracked source inputs without reading runtime data or downloading tools."""
from pathlib import Path
import hashlib,json,re,sys
ROOT=Path(__file__).resolve().parents[1]
def files():
 for f in ROOT.rglob('*'):
  parts=f.relative_to(ROOT).parts
  if not f.is_file() or any(x in {'.git','.godot','.build','dist','__pycache__'} for x in parts) or f.suffix in {'.dll','.exe','.pyc'}:continue
  yield f
def main():
 errors=[];entries=[]
 for f in files():
  rel=f.relative_to(ROOT).as_posix();raw=f.read_bytes();entries.append({'path':rel,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
  if len(raw)>95*1024*1024:errors.append(rel+': exceeds reviewed source file size limit')
  if any(x in {'Runtime','History','Memory','Backups','Tools','Validation'} for x in Path(rel).parts):errors.append(rel+': private/generated directory')
  if f.suffix.lower() in {'.gd','.c','.h','.inc','.py','.md','.cfg','.json','.tscn','.tres','.gdextension','.yml','.yaml','.ps1','.txt'}:
   text=raw.decode('utf-8',errors='replace')
   for pattern,label in [(r'G:[\\/]','development drive'),(r'[A-Za-z]:[\\/]Users[\\/][^%\\/]+','personal user path'),(r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----','credential marker')]:
    if re.search(pattern,text):errors.append(rel+': '+label)
 for name in ['LICENSE','AUTHORS.md','THIRD_PARTY_NOTICES.md','Notices/Fox-Attribution.md','Source/Godot/scripts/FoxFileDialogs.gd','Source/Native/vendor/gdextension_interface.h']:
  if not (ROOT/name).is_file():errors.append('Missing '+name)
 for name in ['Source/Godot/export_presets.cfg','Installer/Source/export_presets.cfg']:
  if re.search(r'custom_template/(?:debug|release)="[^"\n]+"',(ROOT/name).read_text()):errors.append(name+': fixed template path')
 if errors:print('\n'.join(errors));return 1
 print(json.dumps({'source_files':len(entries),'source_bytes':sum(x['bytes'] for x in entries),'privacy_path_size_notice_checks':'pass'}))
 return 0
if __name__=='__main__':sys.exit(main())
