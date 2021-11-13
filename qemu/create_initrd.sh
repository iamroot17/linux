BUILDS="../images"

mkdir -p $BUILDS;

cd initramfs;
find . -print0 | cpio --null -ov --format=newc | gzip -9 > $BUILDS/initramfs.cpio.gz
