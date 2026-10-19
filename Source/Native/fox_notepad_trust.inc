/* Narrow installed-Notepad compatibility. Local cache/catalogs only; no network/UI/elevation. */
static int notepad_location(const WCHAR *path) {
    WCHAR expected[1025]={0},normalized[1025]={0};UINT n=GetWindowsDirectoryW(expected,900);
    if(n<3 || n>=900 || wcslen(path)>512)return 0;
    wcscat(expected,L"\\System32\\notepad.exe");wcscpy(normalized,path);
    for(WCHAR *p=normalized;*p;p++)if(*p==L'/')*p=L'\\';
    return !_wcsicmp(expected,normalized);
}
static int notepad_trusted_handle(HANDLE file,const WCHAR *path) {
    if(!notepad_location(path))return 0;
    HCATADMIN admin=NULL;HCATINFO catalog=NULL;BYTE hash[64];DWORD hash_size=sizeof(hash);int trusted=0;
    GUID action=WINTRUST_ACTION_GENERIC_VERIFY_V2;
    typedef BOOL (WINAPI *Acquire2)(HCATADMIN*,const GUID*,const WCHAR*,const CERT_STRONG_SIGN_PARA*,DWORD);
    typedef BOOL (WINAPI *Hash2)(HCATADMIN,HANDLE,DWORD*,BYTE*,DWORD);
    HMODULE trust=GetModuleHandleW(L"wintrust.dll");
    Acquire2 acquire=trust?(Acquire2)GetProcAddress(trust,"CryptCATAdminAcquireContext2"):NULL;
    Hash2 calculate=trust?(Hash2)GetProcAddress(trust,"CryptCATAdminCalcHashFromFileHandle2"):NULL;
    if(!acquire || !calculate || !acquire(&admin,NULL,L"SHA256",NULL,0))return 0;
    if(!calculate(admin,file,&hash_size,hash,0) || hash_size>sizeof(hash))goto done;
    catalog=CryptCATAdminEnumCatalogFromHash(admin,hash,hash_size,0,NULL);
    if(!catalog)goto done;
    CATALOG_INFO info={0};info.cbStruct=sizeof(info);
    if(!CryptCATCatalogInfoFromContext(catalog,&info,0))goto done;
    WCHAR tag[129]={0};const WCHAR hex[]=L"0123456789ABCDEF";
    for(DWORD i=0;i<hash_size;i++){tag[2*i]=hex[hash[i]>>4];tag[2*i+1]=hex[hash[i]&15];}
    WINTRUST_CATALOG_INFO member={0};member.cbStruct=sizeof(member);member.pcwszCatalogFilePath=info.wszCatalogFile;member.pcwszMemberTag=tag;member.pcwszMemberFilePath=path;member.hMemberFile=file;member.pbCalculatedFileHash=hash;member.cbCalculatedFileHash=hash_size;member.hCatAdmin=admin;
    WINTRUST_DATA check={0};check.cbStruct=sizeof(check);check.dwUIChoice=WTD_UI_NONE;check.fdwRevocationChecks=WTD_REVOKE_NONE;check.dwUnionChoice=WTD_CHOICE_CATALOG;check.pCatalog=&member;check.dwStateAction=WTD_STATEACTION_VERIFY;check.dwProvFlags=WTD_CACHE_ONLY_URL_RETRIEVAL|WTD_REVOCATION_CHECK_NONE|0x2000; /* WTD_DISABLE_MD2_MD4, older bundled header lacks its name. */
    trusted=WinVerifyTrust(NULL,&action,&check)==ERROR_SUCCESS;
    check.dwStateAction=WTD_STATEACTION_CLOSE;WinVerifyTrust(NULL,&action,&check);
done:
    if(catalog)CryptCATAdminReleaseCatalogContext(admin,catalog,0);
    CryptCATAdminReleaseContext(admin,0);return trusted;
}
static int notepad_trusted_snapshot(const WCHAR *path,const BY_HANDLE_FILE_INFORMATION *expected) {
    if(!notepad_location(path))return 0;
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_OPEN_NO_RECALL,NULL);
    if(file==INVALID_HANDLE_VALUE)return 0;
    BY_HANDLE_FILE_INFORMATION actual={0};int ok=GetFileInformationByHandle(file,&actual) && !(actual.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_OFFLINE|FILE_ATTRIBUTE_SYSTEM)) && actual.dwVolumeSerialNumber==expected->dwVolumeSerialNumber && actual.nFileIndexHigh==expected->nFileIndexHigh && actual.nFileIndexLow==expected->nFileIndexLow && actual.nFileSizeHigh==expected->nFileSizeHigh && actual.nFileSizeLow==expected->nFileSizeLow && !CompareFileTime(&actual.ftLastWriteTime,&expected->ftLastWriteTime) && notepad_trusted_handle(file,path);
    CloseHandle(file);return ok;
}
