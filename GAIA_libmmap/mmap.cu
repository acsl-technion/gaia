#define __KERNEL__
//#include "shared_test.h"
#include <stdio.h>
#include <cuda_runtime.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <dlfcn.h>
#include <errno.h>
#include <uvm_ioctl.h>
//#include "mmap_cu.h"
#include <sys/time.h>

#include <dirent.h>
#include "ucm_mmap.h"

#define UCM_ERR(fmt, ...) \
	printf("UCM_ERR: %s(): " fmt, __func__, ##__VA_ARGS__);

#define UCM_DBG(fmt, ...) \
	printf("UCM_DBG: %s(): " fmt, __func__, ##__VA_ARGS__);


#define MAP_FAILED ((void*)-1)
#define MAP_HUGETLB	0x100000	/* create a huge page mapping */
typedef void *(*orig_mmap_f_type)(void *addr, size_t length, int prot,
			int flags, int fd, off_t offset);
typedef int (*orig_munmap_f_type)(void *addr, size_t length);

// This will output the proper CUDA error strings in the event that a 
// CUDA host call returns an error
#define checkCudaErrors(err)  __checkCudaErrors (err, __FILE__, __LINE__)

inline void __checkCudaErrors(cudaError err, const char *file, const int line) {
    if(cudaSuccess != err) {
        fprintf(stderr, "%s(%i) : CUDA Runtime API error %d: %s.\n",file, 
        				line, (int)err, cudaGetErrorString(err));
        exit(-1);
    }
}

struct file_map_struct
{
	void *cuda_ptr;
	void *cpu_ptr;
	int taken;
};

#define SUPPORTED_FILES_MAPPED 10
static struct file_map_struct mappings_arr[SUPPORTED_FILES_MAPPED];
static int mappings_arr_idx = 0;
static int mappings_cnt = 0;

#define NVIDI_UVM_CHAR_DEV "/dev/nvidia-uvm"
int nvidia_uvm_fd = -1;
static int open_nvidia_old(void)
{	
	nvidia_uvm_fd = open(NVIDI_UVM_CHAR_DEV, O_RDWR);
	if (nvidia_uvm_fd < 0){
		UCM_ERR("Failed opening %s err = %d\n", NVIDI_UVM_CHAR_DEV, nvidia_uvm_fd);
		return -1;
	}
	return 0;
}

#define PSF_DIR "/proc/self/fd"
static int open_nvidia(void)
{
	DIR *d;
	d = opendir(PSF_DIR);
	char psf_path[256];
	char *psf_realpath;
	struct dirent *dir;

	if (d)
	{
		while ((dir = readdir(d)) != NULL)
		{
			if (dir->d_type == DT_LNK)
			{
				sprintf(psf_path, "%s/%s", PSF_DIR, dir->d_name);
				psf_realpath = realpath(psf_path, NULL);
				if (strcmp(psf_realpath, NVIDI_UVM_CHAR_DEV) == 0)
					nvidia_uvm_fd = atoi(dir->d_name);
				free(psf_realpath);
				if (nvidia_uvm_fd >= 0)
					break;
			}
		}
		closedir(d);
	}
	if (nvidia_uvm_fd < 0)
	{
		fprintf(stderr, "Cannot open %s\n", PSF_DIR);
		return -1;
	}
	return 0;
}

static void close_nvidia(void)
{	
	close(nvidia_uvm_fd);
	nvidia_uvm_fd = -1;
}

static int map_vma_ioctl(unsigned long long uvm_base,
						 unsigned long long cpu_base, int map)
{
	UVM_MAP_VMA_RANGE_PARAMS params;
	UVM_UNMAP_VMA_RANGE_PARAMS uparams;
	
	params.uvm_base = uvm_base;
	params.cpu_base = cpu_base;
	
	uparams.uvm_base = uvm_base;
	
	if (map) {
		if (ioctl(nvidia_uvm_fd, UVM_MAP_VMA_RANGE, &params) == -1) {
    			UCM_ERR("ioctl to uvm failed\n");
    			return -1;
    		}
	} else {
		if (ioctl(nvidia_uvm_fd, UVM_UNMAP_VMA_RANGE, &uparams) == -1) {
            		UCM_ERR("ioctl to uvm failed\n");
            		return -1;
        	}
	}
	return 0;
}
static int touch_pages(unsigned long long uvm_base, unsigned long length)
{
	UVM_TOUCH_RANGE_PARAMS params;
	char c;

	params.uvm_base = uvm_base;
	params.start_addr = uvm_base;
	params.length = length;
	if (ioctl(nvidia_uvm_fd, UVM_TOUCH_RANGE, &params) == -1) {
                UCM_ERR("ioctl to uvm failed with code %u\n", params.rmStatus);
        	return -1;
	}
	return 0;
}

void *map_file_on_gpu(void *addr, size_t length, int prot, int flags,
                  int fd, off_t offset)
{
	long int pagenum=0;
	bool prefetch_to_cpu = false;
	orig_mmap_f_type orig_mmap;
	orig_mmap = (orig_mmap_f_type)dlsym(RTLD_NEXT,"mmap");

	struct file_map_struct *mapping = &mappings_arr[mappings_arr_idx++];
	
	if (flags & PREFETCH_TO_CPU) {
		prefetch_to_cpu = true;
		flags &= NOT_PREFETCH_TO_CPU;
		printf("got PREFETCH_TO_CPU. revert it: flags = 0x%lx\n", flags);
	}
	if (mapping->taken) {
		UCM_ERR("mapping taken!!\n");
		//TODO: handle this case/ a lock might be needed
	}
	mapping->taken = 1;
	mappings_cnt++;
	mapping->cpu_ptr = 0;

	mapping->cpu_ptr = orig_mmap(addr, length, prot, flags , fd, offset);
	if (mapping->cpu_ptr == MAP_FAILED)
	{
	 	printf("Oh dear, something went wrong with orig_mmap()! %s, errno=%d, length=%lu\n", strerror(errno), errno, length);
	    	exit(EXIT_FAILURE);
	}

	long start1, end1;
	struct timeval timecheck1;
	gettimeofday(&timecheck1, NULL);
	start1 = (long)timecheck1.tv_sec * 1000 + (long)timecheck1.tv_usec / 1000;
	checkCudaErrors( cudaMallocManaged((void **)&mapping->cuda_ptr, length, cudaMemAttachGlobal) );
	gettimeofday(&timecheck1, NULL);
	end1 = (long)timecheck1.tv_sec * 1000 + (long)timecheck1.tv_usec / 1000;
    printf("Time_consumed_malloc,%ld,ms\n", (end1 - start1));

	/* Need to try open the file after first cudaMalloc. Otherwise it's not created */
	if (nvidia_uvm_fd < 0 && open_nvidia()) {
        	//TODO: Handle this err properly
        	return NULL;
    	}

	/* Now issue IOCTL to uvm to set up the connection in uvm_va_space */
	if (map_vma_ioctl((unsigned long long)mapping->cuda_ptr,
					  (unsigned long long)mapping->cpu_ptr, 1)) {
    		UCM_ERR("ioctl to uvm failed\n");
    		//TODO: handle properly
    		return NULL;
    	}
	
	if (!prefetch_to_cpu && touch_pages((unsigned long long)mapping->cuda_ptr, length)) {
                UCM_ERR("touch pages failed\n");
       }
#if 0
if (!touch_data) {
	checkCudaErrors( cudaMemPrefetchAsync(mapping->cuda_ptr, length, -1, 0) );
	UCM_DBG("cudaMemPrefetchAsync to host\n");
	checkCudaErrors(cudaDeviceSynchronize());
        checkCudaErrors( cudaGetLastError() );
} else {
#endif
	if (1 /*length / 4096 >= 48*/) {
		long start, end;
    		struct timeval timecheck;
 		gettimeofday(&timecheck, NULL);
    		start = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
		while (pagenum * 4096 < length) {
			char *tmp = (char *)(mapping->cuda_ptr) + pagenum * 4096;
			if (*tmp == '!')
				UCM_ERR("hit :) %d\n", pagenum);
			pagenum++;
		}
		gettimeofday(&timecheck, NULL);
    		end = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
 		printf("touch_pages,%ld,ms\n", (end - start));
	}

	if (!prefetch_to_cpu && touch_pages((unsigned long long)mapping->cuda_ptr, length)) {
                UCM_ERR("touch pages second time failed\n");
        }
	return mapping->cuda_ptr;
}

extern "C"
void *mmap(void *addr, size_t length, int prot, int flags,
                  int fd, off_t offset)
{
	orig_mmap_f_type orig_mmap;
	orig_mmap = (orig_mmap_f_type)dlsym(RTLD_NEXT,"mmap");
	
	if (!(flags & MAP_ON_GPU))
		return orig_mmap(addr, length, prot, flags, fd, offset);

	//If I got here MAP_ON_GPU is on
	if (flags & ACQUIRE) {
		//This is a hack for calling aquire
		flags |= MA_PROC_NVIDIA;
		return (void *)maquire(addr, length, flags);
	}
	if (flags & RELEASE) {
		//This is a hack for calling release
		flags |= MA_PROC_NVIDIA;
		return (void *)mrelease(addr, length, flags);
	}
    return map_file_on_gpu(addr, length, prot, flags, fd, offset);
}

void *gmmap(void *addr, size_t length, int prot, int flags,
                  int fd, off_t offset) {
	return mmap(addr, length, prot, flags, fd, offset);
}

extern "C"
int munmap (void *addr, size_t length)
{
	int i;
	orig_munmap_f_type orig_munmap;
	orig_munmap = (orig_munmap_f_type)dlsym(RTLD_NEXT,"munmap");

	for (i = 0; i < mappings_cnt; i++)
		if (mappings_arr[i].cuda_ptr == addr && mappings_arr[i].taken) {
			struct file_map_struct *mapping = &mappings_arr[i];
			mappings_arr[i].taken = 0;
			mappings_cnt--;

			/* Now issue IOCTL to uvm to remove the connection in uvm_va_space */
			if (map_vma_ioctl((unsigned long long)mapping->cuda_ptr,
						  (unsigned long long)mapping->cpu_ptr, 0)) {
				UCM_ERR("ioctl to uvm failed\n");
				//TODO: handle properly
			}
			//giving an err. need to understand why	
			checkCudaErrors( cudaFree(addr) );

			if (!mappings_cnt)
                close_nvidia();
			UCM_DBG("call original munmap for cpu addr\%p. free managed memory\n", mapping->cpu_ptr);
			return orig_munmap(mapping->cpu_ptr, length);
		}
    return orig_munmap(addr, length);
}

int gmunmap (void *addr, size_t length) {
	return munmap(addr, length);
}

//map the pages into cpu_ptr vma
int maquire(void *start, size_t length, int flags) {
	int i;
	long int pagenum=0;
	struct file_map_struct *mapping = NULL;

	for (i = 0; i < mappings_cnt; i++)
		if (mappings_arr[i].cuda_ptr == start && mappings_arr[i].taken) {
			mapping = &mappings_arr[i];
		}
	if (!mapping)
		return -1;

	if (0 /*length / 4096 >= 48*/) {
		long start, end;
			struct timeval timecheck;
		gettimeofday(&timecheck, NULL);
			start = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
		while (pagenum * 4096 < length) {
			char *tmp2 = (char *)(mapping->cpu_ptr) + pagenum * 4096;
			if (*tmp2 == '!')
				UCM_ERR("hit :) %d\n", pagenum);
			pagenum++;
		}
		gettimeofday(&timecheck, NULL);
			end = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
	}

	return syscall(327, start, length, 0x10);
}

int mrelease(void *start, size_t len, int flags) {
	return syscall(328, start, len, flags);
}

