BUILDS="../images"

mkdir -p $BUILDS;

cd rootfs;
find . ! -name '.git*' -print0 \
	| cpio --null --create --verbose --owner root:root --format=newc \
	| lz4c -l > $BUILDS/initramfs.img.lz4
