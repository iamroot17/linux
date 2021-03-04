
## IAMROOT17A 커널 스터디
### 코드 버전 : mainline 5.9

### 2020년 8주차 스터디

+ 2020년 10월 17일
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_CODE_START_LOCAL(preserve_boot_args)
  + SYM_FUNC_START_PI(__inval_dcache_area)
  + SYM_FUNC_START(el2_setup) 진행중
+ commit : 8b34c33c56ad2cb0cce45a974e078cb993470073
------

### 2020년 9주차 스터디
+ 2020년 10월 24일
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_FUNC_START(el2_setup)
  + SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
  + SYM_FUNC_START_LOCAL(__create_page_tables) 진행중
+ commit : a9766d1e06fe2c48e9325cc7212f6b231a9063d4
------

### 2020년 10주차 스터디
+ 2020년 10월 31일
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
+ commit : c60091335faba38a0a7d814880586967bb55cf16
------

### 2020년 14주차 스터디
+ 2020년 11월 28일
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

  + cgroup의 개념 등 이론적인 부분 추가 분석
  + IDR/IDA 분석
+ commit : 27246bf040abce66f3769f9e752a374d73b403af
------

### 2020년 15주차 스터디
+ 2020년 12월 5일
 + kernel/cgroup/cgroup.c cgroup_init_early() 분석 마무리
  + cgroup의 개념 등 이론적인 부분 추가 분석
  + IDR/IDA 분석
+ commit : a1266cfe8ec347cc5d671ecd822ec9d29dc9ebfa
------

### 2020년 16주차 스터디
+ 2020년 12월 12일
+ init/main.c start_kernel() 분석 중
  + local_irq_disable() 분석
  + boot_cpu_init() 분석
  + page_address_init() 분석
  + pr_notice() 분석 (linux_banner)
  + ARM64에서 구현된 atomic operation 관련 내용 분석
   LL/SC, LSE방식으로 구현된 atomic operation 확인
   bitops에서 구현된 CAS(Compare-And-Swap) 방식 확인
+ commit : fd6d33e4da3d349f1e2d3c96eaeab174c7a5a034
------

### 2020년 17주차 스터디
+ 2020년 12월 19일
+ init/main.c start_kernel() 분석 중
  + early_security_init() 분석
  + setup_arch() 분석 중
  + kaslr_requires_kpit() 분석
  + early_fixmap_init() 분석 중
  + atomic_ops 구현의 static key 기술 분석
+ commit : 261efe3bb57068e0dbf6cefd204d092554bf6fe3
------

### 2020년 18주차 스터디
+ 2020년 12월 26일
+ init/main.c start_kernel() 분석 중
  + arch/arm64/mm/mmu.c
  + setup_arch() 의 early_fixmap_init() 마무리
+ RCU 이론 스터디
------

### 2020년 19주차 스터디
+ 2021년 1월 2일
+ init/main.c start_kernel() 분석 중
  + arch/arm64/kernel/setup.c
  + setup_arch() 분석
  + early_ioremap_init() 분석
  + setup_machine_fdt() 분석 중
  + fixmap_remap_fdt() 분석
+ RCU 이론 스터디
------

### 2020년 20주차 스터디
+ 2021년 1월 9일
+ init/main.c start_kernel() 분석 중
  + arch/arm64/kernel/setup.c
  + setup_arch() 분석
  + setup_machine_fdt() 분석 중
  + memblock_reserve() 분석
  + early_init_dt_scan() 분석 중
  + early_init_dt_scan_chosen() 분석 완료
+ Device Tree 이론 스터디
------

### 2020년 21주차 스터디
+ 2021년 1월 16일
+ init/main.c start_kernel() 분석 중
  + arch/arm64/kernel/setup.c
  + setup_arch() 분석
  + early_init_dt_scan_nodes 분석
    + early_init_dt_scan_root
    + early_init_dt_scan_memory
  + kernel/jump_label.c
  + jump_label_init() 분석
+ RCU 이론 스터디
+ commit : a1ee33e2b3f9b76605e8c878df7a822ad1c765bf
------

### 2020년 22주차 스터디
+ 2021년 1월 23일
+ init/main.c start_kernel() 분석 중
  + kernel/jump_label.c
  + jump_label_init() 분석
  + cpus_read_lock() 분석
   + percpu_down_read
+ 이론 스터디
  + spin-lock 
+ commit : 57aac235b4ff8fd2661ab08b5624a63909ea9284
------

### 2020년 23주차 스터디
+ 2021년 1월 30일
+ init/main.c start_kernel() 분석 중
  + kernel/jump_label.c
  + jump_label_init() 분석
   + jump_entry 구조
  + parse_early_param() 분석
+ 이론 스터디
  + spin-lock 및 qspin-lock (MCS lock)
+ commit : 1d16538d546e99a876cbca3dc3eff12bfa3487dd
------

### 2020년 24주차 스터디
+ 2021년 2월 6일
+ init/main.c start_kernel() 분석 중
  + local_daif_restore 분석
  + xen_early_init (생략)
+ 이론 스터디
  + spin-lock 및 qspin-lock (MCS lock)
------

### 2020년 25주차 스터디
+ 2021년 2월 20일
+ 조 통합
+ init/main.c start_kernel() 분석 중
  + kernel/jump_label.c 내 기존 스터디 설명 보충
+ 이론 스터디
  + Cache 및 버퍼, Cache Coherency
------

### 2020년 26주차 스터디
+ 2021년 2월 27일
+ init/main.c start_kernel() 분석 중
  + parse_early_param() 분석
  + local_daif_restore() 분석
+ 이론 스터디
  + Cache 기본 동작
------