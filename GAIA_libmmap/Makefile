all:  mmap

mmap:
	nvcc -arch=sm_35 --ptxas-options=-v --compiler-options -fPIC -o libmmap_cu.so \
		--shared mmap.cu \
		-I/home/tanya/NVIDIA-Linux-x86_64-384.59-UCM/kernel/nvidia-uvm \
		-I/home/tanya/NVIDIA-Linux-x86_64-384.59-UCM/kernel/common/inc \
		-L/usr/local/cuda/lib \
		-lcuda -lopencv_core -lopencv_highgui

	
clean: 
	rm *.o *.so
