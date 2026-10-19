// T02: fixed, in-process control of Godot's MAIN window only. No caller HWND.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <sddl.h>
#include <wtsapi32.h>
#include "vendor/gdextension_interface.h"

// Sizes and method hash are from this project's pinned 4.7.2 float_64 API dump.
typedef struct { uint64_t storage; } GodotName;
static GDExtensionClassLibraryPtr library;
static GodotName class_name, parent_name, display_name, native_method, empty_name;
static uint64_t empty_string;
static GDExtensionInterfaceStringNameNewWithLatin1Chars name_new;
static GDExtensionPtrDestructor name_free, string_free;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceGlobalGetSingleton singleton;
static GDExtensionInterfaceClassdbGetMethodBind get_method;
static GDExtensionInterfaceObjectMethodBindPtrcall ptrcall;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionTypeFromVariantConstructorFunc to_bool;
static GDExtensionVariantFromTypeConstructorFunc from_int;
static GDExtensionMethodBindPtr native_handle_method;
static BOOL passthrough_active;
static LONG_PTR original_mouse_styles;
static BOOL drag_tracking;
// T13: fixed current-user handles and this process's own window messages only.
static HANDLE instance_mutex, recover_event;
static HWND lifecycle_window;
static WNDPROC previous_proc;
static UINT taskbar_created;
static int64_t lifecycle_events;
static BOOL session_registered;

static int64_t acquire_instance(GDExtensionBool validation) {
    if (instance_mutex) return 1;
    HANDLE token = NULL;
    BYTE user_buffer[1024]; DWORD required = 0;
    LPWSTR sid = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return -1;
    BOOL ok = GetTokenInformation(token, TokenUser, user_buffer, sizeof(user_buffer), &required);
    CloseHandle(token);
    if (!ok || !ConvertSidToStringSidW(((TOKEN_USER *)user_buffer)->User.Sid, &sid)) return -1;
    WCHAR mutex_name[256], event_name[256];
    const WCHAR *scope = validation ? L"Validation" : L"Pet";
    wsprintfW(mutex_name, L"Local\\DesktopFox.%s.%s.Mutex", sid, scope);
    wsprintfW(event_name, L"Local\\DesktopFox.%s.%s.Recover", sid, scope);
    LocalFree(sid);
    // Windows supplies the current token's default DACL (including its logon
    // restrictions). Request only synchronization, not MUTEX_ALL_ACCESS.
    HANDLE mutex = CreateMutexExW(NULL, mutex_name, 0, SYNCHRONIZE);
    DWORD error = GetLastError();
    if (!mutex) return -(int64_t)(5000 + error);
    if (error == ERROR_ALREADY_EXISTS) {
        HANDLE event = OpenEventW(EVENT_MODIFY_STATE, FALSE, event_name);
        if (event) { SetEvent(event); CloseHandle(event); }
        else { CloseHandle(mutex); return -(int64_t)(6000 + GetLastError()); }
        CloseHandle(mutex); return 0;
    }
    recover_event = CreateEventExW(NULL, event_name, 0, EVENT_MODIFY_STATE | SYNCHRONIZE);
    if (!recover_event) { CloseHandle(mutex); return -1; }
    instance_mutex = mutex; return 1;
}

static LRESULT CALLBACK lifecycle_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == taskbar_created) lifecycle_events |= 32;
    if (message == WM_POWERBROADCAST) {
        if (wparam == PBT_APMSUSPEND) lifecycle_events |= 2;
        if (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND) lifecycle_events |= 4;
    }
    if (message == WM_WTSSESSION_CHANGE) {
        if (wparam == WTS_SESSION_LOCK) lifecycle_events |= 8;
        if (wparam == WTS_SESSION_UNLOCK) lifecycle_events |= 16;
    }
    return CallWindowProcW(previous_proc, window, message, wparam, lparam);
}

