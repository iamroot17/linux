set arch aarch64
target remote localhost:1234
set pagination off

tb start_kernel
c

#lay split
