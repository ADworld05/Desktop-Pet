// Optional T15 compact-window backdrop. Existing fox_window bridge is untouched.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <wchar.h>
#include "vendor/gdextension_interface.h"
typedef struct { uint64_t storage; } Name;
typedef struct { int left,right,top,bottom; } Margins;
typedef HRESULT (WINAPI *SetAttr)(HWND,DWORD,LPCVOID,DWORD);
typedef HRESULT (WINAPI *GetAttr)(HWND,DWORD,PVOID,DWORD);
typedef HRESULT (WINAPI *Extend)(HWND,const Margins*);
static GDExtensionClassLibraryPtr library;
static Name class_name,parent_name,display_name,native_name,empty_name;
static uint64_t empty_string;
static GDExtensionInterfaceStringNameNewWithLatin1Chars name_new;
static GDExtensionPtrDestructor name_free,string_free;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceGlobalGetSingleton singleton;
static GDExtensionInterfaceObjectMethodBindPtrcall ptrcall;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionTypeFromVariantConstructorFunc to_int;
static GDExtensionVariantFromTypeConstructorFunc from_int;
static GDExtensionMethodBindPtr native_method;
static HMODULE dwm;
static SetAttr set_attr;
static GetAttr get_attr;
static Extend extend;
// Guarded compatibility path: exported User32 API, undocumented accent-policy
// enum. Only the already validated owned compact HWND; never global settings.
typedef struct { int state,flags; DWORD color; int animation; } Accent;
typedef struct { int attribute; PVOID data; SIZE_T bytes; } CompositionData;
typedef BOOL (WINAPI *Composition)(HWND,CompositionData*);
static Composition composition;
// Temporary mouse-only Raw Input registration for outside-button dismissal.
// No global hook, keyboard input, capture, event injection, or retained movement.
static HWND watched_window;
static WNDPROC previous_proc;
static RAWINPUTDEVICE previous_mouse;
static int had_previous_mouse,watching;
static LONG dismiss_pending;
static HWND compact_window(int64_t request,int allow_full) {
    // Godot window id in upper bits, frost amount0..100 in low byte.
    // No caller HWND; reject main, foreign thread/process and other app windows.
    if (request<256 || request>0xFFFFFF) return NULL;
    int64_t id=request>>8,handle_type=1,result=0;
    const void *args[]={&handle_type,&id};
    GDExtensionObjectPtr display=singleton(&display_name);
    if (!display || !native_method) return NULL;
    ptrcall(native_method,display,args,&result);
    HWND window=(HWND)(intptr_t)result;DWORD pid=0;
    DWORD thread=GetWindowThreadProcessId(window,&pid);
    WCHAR title[80]={0};GetWindowTextW(window,title,80);
    if (!IsWindow(window) || pid!=GetCurrentProcessId() || thread!=GetCurrentThreadId() ||
        GetAncestor(window,GA_ROOT)!=window ||
        (wcscmp(title,L"Desktop Pet — Compact Chat") &&
         (!(allow_full&1) || wcscmp(title,L"Desktop Pet — Chat")) &&
         (!(allow_full&2) || wcscmp(title,L"Desktop Pet — Quick Menu")))) return NULL;
    return window;
}
static int64_t configure(int64_t request) {
    HWND window=compact_window(request,3);
    if (!window || (request&255)>100) return 0;
    int64_t status=1;
    WCHAR title[80]={0};GetWindowTextW(window,title,80);
    if (!wcscmp(title,L"Desktop Pet — Compact Chat") || !wcscmp(title,L"Desktop Pet — Quick Menu")) {
    LONG_PTR style=GetWindowLongPtrW(window,GWL_EXSTYLE);
    SetWindowLongPtrW(window,GWL_EXSTYLE,(style|WS_EX_TOOLWINDOW)&~WS_EX_APPWINDOW);
    if ((GetWindowLongPtrW(window,GWL_EXSTYLE)&(WS_EX_TOOLWINDOW|WS_EX_APPWINDOW))==WS_EX_TOOLWINDOW) status|=32;
    RECT rect;GetWindowRect(window,&rect);
    HRGN region=CreateRoundRectRgn(0,0,rect.right-rect.left+1,rect.bottom-rect.top+1,36,36);
    if (region) { if (SetWindowRgn(window,region,TRUE)) status|=16;else DeleteObject(region); }
    } // Full chat keeps native taskbar/frame; only compact is a tool window.
    if (!set_attr || !get_attr || !extend) return status;
    int backdrop=(request&255)>0?3:1; // documented TRANSIENTWINDOW Acrylic / NONE
    int corners=2,light=0;Margins margins={backdrop==3?-1:0,backdrop==3?-1:0,backdrop==3?-1:0,backdrop==3?-1:0};
    set_attr(window,20,&light,sizeof(light)); // readable light glass presentation
    set_attr(window,33,&corners,sizeof(corners));
    if (SUCCEEDED(extend(window,&margins))) status|=8;
    if (SUCCEEDED(set_attr(window,38,&backdrop,sizeof(backdrop)))) status|=2;
    int actual=0;
    if (SUCCEEDED(get_attr(window,38,&actual,sizeof(actual))) && actual==backdrop) status|=4;
    // Prefer direct desktop blur for this transparent OpenGL popup. Windows can
    // decline or suppress it (power/accessibility/compositor policy).
    if (composition) {
        int quick=!wcscmp(title,L"Desktop Pet — Quick Menu");
        Accent accent={(request&255)>0?(quick?4:3):0,quick?2:0,quick?0x55fff4e8:0,0};
        CompositionData data={19,&accent,sizeof(accent)};
        if (composition(window,&data) && accent.state>0) status|=64;
    }
    return status; // API acceptance is not proof of visible desktop blur.
}
static int current_mouse(RAWINPUTDEVICE *found) {
    RAWINPUTDEVICE devices[64];UINT count=64;
    UINT total=GetRegisteredRawInputDevices(devices,&count,sizeof(devices[0]));
    if (total==(UINT)-1) return -1;
    for (UINT i=0;i<total;i++) if (devices[i].usUsagePage==1 && devices[i].usUsage==2) {*found=devices[i];return 1;}
    return 0;
}
static void stop_watch(void);
static int ensure_watch(void) {
    RAWINPUTDEVICE actual;int found=current_mouse(&actual);
    if (!watching || found<0) return 0;
    if (found==1 && actual.hwndTarget==watched_window && (actual.dwFlags&RIDEV_INPUTSINK)) return 1;
    // Godot updates its mouse registration on focus changes. Remember its
    // latest desired registration so closing the popup restores that state.
    had_previous_mouse=found;if (found) previous_mouse=actual;
    RAWINPUTDEVICE mouse={1,2,RIDEV_INPUTSINK,watched_window};
    return RegisterRawInputDevices(&mouse,1,sizeof(mouse))!=0;
}
static LRESULT CALLBACK raw_proc(HWND window,UINT message,WPARAM wparam,LPARAM lparam) {
    WNDPROC prior=previous_proc;
    if (message==WM_INPUT && watching) {
        RAWINPUT input;UINT bytes=sizeof(input);
        if (GetRawInputData((HRAWINPUT)lparam,RID_INPUT,&input,&bytes,sizeof(RAWINPUTHEADER))!=(UINT)-1 && input.header.dwType==RIM_TYPEMOUSE) {
            if (input.data.mouse.usButtonFlags&(RI_MOUSE_LEFT_BUTTON_DOWN|RI_MOUSE_RIGHT_BUTTON_DOWN|RI_MOUSE_MIDDLE_BUTTON_DOWN|RI_MOUSE_BUTTON_4_DOWN|RI_MOUSE_BUTTON_5_DOWN)) {
                POINT point;DWORD pid=0;
                if (IsWindowVisible(window) && GetCursorPos(&point)) {
                    HWND clicked=WindowFromPoint(point);GetWindowThreadProcessId(clicked,&pid);
                    // Owned dropdown/pet clicks stay in normal handlers.
                    if (pid!=GetCurrentProcessId()) dismiss_pending=1;
                }
            }
            return DefWindowProcW(window,message,wparam,lparam);
        }
    }
    if (message==WM_NCDESTROY) stop_watch();
    LRESULT result=CallWindowProcW(prior,window,message,wparam,lparam);
    if (watching && (message==WM_SETFOCUS || message==WM_KILLFOCUS)) ensure_watch();
    return result;
}
static void stop_watch(void) {
    if (watching) {
        RAWINPUTDEVICE actual;
        if (current_mouse(&actual)==1 && actual.hwndTarget==watched_window) {
            RAWINPUTDEVICE restore=had_previous_mouse?previous_mouse:(RAWINPUTDEVICE){1,2,RIDEV_REMOVE,NULL};
            RegisterRawInputDevices(&restore,1,sizeof(restore));
        }
        if (IsWindow(watched_window) && (WNDPROC)GetWindowLongPtrW(watched_window,GWLP_WNDPROC)==raw_proc) SetWindowLongPtrW(watched_window,GWLP_WNDPROC,(LONG_PTR)previous_proc);
    }
    watching=0;watched_window=NULL;previous_proc=NULL;dismiss_pending=0;
}
static int64_t observe(int64_t request) {
    HWND window=compact_window(request,2);
    if (!window || (request&255)>2) return 0;
    switch (request&255) {
        case 0:stop_watch();return 1;
        case 1: {
            stop_watch();int previous=current_mouse(&previous_mouse);
            if (previous<0) return 0;
            had_previous_mouse=previous;watched_window=window;
            SetLastError(0);previous_proc=(WNDPROC)SetWindowLongPtrW(window,GWLP_WNDPROC,(LONG_PTR)raw_proc);
            if (!previous_proc) {watched_window=NULL;return 0;}
            watching=1;RAWINPUTDEVICE mouse={1,2,RIDEV_INPUTSINK,window};
            if (!RegisterRawInputDevices(&mouse,1,sizeof(mouse))) {stop_watch();return 0;}
            return 1;
        }
        default: {
            int active=ensure_watch();
            int64_t result=(active?2:0)|dismiss_pending;dismiss_pending=0;return result;
        }
    }
}
static int64_t invoke(void *data,int64_t request) {return data?observe(request):configure(request);}
static void call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *params,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    (void)instance;int64_t request=0,answer=0;error->error=GDEXTENSION_CALL_OK;
    if (count!=1) {error->error=count<1?GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS:GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;error->expected=1;}
    else if (variant_type(params[0])!=GDEXTENSION_VARIANT_TYPE_INT) {error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;error->argument=0;error->expected=GDEXTENSION_VARIANT_TYPE_INT;}
    else {to_int(&request,(GDExtensionVariantPtr)params[0]);answer=invoke(data,request);}
    from_int(result,&answer);
}
static void ptr_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *params,GDExtensionTypePtr result) {
    (void)instance;*(int64_t*)result=invoke(data,*(const int64_t*)params[0]);
}
static void free_instance(void *data,GDExtensionClassInstancePtr instance) {(void)data;(void)instance;}
static void initialize(void *data,GDExtensionInitializationLevel level) {
    (void)data;if (level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    name_new(&class_name,"FoxGlassBridge",0);name_new(&parent_name,"Object",0);name_new(&display_name,"DisplayServer",0);name_new(&native_name,"window_get_native_handle",0);name_new(&empty_name,"",0);
    GDExtensionInterfaceClassdbGetMethodBind bind=(GDExtensionInterfaceClassdbGetMethodBind)((GDExtensionInterfaceGetProcAddress)data)("classdb_get_method_bind");
    native_method=bind(&display_name,&native_name,1096425680);
    GDExtensionClassCreationInfo6 info={0};info.is_abstract=1;info.is_exposed=1;info.free_instance_func=free_instance;
    register_class(library,&class_name,&parent_name,&info);
    Name method,arg;name_new(&arg,"request",0);
    GDExtensionPropertyInfo ret={0},argument={0};ret.type=argument.type=GDEXTENSION_VARIANT_TYPE_INT;ret.name=&empty_name;argument.name=&arg;ret.class_name=argument.class_name=&empty_name;ret.hint_string=argument.hint_string=&empty_string;
    GDExtensionClassMethodArgumentMetadata meta=GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
    GDExtensionClassMethodInfo m={0};m.name=&method;m.call_func=call;m.ptrcall_func=ptr_call;m.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_STATIC;m.has_return_value=1;m.return_value_info=&ret;m.return_value_metadata=meta;m.argument_count=1;m.arguments_info=&argument;m.arguments_metadata=&meta;
    name_new(&method,"configure",0);register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"observe",0);m.method_userdata=(void*)1;register_method(library,&class_name,&m);name_free(&method);name_free(&arg);
    // System DLL only; no downloadable libraries or arbitrary paths.
    composition=(Composition)GetProcAddress(GetModuleHandleW(L"user32.dll"),"SetWindowCompositionAttribute");
    dwm=LoadLibraryExW(L"dwmapi.dll",NULL,0x00000800);
    if (dwm) {set_attr=(SetAttr)GetProcAddress(dwm,"DwmSetWindowAttribute");get_attr=(GetAttr)GetProcAddress(dwm,"DwmGetWindowAttribute");extend=(Extend)GetProcAddress(dwm,"DwmExtendFrameIntoClientArea");}
}
static void deinitialize(void *data,GDExtensionInitializationLevel level) {
    (void)data;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;stop_watch();
    unregister_class(library,&class_name);name_free(&empty_name);name_free(&native_name);name_free(&display_name);name_free(&parent_name);name_free(&class_name);string_free(&empty_string);if(dwm)FreeLibrary(dwm);
}
__declspec(dllexport) GDExtensionBool fox_glass_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init) {
    library=lib;
#define LOAD(variable,type,symbol) variable=(type)get(symbol);if(!variable)return 0
    LOAD(name_new,GDExtensionInterfaceStringNameNewWithLatin1Chars,"string_name_new_with_latin1_chars");
    LOAD(register_class,GDExtensionInterfaceClassdbRegisterExtensionClass6,"classdb_register_extension_class6");LOAD(unregister_class,GDExtensionInterfaceClassdbUnregisterExtensionClass,"classdb_unregister_extension_class");LOAD(register_method,GDExtensionInterfaceClassdbRegisterExtensionClassMethod,"classdb_register_extension_class_method");LOAD(singleton,GDExtensionInterfaceGlobalGetSingleton,"global_get_singleton");LOAD(ptrcall,GDExtensionInterfaceObjectMethodBindPtrcall,"object_method_bind_ptrcall");LOAD(variant_type,GDExtensionInterfaceVariantGetType,"variant_get_type");
    GDExtensionInterfaceVariantGetPtrDestructor destructor;GDExtensionInterfaceGetVariantFromTypeConstructor from;GDExtensionInterfaceGetVariantToTypeConstructor to;GDExtensionInterfaceStringNewWithUtf8Chars string_new;
    LOAD(destructor,GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor");LOAD(from,GDExtensionInterfaceGetVariantFromTypeConstructor,"get_variant_from_type_constructor");LOAD(to,GDExtensionInterfaceGetVariantToTypeConstructor,"get_variant_to_type_constructor");LOAD(string_new,GDExtensionInterfaceStringNewWithUtf8Chars,"string_new_with_utf8_chars");
    name_free=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);string_free=destructor(GDEXTENSION_VARIANT_TYPE_STRING);from_int=from(GDEXTENSION_VARIANT_TYPE_INT);to_int=to(GDEXTENSION_VARIANT_TYPE_INT);string_new(&empty_string,"");
    init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;init->userdata=(void*)get;init->initialize=initialize;init->deinitialize=deinitialize;return 1;
}
