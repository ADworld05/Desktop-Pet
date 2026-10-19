// Fixed metadata/system info, bounded read/search and reviewed launch adapters. No shell/write/elevation retry.
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0602
#define NTDDI_VERSION 0x06020000
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <wchar.h>
#include <shlwapi.h>
#include <wintrust.h>
#include <softpub.h>
#include <mscat.h>
#include "vendor/gdextension_interface.h"

typedef struct { uint64_t storage; } Name;
static GDExtensionClassLibraryPtr library;
static Name class_name, parent_name, empty_name;
static uint64_t empty_string;
static volatile LONG search_generation=0;
static GDExtensionInterfaceStringNameNewWithLatin1Chars name_new;
static GDExtensionInterfaceStringNewWithUtf8Chars string_new;
static GDExtensionInterfaceStringToUtf8Chars string_utf8;
static GDExtensionPtrDestructor name_free, string_free;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionTypeFromVariantConstructorFunc to_string;
static GDExtensionVariantFromTypeConstructorFunc from_string;
static void deny(char *out, const char *reason);

static int process_safety(void) {
    HANDLE token=NULL; TOKEN_ELEVATION elevation={0}; DWORD length=0;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token))return -1;
    BOOL ok=GetTokenInformation(token,TokenElevation,&elevation,sizeof(elevation),&length);
    CloseHandle(token);
    if(!ok || length!=sizeof(elevation))return -1;
    if(elevation.TokenIsElevated)return 1;
    // This boundary accepts no impersonated execution context.
    if(OpenThreadToken(GetCurrentThread(),TOKEN_QUERY,TRUE,&token)) {CloseHandle(token);return -1;}
    return GetLastError()==ERROR_NO_TOKEN?0:-1;
}
static void safety_json(char *out) {
    int state=process_safety();
    snprintf(out,8192,"{\"ok\":%s,\"elevated\":%s,\"reason\":\"%s\"}",state==0?"true":"false",state==1?"true":"false",state==0?"none":state==1?"elevated_process":"safety_unavailable");
}
static void system_json(char *out) {
    if(process_safety()!=0) {deny(out,"non_elevated_context_required");return;}
    SYSTEM_INFO cpu={0}; MEMORYSTATUSEX memory={0}; SYSTEM_POWER_STATUS power={0};
    GetNativeSystemInfo(&cpu);memory.dwLength=sizeof(memory);
    BOOL mem_ok=GlobalMemoryStatusEx(&memory),power_ok=GetSystemPowerStatus(&power);
    char ram[32]="null",battery[8]="null",charging[8]="null";
    if(mem_ok)snprintf(ram,sizeof(ram),"%llu",(unsigned long long)memory.ullTotalPhys);
    if(power_ok && power.BatteryFlag!=255 && !(power.BatteryFlag&128)) {
        if(power.BatteryLifePercent<=100)snprintf(battery,sizeof(battery),"%u",power.BatteryLifePercent);
        snprintf(charging,sizeof(charging),"%s",power.BatteryFlag&8?"true":"false");
    }
    snprintf(out,8192,"{\"ok\":true,\"values\":{\"os_version\":null,\"cpu_count\":%lu,\"memory_total\":%s,\"battery_percent\":%s,\"battery_charging\":%s,\"uptime_seconds\":%llu}}",(unsigned long)cpu.dwNumberOfProcessors,ram,battery,charging,(unsigned long long)(GetTickCount64()/1000));
}