static HWND main_window(void) {
    GDExtensionObjectPtr display = singleton(&display_name);
    if (!display || !native_handle_method) return NULL;
    int64_t handle_type = 1, window_id = 0, result = 0;
    const void *params[] = { &handle_type, &window_id };
    ptrcall(native_handle_method, display, params, &result);
    HWND window = (HWND)(intptr_t)result;
    DWORD owner = 0;
    DWORD thread = GetWindowThreadProcessId(window, &owner);
    if (!IsWindow(window) || owner != GetCurrentProcessId() ||
            thread != GetCurrentThreadId() || GetAncestor(window, GA_ROOT) != window)
        return NULL;
    return window;
}

// Bitmask: valid=64, appwindow=1, toolwindow=2, noactivate=4,
// visible=8, topmost=16, foreground=32. -1 means no valid main window.
static int64_t window_state(void) {
    HWND window = main_window();
    if (!window) return -1;
    LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    return 64 | ((style & WS_EX_APPWINDOW) ? 1 : 0) |
        ((style & WS_EX_TOOLWINDOW) ? 2 : 0) |
        ((style & WS_EX_NOACTIVATE) ? 4 : 0) |
        (IsWindowVisible(window) ? 8 : 0) |
        ((style & WS_EX_TOPMOST) ? 16 : 0) |
        ((GetForegroundWindow() == window) ? 32 : 0) |
        ((style & WS_EX_LAYERED) ? 128 : 0) |
        ((style & WS_EX_TRANSPARENT) ? 256 : 0) |
        (IsIconic(window) ? 512 : 0);
}

static int64_t configure_passthrough(GDExtensionBool enabled) {
    HWND window = main_window();
    if (!window) return 0;
    LONG_PTR before = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if (!(before & WS_EX_NOACTIVATE)) return 0;
    const LONG_PTR mask = WS_EX_LAYERED | WS_EX_TRANSPARENT;
    if (!enabled && !passthrough_active) return 1;
    LONG_PTR original = passthrough_active ? original_mouse_styles : (before & mask);
    LONG_PTR after = enabled ? (before | mask) : ((before & ~mask) | original);
    SetLastError(0);
    LONG_PTR previous = SetWindowLongPtrW(window, GWL_EXSTYLE, after);
    if (!previous && GetLastError()) return 0;
    // Full opacity preserves the DWM/OpenGL content; layered+transparent makes
    // hit testing pass to OTHER processes instead of only this UI thread.
    if (enabled && !SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA)) {
        SetWindowLongPtrW(window, GWL_EXSTYLE, before);
        return 0;
    }
    if (!SetWindowPos(window, NULL, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)) {
        SetWindowLongPtrW(window, GWL_EXSTYLE, before);
        return 0;
    }
    original_mouse_styles = original;
    passthrough_active = enabled != 0;
    return (GetWindowLongPtrW(window, GWL_EXSTYLE) & mask) == (after & mask);
}

