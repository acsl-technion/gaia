#ifndef __UCM_MMAP_H_
#define __UCM_MMAP_H_

#define MAP_ON_GPU      0x80000

#define ACQUIRE		0x100000
#define RELEASE		0x200000
#define MA_PROC_NVIDIA 0x10
#define PREFETCH_TO_CPU  0x40000
#define NOT_PREFETCH_TO_CPU 0xFFFFFFFFFFFBFFFF

extern void *gmmap(void *addr, size_t length, int prot, int flags,
                  int fd, off_t offset);
extern int gmunmap (void *addr, size_t length);
extern int maquire(void *start, size_t length, int flags);
extern int mrelease(void *start, size_t len, int flags);

#endif
