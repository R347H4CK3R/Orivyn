#include "CArchive.h"
#include <zlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

int oz_available_space(const char *path, uint64_t *bytes) {
    struct statvfs info;
    if (!bytes || statvfs(path,&info)<0 || info.f_frsize==0) return -1;
    uint64_t count=(uint64_t)info.f_bavail,size=(uint64_t)info.f_frsize;
    *bytes=count>UINT64_MAX/size?UINT64_MAX:count*size;
    return 0;
}
int oz_create_member(int root_fd, const char *path, int directory) {
    char *copy = strdup(path); if (!copy) return -1;
    int current = dup(root_fd); if (current < 0) { free(copy); return -1; }
    char *save = NULL, *part = strtok_r(copy, "/", &save);
    while (part) {
        char *next = strtok_r(NULL, "/", &save);
        if (!strcmp(part,".") || !strcmp(part,"..") || !*part) { close(current);free(copy);return -1; }
        int fd;
        if (next || directory) {
            if (mkdirat(current,part,0700) < 0 && errno != EEXIST) { close(current);free(copy);return -1; }
            fd = openat(current,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        } else {
            fd = openat(current,part,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        }
        if (fd>=0 && fsync(current)<0) { close(fd);fd=-1; }
        close(current);current=fd;
        if (fd < 0) { free(copy);return -1; }
        part=next;
    }
    free(copy);return current;
}
static int read_exact(int fd, unsigned char *p, size_t count, uint64_t offset) {
    while (count) {
        ssize_t n=pread(fd,p,count,(off_t)offset);
        if (n<0 && errno==EINTR) continue;
        if (n<=0) return 1;
        p+=n;count-=(size_t)n;offset+=(uint64_t)n;
    }
    return 0;
}
static int write_exact(int fd,const unsigned char *p,size_t count) {
    while (count) {
        ssize_t n=write(fd,p,count);
        if (n<0 && errno==EINTR) continue;
        if (n<=0) return 1;
        p+=n;count-=(size_t)n;
    }
    return 0;
}
int oz_extract(int source_fd,int output_fd,uint64_t offset,uint64_t compressed,
               uint64_t expanded,uint32_t expected_crc,int method,
               int (*cancelled)(void *),void *context) {
    if (offset>INT64_MAX || compressed>INT64_MAX-offset || expanded>INT64_MAX || (method!=0 && method!=8)) return 2;
    if (method==0 && compressed!=expanded) return 2;
    unsigned char input[65536], output[65536];
    uint64_t remaining=compressed, produced=0, consumed=0;
    uLong crc=crc32(0L,Z_NULL,0);
    z_stream z;memset(&z,0,sizeof(z));int initialized=0,status=0,ended=0;
    if (method==8) { if (inflateInit2(&z,-MAX_WBITS)!=Z_OK) return 2; initialized=1; }
    while (remaining || (method==8 && !ended)) {
        if (cancelled && cancelled(context)) { status=3;break; }
        if (method==0) {
            size_t n=remaining>sizeof(input)?sizeof(input):(size_t)remaining;
            if (read_exact(source_fd,input,n,offset+consumed) || write_exact(output_fd,input,n)) {status=1;break;}
            crc=crc32(crc,input,(uInt)n);remaining-=n;consumed+=n;produced+=n;
        } else {
            if (!z.avail_in && remaining) {
                size_t n=remaining>sizeof(input)?sizeof(input):(size_t)remaining;
                if (read_exact(source_fd,input,n,offset+consumed)) {status=1;break;}
                remaining-=n;consumed+=n;z.next_in=input;z.avail_in=(uInt)n;
            }
            z.next_out=output;z.avail_out=sizeof(output);
            uInt before=z.avail_in;int rc=inflate(&z,Z_NO_FLUSH);
            size_t n=sizeof(output)-z.avail_out;
            if (n>expanded-produced) {status=2;break;}
            if (n && write_exact(output_fd,output,n)) {status=1;break;}
            produced+=n;crc=crc32(crc,output,(uInt)n);
            if (rc==Z_STREAM_END) {ended=1;if (remaining || z.avail_in) status=2;break;}
            if (rc!=Z_OK || (before==z.avail_in && !n)) {status=2;break;}
        }
    }
    if (initialized) inflateEnd(&z);
    if (!status && (produced!=expanded || (method==8 && !ended) || (uint32_t)crc!=expected_crc)) status=2;
    if (!status && fsync(output_fd)<0) status=1;
    /* Check written bytes again, not just the producer's buffer. */
    if (!status) {
        uint64_t position=0;crc=crc32(0L,Z_NULL,0);
        while (position<expanded) {
            if (cancelled && cancelled(context)) {status=3;break;}
            size_t n=expanded-position>sizeof(input)?sizeof(input):(size_t)(expanded-position);
            if (read_exact(output_fd,input,n,position)) {status=1;break;}
            crc=crc32(crc,input,(uInt)n);position+=n;
        }
        if (!status && (uint32_t)crc!=expected_crc) status=2;
    }
    return status;
}
