Linux Kernel Study 1st week practice, CH2-7 Question
====================================================

Question
---------
init/main.c 파일의 start_kernel() 함수의 뒤쪽에 자신의 이름을 printk()로 출력해 보자. 왜 부팅 메시지의 멘 마지막에 찍히지 않을까?

System
--------------
<b>MainFrame[a.k.a buildbot]</b><br>
OS: Ubuntu Server 20.04<br>
CPU: i7-6800K[6C, 12T]<br>
GPU: N/A<br>
RAM: 8GB[DDR4]<br>
SSD: 512GB<br><br>

<b>Tester[MBP 2019, 16"]</b><br>
|HW|Host|Guest[VMWare Fusion]|
|--|----|-----|
|OS|macOS 11.xx Big Sur Public Beta|Ubuntu Desktop 20.04|
|CPU|i9-9880H[8C, 16T]|6C, 6T|
|GPU|iGPU/Radeon 5500M|Shared Graphic, 2048MB|
|RAM|16GB|8GB|
|SSD|1024GB|60GB|

Approach
----------
1. 현재 사용중인 5.8 Stable 소스를 사용한다.
2. init/main.c의 start_kernel(void)에서 커스텀 스트링을 출력해 준다.
3. 커널 컴파일/설치 후 dmesg로 로그를 확인한다.

주의 사항
------
분명, 책에서는 함수의 '뒤쪽' 이라고 하여 그냥 함수의 마지막 부분에다가 printk를 적었지만 별 내용이 출력되지 않아 pr_notice등, pr_* 메크로[printk cover]도 사용해 보았지만, 원하는 결과를 얻지는 못하였다. <br>
어떤 이유에서인지는 모르겠으나, 수정 내용들을 맨 앞으로 옮겨 주면 잘 작동한다. 해당 내용은, https://github.com/KangDroid/linux/commit/22fa4ba2ec8f3ef288818f2963dfdd97fb8c94bd 이 부분을 참고하면 될 것 같다.

최종 결과
--------
성공! <br>
![](https://i.imgur.com/rcZbBxJ.png)
