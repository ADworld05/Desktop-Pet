/* Shared finite file helpers for the unsigned, per-user setup. No elevation. */
#include <bcrypt.h>
#include <stdint.h>
static BOOL setup_plain(const WCHAR *path) {
    WCHAR p[MAX_PATH]; size_t length=wcslen(path);
    if(length<3 || length>=MAX_PATH || path[1]!=L':' || (path[2]!=L'\\' && path[2]!=L'/'))return FALSE;
    wcscpy(p,path);
    for(WCHAR *s=p+3;;s++) {
        if(*s && *s!=L'\\' && *s!=L'/')continue;
        WCHAR c=*s; *s=0; DWORD a=GetFileAttributesW(p); *s=c;
        if(a==INVALID_FILE_ATTRIBUTES || (a&FILE_ATTRIBUTE_REPARSE_POINT))return FALSE;
        if(!c)break;
    }
    HANDLE f=CreateFileW(path,FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,NULL);
    BY_HANDLE_FILE_INFORMATION i={0}; BOOL ok=f!=INVALID_HANDLE_VALUE && GetFileInformationByHandle(f,&i) && !(i.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT) && ((i.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)||i.nNumberOfLinks==1);
    if(f!=INVALID_HANDLE_VALUE)CloseHandle(f);
    return ok;
}
static BOOL setup_hash(const WCHAR *path,WCHAR out[65]) {
    if(!setup_plain(path))return FALSE;
    HANDLE f=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN,NULL);
    if(f==INVALID_HANDLE_VALUE)return FALSE;
    BCRYPT_ALG_HANDLE a=NULL;BCRYPT_HASH_HANDLE h=NULL;BYTE digest[32],buffer[65536];DWORD n;BOOL ok=FALSE;
    if(BCryptOpenAlgorithmProvider(&a,BCRYPT_SHA256_ALGORITHM,NULL,0)<0 || BCryptCreateHash(a,&h,NULL,0,NULL,0,0)<0)goto done;
    for(;;) {
        if(!ReadFile(f,buffer,sizeof(buffer),&n,NULL))goto done;
        if(!n)break;
        if(BCryptHashData(h,buffer,n,0)<0)goto done;
    }
    if(BCryptFinishHash(h,digest,32,0)<0)goto done;
    for(int j=0;j<32;j++)swprintf(out+j*2,3,L"%02x",digest[j]);
    out[64]=0;ok=TRUE;
done:
    if(h)BCryptDestroyHash(h);
    if(a)BCryptCloseAlgorithmProvider(a,0);
    CloseHandle(f);return ok;
}
