Linux Kernel Study 1st week practice, CH2-6 Question
====================================================

Question
---------
이 장에서 설명된 방식대로 커널을 컴파일 하고 새로 생성된 커널로 부팅시켜 보자.

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

Approach - Expected
---------
1. https://www.kernel.org 에 접속해서 최신 메인라인 커널[5.9-RC1]을 다운받는다.
2. 현재 시스템의 config를 가져와서 빌드할 커널에 적용한다.
3. 컴파일 후, 인스톨 해 준다.

Result
------
<b><i><u>부팅이 전혀 되질 않는다.</u></i></b><br>
먼저, 다음과 같은 문제가 생긴다.
1. Grub에서 새로 설치된 메뉴엔트리를 통해 들어가지만, 들어가는 순간 프리징이 걸린다.<br>
   혹시 몰라 메뉴엔트리 관련 설정도 확인 해 보았지만, 기존 커널 메뉴엔트리와 다를 점도 없었고, 옵션들도 문제 될 것이 없었다.
2. 어찌어찌 grub에서 빠져 나온다면, 생기는 에러는 바로 "Error: out of memory, press any key to continue..." 와 같은 에러가 발생한다.
3. 더불어, 자동으로 알아서 커널 로그[부팅]를 간략하게 보여주는데, 애초에 OS로딩이 되어있지 않으므로 스크롤이 불가능해 자세한 로그 확인이 필요 했지만, 마지막 부분에서 발견한 점은, 커널 이미지가 로딩이 된 후, root 파일 시스템을 찾을 수 없다는 에러였다.<br>
   우분투의 로그 시스템은 rsyslog 데몬으로 이루어져 있어 운영체제의 갑작스러운 재부팅 등과 같은 상황에서는 유용하게 쓰이지만, 애초에 운영체제가 로딩이 되어있지 않아 데몬 자체가 성립되지 않을 때는 로그 확인이 많이 힘들다.[덤프..?]

Approach - Alternative Way
---------------
따라서, 조금 루트를 바꿔서 진행하기로 했다.
1. 5.9 RC1 버전 대신, 5.8 Stable 버전을 사용하며,
2. 기존 make 유틸리티 말고, make-kpkg 유틸리티를 사용하며,
3. 이에 따라 컴파일 된 커널 인스톨도 deb 형식으로 진행한다.[dpkg -i ~]

Command I used
----------------
주의: J-Thread는 각자 빌드하는 컴퓨터의 CPU에 맞게 조절하시면 됩니다.[저는 12스레드를 사용하므로, 컴파일 시, -j옵션에 12를 주었습니다.]
```
# Download Kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.8.3.tar.xz

# Unzip[tar] it
tar -xvf linux-5.8.3.tar.xz
cd linux-*

# Copy system's config to local kernel source directory.
cp /boot/config-5.4.0-42-generic ./.config

# Do the menuconfig
make menuconfig

# Compile it!
sudo make-kpkg -j12 --initrd --revision=1.0a kernel_image kernel_headers

# *.deb packages will be created on parent directory of source directory.
# For me, I transferred those debian package files from buildbot to Guest OS using SCP first.
# Package name would be differ with mine, adjust as your needs.
sudo dpkg -i linux-headers-5.8.3_1.0a_amd64.deb
sudo dpkg -i linux-image-5.8.3_1.0a_amd64.deb

# Reboot!
sudo init 6
```

Warning[Or disclaimer]
------------------------
1. 커널 컴파일 시간이 대충 6코어 12스레드 기준 약 30~40분 이내입니다. 상당히 긴 시간입니다.<br>
   굳이 빌드봇과 게스트를 나눈 이유도 여기에 있습니다. 가상화 프로그램의 특성상 게스트OS에서는 호스트OS의 모든 자원을 쓰지 못하기 때문에 최대한 효율을 낼 수 있는 것을 사용하기 위해 빌드봇을 썼습니다!
2. 왠만해서 로컬에 직접 설치하고 직접 테스트는 강력히 비추천합니다.<br>
   처음에 메인빌드봇으로 쓰고 있는 기기에 설치 했다가 5.9 커널 버전에서 부팅 안돼서 복구하느라 살짝 애먹었습니다.[GPU가 없는 기기라..]<br>
   편하게 게스트에서 컴파일/설치 하시거나, 저처럼 빌드봇 하나 두고 컴파일 --> 게스트에서 설치 하는 것을 추천드립니다. <br>
   차라리 여차 하면 간편하게 밀어버릴 수 있는 가상이 상대적으로 더 안전합니다!
3. Ubuntu 20.04 Desktop 기준, 5.8로 판업을 하게 되면 부팅 속도가 조금 느려집니다.<br>
   이 부분은 VMWare과 5.8이 잘 안맞는 조합인지, 혹은 5.8에서 뭔가 부팅 과정에 있어 크게 바뀐게 있는지는 확인하지 못했습니다.
4. Ubuntu 기준, 커널 부팅 이전에 부트로더 자체는 GRUB2를 쓰고 있습니다.<br>
   만약, 커널 패닉과, 이와 동등한 에러가 발생해 정상적인 사용이 불가능한 경우, BIOS/UEFI 스플래시 스크린이 꺼진 뒤, ESC[BIOS의 경우], Shift[UEFI의 경우] 키를 연타해 GRUB메뉴로 진입할 수 있습니다.<br>
   해당 메뉴에서 고급 옵션 메뉴에 들어가면, 커널 버전별로 부팅이 가능 합니다. 즉, 패닉난 커널 이전의 정상적인 커널로 부팅이 가능 하니, 이 점 참고하면 좋을 것 같습니다!


최종 결과
--------
성공! <br>
![](https://i.imgur.com/msLQqao.png)
