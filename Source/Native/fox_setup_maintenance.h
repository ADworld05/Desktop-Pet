#include "fox_setup_files.h"
/* Ownership is separate from payload hashes to avoid embedding the setup in itself.
   Registry identity derives from the installation root, so isolated profiles do
   not overwrite the normal user's maintenance registration. */
static int setup_maintenance(const WCHAR *action) {
    BOOL remove=!wcscmp(action,L"Remove");if(!remove && wcscmp(action,L"Register"))return 2;
    WCHAR local[MAX_PATH],root[MAX_PATH],target[MAX_PATH],source[MAX_PATH],key[160],hash[65],oldhash[65],command[MAX_PATH+32],modify[MAX_PATH+4];
    DWORD n=GetEnvironmentVariableW(L"LOCALAPPDATA",local,MAX_PATH);
    if(!n||n>MAX_PATH-65)return 2;
    swprintf(root,MAX_PATH,L"%ls\\Programs\\DesktopFox",local);
    swprintf(target,MAX_PATH,L"%ls\\DesktopFoxMaintenance.exe",root);
    swprintf(command,MAX_PATH+32,L"\"%ls\" /uninstall",target);
    swprintf(modify,MAX_PATH+4,L"\"%ls\"",target);
    /* FNV root discriminator is an identity, never a security hash. */
    unsigned long id=2166136261u;for(WCHAR *c=root;*c;c++){WCHAR v=towlower(*c);id=(id^(unsigned long)v)*16777619u;}
    swprintf(key,160,L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\DesktopFox.%08lx",id);
    if(!setup_plain(root))return 3;
    HKEY k=NULL;BOOL existed=RegOpenKeyExW(HKEY_CURRENT_USER,key,0,KEY_READ|KEY_WRITE,&k)==ERROR_SUCCESS;
    if(existed) {
        WCHAR value[MAX_PATH+32];DWORD bytes=sizeof(value),type=0;
        if(RegGetValueW(k,NULL,L"UninstallString",RRF_RT_REG_SZ,&type,value,&bytes)!=ERROR_SUCCESS||wcscmp(value,command)){RegCloseKey(k);return 4;}
        bytes=sizeof(oldhash);
        if(RegGetValueW(k,NULL,L"MaintenanceSHA256",RRF_RT_REG_SZ,&type,oldhash,&bytes)!=ERROR_SUCCESS||wcslen(oldhash)!=64 ||
           (GetFileAttributesW(target)!=INVALID_FILE_ATTRIBUTES && (!setup_hash(target,hash)||wcscmp(hash,oldhash)))){RegCloseKey(k);return 5;}
    } else if(GetFileAttributesW(target)!=INVALID_FILE_ATTRIBUTES)return 6;
    if(remove) {
        if(!existed)return 7;
        RegCloseKey(k);
        n=GetEnvironmentVariableW(L"FOX_SETUP_SOURCE",source,MAX_PATH);
        BOOL self=n && n<MAX_PATH && !_wcsicmp(source,target);
        if(!self && GetFileAttributesW(target)!=INVALID_FILE_ATTRIBUTES && !DeleteFileW(target))return 9;
        if(!self && RegDeleteKeyW(HKEY_CURRENT_USER,key)!=ERROR_SUCCESS)return 8;
        if(!self)RemoveDirectoryW(root); /* Empty only. */
        printf("{\"ok\":true,\"defer_self_removal\":%s}\n",self?"true":"false");return 0;
    }
    n=GetEnvironmentVariableW(L"FOX_SETUP_SOURCE",source,MAX_PATH);
    if(!n||n>=MAX_PATH||!setup_hash(source,hash)){if(k)RegCloseKey(k);return 10;}
    if(_wcsicmp(source,target)) {
        WCHAR stage[MAX_PATH];swprintf(stage,MAX_PATH,L"%ls.new",target);
        if(!CopyFileW(source,stage,TRUE)){if(k)RegCloseKey(k);return 11;}
        WCHAR copied[65];
        if(!setup_hash(stage,copied)||wcscmp(hash,copied)||!MoveFileExW(stage,target,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)){DeleteFileW(stage);if(k)RegCloseKey(k);return 12;}
    }
    if(!k && RegCreateKeyExW(HKEY_CURRENT_USER,key,0,NULL,0,KEY_READ|KEY_WRITE,NULL,&k,NULL)!=ERROR_SUCCESS)return 13;
    struct {const WCHAR *name,*value;} values[]={
        {L"DisplayName",L"Desktop Pet"},{L"DisplayVersion",L"1.0.0-rc.7"},
        {L"Publisher",L"Desktop Pet project"},{L"InstallLocation",root},
        {L"UninstallString",command},{L"ModifyPath",modify},{L"MaintenanceSHA256",hash}
    };
    BOOL ok=TRUE;for(unsigned j=0;j<sizeof(values)/sizeof(values[0]);j++)
        if(RegSetValueExW(k,values[j].name,0,REG_SZ,(BYTE*)values[j].value,(DWORD)((wcslen(values[j].value)+1)*sizeof(WCHAR)))!=ERROR_SUCCESS)ok=FALSE;
    RegCloseKey(k);printf("{\"ok\":%s}\n",ok?"true":"false");return ok?0:14;
}
