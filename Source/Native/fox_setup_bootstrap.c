#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <wchar.h>
#include <wctype.h>
#include "fox_setup_files.h"
#include "fox_setup_bundle.h" /* Generated finite names, lengths and SHA256. */
static BOOL join(WCHAR out[MAX_PATH],const WCHAR *a,const WCHAR *b) {
    return wcslen(a)+wcslen(b)+2<MAX_PATH && swprintf(out,MAX_PATH,L"%ls\\%ls",a,b)>0;
}
/* Windows cannot remove the running maintenance image. The built-in PowerShell
   performs only this exact hash-owned deletion after this process has exited.
   No recursive removal, user profile scripts, admin or shell-built file list. */
static BOOL defer_self_delete(const WCHAR *dir,const WCHAR *source,const WCHAR *hash) {
    WCHAR local[MAX_PATH],expected[MAX_PATH],ps[MAX_PATH],system[MAX_PATH],cmd[6000],wide[4500],pid[24],root[MAX_PATH],key[180];
    DWORD n=GetEnvironmentVariableW(L"LOCALAPPDATA",local,MAX_PATH);
    if(!n||n>MAX_PATH-65||!join(expected,local,L"Programs\\DesktopFox\\DesktopFoxMaintenance.exe")||_wcsicmp(source,expected))return FALSE;
    wcscpy(root,expected);*wcsrchr(root,L'\\')=0;
    unsigned long id=2166136261u;for(WCHAR *c=root;*c;c++)id=(id^(unsigned long)towlower(*c))*16777619u;
    swprintf(key,180,L"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\DesktopFox.%08lx",id);
    SetEnvironmentVariableW(L"FOX_SETUP_DELETE_KEY",key);
    const char code[]=
      "$Target=$env:FOX_SETUP_DELETE_TARGET;$Hash=$env:FOX_SETUP_DELETE_HASH;$WaitId=[int]$env:FOX_SETUP_DELETE_PID;"
      "$ErrorActionPreference='Stop';"
      "Wait-Process -Id $WaitId -Timeout 30 -ErrorAction SilentlyContinue;"
      "$expected=Join-Path $env:LOCALAPPDATA 'Programs\\DesktopFox\\DesktopFoxMaintenance.exe';"
      "if([IO.Path]::GetFullPath($Target) -ne [IO.Path]::GetFullPath($expected)){exit 2};"
      "$p=$Target;while($p){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){exit 3};$parent=[IO.Directory]::GetParent($p);$p=if($parent){$parent.FullName}else{$null}};"
      "$stream=[IO.File]::OpenRead($Target);$sha=[Security.Cryptography.SHA256]::Create();"
      "try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()};"
      "if($actual -ne $Hash){exit 4};"
      "$key=$env:FOX_SETUP_DELETE_KEY;$record=Get-ItemProperty -LiteralPath $key;"
      "if($record.MaintenanceSHA256 -ne $Hash -or $record.UninstallString -ne ([char]34+$Target+[char]34+' /uninstall')){exit 5};"
      "Remove-Item -LiteralPath $Target;Remove-Item -LiteralPath $key;"
      "$app=[IO.Path]::GetDirectoryName($Target);"
      "if(@(Get-ChildItem -LiteralPath $app -Force).Count -eq 0){Remove-Item -LiteralPath $app};"
      "$work=$env:FOX_SETUP_DELETE_WORK;"
      "if(@(Get-ChildItem -LiteralPath $work -Force).Count -eq 0){Remove-Item -LiteralPath $work};";
    if(!MultiByteToWideChar(CP_UTF8,0,code,-1,wide,4500))return FALSE;
    swprintf(pid,24,L"%lu",GetCurrentProcessId());
    SetEnvironmentVariableW(L"FOX_SETUP_DELETE_TARGET",source);SetEnvironmentVariableW(L"FOX_SETUP_DELETE_HASH",hash);
    SetEnvironmentVariableW(L"FOX_SETUP_DELETE_PID",pid);SetEnvironmentVariableW(L"FOX_SETUP_DELETE_WORK",dir);
    n=GetEnvironmentVariableW(L"SystemRoot",system,MAX_PATH);
    if(!n||n>MAX_PATH-64||!join(ps,system,L"System32\\WindowsPowerShell\\v1.0\\powershell.exe"))return FALSE;
    swprintf(cmd,6000,L"\"%ls\" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -Command \"%ls\"",ps,wide);
    STARTUPINFOW si={0};si.cb=sizeof(si);si.dwFlags=STARTF_USESHOWWINDOW;si.wShowWindow=SW_HIDE;PROCESS_INFORMATION pi={0};
    if(!CreateProcessW(ps,cmd,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,system,&si,&pi))return FALSE;
    CloseHandle(pi.hThread);CloseHandle(pi.hProcess);return TRUE;
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,LPWSTR line,int show) {
    (void)instance;(void)previous;(void)line;(void)show;
    int count=0;WCHAR **args=CommandLineToArgvW(GetCommandLineW(),&count);
    BOOL verify=count==2&&!wcscmp(args[1],L"/verify");BOOL uninstall=count==2&&!wcscmp(args[1],L"/uninstall");
    if(!args||count>2||(count==2&&!verify&&!uninstall)){if(args)LocalFree(args);return 2;}LocalFree(args);
    WCHAR source[MAX_PATH],temp[MAX_PATH],dir[MAX_PATH],path[MAX_PATH],hash[65];DWORD n=GetModuleFileNameW(NULL,source,MAX_PATH);
    int code=3;HANDLE file=INVALID_HANDLE_VALUE;BOOL made=FALSE,deferred=FALSE;
    DWORD temp_length=GetTempPathW(MAX_PATH,temp);
    if(!n||n>=MAX_PATH||!setup_plain(source)||!temp_length||temp_length>=MAX_PATH||!setup_plain(temp))goto done;
    BYTE random[12];if(BCryptGenRandom(NULL,random,sizeof(random),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)goto done;
    WCHAR leaf[64]=L"DesktopFoxSetup-";for(int j=0;j<12;j++)swprintf(leaf+16+j*2,3,L"%02x",random[j]);
    if(!join(dir,temp,leaf)||!CreateDirectoryW(dir,NULL)||!setup_plain(dir))goto done;made=TRUE;
    file=CreateFileW(source,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN,NULL);
    LARGE_INTEGER size,offset;if(file==INVALID_HANDLE_VALUE||!GetFileSizeEx(file,&size)||size.QuadPart<0||(uint64_t)size.QuadPart<BUNDLE_BYTES+8)goto done;
    offset.QuadPart=size.QuadPart-BUNDLE_BYTES; if(!SetFilePointerEx(file,offset,NULL,FILE_BEGIN))goto done;
    for(unsigned j=0;j<BUNDLE_COUNT;j++) {
        if(!join(path,dir,bundle[j].name))goto done;
        HANDLE out=CreateFileW(path,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);if(out==INVALID_HANDLE_VALUE)goto done;
        uint64_t remaining=bundle[j].bytes;BYTE buffer[65536];BOOL ok=TRUE;
        while(remaining){DWORD want=remaining>sizeof(buffer)?sizeof(buffer):(DWORD)remaining,got=0,written=0;
            if(!ReadFile(file,buffer,want,&got,NULL)||got!=want||!WriteFile(out,buffer,got,&written,NULL)||written!=got){ok=FALSE;break;}remaining-=got;}
        if(!FlushFileBuffers(out))ok=FALSE;CloseHandle(out);
        if(!ok||!setup_hash(path,hash)||wcscmp(hash,bundle[j].hash))goto done;
    }
    CloseHandle(file);file=INVALID_HANDLE_VALUE;code=0;if(verify)goto done;
    SetEnvironmentVariableW(L"FOX_SETUP_SOURCE",source);SetEnvironmentVariableW(L"FOX_SETUP_MODE",uninstall?L"uninstall":L"normal");
    WCHAR flag[MAX_PATH];if(!join(flag,dir,L"uninstall-complete.flag"))goto done;SetEnvironmentVariableW(L"FOX_SETUP_CLEANUP_FLAG",flag);
    if(!join(path,dir,L"SetupEngine.exe"))goto done;
    WCHAR command[MAX_PATH+4];swprintf(command,MAX_PATH+4,L"\"%ls\"",path);
    STARTUPINFOW si={0};si.cb=sizeof(si);PROCESS_INFORMATION pi={0};
    if(!CreateProcessW(path,command,NULL,NULL,FALSE,0,NULL,dir,&si,&pi)){code=4;goto done;}
    CloseHandle(pi.hThread);WaitForSingleObject(pi.hProcess,INFINITE);DWORD exit_code=1;GetExitCodeProcess(pi.hProcess,&exit_code);CloseHandle(pi.hProcess);code=(int)exit_code;
    if(GetFileAttributesW(flag)!=INVALID_FILE_ATTRIBUTES && setup_plain(flag)) {
        HANDLE mark=CreateFileW(flag,GENERIC_READ,0,NULL,OPEN_EXISTING,0,NULL);char value[32]={0};DWORD read=0;
        if(mark!=INVALID_HANDLE_VALUE){ReadFile(mark,value,31,&read,NULL);CloseHandle(mark);}
        if(read==18&&!memcmp(value,"uninstall complete",18)&&setup_hash(source,hash))deferred=defer_self_delete(dir,source,hash);
        DeleteFileW(flag);
    }
done:
    if(file!=INVALID_HANDLE_VALUE)CloseHandle(file);
    if(made){
        for(unsigned j=0;j<BUNDLE_COUNT;j++)if(join(path,dir,bundle[j].name)&&setup_hash(path,hash)&&!wcscmp(hash,bundle[j].hash))DeleteFileW(path);
        if(!deferred)RemoveDirectoryW(dir); /* Empty only; changed/unknown files kept. */
    }
    if(code && !verify)MessageBoxW(NULL,L"Setup could not verify or start its components. Keep the complete original file, check free space and retry. Your saved data was not removed.",L"Desktop Pet Setup",MB_OK|MB_ICONERROR);
    return code;
}
