#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
/* Fixed sibling engine only. Preserve the user's real AppData and Ollama env. */
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR supplied,int show) {
    (void)instance;(void)previous;(void)show;
    if (*supplied) return 2;
    WCHAR folder[32768],engine[32768],pack[32768],command[32768];
    DWORD length=GetModuleFileNameW(NULL,folder,32768);
    if (!length || length>=32000) return 1;
    WCHAR *slash=wcsrchr(folder,L'\\');if(!slash)return 1;*slash=0;
    if(swprintf(engine,32768,L"%ls\\DesktopFox.exe",folder)<0 || swprintf(pack,32768,L"%ls\\DesktopFox.pck",folder)<0)return 1;
    if(GetFileAttributesW(engine)==INVALID_FILE_ATTRIBUTES || GetFileAttributesW(pack)==INVALID_FILE_ATTRIBUTES) {
        MessageBoxW(NULL,L"Keep DesktopPet.exe with DesktopFox.exe, DesktopFox.pck and the supplied DLLs.",L"Desktop Pet",MB_OK|MB_ICONERROR);return 1;
    }
    const WCHAR *required[]={L"fox_window.dll",L"fox_chat_window.dll",L"fox_glass.dll",L"fox_path_boundary.dll",L"DesktopFoxStartup.exe"};
    for(int i=0;i<5;i++) {
        WCHAR dependency[32768];
        if(swprintf(dependency,32768,L"%ls\\%ls",folder,required[i])<0 || GetFileAttributesW(dependency)==INVALID_FILE_ATTRIBUTES) {
            MessageBoxW(NULL,L"Desktop Pet runtime files are missing. Extract the complete application folder again. Your saved data is separate and will be kept.",L"Desktop Pet",MB_OK|MB_ICONERROR);return 1;
        }
    }
    if(swprintf(command,32768,L"\"%ls\"",engine)<0)return 1;
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);PROCESS_INFORMATION process={0};
    if(!CreateProcessW(engine,command,NULL,NULL,FALSE,0,NULL,folder,&startup,&process)) {
        MessageBoxW(NULL,L"Desktop Pet could not start. Keep all extracted runtime files together and check access to your Windows user-data folder.",L"Desktop Pet",MB_OK|MB_ICONERROR);return 1;
    }
    CloseHandle(process.hThread);CloseHandle(process.hProcess);return 0;
}
