#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <shlobj.h>
#include <objbase.h>
#include <stdio.h>
#include <wchar.h>
// Fixed current-user shortcut only. No script execution, registry or elevation.
int wmain(int count, WCHAR **args) {
    int action = 0; BOOL fixture = FALSE, enabled = FALSE, conflict = FALSE;
    if (count < 2 || count > 3) return 2;
    if (!wcscmp(args[1], L"Enable")) action = 1;
    else if (!wcscmp(args[1], L"Disable")) action = 2;
    else if (wcscmp(args[1], L"Status")) return 2;
    if (count == 3) { if (wcscmp(args[2], L"Fixture")) return 2; fixture = TRUE; }
    WCHAR path[MAX_PATH]; HRESULT error = S_OK;
    WCHAR launcher[MAX_PATH], folder[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, folder, MAX_PATH);
    if (!length || length >= MAX_PATH - 20) return 2;
    WCHAR *last = wcsrchr(folder, L'\\'); if (!last) return 2; *last = 0;
    swprintf(launcher, MAX_PATH, L"%ls\\DesktopPet.exe", folder);
    if (fixture) {
        /* A test fixture is always relative to this helper, never real Startup. */
        if (swprintf(path, MAX_PATH, L"%ls\\StartupFixture", folder) < 0) return 2;
        if (action == 1) CreateDirectoryW(path, NULL);
    } else {
        error = SHGetFolderPathW(NULL, CSIDL_STARTUP, NULL, SHGFP_TYPE_CURRENT, path);
    }
    if (FAILED(error)) goto report;
    wcscat(path, L"\\Desktop Fox.lnk");
    error = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(error)) goto report;
    IShellLinkW *link = NULL; IPersistFile *file = NULL;
    error = CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, (void **)&link);
    if (SUCCEEDED(error)) error = IShellLinkW_QueryInterface(link, &IID_IPersistFile, (void **)&file);
    if (SUCCEEDED(error) && GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES) {
        WCHAR target[MAX_PATH] = {0}, arguments[512] = {0};
        HRESULT loaded = IPersistFile_Load(file, path, STGM_READ);
        if (SUCCEEDED(loaded)) loaded = IShellLinkW_GetPath(link, target, MAX_PATH, NULL, SLGP_RAWPATH);
        if (SUCCEEDED(loaded)) loaded = IShellLinkW_GetArguments(link, arguments, 512);
        conflict = FAILED(loaded) || _wcsicmp(target, launcher) || arguments[0];
        enabled = !conflict;
    }
    if (SUCCEEDED(error) && conflict && action) error = HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS);
    if (SUCCEEDED(error) && action == 1) {
        if (GetFileAttributesW(launcher) == INVALID_FILE_ATTRIBUTES) error = HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
        if (SUCCEEDED(error)) error = IShellLinkW_SetPath(link, launcher);
        if (SUCCEEDED(error)) error = IShellLinkW_SetArguments(link, L"");
        if (SUCCEEDED(error)) error = IShellLinkW_SetWorkingDirectory(link, folder);
        if (SUCCEEDED(error)) error = IShellLinkW_SetDescription(link, L"Start Desktop Pet locally at sign-in. Disable in Desktop Pet settings.");
        if (SUCCEEDED(error)) error = IShellLinkW_SetShowCmd(link, SW_SHOWNOACTIVATE);
        if (SUCCEEDED(error)) error = IPersistFile_Save(file, path, TRUE);
        if (SUCCEEDED(error)) enabled = TRUE;
    }
    if (SUCCEEDED(error) && action == 2 && enabled) {
        if (DeleteFileW(path)) enabled = FALSE;
        else error = HRESULT_FROM_WIN32(GetLastError());
    }
    if (file) IPersistFile_Release(file);
    if (link) IShellLinkW_Release(link);
    CoUninitialize();
report:
    printf("{\"available\":%s,\"enabled\":%s,\"conflict\":%s,\"error\":\"",
        SUCCEEDED(error) ? "true" : "false", enabled ? "true" : "false", conflict ? "true" : "false");
    if (FAILED(error)) printf("Windows startup helper failed (0x%08lx). A conflicting shortcut is preserved.", (unsigned long)error);
    printf("\"}\n");
    return SUCCEEDED(error) ? 0 : 1;
}
