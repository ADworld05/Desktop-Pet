#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <shlobj.h>
#include <objbase.h>
#include <stdio.h>
#include <wchar.h>
#include <wctype.h>
#include "fox_setup_maintenance.h"
/* Finite installer-only shortcut operations, fixed App target, no shell. */
int wmain(int count,WCHAR **args) {
    if(count==3 && !wcscmp(args[1],L"Maintenance"))return setup_maintenance(args[2]);
    if(count<3 || count>4)return 2;
    int folder_id=0,action=0;const WCHAR *kind=NULL;
    if(!wcscmp(args[1],L"Desktop")){folder_id=CSIDL_DESKTOPDIRECTORY;kind=L"Desktop";}
    else if(!wcscmp(args[1],L"Menu")){folder_id=CSIDL_PROGRAMS;kind=L"Menu";}
    else if(!wcscmp(args[1],L"Startup")){folder_id=CSIDL_STARTUP;kind=L"Startup";}
    else return 2;
    if(!wcscmp(args[2],L"Enable"))action=1;
    else if(!wcscmp(args[2],L"Disable"))action=2;
    else if(wcscmp(args[2],L"Status"))return 2;
    BOOL fixture=count==4;
    if(fixture && wcscmp(args[3],L"Fixture"))return 2;
    WCHAR folder[MAX_PATH]={0},path[MAX_PATH]={0};BOOL enabled=FALSE,conflict=FALSE;
    HRESULT error=S_OK;
    WCHAR local[MAX_PATH]={0},target[MAX_PATH]={0},working[MAX_PATH]={0};
    DWORD got=GetEnvironmentVariableW(L"LOCALAPPDATA",local,MAX_PATH);
    if(!got || got>=MAX_PATH-45)return 2;
    if(swprintf(working,MAX_PATH,L"%ls\\Programs\\DesktopFox",local)<0 || swprintf(target,MAX_PATH,L"%ls\\DesktopPet.exe",working)<0)return 2;
    if(fixture){
        WCHAR helper[MAX_PATH]={0};
        DWORD length=GetModuleFileNameW(NULL,helper,MAX_PATH);
        if(!length || length>=MAX_PATH-35)return 2;
        WCHAR *last=wcsrchr(helper,L'\\');if(!last)return 2;*last=0;
        WCHAR fixtures[MAX_PATH]={0};swprintf(fixtures,MAX_PATH,L"%ls\\ShortcutFixture",helper);CreateDirectoryW(fixtures,NULL);
        swprintf(folder,MAX_PATH,L"%ls\\%ls",fixtures,kind);
        CreateDirectoryW(folder,NULL);
    }else error=SHGetFolderPathW(NULL,folder_id,NULL,SHGFP_TYPE_CURRENT,folder);
    if(FAILED(error))goto done;
    if(swprintf(path,MAX_PATH,L"%ls\\Desktop Fox.lnk",folder)<0)return 2;
    error=CoInitializeEx(NULL,COINIT_APARTMENTTHREADED);if(FAILED(error))goto done;
    IShellLinkW *link=NULL;IPersistFile *file=NULL;
    error=CoCreateInstance(&CLSID_ShellLink,NULL,CLSCTX_INPROC_SERVER,&IID_IShellLinkW,(void**)&link);
    if(SUCCEEDED(error))error=IShellLinkW_QueryInterface(link,&IID_IPersistFile,(void**)&file);
    if(SUCCEEDED(error) && GetFileAttributesW(path)!=INVALID_FILE_ATTRIBUTES){
        HANDLE snapshot=CreateFileW(path,FILE_READ_ATTRIBUTES,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,NULL);
        BY_HANDLE_FILE_INFORMATION info={0};
        BOOL safe=snapshot!=INVALID_HANDLE_VALUE && GetFileInformationByHandle(snapshot,&info) && info.nNumberOfLinks==1 && !(info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY));
        if(snapshot!=INVALID_HANDLE_VALUE)CloseHandle(snapshot);
        WCHAR existing[MAX_PATH]={0},arguments[512]={0};
        HRESULT loaded=IPersistFile_Load(file,path,STGM_READ);
        if(SUCCEEDED(loaded))loaded=IShellLinkW_GetPath(link,existing,MAX_PATH,NULL,SLGP_RAWPATH);
        if(SUCCEEDED(loaded))loaded=IShellLinkW_GetArguments(link,arguments,512);
        conflict=!safe||FAILED(loaded)||_wcsicmp(existing,target)||arguments[0];enabled=!conflict;
    }
    if(SUCCEEDED(error) && conflict && action)error=HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS);
    if(SUCCEEDED(error) && action==1){
        if(!fixture && GetFileAttributesW(target)==INVALID_FILE_ATTRIBUTES)error=HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
        if(SUCCEEDED(error))error=IShellLinkW_SetPath(link,target);
        if(SUCCEEDED(error))error=IShellLinkW_SetArguments(link,L"");
        if(SUCCEEDED(error))error=IShellLinkW_SetWorkingDirectory(link,working);
        if(SUCCEEDED(error))error=IShellLinkW_SetDescription(link,L"Desktop Fox â€” local companion");
        if(SUCCEEDED(error))error=IShellLinkW_SetShowCmd(link,SW_SHOWNORMAL);
        if(SUCCEEDED(error))error=IPersistFile_Save(file,path,TRUE);
        if(SUCCEEDED(error))enabled=TRUE;
    }
    if(SUCCEEDED(error) && action==2 && enabled){if(DeleteFileW(path))enabled=FALSE;else error=HRESULT_FROM_WIN32(GetLastError());}
    if(file)IPersistFile_Release(file);
    if(link)IShellLinkW_Release(link);
    CoUninitialize();
done:
    printf("{\"available\":%s,\"enabled\":%s,\"conflict\":%s,\"error\":\"",SUCCEEDED(error)?"true":"false",enabled?"true":"false",conflict?"true":"false");
    if(FAILED(error))printf("Shortcut unavailable (0x%08lx); conflicting links are preserved.",(unsigned long)error);
    printf("\"}\n");return SUCCEEDED(error)?0:1;
}
