
## IAMROOT17A Ŀ�� ���͵�

### 2020�� 8���� ���͵�
+ 2020�� 10�� 17��
+ �ڵ� ���� : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) ������
  + SYM_CODE_START_LOCAL(preserve_boot_args)
  + SYM_FUNC_START_PI(__inval_dcache_area)
  + SYM_FUNC_START(el2_setup) ������
------

### 2020�� 9���� ���͵�
+ 2020�� 10�� 24��
+ �ڵ� ���� : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) ������
  + SYM_FUNC_START(el2_setup)
  + SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
  + SYM_FUNC_START_LOCAL(__create_page_tables) ������
------

### 2020�� 10���� ���͵�
+ 2020�� 10�� 31��
+ �ڵ� ���� : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) ������
  + SYM_FUNC_START_LOCAL(__create_page_tables) ������
    + .macro compute_indices
    + .macro map_memory
    + .macro populate_entries
    + .macre phys_to_pte
------

### 2020�� 11���� ���͵�
+ 2020�� 11�� 7��
+ �ڵ� ���� : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) ������
  + SYM_FUNC_START_LOCAL(__create_page_tables) ������
  
    .macro compute_indices ���� ��ũ
    1. http://www.iamroot.org/xe/index.php?mid=Programming&document_srl=207287
    2. http://jake.dothome.co.kr/head-64/ (compute_indices count �� count -1�� ����ϴ� ����)

  + SYM_FUNC_START(_cpu_setup)
    + MAIR_EL1_SET : 0x00_00_bb_ff_44_0c_04_00 ����
------

### 2020�� 12���� ���͵�
+ 2020�� 11�� 14��
+ �ڵ� ���� : mainline 5.9
+ head.S
  + SYM_CODE_START(primary_entry) ������
    + .macro tcr_compute_pa_size
    + https://stackoverflow.com/questions/53065579/confusion-about-arm-documentation-on-carry-flag(���̳ʽ� ĳ���� ���� ����)

  + SYM_FUNC_START_LOCAL(_primary_switch)
  + SYM_FUNC_START(_enable_mmu)
  + SYM_FUNC_START_LOCAL(_relocate_kernel)
  + SYM_FUNC_START_LOCAL(_primary_switched) ������
------

### 2020�� 13���� ���͵�
+ 2020�� 11�� 21��
+ �ڵ� ���� : mainline 5.9
+ head.S ����
  + SYM_CODE_START_LOCAL(__primary_switched) �м�
  + Exception Vector ����
    + Exception Vector �ڵ� ���� �м�
      
  + BSS �ʱ�ȭ ���� �м�
  + __pi_memset �ɺ� Ȯ��
  + KASLR�� ���� offset ���� ���� �м�
  + kaslr_early_init()
  + KASLR ���/���� ���� start_kernel()�� �����ϴ� ���� �м�
  + KASLR ���� �� MMU ��Ȱ��ȭ �ϰ� init_pg_dir ����� �� relocate Ȯ��
------

### 2020�� 14���� ���͵�
+ 2020�� 11�� 28��
+ �ڵ� ���� : mainline 5.9
+ init/main.c start_kernel() �м� ����
  + init_task �� struct task_struct �м�
  + set_task_stack_end_magic() �м�
  + smp_setup_processor_id() �м�
    + MPIDR_EL1, MIDR_EL1 �м�

  + debug_object_early_init() �м�
  + cgroup_init_early() �м�
    + cgrp_dfl_root�� ���� (DEFINE_PER_CPU �м�)
    + init_cgroup_root() �м�
    + list.h�� INIT_LIST_HEAD���� WRITE_ONCE ��� ���� �м�
  + atomic_set�� architecture dependent ���� �帧 �м�
  + init_cgroup_housekeeping() �м�
    + Ŀ�� �� linked list ������ ���� �м�
    + mutex, spin_lock, optimistic_spin_queue �м�
    + prev_cputime �м�
    + for_each_subsys() ��ũ�� �м�

   + RCU_INIT_POINTER() ��ũ�� �м� ��
------

### 2020�� 14���� ���͵�
+ 2020�� 11�� 28��
+ �ڵ� ���� : mainline 5.9
+ init/main.c start_kernel() �м� ����
  + kernel/cgroup/cgroup.c cgroup_init_early() �м� ������
  + cgroup�� ���� �� �̷����� �κ� �߰� �м�
  + IDR/IDA �м�
------

### 2020�� 16���� ���͵�
+ 2020�� 12�� 12��
+ �ڵ� ���� : mainline 5.9
+ init/main.c start_kernel() �м� ��
  + local_irq_disable() �м�
  + boot_cpu_init() �м�
  + page_address_init() �м�
  + pr_notice() �м� (linux_banner)
  + ARM64���� ������ atomic operation ���� ���� �м�
   LL/SC, LSE������� ������ atomic operation Ȯ��
   bitops���� ������ CAS(Compare-And-Swap) ��� Ȯ��
  + ���� �ּ� ����� ����
------


