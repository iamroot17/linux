
## IAMROOT17A 커널 스터디

### 2020년 8주차 스터디
+ 2020년 10월 17일
+ 코드 버전 : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_CODE_START_LOCAL(preserve_boot_args)
  + SYM_FUNC_START_PI(__inval_dcache_area)
  + SYM_FUNC_START(el2_setup) 진행중
------

### 2020년 9주차 스터디
+ 2020년 10월 24일
+ 코드 버전 : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_FUNC_START(el2_setup)
  + SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
  + SYM_FUNC_START_LOCAL(__create_page_tables) 진행중
------

### 2020년 10주차 스터디
+ 2020년 10월 31일
+ 코드 버전 : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_FUNC_START_LOCAL(__create_page_tables) 진행중
    + .macro compute_indices
    + .macro map_memory
    + .macro populate_entries
    + .macre phys_to_pte
------

### 2020년 11주차 스터디
+ 2020년 11월 7일
+ 코드 버전 : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_FUNC_START_LOCAL(__create_page_tables) 진행중
  
    .macro compute_indices 관련 링크
    1. http://www.iamroot.org/xe/index.php?mid=Programming&document_srl=207287
    2. http://jake.dothome.co.kr/head-64/ (compute_indices count 가 count -1로 고려하는 이유)

  + SYM_FUNC_START(_cpu_setup)
    + MAIR_EL1_SET : 0x00_00_bb_ff_44_0c_04_00 구조
------

### 2020년 12주차 스터디
+ 2020년 11월 14일
+ 코드 버전 : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
    + .macro tcr_compute_pa_size
    + https://stackoverflow.com/questions/53065579/confusion-about-arm-documentation-on-carry-flag(마이너스 캐리에 관한 내용)

  + SYM_FUNC_START_LOCAL(_primary_switch)
  + SYM_FUNC_START(_enable_mmu)
  + SYM_FUNC_START_LOCAL(_relocate_kernel)
  + SYM_FUNC_START_LOCAL(_primary_switched) 진행중
------

### 2020년 13주차 스터디
+ 2020년 11월 21일
+ 코드 버전 : mainline 5.9
+ head.S 종료
  + SYM_CODE_START_LOCAL(__primary_switched) 분석
  + Exception Vector 설정
    + Exception Vector 코드 구성 분석
      
  + BSS 초기화 과정 분석
  + __pi_memset 심볼 확인
  + KASLR을 위한 offset 생성 과정 분석
  + kaslr_early_init()
  + KASLR 취소/적용 이후 start_kernel()로 진입하는 과정 분석
  + KASLR 적용 시 MMU 비활성화 하고 init_pg_dir 재생성 및 relocate 확인
------

### 2020년 14주차 스터디
+ 2020년 11월 28일
+ 코드 버전 : mainline 5.9
+ init/main.c start_kernel() 분석 시작
  + init_task 및 struct task_struct 분석
  + set_task_stack_end_magic() 분석
  + smp_setup_processor_id() 분석
    + MPIDR_EL1, MIDR_EL1 분석

  + debug_object_early_init() 분석
  + cgroup_init_early() 분석
    + cgrp_dfl_root의 정의 (DEFINE_PER_CPU 분석)
    + init_cgroup_root() 분석
    + list.h의 INIT_LIST_HEAD에서 WRITE_ONCE 사용 이유 분석
  + atomic_set의 architecture dependent 구현 흐름 분석
  + init_cgroup_housekeeping() 분석
    + 커널 내 linked list 사용법에 대한 분석
    + mutex, spin_lock, optimistic_spin_queue 분석
    + prev_cputime 분석
    + for_each_subsys() 매크로 분석

   + RCU_INIT_POINTER() 매크로 분석 중
------

### 2020년 14주차 스터디
+ 2020년 11월 28일
+ 코드 버전 : mainline 5.9
+ init/main.c start_kernel() 분석 시작
  + kernel/cgroup/cgroup.c cgroup_init_early() 분석 마무리
  + cgroup의 개념 등 이론적인 부분 추가 분석
  + IDR/IDA 분석
------

### 2020년 16주차 스터디
+ 2020년 12월 12일
+ 코드 버전 : mainline 5.9
+ init/main.c start_kernel() 분석 중
  + local_irq_disable() 분석
  + boot_cpu_init() 분석
  + page_address_init() 분석
  + pr_notice() 분석 (linux_banner)
  + ARM64에서 구현된 atomic operation 관련 내용 분석
   LL/SC, LSE방식으로 구현된 atomic operation 확인
   bitops에서 구현된 CAS(Compare-And-Swap) 방식 확인
  + 기존 주석 맞춤법 수정
------


