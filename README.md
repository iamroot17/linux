
## IAMROOT17A 커널 스터디
### 코드 버전 : mainline 5.9

------

### 1~7주차 스터디
+ 커널 이론 공부 (리눅스 커널 내부 구조)
+ ARM 아키텍처 공부 (코드로 알아보는 ARM 리눅스 커널 2판)
------

### 8주차 스터디
+ 2020년 10월 17일
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_CODE_START_LOCAL(preserve_boot_args)
  + SYM_FUNC_START_PI(__inval_dcache_area)
  + SYM_FUNC_START(el2_setup) 진행중
+ commit : 8b34c33c56ad2cb0cce45a974e078cb993470073
------

### 9주차 스터디
+ 2020년 10월 24일
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_FUNC_START(el2_setup)
  + SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
  + SYM_FUNC_START_LOCAL(__create_page_tables) 진행중
+ commit : a9766d1e06fe2c48e9325cc7212f6b231a9063d4
------

### 10주차 스터디
+ 2020년 10월 31일
+ head.S
  + SYM_CODE_START(primary_entry) 진행중
  + SYM_FUNC_START_LOCAL(__create_page_tables) 진행중
    + .macro compute_indices
    + .macro map_memory
    + .macro populate_entries
    + .macre phys_to_pte
------

### 11주차 스터디
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

### 12주차 스터디
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

### 13주차 스터디
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

### 14주차 스터디
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

### 15주차 스터디
+ 2020년 12월 5일
 + kernel/cgroup/cgroup.c cgroup_init_early() 분석 마무리
  + cgroup의 개념 등 이론적인 부분 추가 분석
  + IDR/IDA 분석
+ commit : a1266cfe8ec347cc5d671ecd822ec9d29dc9ebfa
------

### 16주차 스터디
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

### 17주차 스터디
+ 2020년 12월 19일
+ init/main.c start_kernel() 분석 중
  + early_security_init() 분석
  + arch/arm64/kernel/setup.c setup_arch() 분석 중
    + kaslr_requires_kpit() 분석
    + early_fixmap_init() 분석 중
  + atomic_ops 구현의 static key 기술 분석
+ commit : 261efe3bb57068e0dbf6cefd204d092554bf6fe3
------

### 18주차 스터디
+ 2020년 12월 26일
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + arch/arm64/mm/mmu.c early_fixmap_init() 마무리
+ RCU 이론 스터디
------

### 19주차 스터디
+ 2021년 1월 2일
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + early_ioremap_init() 분석
  + setup_machine_fdt() 분석 중
    + fixmap_remap_fdt() 분석
+ RCU 이론 스터디
------

### 20주차 스터디
+ 2021년 1월 9일
+ arch/arm64/kernel/setup.c setup_machine_fdt() 분석 중
    + memblock_reserve() 분석
    + early_init_dt_scan() 분석 중
    + early_init_dt_scan_chosen() 분석 완료
+ Device Tree 이론 스터디
------

### 21주차 스터디
+ 2021년 1월 16일
+ arch/arm64/kernel/setup.c setup_machine_fdt() 분석
  + early_init_dt_scan_nodes() 분석
    + early_init_dt_scan_root() 분석
    + early_init_dt_scan_memory() 분석
+ kernel/jump_label.c jump_label_init() 분석 중
+ RCU 이론 스터디
+ commit : a1ee33e2b3f9b76605e8c878df7a822ad1c765bf
------

### 22주차 스터디
+ 2021년 1월 23일
+ kernel/jump_label.c jump_label_init() 분석 중
  + cpus_read_lock() 분석
    + percpu_down_read() 분석
+ Spin-lock 이론 스터디
  + 기본 Spin-lock 개념, Ticket-based
+ commit : 57aac235b4ff8fd2661ab08b5624a63909ea9284
------

### 23주차 스터디
+ 2021년 1월 30일
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + kernel/jump_label.c jump_label_init() 분석
    + struct jump_entry 구조
  + parse_early_param() 분석
+ Spin-lock 이론 스터디
  + Qspinlock (mcs lock)
+ commit : 1d16538d546e99a876cbca3dc3eff12bfa3487dd
------

