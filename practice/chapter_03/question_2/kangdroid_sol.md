Linux Kernel Study 1st week practice, CH3-2 Question
====================================================

Question
---------
pthread_create()를 이용하여 새로운 쓰레드를 생성한 뒤, 자식 쓰레드에서 exec() 혹은 exit() 등의 함수를 수행하여 fork()와 차이점을 알아보자.

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
1. pthread_create로 Thread 생성
2. thread 함수에서 exit(0)을 호출
```
#include <iostream>
#include <unistd.h>
#include <pthread.h>

using namespace std;

void* thread_function(void* tmp) {
    cout << "Thread called!" << endl;
    exit(0);
}

int main(void) {
    pthread_t thread_creating;
    pthread_create(&thread_creating, NULL, thread_function, NULL);
    pthread_join(thread_creating, NULL);

    cout << "After thread call!" << endl;
    return 0;
}
```

결과
----
exit(0) 함수는 프로그램 자체를 종료하는 함수인데, fork()와 달리 thread는 하나의 프로그램[프로세스] 안에서 돌아가는 형식이기 때문에 스레드 조인이 끝난 후의 cout이 출력되지 않는다.