static void deny(char *out, const char *reason) {
    snprintf(out, 8192, "{\"ok\":false,\"reason\":\"%s\"}", reason);
}
static int reserved(const WCHAR *part) {
    WCHAR base[16]={0}; size_t i=0;
    while(part[i] && part[i]!=L'.' && i<15) {base[i]=part[i]; i++;}
    if (!_wcsicmp(base,L"CON") || !_wcsicmp(base,L"PRN") || !_wcsicmp(base,L"AUX") || !_wcsicmp(base,L"NUL") || !_wcsicmp(base,L"CONIN$") || !_wcsicmp(base,L"CONOUT$")) return 1;
    return i==4 && (!_wcsnicmp(base,L"COM",3) || !_wcsnicmp(base,L"LPT",3)) && base[3]>=L'1' && base[3]<=L'9';
}
static HANDLE metadata(const WCHAR *path) {
    return CreateFileW(path,0,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_NO_RECALL,NULL);
}
static int json_escape(const char *in, char *out, size_t capacity) {
    size_t n=0;
    for(size_t i=0;in[i];i++) {
        unsigned char c=(unsigned char)in[i];
        if(c<32) return 0;
        if(c=='"' || c=='\\') {if(n+2>=capacity)return 0;out[n++]='\\';}
        if(n+1>=capacity)return 0;
        out[n++]=(char)c;
    }
    out[n]=0;return 1;
}
#include "fox_notepad_trust.inc"
static void resolve_mode(const char *request,char *out,int application) {
    if(process_safety()!=0) {deny(out,"non_elevated_context_required");return;}
    WCHAR path[1025]={0},final_path[1025]={0},root[4]={0};
    int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,request,-1,path,1025);
    if(count<5 || count>513 || path[1]!=L':' || (path[2]!=L'/' && path[2]!=L'\\') || !((path[0]>=L'A'&&path[0]<=L'Z')||(path[0]>=L'a'&&path[0]<=L'z'))) {deny(out,"invalid_path");return;}
    for(int i=0;i<count-1;i++) {
        WCHAR c=path[i];
        if(c==L'/')path[i]=L'\\';
        if(c<32 || c==L'"'||c==L'<'||c==L'>'||c==L'|'||c==L'*'||c==L'?'||(c==L':'&&i!=1)) {deny(out,"invalid_path");return;}
    }
    root[0]=path[0];root[1]=L':';root[2]=L'\\';
    if(GetDriveTypeW(root)!=DRIVE_FIXED) {deny(out,"nonlocal_drive");return;}
    // Inspect every ancestor before following any reparse point. Deny links even within a root.
    for(int i=3;i<count;i++) {
        if(path[i]!=L'\\' && path[i]!=0)continue;
        int begin=i-1;while(begin>=3 && path[begin]!=L'\\')begin--;begin++;
        WCHAR saved=path[i];path[i]=0;
        if(begin==i || path[i-1]==L'.' || path[i-1]==L' ' || reserved(path+begin)) {path[i]=saved;deny(out,"ambiguous_component");return;}
        DWORD attrs=GetFileAttributesW(path);
        if(attrs==INVALID_FILE_ATTRIBUTES) {path[i]=saved;deny(out,"missing_or_denied");return;}
        if(attrs & (FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_OFFLINE|FILE_ATTRIBUTE_SYSTEM)) {path[i]=saved;deny(out,"reparse_or_system");return;}
        if(attrs&FILE_ATTRIBUTE_DIRECTORY) {
            HANDLE dir=metadata(path);DWORD flags=0;
            if(dir==INVALID_HANDLE_VALUE) {path[i]=saved;deny(out,"missing_or_denied");return;}
            // FileCaseSensitiveInfo (23); fail closed if unavailable on this filesystem/OS.
            BOOL checked=GetFileInformationByHandleEx(dir,(FILE_INFO_BY_HANDLE_CLASS)23,&flags,sizeof(flags));
            CloseHandle(dir);
            if(!checked || flags) {path[i]=saved;deny(out,"case_semantics_unavailable");return;}
        }
        path[i]=saved;
    }
    HANDLE handle=metadata(path);
    if(handle==INVALID_HANDLE_VALUE) {deny(out,"missing_or_denied");return;}
    BY_HANDLE_FILE_INFORMATION info={0};DWORD length=GetFinalPathNameByHandleW(handle,final_path,1025,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    BOOL valid=GetFileType(handle)==FILE_TYPE_DISK && length>4 && length<1025 && GetFileInformationByHandle(handle,&info);
    CloseHandle(handle);
    if(!valid) {deny(out,"resolution_unavailable");return;}
    if(wcsncmp(final_path,L"\\\\?\\",4) || final_path[5]!=L':' || final_path[6]!=L'\\') {deny(out,"nonlocal_target");return;}
    root[0]=final_path[4];
    if(GetDriveTypeW(root)!=DRIVE_FIXED || info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_OFFLINE|FILE_ATTRIBUTE_SYSTEM)) {deny(out,"nonlocal_target");return;}
    if(application && ((info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) || !wcsrchr(path,L'.') || _wcsicmp(wcsrchr(path,L'.'),L".exe"))){deny(out,"application_required");return;}
    if(!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) && info.nNumberOfLinks!=1 && !(application && notepad_trusted_snapshot(path,&info))) {deny(out,"hardlink_denied");return;}
    char utf8[4096]={0},escaped[6144]={0};
    for(DWORD i=4;i<length;i++)if(final_path[i]==L'\\')final_path[i]=L'/';
    if(!WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,final_path+4,-1,utf8,sizeof(utf8),NULL,NULL) || !json_escape(utf8,escaped,sizeof(escaped))) {deny(out,"invalid_encoding");return;}
    snprintf(out,8192,"{\"ok\":true,\"path\":\"%s\",\"identity\":\"%08lx:%08lx%08lx\",\"stamp\":\"%08lx%08lx\",\"size\":%llu,\"directory\":%s}",escaped,(unsigned long)info.dwVolumeSerialNumber,(unsigned long)info.nFileIndexHigh,(unsigned long)info.nFileIndexLow,(unsigned long)info.ftLastWriteTime.dwHighDateTime,(unsigned long)info.ftLastWriteTime.dwLowDateTime,(unsigned long long)(((uint64_t)info.nFileSizeHigh<<32)|info.nFileSizeLow),(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)?"true":"false");
}
static void resolve(const char *request,char *out){resolve_mode(request,out,0);}
static void resolve_application(const char *request,char *out){resolve_mode(request,out,1);}
static void invoke_mode(const void *request,void *result,int application) {
    char input[4096]={0},output[8192]={0};
    int64_t length=string_utf8((GDExtensionConstStringPtr)request,NULL,0);
    if(length<1 || length>=4096)deny(output,"invalid_length");
    else {string_utf8((GDExtensionConstStringPtr)request,input,sizeof(input)-1);resolve_mode(input,output,application);}
    string_new(result,output);
}
static void text_invoke(const void *request,void *result) {
    char input[4096]={0},error[8192]={0};int64_t length=string_utf8(request,NULL,0);
    char *fields[5]={0};WCHAR path[1025]={0},final_path[1025]={0};HANDLE file=INVALID_HANDLE_VALUE;
    unsigned char bytes[65536];DWORD count=0;char *output=NULL;
    if(length<1 || length>=4096 || process_safety()!=0) {deny(error,"request_or_context_denied");goto done;}
    string_utf8(request,input,4095);fields[0]=input;int parts=1;
    for(char *p=input;*p;p++)if(*p=='\t') {if(parts==5){deny(error,"request_schema");goto done;}*p=0;fields[parts++]=p+1;}
    if(parts!=5){deny(error,"request_schema");goto done;}
    char *end=NULL;unsigned long long expected=_strtoui64(fields[3],&end,10);
    if(!*fields[3] || *end || expected>65536){deny(error,"size_limit");goto done;}
    unsigned long limit=strtoul(fields[4],&end,10);
    if(!*fields[4] || *end || limit<1 || limit>65536 || expected>limit){deny(error,"size_limit");goto done;}
    resolve(fields[0],error);if(!strstr(error,"\"ok\":true"))goto done;error[0]=0;
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,fields[0],-1,path,1025)){deny(error,"invalid_path");goto done;}
    const WCHAR *ext=wcsrchr(path,L'.');if(!ext || (_wcsicmp(ext,L".txt") && _wcsicmp(ext,L".md") && _wcsicmp(ext,L".json"))){deny(error,"text_format_denied");goto done;}
    file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_OPEN_NO_RECALL,NULL);
    if(file==INVALID_HANDLE_VALUE){deny(error,"access_denied_or_missing");goto done;}
    BY_HANDLE_FILE_INFORMATION info={0};DWORD n=GetFinalPathNameByHandleW(file,final_path,1025,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    if(!GetFileInformationByHandle(file,&info) || GetFileType(file)!=FILE_TYPE_DISK || n<7 || n>=1025 || info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_OFFLINE|FILE_ATTRIBUTE_SYSTEM) || info.nNumberOfLinks!=1){deny(error,"unsafe_handle");goto done;}
    for(DWORD i=4;i<n;i++)if(final_path[i]==L'\\')final_path[i]=L'/';
    for(WCHAR *p=path;*p;p++)if(*p==L'\\')*p=L'/';
    char identity[32],stamp[24];snprintf(identity,sizeof(identity),"%08lx:%08lx%08lx",(unsigned long)info.dwVolumeSerialNumber,(unsigned long)info.nFileIndexHigh,(unsigned long)info.nFileIndexLow);snprintf(stamp,sizeof(stamp),"%08lx%08lx",(unsigned long)info.ftLastWriteTime.dwHighDateTime,(unsigned long)info.ftLastWriteTime.dwLowDateTime);
    uint64_t size=((uint64_t)info.nFileSizeHigh<<32)|info.nFileSizeLow;
    if(_wcsicmp(path,final_path+4) || strcmp(identity,fields[1]) || strcmp(stamp,fields[2]) || size!=expected){deny(error,"target_changed");goto done;}
    if(size && (!ReadFile(file,bytes,(DWORD)size,&count,NULL) || count!=size)){deny(error,"read_failed");goto done;}
    for(DWORD i=0;i<count;i++)if(!bytes[i]){deny(error,"binary_text_denied");goto done;}
    if(count && !MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,(char*)bytes,count,NULL,0)){deny(error,"invalid_utf8");goto done;}
    output=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,2*(size_t)count+128);if(!output){deny(error,"allocation_failed");goto done;}
    strcpy(output,"{\"ok\":true,\"hex\":\"");size_t offset=strlen(output);const char hex[]="0123456789abcdef";
    for(DWORD i=0;i<count;i++){output[offset++]=hex[bytes[i]>>4];output[offset++]=hex[bytes[i]&15];}strcpy(output+offset,"\"}");
