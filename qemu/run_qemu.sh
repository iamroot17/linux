#!/bin/bash

image=./images/Image
initrd=./images/initramfs.cpio.gz

qemu-system-aarch64 \
	-machine virt \
	-cpu cortex-a57 \
	-m 6144M \
	-object memory-backend-ram,id=mem0,size=5120M \
	-object memory-backend-ram,id=mem1,size=1024M \
	-smp cpus=4,sockets=2,cores=2 \
	-numa node,memdev=mem0,cpus=0-1,nodeid=0 \
	-numa node,memdev=mem1,cpus=2-3,nodeid=1 \
	-numa dist,src=0,dst=1,val=20 \
	-nographic \
	-gdb tcp::1234 \
	-S \
	-kernel $image \
	-initrd $initrd \
#	-machine dumpdtb=dtb_dump.dtb \
	-append "kgdboc=ttyS0,115200"
