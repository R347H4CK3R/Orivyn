#ifndef ORIVYN_ARCHIVE_H
#define ORIVYN_ARCHIVE_H
#include <stdint.h>
/* Caller validates relative UTF-8 path; all components are opened without following links. */
int oz_available_space(const char *path, uint64_t *bytes);
int oz_create_member(int root_fd, const char *path, int directory);
/* Only methods 0/8. Exactly bounded pread, output, CRC and raw-deflate termination. */
int oz_extract(int source_fd, int output_fd, uint64_t offset, uint64_t compressed,
               uint64_t expanded, uint32_t crc, int method,
               int (*cancelled)(void *), void *context);
#endif