static int64_t configure_taskbar(GDExtensionBool enabled) {
    HWND window = main_window();
    if (!window) return 0;
    LONG_PTR old_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    // Refuse to turn a focusable editor or other ordinary main window into an overlay.
    if (!(old_style & WS_EX_NOACTIVATE)) return 0;
    LONG_PTR new_style = old_style & ~(WS_EX_APPWINDOW | WS_EX_TOOLWINDOW);
    new_style |= enabled ? WS_EX_APPWINDOW : WS_EX_TOOLWINDOW;
    if (new_style == old_style) return 1;
    BOOL visible = IsWindowVisible(window);
    // Shell taskbar membership is refreshed by hiding before changing styles.
    if (visible) ShowWindow(window, SW_HIDE);
    SetLastError(0);
    LONG_PTR previous = SetWindowLongPtrW(window, GWL_EXSTYLE, new_style);
    DWORD error = GetLastError();
    BOOL success = previous != 0 || error == 0;
    if (success) success = SetWindowPos(window, NULL, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    if (!success) SetWindowLongPtrW(window, GWL_EXSTYLE, old_style);
    if (visible) ShowWindow(window, SW_SHOWNOACTIVATE);
    LONG_PTR actual = GetWindowLongPtrW(window, GWL_EXSTYLE);
    const LONG_PTR mask = WS_EX_APPWINDOW | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    return success && ((actual & mask) == (new_style & mask));
}

static int64_t window_dpi(void) {
    HWND window = main_window();
    if (!window) return 0;
    typedef UINT (WINAPI *DpiFunction)(HWND);
    DpiFunction dpi = (DpiFunction)GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow");
    return dpi ? dpi(window) : 0;
}

// Scoped fallback for a release outside the moving silhouette. Armed only by
// the overlay's own left press; no keyboard polling or global input hook.
static int64_t configure_drag_tracking(GDExtensionBool enabled) {
    drag_tracking = FALSE;
    if (!enabled) return 1;
    HWND window = main_window();
    if (!window || !IsWindowVisible(window) || passthrough_active ||
            !(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_NOACTIVATE)) return 0;
    int primary = GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
    if (!(GetAsyncKeyState(primary) & 0x8000)) return 0;
    drag_tracking = TRUE;
    return 1;
}
static int64_t drag_button_state(void) {
    if (!drag_tracking) return -1; // No mouse query while idle.
    HWND window = main_window();
    if (!window || !IsWindowVisible(window) || passthrough_active) {
        drag_tracking = FALSE;
        return 0;
    }
    int primary = GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
    int64_t down = (GetAsyncKeyState(primary) & 0x8000) != 0;
    if (!down) drag_tracking = FALSE;
    return down;
}
// T11 read-only geometry predicate on the overlay's monitor. No foreign title,
// content, input, HWND or PID is returned; no caller-supplied target is accepted.
static int64_t foreground_fullscreen(void) {
    HWND own = main_window(), foreground = GetForegroundWindow();
    if (!own) return -1;
    if (!foreground || foreground == GetShellWindow() || foreground == GetDesktopWindow() ||
            !IsWindowVisible(foreground) || IsIconic(foreground)) return 0;
    DWORD owner = 0;
    if (!GetWindowThreadProcessId(foreground, &owner)) return -1;
    if (owner == GetCurrentProcessId()) return 0;
    HMONITOR monitor = MonitorFromWindow(own, MONITOR_DEFAULTTONEAREST);
    if (MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST) != monitor) return 0;
    MONITORINFO info = {0}; info.cbSize = sizeof(info);
    RECT rect;
    if (!GetMonitorInfoW(monitor, &info) || !GetClientRect(foreground, &rect)) return -1;
    POINT a = {rect.left, rect.top}, b = {rect.right, rect.bottom};
    if (!ClientToScreen(foreground, &a) || !ClientToScreen(foreground, &b)) return -1;
    // Client area must cover the full monitor, including taskbar space. Ordinary
    // maximized windows cover the work area and therefore do not qualify.
    return a.x <= info.rcMonitor.left + 2 && a.y <= info.rcMonitor.top + 2 &&
        b.x >= info.rcMonitor.right - 2 && b.y >= info.rcMonitor.bottom - 2;
}
static int64_t watch_lifecycle(void) {
    HWND window = main_window();
    if (!window || !(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_NOACTIVATE)) return 0;
    if (lifecycle_window) return lifecycle_window == window;
    taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
    if (!taskbar_created) return 0;
    SetLastError(0);
    previous_proc = (WNDPROC)SetWindowLongPtrW(window, GWLP_WNDPROC, (LONG_PTR)lifecycle_proc);
    if (!previous_proc) return 0;
    lifecycle_window = window;
    session_registered = WTSRegisterSessionNotification(window, NOTIFY_FOR_THIS_SESSION);
    return session_registered ? 1 : 2; // Power/tray work, session unavailable.
}
static int64_t poll_lifecycle(void) {
    int64_t answer = lifecycle_events; lifecycle_events = 0;
    if (recover_event && WaitForSingleObject(recover_event, 0) == WAIT_OBJECT_0) answer |= 1;
    return answer;
}
static int64_t release_instance(void) {
    if (lifecycle_window && IsWindow(lifecycle_window)) {
        if (session_registered) WTSUnRegisterSessionNotification(lifecycle_window);
        if ((WNDPROC)GetWindowLongPtrW(lifecycle_window, GWLP_WNDPROC) == lifecycle_proc)
            SetWindowLongPtrW(lifecycle_window, GWLP_WNDPROC, (LONG_PTR)previous_proc);
    }
    lifecycle_window = NULL; previous_proc = NULL; session_registered = FALSE;
    lifecycle_events = 0;
    if (recover_event) CloseHandle(recover_event);
    if (instance_mutex) CloseHandle(instance_mutex);
    recover_event = instance_mutex = NULL;
    return 1;
}
// T20: read-only AC state; charging is not the same as plugged in. Unknown
// status stays unknown, including machines without a usable power report.
static int64_t ac_power_state(void) {
    SYSTEM_POWER_STATUS power = {0};
    if (!GetSystemPowerStatus(&power) || power.ACLineStatus > 1) return -1;
    return power.ACLineStatus;
}
enum { SET_TASKBAR, GET_STATE, GET_DPI, SET_VISIBLE, SET_PASSTHROUGH, SET_DRAG_TRACKING, GET_DRAG_BUTTON, GET_FULLSCREEN, ACQUIRE_INSTANCE, WATCH_LIFECYCLE, POLL_LIFECYCLE, RELEASE_INSTANCE, GET_AC_POWER };
static int takes_argument(int method) { return method == SET_TASKBAR || method == SET_VISIBLE || method == SET_PASSTHROUGH || method == SET_DRAG_TRACKING || method == ACQUIRE_INSTANCE; }
static int64_t invoke(int method, GDExtensionBool enabled) {
	if (method == SET_TASKBAR) return configure_taskbar(enabled);
	if (method == GET_STATE) return window_state();
	if (method == SET_PASSTHROUGH) return configure_passthrough(enabled);
	if (method == SET_DRAG_TRACKING) return configure_drag_tracking(enabled);
	if (method == GET_DRAG_BUTTON) return drag_button_state();
	if (method == GET_FULLSCREEN) return foreground_fullscreen();
	if (method == ACQUIRE_INSTANCE) return acquire_instance(enabled);
	if (method == WATCH_LIFECYCLE) return watch_lifecycle();
	if (method == POLL_LIFECYCLE) return poll_lifecycle();
	if (method == RELEASE_INSTANCE) return release_instance();
	if (method == GET_AC_POWER) return ac_power_state();
	if (method == SET_VISIBLE) {
		HWND window = main_window();
		if (!window || !(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_NOACTIVATE)) return 0;
		ShowWindow(window, enabled ? SW_SHOWNOACTIVATE : SW_HIDE);
		return (IsWindowVisible(window) != 0) == (enabled != 0);
	}
	return window_dpi();
}
static void method_call(void *data, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *params, GDExtensionInt count,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    (void)instance;
    int method = (int)(intptr_t)data;
    int expected = takes_argument(method);
    GDExtensionBool enabled = 0;
    int64_t answer = 0;
    error->error = GDEXTENSION_CALL_OK;
    if (count != expected) {
        error->error = count < expected ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = expected;
    } else if (expected && variant_type(params[0]) != GDEXTENSION_VARIANT_TYPE_BOOL) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->argument = 0;
        error->expected = GDEXTENSION_VARIANT_TYPE_BOOL;
    } else {
        if (expected) to_bool(&enabled, (GDExtensionVariantPtr)params[0]);
        answer = invoke(method, enabled);
    }
    from_int(result, &answer);
}
static void method_ptrcall(void *data, GDExtensionClassInstancePtr instance,
        const GDExtensionConstTypePtr *params, GDExtensionTypePtr result) {
    (void)instance;
    int method = (int)(intptr_t)data;
    *(int64_t *)result = invoke(method, takes_argument(method) ? *(const GDExtensionBool *)params[0] : 0);
}
static void free_instance(void *data, GDExtensionClassInstancePtr instance) {
    (void)data; (void)instance; // Abstract static-only class; no instances allocated.
}
static void bind_method(const char *name, int id) {
    GodotName method_name, argument_name;
    name_new(&method_name, name, 0);
    name_new(&argument_name, "enabled", 0);
    GDExtensionPropertyInfo return_info = {0}, argument_info = {0};
    return_info.type = GDEXTENSION_VARIANT_TYPE_INT;
    return_info.name = &empty_name; return_info.class_name = &empty_name;
    return_info.hint_string = &empty_string;
    argument_info.type = GDEXTENSION_VARIANT_TYPE_BOOL;
    argument_info.name = &argument_name; argument_info.class_name = &empty_name;
    argument_info.hint_string = &empty_string;
    GDExtensionClassMethodArgumentMetadata metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo info = {0};
    info.name = &method_name; info.method_userdata = (void *)(intptr_t)id;
    info.call_func = method_call; info.ptrcall_func = method_ptrcall;
    info.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC;
    info.has_return_value = 1; info.return_value_info = &return_info;
    info.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
    info.argument_count = takes_argument(id);
    info.arguments_info = &argument_info; info.arguments_metadata = &metadata;
    register_method(library, &class_name, &info);
    name_free(&argument_name); name_free(&method_name);
}
static void initialize(void *data, GDExtensionInitializationLevel level) {
    (void)data;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    name_new(&class_name, "FoxWindowBridge", 0);
    name_new(&parent_name, "Object", 0);
    name_new(&display_name, "DisplayServer", 0);
    name_new(&native_method, "window_get_native_handle", 0);
    name_new(&empty_name, "", 0);
    native_handle_method = get_method(&display_name, &native_method, 1096425680);
    GDExtensionClassCreationInfo6 info = {0};
    info.is_abstract = 1; info.is_exposed = 1; info.free_instance_func = free_instance;
    register_class(library, &class_name, &parent_name, &info);
    bind_method("set_taskbar_visible", SET_TASKBAR);
    bind_method("get_window_state", GET_STATE);
    bind_method("get_window_dpi", GET_DPI);
    bind_method("set_overlay_visible", SET_VISIBLE);
    bind_method("set_click_through", SET_PASSTHROUGH);
    bind_method("set_drag_tracking", SET_DRAG_TRACKING);
    bind_method("get_drag_button_state", GET_DRAG_BUTTON);
    bind_method("get_foreground_fullscreen", GET_FULLSCREEN);
    bind_method("acquire_instance", ACQUIRE_INSTANCE);
    bind_method("watch_lifecycle", WATCH_LIFECYCLE);
    bind_method("poll_lifecycle", POLL_LIFECYCLE);
    bind_method("release_instance", RELEASE_INSTANCE);
    bind_method("get_ac_power_state", GET_AC_POWER);
}
static void deinitialize(void *data, GDExtensionInitializationLevel level) {
    (void)data;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    release_instance();
    unregister_class(library, &class_name);
    name_free(&empty_name); name_free(&native_method); name_free(&display_name);
    name_free(&parent_name); name_free(&class_name); string_free(&empty_string);
}
__declspec(dllexport) GDExtensionBool fox_window_init(
        GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr lib,
        GDExtensionInitialization *init) {
    library = lib;
#define LOAD(variable, type, symbol) variable = (type)get(symbol); if (!variable) return 0
    LOAD(name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
    LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
    LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
    LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD(singleton, GDExtensionInterfaceGlobalGetSingleton, "global_get_singleton");
    LOAD(get_method, GDExtensionInterfaceClassdbGetMethodBind, "classdb_get_method_bind");
    LOAD(ptrcall, GDExtensionInterfaceObjectMethodBindPtrcall, "object_method_bind_ptrcall");
    LOAD(variant_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
    GDExtensionInterfaceVariantGetPtrDestructor destructor;
    GDExtensionInterfaceGetVariantFromTypeConstructor from;
    GDExtensionInterfaceGetVariantToTypeConstructor to;
    GDExtensionInterfaceStringNewWithUtf8Chars string_new;
    LOAD(destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD(from, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD(to, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
    LOAD(string_new, GDExtensionInterfaceStringNewWithUtf8Chars, "string_new_with_utf8_chars");
    name_free = destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    string_free = destructor(GDEXTENSION_VARIANT_TYPE_STRING);
    from_int = from(GDEXTENSION_VARIANT_TYPE_INT);
    to_bool = to(GDEXTENSION_VARIANT_TYPE_BOOL);
    string_new(&empty_string, "");
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = NULL; init->initialize = initialize; init->deinitialize = deinitialize;
    return 1;
}
