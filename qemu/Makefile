CROSS_COMPILE = aarch64-linux-gnu-
OUTPUT = $(shell pwd)/images
ROOTFS = $(shell pwd)/rootfs

defconfig:
	make -C ../ \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(OUTPUT) \
		defconfig

kernel:
	make -C ../ \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(OUTPUT) \
		Image -j`nproc`

modules:
	make -C ../ \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(OUTPUT) \
		modules -j`nproc`

install_modules:
	make -C ../ \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(OUTPUT) \
		INSTALL_MOD_PATH=$(ROOTFS) \
		modules_install

clear_modules:
	rm -rf $(ROOTFS)/lib/modules/*

initramfs:
	cd rootfs; \
	find . ! -name '.git*' -print0 \
		| cpio --null --create --verbose --owner root:root --format=newc \
		| lz4c -l > $(OUTPUT)/initramfs.img.lz4; \
	cd ..;
