# [QEMU로 실행 방법]

## 커널 빌드

```sh
# pwd: $(IAMROOT_SRC)/qemu
make defconfig	# arm64 defconfig를 $(IAMROOT_SRC)/qemu/images 에 설정
make kernel	# 빌드 이미지를 $(IAMROOT_SRC)/qemu/images 에 빌드
```

## rootfs 이미지 생성

```sh
# pwd: $(IAMROOT_SRC)/qemu
make initramfs	# $(IAMROOT_SRC)/qemu/images/initramfs.img.lz4 생성
```

## qemu 실행하기

qemu가 올라올 shell에서 아래 명령 실행

```sh
# pwd: $(IAMROOT_SRC)/qemu
./run_qemu.sh
# 아래 gdb에서 continue 하면 boot log가 나오고 login이 나타남
# ID: root PW: iamroot
```

qemu를 gdb로 제어할 shell에서 아래 명령 실행

```sh
# pwd: $(IAMROOT_SRC)/qemu
./qemu_gdb.sh
```

```text
# 현재 qemu는 start_kernel에 bp가 걸려있음. c 로 continue
(gdb) c
# 실행된 뒤로는 qemu shell에서 login shell까지 올라올 것임
# qemu를 강제종료 하려면 gdb에서 Ctrl-C로 SIGINT 후 아래 명령 입력
(gdb) kill inferiors 1
```

## 모듈 설치 / 삭제하기

```sh
# pwd: $(IAMROOT_SRC)/qemu
make modules		# $(IAMROOT_SRC)/qemu/images/에 모듈 컴파일
make install_modules	# rootfs 원본에 현재 컴파일된 모듈 설치
make initramfs		# 모듈이 포함된 rootfs 생성
```

```sh
# pwd: $(IAMROOT_SRC)/qemu
make clear_modules	# rootfs 원본에 모든 추가 모듈 제거
make initramfs		# 모듈이 제거된 rootfs 생성
```

