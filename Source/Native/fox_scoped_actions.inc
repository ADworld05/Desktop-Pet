/* Private finite adapters. No command interpreter, arbitrary verb or elevation retry. */
typedef struct { HANDLE handles[260]; int count; } PinnedPath;
static void unpin(PinnedPath *p) {while(p->count)CloseHandle(p->handles[--p->count]);}
static int pin_path_mode(const WCHAR *input, DWORD access, PinnedPath *p, BY_HANDLE_FILE_INFORMATION *last,int application) {
    WCHAR path[1025],final[1025];size_t n=wcslen(input);
    if(n<4 || n>512)return 0;
    wcscpy(path,input);for(size_t i=0;i<n;i++)if(path[i]==L'/')path[i]=L'\\';
    for(size_t i=3;i<=n;i++) {
        if(path[i] && path[i]!=L'\\')continue;
        WCHAR saved=path[i];path[i]=0;
        HANDLE h=CreateFileW(path,i==n?access:FILE_READ_ATTRIBUTES,i==n?FILE_SHARE_READ:(FILE_SHARE_READ|FILE_SHARE_WRITE),NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_OPEN_NO_RECALL,NULL);
        BY_HANDLE_FILE_INFORMATION info={0};DWORD length=0,flags=0;
        int valid=h!=INVALID_HANDLE_VALUE && GetFileType(h)==FILE_TYPE_DISK && GetFileInformationByHandle(h,&info);
        if(valid)length=GetFinalPathNameByHandleW(h,final,1025,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
        valid=valid && length>4 && length<1025 && !wcsncmp(final,L"\\\\?\\",4) && !_wcsicmp(path,final+4) && !(info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_OFFLINE|FILE_ATTRIBUTE_SYSTEM));
        if(valid && (info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY))valid=GetFileInformationByHandleEx(h,(FILE_INFO_BY_HANDLE_CLASS)23,&flags,sizeof(flags)) && !flags;
        if(valid && !(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY))valid=info.nNumberOfLinks==1 || (application && i==n && notepad_trusted_handle(h,path));
        path[i]=saved;
        if(!valid || p->count>=260) {if(h!=INVALID_HANDLE_VALUE)CloseHandle(h);unpin(p);return 0;}
        p->handles[p->count++]=h;if(i==n)*last=info;
    }
    return p->count>0;
}
static int pin_path(const WCHAR *input,DWORD access,PinnedPath *p,BY_HANDLE_FILE_INFORMATION *last){return pin_path_mode(input,access,p,last,0);}
static int pin_application_path(const WCHAR *input,PinnedPath *p,BY_HANDLE_FILE_INFORMATION *last){return pin_path_mode(input,GENERIC_READ|FILE_READ_ATTRIBUTES,p,last,1);}
static int fields_split(char *input,char **fields,int maximum) {
    int count=1;fields[0]=input;
    for(char *q=input;*q;q++)if(*q=='\t') {if(count==maximum)return 0;*q=0;fields[count++]=q+1;}
    return count;
}
static int uint_field(const char *s,unsigned long long maximum,unsigned long long *value) {
    if(!*s)return 0;
    for(const char *p=s;*p;p++)if(*p<'0'||*p>'9')return 0;
    char *end=NULL;*value=_strtoui64(s,&end,10);return !*end && *value<=maximum;
}
static int snapshot_matches(const BY_HANDLE_FILE_INFORMATION *info,char **fields) {
    char identity[32],stamp[24];unsigned long long size=0;
    snprintf(identity,sizeof(identity),"%08lx:%08lx%08lx",(unsigned long)info->dwVolumeSerialNumber,(unsigned long)info->nFileIndexHigh,(unsigned long)info->nFileIndexLow);
    snprintf(stamp,sizeof(stamp),"%08lx%08lx",(unsigned long)info->ftLastWriteTime.dwHighDateTime,(unsigned long)info->ftLastWriteTime.dwLowDateTime);
    return uint_field(fields[3],0x7fffffffffffffffULL,&size) && !strcmp(identity,fields[1]) && !strcmp(stamp,fields[2]) && size==(((uint64_t)info->nFileSizeHigh<<32)|info->nFileSizeLow);
}
static int blocked_executable(const WCHAR *path) {
    const WCHAR *base=path;for(const WCHAR *p=path;*p;p++)if(*p==L'/'||*p==L'\\')base=p+1;
    const WCHAR *blocked[]={L"cmd.exe",L"powershell.exe",L"pwsh.exe",L"wscript.exe",L"cscript.exe",L"mshta.exe",L"rundll32.exe",L"regsvr32.exe",L"reg.exe",L"python.exe",L"pythonw.exe",L"node.exe",L"bash.exe",L"sh.exe",L"wsl.exe",L"java.exe",L"dotnet.exe",L"msiexec.exe",L"schtasks.exe",L"wmic.exe",L"conhost.exe",L"wt.exe",L"windowsterminal.exe",L"git.exe",L"gcc.exe"};
    for(size_t i=0;i<sizeof(blocked)/sizeof(blocked[0]);i++)if(!_wcsicmp(base,blocked[i]))return 1;
    const WCHAR *ext=wcsrchr(base,L'.');return !ext || _wcsicmp(ext,L".exe") || !_wcsnicmp(base,L"python",6) || !_wcsnicmp(base,L"powershell",10);
}
static int document_path(const WCHAR *path) {
    const WCHAR *ext=wcsrchr(path,L'.');if(!ext)return 0;
    const WCHAR *allowed[]={L".txt",L".md",L".json",L".pdf",L".docx",L".xlsx",L".pptx",L".png",L".jpg",L".jpeg",L".webp"};
    for(size_t i=0;i<sizeof(allowed)/sizeof(allowed[0]);i++)if(!_wcsicmp(ext,allowed[i]))return 1;
    return 0;
}
static void launch_json(char *request,char *out) {
    char *fields[5];WCHAR target[1025]={0},exe[1025]={0},command[2200]={0};PinnedPath pinned={0},handler={0};BY_HANDLE_FILE_INFORMATION info={0},handler_info={0};
    if(process_safety()!=0 || fields_split(request,fields,5)!=5){deny(out,"request_or_context_denied");return;}
    const char *operation=fields[0];char *snapshot[4]={fields[1],fields[2],fields[3],fields[4]};
    if(strcmp(operation,"open_application") && strcmp(operation,"open_folder") && strcmp(operation,"reveal_in_explorer") && strcmp(operation,"open_file")){deny(out,"operation_denied");return;}
    if(!strcmp(operation,"open_application"))resolve_application(snapshot[0],out);else resolve(snapshot[0],out);
    if(!strstr(out,"\"ok\":true"))return;
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,snapshot[0],-1,target,1025) || (!strcmp(operation,"open_application")?!pin_application_path(target,&pinned,&info):!pin_path(target,FILE_READ_ATTRIBUTES,&pinned,&info))){deny(out,"unsafe_or_busy_target");return;}
    if(!snapshot_matches(&info,snapshot)){deny(out,"target_changed");goto done;}
    for(WCHAR *p=target;*p;p++)if(*p==L'/')*p=L'\\';
    if(!strcmp(operation,"open_application")) {
        if((info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) || blocked_executable(target)){deny(out,"application_denied");goto done;}
        wcscpy(exe,target);swprintf(command,2200,L"\"%ls\"",exe); /* argv[0] only; no caller arguments. */
    } else if(!strcmp(operation,"open_file")) {
        if((info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) || !document_path(target)){deny(out,"document_format_denied");goto done;}
        DWORD length=1025;
        if(AssocQueryStringW(ASSOCF_NOTRUNCATE,ASSOCSTR_EXECUTABLE,wcsrchr(target,L'.'),L"open",exe,&length)!=S_OK || blocked_executable(exe) || !pin_application_path(exe,&handler,&handler_info) || (handler_info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)){deny(out,"desktop_association_unavailable_or_denied");goto done;}
        swprintf(command,2200,L"\"%ls\" \"%ls\"",exe,target); /* Never execute the registry's command template. */
    } else {
        if(!strcmp(operation,"open_folder") && !(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)){deny(out,"folder_required");goto done;}
        if(!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) && !document_path(target)){deny(out,"document_format_denied");goto done;}
        UINT length=GetWindowsDirectoryW(exe,1000);if(length<3 || length>=1000){deny(out,"explorer_unavailable");goto done;}
        wcscat(exe,L"\\explorer.exe");
        swprintf(command,2200,!strcmp(operation,"reveal_in_explorer")?L"\"%ls\" /select,\"%ls\"":L"\"%ls\" \"%ls\"",exe,target);
    }
    STARTUPINFOW startup={0};PROCESS_INFORMATION process={0};startup.cb=sizeof(startup);
    if(!CreateProcessW(exe,command,NULL,NULL,FALSE,0,NULL,NULL,&startup,&process)) {
        DWORD error=GetLastError();snprintf(out,8192,"{\"ok\":false,\"reason\":\"%s\",\"windows_error\":%lu}",error==740?"elevation_denied":"launch_failed",(unsigned long)error);goto done;
    }
    snprintf(out,8192,"{\"ok\":true,\"status\":\"launch_requested\",\"pid\":%lu,\"foreground_verified\":false}",(unsigned long)process.dwProcessId);
    CloseHandle(process.hThread);CloseHandle(process.hProcess);