### 24주차 스터디
+ 2021년 2월 6일
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + local_daif_restore() 분석
  + xen_early_init (생략)
+ Spin-lock 이론 스터디
  + Qspinlock (mcs lock)
------

### 25주차 스터디
+ 2021년 2월 20일
+ 조 통합
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + kernel/jump_label.c 기존 스터디 보충
+ Cache 이론 스터디
  + Cache 및 버퍼, Cache Coherency
------

### 26주차 스터디
+ 2021년 2월 27일
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + parse_early_param() 분석
  + local_daif_restore() 분석
+ Cache 이론 스터디
  + Cache 기본 동작
------

### 27주차 스터디
+ 2021년 3월 6일
+ arch/arm64/kernel/setup.c setup_arch() 분석 중
  + xen_early_init() 간략 분석 (빌드 연결 확인)
  + efi_init() 생략 (추후 이론 공부 이후 시도)
  + arm64_memblock_init() 분석 중
+ Cache 이론 스터디
  + Policy, Branch Prediction
------

### 28주차 스터디
+ 2021년 3월 13일
+ arch/arm64/mm/init.c arm64_memblock_init() 분석 중
  + memblock 관련 API, 개념 분석
+ Cache 이론 스터디
  + Barrier
------

### 29주차 스터디
+ 2021년 3월 20일
+ arch/arm64/mm/init.c arm64_memblock_init() 분석 중
  + fdt_enforce_memory_region() 분석
  + 물리 주소 범위, 가상 주소 범위 매핑 관련 분석
  + v5.9 버그, 수정 사항 확인  
    7bc1a0f9e1765830e945669c99c59c35cf9bca82
  + initrd(ramdisk) 확인
+ Bus 이론 스터디
  + PCI, PCIe 하드웨어 구성 및 특성 분석
------

### 30주차 스터디
+ 2021년 3월 27일
+ arch/arm64/mm/init.c arm64_memblock_init() 분석 중
  + early_init_fdt_scan_reserved_mem() 분석
+ Bus 이론 스터디
  + PCIe Link, transaction layer 관련 스터디
------

### 31주차 스터디
+ 2021년 4월 3일
+ arch/arm64/mm/init.c arm64_memblock_init() 분석 중
  + reserve_crashkernel() 분석
+ qspinlock 이론 스터디
  + Queued Spinlock, MCS lock 관련 스터디
------

### 32주차 스터디
+ 2021년 4월 10일
+ arch/arm64/mm/init.c arm64_memblock_init() 분석 중
  + reserve_elfcorehdr() 분석
  + dma_contiguous_reserve() 분석 중
+ qspinlock 이론 스터디
  + Queued Spinlock, MCS lock 관련 스터디
------

### 33주차 스터디
+ 2021년 4월 17일
+ arch/arm64/mm/init.c arm64_memblock_init() 분석
  + cma_declare_contiguous_nid() 분석
+ qspinlock 이론 스터디
  + Queued Spinlock, MCS lock 구조 및 관계
------

### 34주차 스터디
+ 2021년 4월 24일
+ arch/arm64/kernel/setup.c paging init() 분석 중
  + map_kernel_segment() 분석 중
  + __create_pgd_mapping() 분석 중
  + pgd, pud, pmd, pte 테이블 분석 중
+ qspinlock 이론 스터디
  + kernel/locking/qspinlock.c
  + queued_spin_lock_slowpath() 분석
------

### 35주차 스터디
+ 2021년 5월 1일
+ arch/arm64/kernel/setup.c paging init() 분석 중
  + __create_pgd_mapping() 분석 중
  + alloc_init_pud() 분석 중
  + BTI 개념 분석
+ ACPI, ROP 이론 스터디
------

### 36주차 스터디
+ 2021년 5월 8일
+ arch/arm64/kernel/setup.c paging init() 분석 중
  + map_kernel_segment() 분석
  + Contiguous bit와 TLB entry
+ Vmap 이론 스터디
  + 변경 전 RB 트리, 리스트 동작 방식 분석
  + Vmap update (v5.2-rc1)
------