Linux Kernel Study 1st week practice, CH3-3 Question
====================================================

Question
---------
/proc 가상 파일시스템 하위에 존재하는 숫자 엔트리들은 어떤 의미를 가지는가?

Short Answer
------------
숫자 엔트리 자체는 현재 시스템에서 실행되고 있는 프로세스의 PID를 나타낸다.<br>

Long one
--------
/proc/${number_entries}[Where number_entries are number of pid] contains multiple data, such as:
- process-mapped-memory data<br>
  Entries --> ``/proc/${number_entries}/maps``
- Process command line ARGV[cmdline]<br>
  Entries --> ``/proc/${number_entries}/cmdline``
- The file that process currently using<br>
  Entries --> ``/proc/${number_entries}/cwd``
- process ENV<br>
  Entries --> ``/proc/${number_entries}/environ``
- process resource limits<br>
  Entries --> ``/proc/${number_entries}/limits``
- Current memory status of process<br>
  Entries --> ``/proc/${number_entries}/mem``
- Page information of P-Mem that process using.<br>
  Entries --> ``/proc/${number_entries}/pagemap``
- Scheduling Information<br>
  Entries --> ``/proc/${number_entries}/sched``
- and many more..

Reference:
----------
Most of reference: https://man7.org/linux/man-pages/man5/proc.5.html
