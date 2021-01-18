
## IAMROOT17A Ŀ�� ���͵�
### �ڵ� ���� : mainline 5.9

### 2020�� 8���� ���͵�

+ 2020�� 10�� 17��
+ head.S
  + SYM_CODE_START(primary_entry) ������
  + SYM_CODE_START_LOCAL(preserve_boot_args)
  + SYM_FUNC_START_PI(__inval_dcache_area)
  + SYM_FUNC_START(el2_setup) ������
+ commit : 8b34c33c56ad2cb0cce45a974e078cb993470073
------

### 2020�� 9���� ���͵�
+ 2020�� 10�� 24��
+ head.S
  + SYM_CODE_START(primary_entry) ������
  + SYM_FUNC_START(el2_setup)
  + SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
  + SYM_FUNC_START_LOCAL(__create_page_tables) ������
+ commit : a9766d1e06fe2c48e9325cc7212f6b231a9063d4
------

### 2020�� 10���� ���͵�
+ 2020�� 10�� 31��
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
+ commit : c60091335faba38a0a7d814880586967bb55cf16
------

### 2020�� 14���� ���͵�
+ 2020�� 11�� 28��
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

  + cgroup�� ���� �� �̷����� �κ� �߰� �м�
  + IDR/IDA �м�
+ commit : 27246bf040abce66f3769f9e752a374d73b403af
------

### 2020�� 15���� ���͵�
+ 2020�� 12�� 5��
 + kernel/cgroup/cgroup.c cgroup_init_early() �м� ������
  + cgroup�� ���� �� �̷����� �κ� �߰� �м�
  + IDR/IDA �м�
+ commit : a1266cfe8ec347cc5d671ecd822ec9d29dc9ebfa
------

### 2020�� 16���� ���͵�
+ 2020�� 12�� 12��
+ init/main.c start_kernel() �м� ��
  + local_irq_disable() �м�
  + boot_cpu_init() �м�
  + page_address_init() �м�
  + pr_notice() �м� (linux_banner)
  + ARM64���� ������ atomic operation ���� ���� �м�
   LL/SC, LSE������� ������ atomic operation Ȯ��
   bitops���� ������ CAS(Compare-And-Swap) ��� Ȯ��
+ commit : fd6d33e4da3d349f1e2d3c96eaeab174c7a5a034
------

### 2020�� 17���� ���͵�
+ 2020�� 12�� 19��
+ init/main.c start_kernel() �м� ��
  + early_security_init() �м�
  + setup_arch() �м� ��
  + kaslr_requires_kpit() �м�
  + early_fixmap_init() �м� ��
  + atomic_ops ������ static key ��� �м�
+ commit : 261efe3bb57068e0dbf6cefd204d092554bf6fe3
------

### 2020�� 18���� ���͵�
+ 2020�� 12�� 26��
+ init/main.c start_kernel() �м� ��
  + arch/arm64/mm/mmu.c
  + setup_arch() �� early_fixmap_init() ������
+ RCU �̷� ���͵�
------

### 2020�� 19���� ���͵�
+ 2021�� 1�� 2��
+ init/main.c start_kernel() �м� ��
  + arch/arm64/kernel/setup.c
  + setup_arch() �м�
  + early_ioremap_init() �м�
  + setup_machine_fdt() �м� ��
  + fixmap_remap_fdt() �м�
+ RCU �̷� ���͵�
------

### 2020�� 20���� ���͵�
+ 2021�� 1�� 9��
+ init/main.c start_kernel() �м� ��
  + arch/arm64/kernel/setup.c
  + setup_arch() �м�
  + setup_machine_fdt() �м� ��
  + memblock_reserve() �м�
  + early_init_dt_scan() �м� ��
  + early_init_dt_scan_chosen() �м� �Ϸ�
+ Device Tree �̷� ���͵�
------

### 2020�� 21���� ���͵�
+ 2021�� 1�� 16��
+ init/main.c start_kernel() �м� ��
  + arch/arm64/kernel/setup.c
  + setup_arch() �м�
  + early_init_dt_scan_nodes �м�
    + early_init_dt_scan_root
    + early_init_dt_scan_memory
  + kernel/jump_label.c
  + jump_label_init() �м�
+ RCU �̷� ���͵�
------