done:
    if(file!=INVALID_HANDLE_VALUE)CloseHandle(file);
    string_new(result,output?output:error);if(output)HeapFree(GetProcessHeap(),0,output);
}
static void text_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *params,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    (void)data;(void)instance;uint64_t request=0,answer=0;error->error=GDEXTENSION_CALL_OK;
    if(count!=1 || variant_type(params[0])!=GDEXTENSION_VARIANT_TYPE_STRING){error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;string_new(&answer,"{\"ok\":false,\"reason\":\"invalid_request\"}");}
    else {to_string(&request,(GDExtensionVariantPtr)params[0]);text_invoke(&request,&answer);string_free(&request);}
    from_string(result,&answer);string_free(&answer);
}
static void text_ptr_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *params,GDExtensionTypePtr result){(void)data;(void)instance;text_invoke(params[0],result);}
static void call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *params,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    (void)data;(void)instance;uint64_t request=0,answer=0;error->error=GDEXTENSION_CALL_OK;
    if(count!=1 || variant_type(params[0])!=GDEXTENSION_VARIANT_TYPE_STRING) {error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;error->argument=0;error->expected=GDEXTENSION_VARIANT_TYPE_STRING;string_new(&answer,"{\"ok\":false,\"reason\":\"invalid_type\"}");}
    else {to_string(&request,(GDExtensionVariantPtr)params[0]);invoke_mode(&request,&answer,data!=NULL);string_free(&request);}
    from_string(result,&answer);string_free(&answer);
}
static void ptr_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *params,GDExtensionTypePtr result) {(void)instance;invoke_mode(params[0],result,data!=NULL);}
static void safety_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *params,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    (void)data;(void)instance;(void)params;uint64_t answer=0;char out[8192]={0};
    error->error=count?GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS:GDEXTENSION_CALL_OK;error->expected=0;
    if(count)deny(out,"invalid_arguments");else if(data==(void*)2){InterlockedIncrement(&search_generation);strcpy(out,"{\"ok\":true}");}else if(data)system_json(out);else safety_json(out);
    string_new(&answer,out);from_string(result,&answer);string_free(&answer);
}
static void safety_ptr_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *params,GDExtensionTypePtr result) {
    (void)instance;(void)params;char out[8192]={0};if(data==(void*)2){InterlockedIncrement(&search_generation);strcpy(out,"{\"ok\":true}");}else if(data)system_json(out);else safety_json(out);string_new(result,out);
}
static void window_invoke(void *data,const void *request,void *result);
#include "fox_scoped_actions.inc"
#include "fox_window_actions.inc"
static void free_instance(void *data,GDExtensionClassInstancePtr instance) {(void)data;(void)instance;}
static void initialize(void *data,GDExtensionInitializationLevel level) {
    (void)data;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    name_new(&class_name,"FoxPathBoundary",0);name_new(&parent_name,"Object",0);name_new(&empty_name,"",0);
    GDExtensionClassCreationInfo6 info={0};info.is_abstract=1;info.is_exposed=1;info.free_instance_func=free_instance;
    register_class(library,&class_name,&parent_name,&info);
    Name method,arg;name_new(&method,"resolve_metadata",0);name_new(&arg,"path",0);
    GDExtensionPropertyInfo ret={0},argument={0};ret.type=argument.type=GDEXTENSION_VARIANT_TYPE_STRING;ret.name=&empty_name;argument.name=&arg;ret.class_name=argument.class_name=&empty_name;ret.hint_string=argument.hint_string=&empty_string;
    GDExtensionClassMethodArgumentMetadata meta=GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo m={0};m.name=&method;m.call_func=call;m.ptrcall_func=ptr_call;m.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_STATIC;m.has_return_value=1;m.return_value_info=&ret;m.argument_count=1;m.arguments_info=&argument;m.arguments_metadata=&meta;
    register_method(library,&class_name,&m);name_free(&method);name_free(&arg);
    name_new(&method,"resolve_application",0);name_new(&arg,"path",0);argument.name=&arg;m.method_userdata=(void*)1;
    register_method(library,&class_name,&m);name_free(&method);name_free(&arg);m.method_userdata=NULL;
    name_new(&method,"process_safety",0);m.argument_count=0;m.arguments_info=NULL;m.arguments_metadata=NULL;m.call_func=safety_call;m.ptrcall_func=safety_ptr_call;
    register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"system_information",0);m.method_userdata=(void*)1;
    register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"read_text_snapshot",0);name_new(&arg,"request",0);argument.name=&arg;m.method_userdata=NULL;m.argument_count=1;m.arguments_info=&argument;m.arguments_metadata=&meta;m.call_func=text_call;m.ptrcall_func=text_ptr_call;
    register_method(library,&class_name,&m);name_free(&method);name_free(&arg);
    name_new(&method,"launch_snapshot",0);name_new(&arg,"request",0);argument.name=&arg;m.call_func=scoped_call;m.ptrcall_func=scoped_ptr_call;
    register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"search_snapshot",0);m.method_userdata=(void*)1;
    register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"list_app_windows",0);m.method_userdata=(void*)3;register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"query_app_window",0);m.method_userdata=(void*)4;register_method(library,&class_name,&m);name_free(&method);
    name_new(&method,"close_app_window",0);m.method_userdata=(void*)5;register_method(library,&class_name,&m);name_free(&method);name_free(&arg);
    name_new(&method,"cancel_search",0);m.method_userdata=(void*)2;m.argument_count=0;m.arguments_info=NULL;m.arguments_metadata=NULL;m.call_func=safety_call;m.ptrcall_func=safety_ptr_call;
    register_method(library,&class_name,&m);name_free(&method);
}
static void deinitialize(void *data,GDExtensionInitializationLevel level) {
    (void)data;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    unregister_class(library,&class_name);name_free(&empty_name);name_free(&parent_name);name_free(&class_name);string_free(&empty_string);
}
__declspec(dllexport) GDExtensionBool fox_path_boundary_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init) {
    library=lib;
#define LOAD(v,t,s) v=(t)get(s);if(!v)return 0
    LOAD(name_new,GDExtensionInterfaceStringNameNewWithLatin1Chars,"string_name_new_with_latin1_chars");LOAD(string_new,GDExtensionInterfaceStringNewWithUtf8Chars,"string_new_with_utf8_chars");LOAD(string_utf8,GDExtensionInterfaceStringToUtf8Chars,"string_to_utf8_chars");
    LOAD(register_class,GDExtensionInterfaceClassdbRegisterExtensionClass6,"classdb_register_extension_class6");LOAD(unregister_class,GDExtensionInterfaceClassdbUnregisterExtensionClass,"classdb_unregister_extension_class");LOAD(register_method,GDExtensionInterfaceClassdbRegisterExtensionClassMethod,"classdb_register_extension_class_method");LOAD(variant_type,GDExtensionInterfaceVariantGetType,"variant_get_type");
    GDExtensionInterfaceVariantGetPtrDestructor destructor;GDExtensionInterfaceGetVariantFromTypeConstructor from;GDExtensionInterfaceGetVariantToTypeConstructor to;
    LOAD(destructor,GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor");LOAD(from,GDExtensionInterfaceGetVariantFromTypeConstructor,"get_variant_from_type_constructor");LOAD(to,GDExtensionInterfaceGetVariantToTypeConstructor,"get_variant_to_type_constructor");
    name_free=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);string_free=destructor(GDEXTENSION_VARIANT_TYPE_STRING);from_string=from(GDEXTENSION_VARIANT_TYPE_STRING);to_string=to(GDEXTENSION_VARIANT_TYPE_STRING);string_new(&empty_string,"");
    init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;init->initialize=initialize;init->deinitialize=deinitialize;return 1;
}