done: unpin(&handler);unpin(&pinned);
}
typedef struct { WCHAR root[1025],query[81];unsigned depth,maximum,found,visited,skipped;ULONGLONG deadline;LONG generation;int limited,failed,cancelled;char *out;size_t used; } Search;
static int search_stop(Search *s) {
    if(InterlockedCompareExchange(&search_generation,0,0)!=s->generation){s->cancelled=1;return 1;}
    if(GetTickCount64()>=s->deadline || s->visited>=10000){s->limited=1;return 1;}
    return 0;
}
static void search_directory(Search *s,const WCHAR *path,HANDLE dir,unsigned depth) {
    unsigned char buffer[16384];int first=1;
    while(!s->limited && !s->failed && !s->cancelled) {
        if(search_stop(s))return;
        if(!GetFileInformationByHandleEx(dir,first?FileIdBothDirectoryRestartInfo:FileIdBothDirectoryInfo,buffer,sizeof(buffer))) {
            if(GetLastError()!=ERROR_NO_MORE_FILES)s->failed=1;
            return;
        }
        first=0;size_t offset=0;
        for(;;) {
            FILE_ID_BOTH_DIR_INFO *entry=(FILE_ID_BOTH_DIR_INFO*)(buffer+offset);
            size_t chars=entry->FileNameLength/sizeof(WCHAR);
            if(search_stop(s))return;
            s->visited++;
            if(chars && chars<256) {
                WCHAR name[256]={0},child[1025];memcpy(name,entry->FileName,entry->FileNameLength);
                if(wcscmp(name,L".") && wcscmp(name,L"..")) {
                    if(entry->FileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_SYSTEM|FILE_ATTRIBUTE_OFFLINE))s->skipped++;
                    else if(wcslen(path)+chars+1<=512) {
                        swprintf(child,1025,L"%ls/%ls",path,name);
                        PinnedPath pinned={0};BY_HANDLE_FILE_INFORMATION info={0};
                        DWORD access=FILE_READ_ATTRIBUTES|((entry->FileAttributes&FILE_ATTRIBUTE_DIRECTORY)?FILE_LIST_DIRECTORY:0);
                        if(!pin_path(child,access,&pinned,&info))s->skipped++;
                        else {
                            WCHAR folded[256];wcscpy(folded,name);CharLowerBuffW(folded,(DWORD)chars);
                            if(!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) && wcsstr(folded,s->query)) {
                                char utf8[4096],escaped[6144],row[6600];
                                if(!WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,child,-1,utf8,sizeof(utf8),NULL,NULL) || !json_escape(utf8,escaped,sizeof(escaped)))s->skipped++;
                                else {
                                    int n=snprintf(row,sizeof(row),"%s{\"path\":\"%s\",\"size\":%llu}",s->found?",":"",escaped,(unsigned long long)(((uint64_t)info.nFileSizeHigh<<32)|info.nFileSizeLow));
                                    if(n>0 && s->used+(size_t)n+256<330000){memcpy(s->out+s->used,row,(size_t)n);s->used+=(size_t)n;s->found++;}
                                    else s->limited=1;
                                    if(s->found>=s->maximum)s->limited=1;
                                }
                            }
                            if(!s->limited && (info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) && depth<s->depth)search_directory(s,child,pinned.handles[pinned.count-1],depth+1);
                            unpin(&pinned);
                        }
                    } else s->skipped++;
                }
            }
            if(s->limited || s->failed || s->cancelled || !entry->NextEntryOffset)break;
            offset+=entry->NextEntryOffset;if(offset+sizeof(FILE_ID_BOTH_DIR_INFO)>sizeof(buffer)){s->failed=1;break;}
        }
    }
}
static char *search_json(char *request,char *error) {
    char *fields[8];unsigned long long depth=0,maximum=0,timeout=0;PinnedPath pinned={0};BY_HANDLE_FILE_INFORMATION info={0};Search s={0};
    if(process_safety()!=0 || fields_split(request,fields,8)!=8 || !uint_field(fields[5],4,&depth) || !uint_field(fields[6],50,&maximum) || !maximum || !uint_field(fields[7],2000,&timeout) || timeout<100){deny(error,"search_schema_or_context");return NULL;}
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,fields[4],-1,s.query,81) || !s.query[0]){deny(error,"invalid_query");return NULL;}
    for(WCHAR *q=s.query;*q;q++)if(*q<32 || wcschr(L"/\\:*?\"<>|;%$",*q)){deny(error,"invalid_query");return NULL;}
    CharLowerBuffW(s.query,(DWORD)wcslen(s.query));
    resolve(fields[0],error);if(!strstr(error,"\"ok\":true"))return NULL;
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,fields[0],-1,s.root,1025) || !pin_path(s.root,FILE_LIST_DIRECTORY|FILE_READ_ATTRIBUTES,&pinned,&info)){deny(error,"unsafe_or_busy_root");return NULL;}
    if(!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) || !snapshot_matches(&info,fields)){unpin(&pinned);deny(error,"root_changed");return NULL;}
    s.depth=(unsigned)depth;s.maximum=(unsigned)maximum;s.deadline=GetTickCount64()+timeout;s.generation=InterlockedCompareExchange(&search_generation,0,0);
    s.out=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,330000);if(!s.out){unpin(&pinned);deny(error,"allocation_failed");return NULL;}
    strcpy(s.out,"{\"ok\":true,\"results\":[");s.used=strlen(s.out);
    search_directory(&s,s.root,pinned.handles[pinned.count-1],0);unpin(&pinned);
    if(s.failed || s.cancelled){HeapFree(GetProcessHeap(),0,s.out);deny(error,s.cancelled?"search_cancelled":"enumeration_unavailable");return NULL;}
    snprintf(s.out+s.used,330000-s.used,"],\"limited\":%s,\"visited\":%u,\"skipped\":%u,\"metadata_only\":true}",s.limited?"true":"false",s.visited,s.skipped);return s.out;
}
static void scoped_invoke(void *data,const void *request,void *result) {
    if(data==(void*)3 || data==(void*)4 || data==(void*)5){window_invoke(data,request,result);return;}
    char input[4096]={0},out[8192]={0};char *large=NULL;int64_t length=string_utf8(request,NULL,0);
    if(length<1 || length>=4096)deny(out,"invalid_request_length");
    else {string_utf8(request,input,4095);if(data)large=search_json(input,out);else launch_json(input,out);}
    string_new(result,large?large:out);if(large)HeapFree(GetProcessHeap(),0,large);
}
static void scoped_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *params,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    (void)instance;uint64_t request=0,answer=0;error->error=GDEXTENSION_CALL_OK;
    if(count!=1 || variant_type(params[0])!=GDEXTENSION_VARIANT_TYPE_STRING){error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;string_new(&answer,"{\"ok\":false,\"reason\":\"invalid_request\"}");}
    else {to_string(&request,(GDExtensionVariantPtr)params[0]);scoped_invoke(data,&request,&answer);string_free(&request);}
    from_string(result,&answer);string_free(&answer);
}
static void scoped_ptr_call(void *data,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *params,GDExtensionTypePtr result){(void)instance;scoped_invoke(data,params[0],result);}
