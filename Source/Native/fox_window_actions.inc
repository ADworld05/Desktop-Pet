/* Selected same-user/session, non-elevated main windows only. No force termination. */
static int same_user(HANDLE process) {
    HANDLE theirs=NULL,ours=NULL;unsigned char a[1024],b[1024];DWORD na=0,nb=0;TOKEN_ELEVATION elevated={0};DWORD n=0;
    if(!OpenProcessToken(process,TOKEN_QUERY,&theirs) || !OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&ours)){if(theirs)CloseHandle(theirs);return 0;}
    int ok=GetTokenInformation(theirs,TokenElevation,&elevated,sizeof(elevated),&n) && !elevated.TokenIsElevated && GetTokenInformation(theirs,TokenUser,a,sizeof(a),&na) && GetTokenInformation(ours,TokenUser,b,sizeof(b),&nb) && EqualSid(((TOKEN_USER*)a)->User.Sid,((TOKEN_USER*)b)->User.Sid);
    CloseHandle(theirs);CloseHandle(ours);return ok;
}
static int window_snapshot(HWND window,char *out) {
    DWORD pid=0,session=0,current_session=0,length=1025;WCHAR image[1025];FILETIME created,exit,kernel,user;
    if(process_safety()!=0 || !IsWindowVisible(window) || !IsWindowEnabled(window) || GetWindow(window,GW_OWNER) || GetAncestor(window,GA_ROOT)!=window)return 0;
    GetWindowThreadProcessId(window,&pid);HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);
    if(!process)return 0;
    int ok=pid!=GetCurrentProcessId() && same_user(process) && ProcessIdToSessionId(pid,&session) && ProcessIdToSessionId(GetCurrentProcessId(),&current_session) && session==current_session && GetProcessTimes(process,&created,&exit,&kernel,&user) && QueryFullProcessImageNameW(process,0,image,&length);
    CloseHandle(process);if(!ok)return 0;
    char utf8[4096],escaped[6144];for(WCHAR *p=image;*p;p++)if(*p==L'\\')*p=L'/';
    if(!WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,image,-1,utf8,sizeof(utf8),NULL,NULL) || !json_escape(utf8,escaped,sizeof(escaped)))return 0;
    snprintf(out,8192,"{\"ok\":true,\"pid\":%lu,\"handle\":%llu,\"started\":\"%08lx%08lx\",\"owner\":\"current_user_verified\",\"session\":%lu,\"path\":\"%s\",\"visible\":true}",(unsigned long)pid,(unsigned long long)(uintptr_t)window,(unsigned long)created.dwHighDateTime,(unsigned long)created.dwLowDateTime,(unsigned long)session,escaped);return 1;
}
typedef struct { WCHAR image[1025];char *output;size_t used;unsigned count; } WindowList;
static BOOL CALLBACK matching_window(HWND window,LPARAM data) {
    WindowList *list=(WindowList*)data;DWORD pid=0,n=1025;WCHAR image[1025];char row[8192];
    GetWindowThreadProcessId(window,&pid);HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);
    if(!process)return TRUE;
    int matches=QueryFullProcessImageNameW(process,0,image,&n);CloseHandle(process);
    for(WCHAR *p=image;matches && *p;p++)if(*p==L'\\')*p=L'/';
    if(matches && !_wcsicmp(image,list->image) && window_snapshot(window,row)) {
        WCHAR title[161]={0};char title_utf8[1024]={0},escaped[2048]={0};GetWindowTextW(window,title,161);
        for(WCHAR *p=title;*p;p++)if(*p<32)*p=L' ';
        WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,title,-1,title_utf8,sizeof(title_utf8),NULL,NULL);json_escape(title_utf8,escaped,sizeof(escaped));row[strlen(row)-1]=0;
        int length=snprintf(list->output+list->used,270000-list->used,"%s%s,\"title\":\"%s\"}",list->count?",":"",row,escaped);list->used+=(size_t)length;list->count++;
    }
    return list->count<32;
}
static void window_invoke(void *data,const void *request,void *result) {
    char input[4096]={0},out[8192]={0},fresh[8192]={0};char *large=NULL;int64_t n=string_utf8(request,NULL,0);
    if(n<1 || n>=4096 || process_safety()!=0){deny(out,"request_or_context_denied");goto done;}
    string_utf8(request,input,4095);
    if(data==(void*)3) {
        WindowList list={0};resolve_application(input,out);if(!strstr(out,"\"ok\":true") || !MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,input,-1,list.image,1025))goto done;
        large=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,270000);if(!large){deny(out,"allocation_failed");goto done;}
        list.output=large;strcpy(large,"{\"ok\":true,\"windows\":[");list.used=strlen(large);EnumWindows(matching_window,(LPARAM)&list);strcpy(large+list.used,"]}");
    } else if(data==(void*)4) {
        unsigned long long handle=0;if(!uint_field(input,9007199254740991ULL,&handle) || !window_snapshot((HWND)(uintptr_t)handle,out))deny(out,"window_unavailable");
    } else {
        char *f[8];unsigned long long handle=0,pid=0,session=0;PinnedPath pinned={0};BY_HANDLE_FILE_INFORMATION info={0};WCHAR image[1025];
        if(fields_split(input,f,8)!=8 || !uint_field(f[4],9007199254740991ULL,&handle) || !uint_field(f[5],4294967295ULL,&pid) || !uint_field(f[7],65535,&session)){deny(out,"close_schema");goto done;}
        if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,f[0],-1,image,1025) || !pin_application_path(image,&pinned,&info) || !snapshot_matches(&info,f)){unpin(&pinned);deny(out,"executable_changed");goto done;}
        HWND window=(HWND)(uintptr_t)handle;DWORD actual=0;
        if(!window_snapshot(window,fresh)){unpin(&pinned);deny(out,"window_changed");goto done;}
        char expected[64];snprintf(expected,sizeof(expected),"\"pid\":%llu,",pid);int ok=strstr(fresh,expected)!=NULL;
        snprintf(expected,sizeof(expected),"\"started\":\"%s\"",f[6]);ok=ok && strlen(f[6])==16 && strstr(fresh,expected);
        snprintf(expected,sizeof(expected),"\"session\":%llu,",session);ok=ok && strstr(fresh,expected);
        char escaped[6144]={0};ok=ok && json_escape(f[0],escaped,sizeof(escaped));char path_field[6200];snprintf(path_field,sizeof(path_field),"\"path\":\"%s\"",escaped);ok=ok && strstr(fresh,path_field);
        GetWindowThreadProcessId(window,&actual);ok=ok && actual==pid;
        if(!ok)deny(out,"window_identity_changed");
        else if(!PostMessageW(window,WM_CLOSE,0,0))deny(out,"close_request_denied");
        else strcpy(out,"{\"ok\":true,\"status\":\"close_requested\",\"termination_verified\":false}");
        unpin(&pinned);
    }
done:string_new(result,large?large:out);if(large)HeapFree(GetProcessHeap(),0,large);
}
