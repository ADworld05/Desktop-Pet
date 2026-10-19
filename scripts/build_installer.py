"""Standalone per-user setup packaging; invoked by build_windows.py --installer.

Only assembles local inputs and runs the setup's extraction-only /verify mode.
It never installs, opens the application, edits a user's registry, or downloads.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile

def build_installer(root,app,version,godot,cc,windres,env,run):
    if not windres.is_file():raise SystemExit('Select an existing MinGW-w64 windres with --windres.')
    work=root/'.build/Installer';project=work/'Project';bundle=work/'Bundle'
    bundle.mkdir(parents=True,exist_ok=True)
    shutil.copytree(root/'Installer/Source',project,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot','payload.json','payload.zip','*.dll'))
    native=project/'native';native.mkdir(exist_ok=True)
    for name in ['fox_window.dll','fox_path_boundary.dll']:shutil.copy2(app/name,native/name)
    sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
    files={f.relative_to(app).as_posix():sha(f) for f in sorted(app.rglob('*')) if f.is_file()}
    (project/'payload.json').write_text(json.dumps({'schema':'desktopfox.payload','release':version,'files':files},indent=2)+'\n',encoding='utf-8')
    with zipfile.ZipFile(project/'payload.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for name in files:archive.write(app/name,name)
    src=root/'Source/Native'
    run('setup_shortcuts',[cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-municode','-static-libgcc',src/'fox_install_shortcuts.c','-o',bundle/'DesktopFoxShortcuts.exe','-lole32','-lshell32','-luuid','-lbcrypt','-ladvapi32'])
    run('setup_import',[godot,'--headless','--path',project,'--editor','--import'])
    run('setup_export',[godot,'--headless','--path',project,'--export-release','Windows Setup',bundle/'SetupEngine.exe'])
    names=['SetupEngine.exe','DesktopFoxShortcuts.exe','fox_path_boundary.dll','fox_window.dll']
    for name in names[2:]:shutil.copy2(app/name,bundle/name)
    header='#define BUNDLE_COUNT 4\n#define BUNDLE_BYTES '+str(sum((bundle/n).stat().st_size for n in names))+'ULL\nstatic const struct {const WCHAR *name; uint64_t bytes; const WCHAR *hash;} bundle[]={\n'
    header+=''.join('{L"'+n+'",'+str((bundle/n).stat().st_size)+'ULL,L"'+sha(bundle/n)+'"},\n' for n in names)+'};\n'
    (work/'fox_setup_bundle.h').write_text(header,encoding='utf-8')
    run('setup_resources',[windres,'-I',src,src/'fox_setup_bootstrap.rc','-O','coff','-o',work/'resources.o'])
    stub=work/'stub.exe'
    run('setup_bootstrap',[cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-municode','-mwindows','-static-libgcc','-I',work,src/'fox_setup_bootstrap.c',work/'resources.o','-o',stub,'-lbcrypt','-lshell32'])
    setup=app.parent/'DesktopPet_Setup.exe'
    with setup.open('wb') as target:
        for source in [stub]+[bundle/n for n in names]:
            with source.open('rb') as data:shutil.copyfileobj(data,target)
    verify=work/'VerifyTemp';verify.mkdir(exist_ok=True)
    verify_env=env.copy();verify_env.update(TEMP=str(verify),TMP=str(verify))
    tested=subprocess.run([str(setup),'/verify'],env=verify_env,timeout=90)
    if tested.returncode or list(verify.iterdir()):raise SystemExit('Standalone setup /verify failed or left extracted files; inspect .build/Installer/VerifyTemp.')
    (work/'bundle.json').write_text(json.dumps({'release':version,'payload_files':len(files),'entries':[{'name':n,'bytes':(bundle/n).stat().st_size,'sha256':sha(bundle/n)} for n in names],'extraction_only_verify':'pass'},indent=2)+'\n',encoding='utf-8')
    print('Standalone setup extraction-only verification passed',flush=True)
    return {'installer_built':True,'setup':str(setup),'setup_sha256':sha(setup),'setup_bytes':setup.stat().st_size,'setup_extract_verify':'pass','actual_install_tested':False}
