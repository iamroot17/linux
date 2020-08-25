Linux Kernel Study 1st week practice, CH2-6 Question
====================================================

Question
---------
이 장에서 설명된 방식대로 커널을 컴파일 하고 새로 생성된 커널로 부팅시켜 보자.

System
--------------
<b>Tester[MBP 2019, 16"]</b><br>
|HW|Host|Guest[VMWare Fusion]|
|--|----|-----|
|OS|macOS 11.xx Big Sur Public Beta|Ubuntu Desktop 20.04|
|CPU|i9-9880H[8C, 16T]|6C, 6T|
|GPU|iGPU/Radeon 5500M|Shared Graphic, 2048MB|
|RAM|16GB|8GB|
|SSD|1024GB|60GB|

Approach
--------
[C++/clang++ 이용]
1. Fork 후 부모는 wait, child process는 ls 명령어 수행.
```
#include <iostream>
#include <unistd.h>

using namespace std;

int main(void) {
    int something_val = 10;
    int ret_val = fork();
    char *args[]={"/bin/ls",NULL}; 

    if (ret_val == 0) {
        cout << "Chiled Process Executed" << endl;
        execvp(args[0], args);
    } else {
        cout << "Parent Process working.." << endl;
        wait(0);
        cout << "Child process ended" << endl;
    }
    return 0;
}
```

Reference
-----------
출처: https://prorion.tistory.com/33 
```
int execl (const char *path const char *arg, ..);
int execlp (const char *file, const char *arg,...);
int execle (const char *path,const char *arg,..., char * const envp[]);
int execv (const char *path, char *const argv[]);
int execvp (const char *file, char *const argv[]);
int execve (const char *filename,char *const argv[],char *const envp[]);
```
Exec Family
- L --> List
- P --> Path
- E --> Environment
- V --> Vector