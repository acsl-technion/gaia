# GAIA - Unified page cache for hetrogeneous systems

```
                   _____  _____ _          _____          _____          
             /\   / ____|/ ____| |        / ____|   /\   |_   _|   /\    
            /  \ | |    | (___ | |       | |  __   /  \    | |    /  \   
           / /\ \| |     \___ \| |       | | |_ | / /\ \   | |   / /\ \  
          / ____ \ |____ ____) | |____   | |__| |/ ____ \ _| |_ / ____ \ 
         /_/    \_\_____|_____/|______|   \_____/_/    \_\_____/_/    \_\
                             
```                      

## Evaluation platform and setup

We use an Intel Xeon CPU E5-2620 v2 at 2.10GHz with 78GB RAM, GeForce GTX 1080 (with 8GB GDDR)
GPU and 800GB Intel NVMe SSD DC P3700 with 2.8GB/s sequential read throughput. We use Ubuntu 16.04.3 with kernel 4.4.115 that includes GAIA modifications, CUDA SDK 8.0.34, and NVIDIA-UVM driver 384.59.

This repository includes the folowing:
1. Linux 4.4.115 code with GAIA patches applied. See https://github.com/acsl-technion/gaia_linux for code.
   Note that you can either downoad the whole code or just pick the patches from GAIA_patches directory. The patch is to be applied on  
   top of linux 4.4.15 commit f0feeec9c246f6518e168daec66d92a4a6bf0965.
2. NVIDIA-UVM driver 384.59 with GAIA patches applied. See https://github.com/acsl-technion/gaia_nvidia for code. 
   Note that you can either downoad the whole code or just pick the patches from GAIA_patches directory. The patch is to be applied on  
   top of clean NVIDIA-Linux-x86_64-384.59 driver.
3. mmap user space library. See GAIA_libmmap.
4. Gunrock application example. See https://github.com/acsl-technion/gaia_gunrock for code.
   Note that you can either downoad the whole code or just pick the patches from GAIA_patches directory. The patch is to be applied on  
   top of commit 85beb835a75aaca5dbfb6e3241c61b53244e0e4d in the Gunrock git.


## Installation

**1.** Linux kernel

Compile kernel code under Linux4.4.115-GAIA and install it:

```
sudo make -j 4 && sudo make modules_install -j 4 && sudo make install -j 4 
sudo update-grub 
sudo reboot 
```


**2.** NVIDIA Driver

Compile and install NVIDIA-UVM driver by running ./nvidia-installer from NVIDIA-Linux-x86_64-384.59-GAIA:
```
sudo ./nvidia-installer
```



**3.** mmap library

Compile the mmap library with the provided make file from Gunrock-GAIA.


When running your application do:
```
LD_PRELOAD=<path to your compiled libmmap_cu.so>
```


## Usage example (Gunrock)
Build gunrock by running the folowing commands:

```
cd build
cmake .. && make -j$(nproc)
```

For usage examples refer to the scripts directory.
For more details refere to https://gunrock.github.io/docs/

## Contributing
NOTE: This is an experimental POC and is provided AS IS. Feel free to use/modify. If used, please retain this disclaimer and cite:

"GAIA: An OS Page Cache for Heterogeneous Systems", 
Brokhman T, Pavel L, Silberstein M. 
USENUX ATC 19, July 2019, Renton, WA, USA

