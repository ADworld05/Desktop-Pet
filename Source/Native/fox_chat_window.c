// Owned full-chat metadata only; no hook, capture, input injection or arbitrary HWND.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <wchar.h>
#include "vendor/gdextension_interface.h"
typedef struct { uint64_t storage; } Name;
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

static int64_t window_state(int64_t id) {
    if (id<1 || id>65535) return 0;
    int64_t handle_type=1,result=0;const void *args[]={&handle_type,&id};
    GDExtensionObjectPtr display=singleton(&display_name);
    if (!display || !native_method) return 0;
    ptrcall(native_method,display,args,&result);
    HWND window=(HWND)(intptr_t)result;DWORD pid=0;
    DWORD thread=GetWindowThreadProcessId(window,&pid);WCHAR title[80]={0};GetWindowTextW(window,title,80);
    if (!IsWindow(window) || pid!=GetCurrentProcessId() || thread!=GetCurrentThreadId() || GetAncestor(window,GA_ROOT)!=window || wcscmp(title,L"Desktop Pet \x2014 Chat") || !IsWindowVisible(window)) return 0;
    LONG_PTR style=GetWindowLongPtrW(window,GWL_STYLE);int64_t state=1;
    int primary=GetSystemMetrics(SM_SWAPBUTTON)?VK_RBUTTON:VK_LBUTTON;
    if (GetAsyncKeyState(primary)&0x8000) state|=2;
    GUITHREADINFO info={0};info.cbSize=sizeof(info);
    if (GetGUIThreadInfo(thread,&info) && (info.flags&GUI_INMOVESIZE) && info.hwndMoveSize==window) state|=4;
    if (IsIconic(window)) state|=8;
    if ((style&WS_CAPTION)==WS_CAPTION) state|=16;
    if (style&WS_MINIMIZEBOX) state|=32;
    if (style&WS_THICKFRAME) state|=64;
    if (style&WS_SYSMENU) state|=128;
    if (IsZoomed(window)) state|=256;
    return state;
}
static int64_t invoke(void *data,int64_t request) {(void)data;return window_state(request);}
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
    name_new(&class_name,"FoxChatWindowBridge",0);name_new(&parent_name,"Object",0);name_new(&display_name,"DisplayServer",0);name_new(&native_name,"window_get_native_handle",0);name_new(&empty_name,"",0);
    GDExtensionInterfaceClassdbGetMethodBind bind=(GDExtensionInterfaceClassdbGetMethodBind)((GDExtensionInterfaceGetProcAddress)data)("classdb_get_method_bind");
    native_method=bind(&display_name,&native_name,1096425680);
    GDExtensionClassCreationInfo6 info={0};info.is_abstract=1;info.is_exposed=1;info.free_instance_func=free_instance;
    register_class(library,&class_name,&parent_name,&info);
    Name method,arg;name_new(&arg,"request",0);
    GDExtensionPropertyInfo ret={0},argument={0};ret.type=argument.type=GDEXTENSION_VARIANT_TYPE_INT;ret.name=&empty_name;argument.name=&arg;ret.class_name=argument.class_name=&empty_name;ret.hint_string=argument.hint_string=&empty_string;
    GDExtensionClassMethodArgumentMetadata meta=GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
    GDExtensionClassMethodInfo m={0};m.name=&method;m.call_func=call;m.ptrcall_func=ptr_call;m.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_STATIC;m.has_return_value=1;m.return_value_info=&ret;m.return_value_metadata=meta;m.argument_count=1;m.arguments_info=&argument;m.arguments_metadata=&meta;
    name_new(&method,"window_state",0);register_method(library,&class_name,&m);name_free(&method);name_free(&arg);
}
static void deinitialize(void *data,GDExtensionInitializationLevel level) {
    (void)data;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    unregister_class(library,&class_name);name_free(&empty_name);name_free(&native_name);name_free(&display_name);name_free(&parent_name);name_free(&class_name);string_free(&empty_string);
}
__declspec(dllexport) GDExtensionBool fox_chat_window_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init) {
    library=lib;
#define LOAD(variable,type,symbol) variable=(type)get(symbol);if(!variable)return 0
    LOAD(name_new,GDExtensionInterfaceStringNameNewWithLatin1Chars,"string_name_new_with_latin1_chars");
    LOAD(register_class,GDExtensionInterfaceClassdbRegisterExtensionClass6,"classdb_register_extension_class6");LOAD(unregister_class,GDExtensionInterfaceClassdbUnregisterExtensionClass,"classdb_unregister_extension_class");LOAD(register_method,GDExtensionInterfaceClassdbRegisterExtensionClassMethod,"classdb_register_extension_class_method");LOAD(singleton,GDExtensionInterfaceGlobalGetSingleton,"global_get_singleton");LOAD(ptrcall,GDExtensionInterfaceObjectMethodBindPtrcall,"object_method_bind_ptrcall");LOAD(variant_type,GDExtensionInterfaceVariantGetType,"variant_get_type");
    GDExtensionInterfaceVariantGetPtrDestructor destructor;GDExtensionInterfaceGetVariantFromTypeConstructor from;GDExtensionInterfaceGetVariantToTypeConstructor to;GDExtensionInterfaceStringNewWithUtf8Chars string_new;
    LOAD(destructor,GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor");LOAD(from,GDExtensionInterfaceGetVariantFromTypeConstructor,"get_variant_from_type_constructor");LOAD(to,GDExtensionInterfaceGetVariantToTypeConstructor,"get_variant_to_type_constructor");LOAD(string_new,GDExtensionInterfaceStringNewWithUtf8Chars,"string_new_with_utf8_chars");
    name_free=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);string_free=destructor(GDEXTENSION_VARIANT_TYPE_STRING);from_int=from(GDEXTENSION_VARIANT_TYPE_INT);to_int=to(GDEXTENSION_VARIANT_TYPE_INT);string_new(&empty_string,"");
    init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;init->userdata=(void*)get;init->initialize=initialize;init->deinitialize=deinitialize;return 1;
}
