/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Low-level CPU initialisation
 * Based on arch/arm/kernel/head.S
 *
 * Copyright (C) 1994-2002 Russell King
 * Copyright (C) 2003-2012 ARM Ltd.
 * Authors:	Catalin Marinas <catalin.marinas@arm.com>
 *		Will Deacon <will.deacon@arm.com>
 */

#include <linux/linkage.h>
#include <linux/init.h>
#include <linux/pgtable.h>

#include <asm/asm_pointer_auth.h>
#include <asm/assembler.h>
#include <asm/boot.h>
#include <asm/bug.h>
#include <asm/ptrace.h>
#include <asm/asm-offsets.h>
#include <asm/cache.h>
#include <asm/cputype.h>
#include <asm/el2_setup.h>
#include <asm/elf.h>
#include <asm/image.h>
#include <asm/kernel-pgtable.h>
#include <asm/kvm_arm.h>
#include <asm/memory.h>
#include <asm/pgtable-hwdef.h>
#include <asm/page.h>
#include <asm/scs.h>
#include <asm/smp.h>
#include <asm/sysreg.h>
#include <asm/thread_info.h>
#include <asm/virt.h>

#include "efi-header.S"

/*; Iamroot17A 2020.Oct.24
 *; 초기 TEXT_OFFSET은 512KB였음. (아마도 ARM32에서 porting한 부분으로 예상)
 *; 해당 512KB를 BSS 영역의 크기로 할당해서 사용했었으나, 현재 무의미해졌음.
 *; KASLR 도입 과정에서 relocatable kernel 개념을 적용하면서 커널의 물리 주소가
 *; 중요하지 않게 됨. (segment align만 잘 맞으면 되는데, 보통 64KB를 기준으로
 *; 하기 때문에 512KB나 0이나 align이 맞게 됨.)
 *; >> 관련 commit: cfa7ede20f133cc81cef01dc3a516dda3a9721ee
 *; 이전에는 빌드 타임에 무작위로 TEXT_OFFSET을 변경하는 config가 존재했는데,
 *; 현재 커널 이미지를 2MB로 정렬하므로, 무의미해져 해당 config가 제거됨.
 *; >> 관련 commit: 751c263bb74fd36b5fc2589d36abc75042336444
 *; ==v5.9 당시 하위호환성을 위해 TEXT_OFFSET 계산이 있었음==
 *; 그때 당시에도 TEXT_OFFSET이 0으로 변경되었으므로, 리팩토링되었다 볼 수 있음
 *; */
/*; #define __PHYS_OFFSET	(KERNEL_START - TEXT_OFFSET) */
#define __PHYS_OFFSET	KERNEL_START

#if (PAGE_OFFSET & 0x1fffff) != 0
#error PAGE_OFFSET must be at least 2MB aligned
#endif

/*; Iamroot17A 2020.Oct.17
 *; 여기가 bootloader 이후 커널의 최초 진입 지점이라 볼 수 있다.
 *; */
/*
 * Kernel startup entry point.
 * ---------------------------
 *
 * The requirements are:
 *   MMU = off, D-cache = off, I-cache = on or off,
 *   x0 = physical address to the FDT blob.
 *
 * This code is mostly position independent so you call this at
 * __pa(PAGE_OFFSET).
 *
 * Note that the callee-saved registers are used for storing variables
 * that are useful before the MMU is enabled. The allocations are described
 * in the entry routines.
 */
	__HEAD
	/*
	 * DO NOT MODIFY. Image header expected by Linux boot-loaders.
	 */
	efi_signature_nop			// special NOP to identity as PE/COFF executable
	b	primary_entry			// branch to kernel start, magic
	.quad	0				// Image load offset from start of RAM, little-endian
	le64sym	_kernel_size_le			// Effective size of kernel image, little-endian
	le64sym	_kernel_flags_le		// Informative flags, little-endian
	.quad	0				// reserved
	.quad	0				// reserved
	.quad	0				// reserved
	.ascii	ARM64_IMAGE_MAGIC		// Magic number
	/*; Iamroot17A 2020.Oct.17
	 *; UEFI가 동작하는 PE(Portable Executable) 실행파일 형식을 제공하기
	 *; 위해서는 PE Header 시작 전에 64bytes의 DOS header가 필요함.
	 *; PE는 Windows 3.1부터 지원되기 시작했는데, 이때 하위호환성
	 *; (This program cannot be run in DOS mode. 출력)을 위해
	 *; 기존의 DOS MZ header로 시작하였다.
	 *; 현대 PE header 해석을 위해서는 "MZ" magic number 검증과,
	 *; PE의 시작점 offset 확인을 위한 [0x3C, 0x3F] 4byte의 값만 확인한다.
	 *; "pe_header" label과 "_head" label 간의 offset 차이는 현재 0x3C이다.
	 *;
	 *; https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files 참고
	 *; https://en.wikipedia.org/wiki/Portable_Executable 그림 참고
	 *; */
	.long	.Lpe_header_offset		// Offset to the PE header.

	__EFI_PE_HEADER

	/*; Iamroot17A 2020.Oct.17
	 *; 실제 실행 코드는 여기서부터 진행되며, 결론적으로 최초 진입 지점은
	 *; "primary_entry"라고 볼 수 있다. (기존 "stext"에서 변경됨)
	 *; */
	__INIT

	/*
	 * The following callee saved general purpose registers are used on the
	 * primary lowlevel boot path:
	 *
	 *  Register   Scope                      Purpose
	 *  x21        primary_entry() .. start_kernel()        FDT pointer passed at boot in x0
	 *  x23        primary_entry() .. start_kernel()        physical misalignment/KASLR offset
	 *  x28        __create_page_tables()                   callee preserved temp register
	 *  x19/x20    __primary_switch()                       callee preserved temp registers
	 *  x24        __primary_switch() .. relocate_kernel()  current RELR displacement
	 */
SYM_CODE_START(primary_entry)
	/*; Iamroot17A 2020.Oct.17
	 *; bl: Branch with Link, 다음 실행할 명령어의 PC(Program Counter)의
	 *; 값을 LR(Link Register, ARM64에서는 X30)에 저장하고 argument 위치로
	 *; 분기하는 명령어, ret명령을 통해 LR에 저장된 위치로 복귀 가능
	 *; */
	bl	preserve_boot_args
	bl	init_kernel_el			// w0=cpu_boot_mode
	/*; Iamroot17A 2020.Oct.24
	 *; 커널 이미지의 재배치를 위한 offset의 값을 X23에 저장한다.
	 *; 추후 해당 값은 KASLR(Kernel Address Space Layout Randomization)의
	 *; offset으로 변형되는데, 지금은 기본적인 offset으로 설정한다고
	 *; 생각하면 된다. (과거엔 __PHYS_OFFSET이 의미있었으나 지금은
	 *; 커널 이미지 재배치로 인해 의미가 거의 없어진 상태다.)
	 *; 커널 이미지는 2MB 단위로 align되어야 한다. (MIN_KIMG_ALIGN == SZ_2M)
	 *; X23은 __create_page_tables에서 참조하는데 왜 먼저 수정하는지 의문
	 *; */
	adrp	x23, __PHYS_OFFSET
	and	x23, x23, MIN_KIMG_ALIGN - 1	// KASLR offset, defaults to 0
	bl	set_cpu_boot_mode_flag
	bl	__create_page_tables
	/*
	 * The following calls CPU setup code, see arch/arm64/mm/proc.S for
	 * details.
	 * On return, the CPU will be ready for the MMU to be turned on and
	 * the TCR will have been set.
	 */
	bl	__cpu_setup			// initialise processor
	b	__primary_switch
SYM_CODE_END(primary_entry)

/*
 * Preserve the arguments passed by the bootloader in x0 .. x3
 */
SYM_CODE_START_LOCAL(preserve_boot_args)
	/*; Iamroot17A 2020.Oct.17
	 *; FDT(dtb;Device Tree Blob)의 물리 주소
	 *; 추후 변수를 저장할 boot_args의 주소가 X0에 할당되므로 미리 X21로
	 *; 옮기는 작업을 수행함.
	 *; */
	mov	x21, x0				// x21=FDT

	/*; Iamroot17A 2020.Oct.17
	 *; ADR: PC의 상대 주소를 기반으로 load한다. 왜 상대 주소를 기준으로
	 *; 하냐면, 리눅스 커널은 PIC(Position Independent Code)로 동작하는데,
	 *; "Bootloader가 올린 커널의 물리메모리 상의 위치"와
	 *; "커널이 가정하는 커널의 가상 주소 공간"이 다를 수도 있기 때문에
	 *; MMU가 활성화 되기 전까지는 LDR대신 ADR을 사용해야 한다.
	 *; (함수나 변수 주소 등 symbol에 해당하는 값을 읽을때)
	 *; */
	adr_l	x0, boot_args			// record the contents of
	stp	x21, x1, [x0]			// x0 .. x3 at kernel entry
	stp	x2, x3, [x0, #16]

	/*; Iamroot17A 2020.Oct.17
	 *; "dmb": Data Memory Barrier, 해당 명령어 전후로 메모리 접근 순서 분리
	 *; "sy": System Sharable, 시스템 전체
	 *; dmb는 캐시가 아니라 메모리 버퍼를 flush시킴. 즉 메모리에 대한
	 *; 확실한 write를 하기 위해 수행함. 메모리에 기록하는 것을 확실하게
	 *; 보장하기 위해 실행한다고 생각하면 됨.
	 *; */
	dmb	sy				// needed before dc ivac with
						// MMU off

	/*; Iamroot17A 2020.Oct.17
	 *; "dcache_inval_poc" 호출 시, 기본 인자로 X0, X1을 사용한다.
	 *; "X0": invalidate할 D-cache의 시작 주소
	 *; "X1": invalidate할 D-cache의 끝 주소
	 *; 이미 X0의 주소는 boot_args를 가리키고 있으므로, X1에 boot_args의
	 *; 크기인 0x20 (4 * 8 bytes)만큼 더한다.
	 *; ==v5.9의 경우, `__inval_dcache_area` 를 사용했으나, 리팩토링됨==
	 *; "__inval_dcache_area" 호출 시, 기본 인자로 X0, X1을 사용한다.
	 *; "X0": invalidate할 D-cache의 시작 주소
	 *; "X1": invalidate할 D-cache의 크기
	 *; 이미 X0의 주소는 boot_args를 가리키고 있으므로, X1만 수정한다.
	 *; */
	add	x1, x0, #0x20			// 4 x 8 bytes
	/*; Iamroot17A 2020.Oct.17
	 *; Boot시의 CPU 조건이 d-cache가 꺼져있는 상태임에도 해당 영역을
	 *; 비우는 이유는 추후 MMU가 켜진 뒤 Clean & invalidate 시 잘못된
	 *; 데이터가 반영되는 것을 막기 위함이다.
	 *; */
	b	dcache_inval_poc		// tail call
	/*; Iamroot17A 2020.Oct.17
	 *; 원래 해당 Procedure가 종료되고 원래 caller(primary_entry)의 위치로
	 *; 돌아가려면 "ret" instruction을 사용해야 한다.
	 *; 게다가 현재 call stack을 사용하고 있지 않으므로, return address는
	 *; 다른 변수에 임시 저장되어야 한다. 하지만 "__inval_dcache_area"
	 *; 내부에서 "ret"를 호출하므로 여기에선 생략했다.
	 *; 만약 tail call 최적화가 없으면 이런 식으로 구성되어야 한다.
	 *;	add	x1, x0, #0x20
	 *;	bl	dcache_inval_poc
	 *;	ret	x2
	 *; https://en.wikipedia.org/wiki/Tail_call 참고
	 *; */
SYM_CODE_END(preserve_boot_args)

/*
 * Macro to create a table entry to the next page.
 *
 *	tbl:	page table address
 *	virt:	virtual address
 *	shift:	#imm page table shift
 *	ptrs:	#imm pointers per table page
 *
 * Preserves:	virt
 * Corrupts:	ptrs, tmp1, tmp2
 * Returns:	tbl -> next level table page address
 */
	.macro	create_table_entry, tbl, virt, shift, ptrs, tmp1, tmp2
	add	\tmp1, \tbl, #PAGE_SIZE
	phys_to_pte \tmp2, \tmp1
	orr	\tmp2, \tmp2, #PMD_TYPE_TABLE	// address of next table and entry type
	lsr	\tmp1, \virt, #\shift
	sub	\ptrs, \ptrs, #1
	and	\tmp1, \tmp1, \ptrs		// table index
	str	\tmp2, [\tbl, \tmp1, lsl #3]
	add	\tbl, \tbl, #PAGE_SIZE		// next level table page
	.endm

/*
 * Macro to populate page table entries, these entries can be pointers to the next level
 * or last level entries pointing to physical memory.
 *
 *	tbl:	page table address
 *	rtbl:	pointer to page table or physical memory
 *	index:	start index to write
 *	eindex:	end index to write - [index, eindex] written to
 *	flags:	flags for pagetable entry to or in
 *	inc:	increment to rtbl between each entry
 *	tmp1:	temporary variable
 *
 * Preserves:	tbl, eindex, flags, inc
 * Corrupts:	index, tmp1
 * Returns:	rtbl
 */
	.macro populate_entries, tbl, rtbl, index, eindex, flags, inc, tmp1
.Lpe\@:	phys_to_pte \tmp1, \rtbl
	orr	\tmp1, \tmp1, \flags	// tmp1 = table entry
	str	\tmp1, [\tbl, \index, lsl #3]
	add	\rtbl, \rtbl, \inc	// rtbl = pa next level
	add	\index, \index, #1
	cmp	\index, \eindex
	b.ls	.Lpe\@
	.endm

/*
 * Compute indices of table entries from virtual address range. If multiple entries
 * were needed in the previous page table level then the next page table level is assumed
 * to be composed of multiple pages. (This effectively scales the end index).
 *
 *	vstart:	virtual address of start of range
 *	vend:	virtual address of end of range - we map [vstart, vend]
 *	shift:	shift used to transform virtual address into index
 *	ptrs:	number of entries in page table
 *	istart:	index in table corresponding to vstart
 *	iend:	index in table corresponding to vend
 *	count:	On entry: how many extra entries were required in previous level, scales
 *			  our end index.
 *		On exit: returns how many extra entries required for next page table level
 *
 * Preserves:	vstart, vend, shift, ptrs
 * Returns:	istart, iend, count
 */
	.macro compute_indices, vstart, vend, shift, ptrs, istart, iend, count
	lsr	\iend, \vend, \shift
	mov	\istart, \ptrs
	sub	\istart, \istart, #1
	and	\iend, \iend, \istart	// iend = (vend >> shift) & (ptrs - 1)
	mov	\istart, \ptrs
	mul	\istart, \istart, \count
	add	\iend, \iend, \istart	// iend += count * ptrs
					// our entries span multiple tables

	lsr	\istart, \vstart, \shift
	mov	\count, \ptrs
	sub	\count, \count, #1
	and	\istart, \istart, \count

	sub	\count, \iend, \istart
	.endm

/*
 * Map memory for specified virtual address range. Each level of page table needed supports
 * multiple entries. If a level requires n entries the next page table level is assumed to be
 * formed from n pages.
 *
 *	tbl:	location of page table
 *	rtbl:	address to be used for first level page table entry (typically tbl + PAGE_SIZE)
 *	vstart:	virtual address of start of range
 *	vend:	virtual address of end of range - we map [vstart, vend - 1]
 *	flags:	flags to use to map last level entries
 *	phys:	physical address corresponding to vstart - physical memory is contiguous
 *	pgds:	the number of pgd entries
 *
 * Temporaries:	istart, iend, tmp, count, sv - these need to be different registers
 * Preserves:	vstart, flags
 * Corrupts:	tbl, rtbl, vend, istart, iend, tmp, count, sv
 */
	.macro map_memory, tbl, rtbl, vstart, vend, flags, phys, pgds, istart, iend, tmp, count, sv
	sub \vend, \vend, #1
	add \rtbl, \tbl, #PAGE_SIZE
	mov \sv, \rtbl
	mov \count, #0
	compute_indices \vstart, \vend, #PGDIR_SHIFT, \pgds, \istart, \iend, \count
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv
	mov \sv, \rtbl

#if SWAPPER_PGTABLE_LEVELS > 3
	compute_indices \vstart, \vend, #PUD_SHIFT, #PTRS_PER_PUD, \istart, \iend, \count
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv
	mov \sv, \rtbl
#endif

#if SWAPPER_PGTABLE_LEVELS > 2
	compute_indices \vstart, \vend, #SWAPPER_TABLE_SHIFT, #PTRS_PER_PMD, \istart, \iend, \count
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv
#endif

	compute_indices \vstart, \vend, #SWAPPER_BLOCK_SHIFT, #PTRS_PER_PTE, \istart, \iend, \count
	bic \count, \phys, #SWAPPER_BLOCK_SIZE - 1
	populate_entries \tbl, \count, \istart, \iend, \flags, #SWAPPER_BLOCK_SIZE, \tmp
	.endm

/*
 * Setup the initial page tables. We only setup the barest amount which is
 * required to get the kernel running. The following sections are required:
 *   - identity mapping to enable the MMU (low address, TTBR0)
 *   - first few MB of the kernel linear mapping to jump to once the MMU has
 *     been enabled
 */
SYM_FUNC_START_LOCAL(__create_page_tables)
	mov	x28, lr

	/*
	 * Invalidate the init page tables to avoid potential dirty cache lines
	 * being evicted. Other page tables are allocated in rodata as part of
	 * the kernel image, and thus are clean to the PoC per the boot
	 * protocol.
	 */
	adrp	x0, init_pg_dir
	adrp	x1, init_pg_end
	bl	dcache_inval_poc

	/*
	 * Clear the init page tables.
	 */
	adrp	x0, init_pg_dir
	adrp	x1, init_pg_end
	sub	x1, x1, x0
1:	stp	xzr, xzr, [x0], #16
	stp	xzr, xzr, [x0], #16
	stp	xzr, xzr, [x0], #16
	stp	xzr, xzr, [x0], #16
	subs	x1, x1, #64
	b.ne	1b

	mov	x7, SWAPPER_MM_MMUFLAGS

	/*
	 * Create the identity mapping.
	 */
	adrp	x0, idmap_pg_dir
	adrp	x3, __idmap_text_start		// __pa(__idmap_text_start)

#ifdef CONFIG_ARM64_VA_BITS_52
	mrs_s	x6, SYS_ID_AA64MMFR2_EL1
	and	x6, x6, #(0xf << ID_AA64MMFR2_LVA_SHIFT)
	mov	x5, #52
	cbnz	x6, 1f
#endif
	mov	x5, #VA_BITS_MIN
1:
	adr_l	x6, vabits_actual
	str	x5, [x6]
	dmb	sy
	dc	ivac, x6		// Invalidate potentially stale cache line

	/*
	 * VA_BITS may be too small to allow for an ID mapping to be created
	 * that covers system RAM if that is located sufficiently high in the
	 * physical address space. So for the ID map, use an extended virtual
	 * range in that case, and configure an additional translation level
	 * if needed.
	 *
	 * Calculate the maximum allowed value for TCR_EL1.T0SZ so that the
	 * entire ID map region can be mapped. As T0SZ == (64 - #bits used),
	 * this number conveniently equals the number of leading zeroes in
	 * the physical address of __idmap_text_end.
	 */
	adrp	x5, __idmap_text_end
	clz	x5, x5
	cmp	x5, TCR_T0SZ(VA_BITS_MIN) // default T0SZ small enough?
	b.ge	1f			// .. then skip VA range extension

	adr_l	x6, idmap_t0sz
	str	x5, [x6]
	dmb	sy
	dc	ivac, x6		// Invalidate potentially stale cache line

#if (VA_BITS < 48)
#define EXTRA_SHIFT	(PGDIR_SHIFT + PAGE_SHIFT - 3)
#define EXTRA_PTRS	(1 << (PHYS_MASK_SHIFT - EXTRA_SHIFT))

	/*
	 * If VA_BITS < 48, we have to configure an additional table level.
	 * First, we have to verify our assumption that the current value of
	 * VA_BITS was chosen such that all translation levels are fully
	 * utilised, and that lowering T0SZ will always result in an additional
	 * translation level to be configured.
	 */
#if VA_BITS != EXTRA_SHIFT
#error "Mismatch between VA_BITS and page size/number of translation levels"
#endif

	mov	x4, EXTRA_PTRS
	create_table_entry x0, x3, EXTRA_SHIFT, x4, x5, x6
#else
	/*
	 * If VA_BITS == 48, we don't have to configure an additional
	 * translation level, but the top-level table has more entries.
	 */
	mov	x4, #1 << (PHYS_MASK_SHIFT - PGDIR_SHIFT)
	str_l	x4, idmap_ptrs_per_pgd, x5
#endif
1:
	ldr_l	x4, idmap_ptrs_per_pgd
	adr_l	x6, __idmap_text_end		// __pa(__idmap_text_end)

	map_memory x0, x1, x3, x6, x7, x3, x4, x10, x11, x12, x13, x14

	/*
	 * Map the kernel image (starting with PHYS_OFFSET).
	 */
	adrp	x0, init_pg_dir
	mov_q	x5, KIMAGE_VADDR		// compile time __va(_text)
	add	x5, x5, x23			// add KASLR displacement
	mov	x4, PTRS_PER_PGD
	adrp	x6, _end			// runtime __pa(_end)
	adrp	x3, _text			// runtime __pa(_text)
	sub	x6, x6, x3			// _end - _text
	add	x6, x6, x5			// runtime __va(_end)

	map_memory x0, x1, x5, x6, x7, x3, x4, x10, x11, x12, x13, x14

	/*
	 * Since the page tables have been populated with non-cacheable
	 * accesses (MMU disabled), invalidate those tables again to
	 * remove any speculatively loaded cache lines.
	 */
	dmb	sy

	adrp	x0, idmap_pg_dir
	adrp	x1, idmap_pg_end
	bl	dcache_inval_poc

	adrp	x0, init_pg_dir
	adrp	x1, init_pg_end
	bl	dcache_inval_poc

	ret	x28
SYM_FUNC_END(__create_page_tables)

	/*
	 * Initialize CPU registers with task-specific and cpu-specific context.
	 *
	 * Create a final frame record at task_pt_regs(current)->stackframe, so
	 * that the unwinder can identify the final frame record of any task by
	 * its location in the task stack. We reserve the entire pt_regs space
	 * for consistency with user tasks and kthreads.
	 */
	.macro	init_cpu_task tsk, tmp1, tmp2
	msr	sp_el0, \tsk

	ldr	\tmp1, [\tsk, #TSK_STACK]
	add	sp, \tmp1, #THREAD_SIZE
	sub	sp, sp, #PT_REGS_SIZE

	stp	xzr, xzr, [sp, #S_STACKFRAME]
	add	x29, sp, #S_STACKFRAME

	scs_load \tsk

	adr_l	\tmp1, __per_cpu_offset
	ldr	w\tmp2, [\tsk, #TSK_CPU]
	ldr	\tmp1, [\tmp1, \tmp2, lsl #3]
	set_this_cpu_offset \tmp1
	.endm

/*
 * The following fragment of code is executed with the MMU enabled.
 *
 *   x0 = __PHYS_OFFSET
 */
SYM_FUNC_START_LOCAL(__primary_switched)
	adr_l	x4, init_task
	init_cpu_task x4, x5, x6

	adr_l	x8, vectors			// load VBAR_EL1 with virtual
	msr	vbar_el1, x8			// vector table address
	isb

	stp	x29, x30, [sp, #-16]!
	mov	x29, sp

	str_l	x21, __fdt_pointer, x5		// Save FDT pointer

	ldr_l	x4, kimage_vaddr		// Save the offset between
	sub	x4, x4, x0			// the kernel virtual and
	str_l	x4, kimage_voffset, x5		// physical mappings

	// Clear BSS
	adr_l	x0, __bss_start
	mov	x1, xzr
	adr_l	x2, __bss_stop
	sub	x2, x2, x0
	bl	__pi_memset
	dsb	ishst				// Make zero page visible to PTW

#if defined(CONFIG_KASAN_GENERIC) || defined(CONFIG_KASAN_SW_TAGS)
	bl	kasan_early_init
#endif
	mov	x0, x21				// pass FDT address in x0
	bl	early_fdt_map			// Try mapping the FDT early
	bl	init_feature_override		// Parse cpu feature overrides
#ifdef CONFIG_RANDOMIZE_BASE
	tst	x23, ~(MIN_KIMG_ALIGN - 1)	// already running randomized?
	b.ne	0f
	bl	kaslr_early_init		// parse FDT for KASLR options
	cbz	x0, 0f				// KASLR disabled? just proceed
	orr	x23, x23, x0			// record KASLR offset
	ldp	x29, x30, [sp], #16		// we must enable KASLR, return
	ret					// to __primary_switch()
0:
#endif
	bl	switch_to_vhe			// Prefer VHE if possible
	ldp	x29, x30, [sp], #16
	bl	start_kernel
	ASM_BUG()
SYM_FUNC_END(__primary_switched)

	.pushsection ".rodata", "a"
SYM_DATA_START(kimage_vaddr)
	.quad		_text
SYM_DATA_END(kimage_vaddr)
EXPORT_SYMBOL(kimage_vaddr)
	.popsection

/*
 * end early head section, begin head code that is also used for
 * hotplug and needs to have the same protections as the text region
 */
	.section ".idmap.text","awx"

/*
 * Starting from EL2 or EL1, configure the CPU to execute at the highest
 * reachable EL supported by the kernel in a chosen default state. If dropping
 * from EL2 to EL1, configure EL2 before configuring EL1.
 *
 * Since we cannot always rely on ERET synchronizing writes to sysregs (e.g. if
 * SCTLR_ELx.EOS is clear), we place an ISB prior to ERET.
 *
 * Returns either BOOT_CPU_MODE_EL1 or BOOT_CPU_MODE_EL2 in w0 if
 * booted in EL1 or EL2 respectively.
 */
/*; Iamroot17A 2020.Oct.17
 *; ==v5.9 당시 el2_setup이었으나, init_kernel_el로 리팩토링됨==
 *; */
/*; SYM_FUNC_START(el2_setup) */
SYM_FUNC_START(init_kernel_el)
	/*; Iamroot17A 2020.Oct.17
	 *; 현재 Exception Level을 가져와서, 해당 값이 EL2일 경우 EL2에 맞게
	 *; 코드 실행, 아닐 경우 EL1에 맞게 수행하고 현재 procedure 종료.
	 *; */
	mrs	x0, CurrentEL
	cmp	x0, #CurrentEL_EL2
	/*; Iamroot17A 2020.Oct.17
	 *; ==v5.9 당시 SYM_INNER_LABEL 방식을 사용하지 않았음==
	 *; 이전에는 EL2 처리에 대한 label은 1f였음 */
	b.eq	init_el2

SYM_INNER_LABEL(init_el1, SYM_L_LOCAL)
	/*; Iamroot17A 2020.Oct.24
	 *; EL1의 SCTLR에 MMU가 꺼진 상태의 초기 값을 설정한다.
	 *; SCTLR: System Control Register
	 *; ==v5.9 당시 각 설정 플래그를 bitwise-or 하였으나, 리팩토링됨==
	 *; SCTLR_EL1에 32-bit mode에 대한 endianness를 설정한다. (64-bit은
	 *; Little-endian으로 고정됨.) RES1은 SCTLR_EL1의 field bit 중
	 *; reserved 값 중 기본 값을 1로 설정한 field들을 말한다. (추후 해당
	 *; field가 다른 용도로 사용될 것을 고려하여 RES0 혹은 RES1을 결정.)
	 *; 일부 RES1 필드는 ARMv8.x extension에서 사용된다.
	 *; 상수 값인 64-bit를 직접 MSR로 집어넣지 못하기 때문에 X0에 넣으며,
	 *; X0에도 64-bit를 직접 집어넣지 못하므로 mov_q 매크로를 사용한다.
	 *; */
	/*; mov_q	x0, (SCTLR_EL1_RES1 | ENDIAN_SET_EL1) */
	mov_q	x0, INIT_SCTLR_EL1_MMU_OFF
	msr	sctlr_el1, x0
	/*; Iamroot17A 2020.Oct.24
	 *; ISB: Instruction Synchronization Barrier
	 *; 해당 명령어를 경계로 이전의 Instruction이 모두 수행되게 한다.
	 *; (미리 pipeline되어 있던 아래쪽 Instruction들을 모두 flush 시킴.)
	 *; Context change operation 수행 시 호출되는 경우가 대표적.
	 *; 현재 Head.S 기준으로는 MSR로 특정 설정을 변경했을 때, 이를
	 *; 반영하지 않은 Instruction들이 수행되는 것을 막기 위해 barrier를
	 *; 거는 것으로 보임.
	 *; */
	isb
	/*; Iamroot17A 2020.Oct.17
	 *; SPsel의 값을 직접 변경하는 것이 아닌, SPSR(변경 가능한 PSTATE)에서
	 *; EL1의 SP를 사용하도록 설정한다.
	 *; PSTATE의 일부 비트 상태가 보장되지 않으므로, 안정적으로 초기화함
	 *; PSTATE: Processor STATE, ARMv8에서는 직접 R/W가 불가
	 *; SPSR: Saved Program Status Register
	 *; x86의 FLAGS 레지스터처럼 ALU 플래그, 실행환경 등을 표현
	 *; >> 관련 commit: d87a8e65b5101123a24cddeb7a8a2c7b45f7b60c
	 *; ==v5.9 당시 SPsel을 직접 변경함==
	 *; SPsel 레지스터의 설정 값을 1로 변경 (스택 포인터로 EL0를 쓸 것인지,
	 *; 혹은 EL1/EL2를 사용할 것인지 선택)
	 *; */
	/*; msr	SPsel, #1			// We want to use SP_EL{1,2}*/
	mov_q	x0, INIT_PSTATE_EL1
	msr	spsr_el1, x0
	/*; Iamroot17A 2020.Oct.17
	 *; 이후 설정된 SPSR이 PSTATE에 반영되도록 eret으로 반환함
	 *; ELR: Exception Link Register, exception이 끝나고 돌아갈 address
	 *; ==v5.9 당시 SPsel을 직접 수정, ret으로 반환==
	 *; */
	/*; ret */
	msr	elr_el1, lr
	/*; Iamroot17A 2020.Oct.24
	 *; init_kernel_el에서 최종적으로 W0에 선택될 Exception Level을
	 *; 반환해야 한다. (현재 EL1으로 선택되었으므로, BOOT_CPU_MODE_EL1 선택)
	 *; */
	mov	w0, #BOOT_CPU_MODE_EL1
	eret

/*; Iamroot17A 2020.Oct.17
 *; 본 분석에서는 EL2 (Hypervisor mode)로 동작하는 흐름은 분석하지
 *; 않는다. 단, EL1에서 처리하는 코드와 같은 내용이 어디에서 처리되는지
 *; 유사한 흐름을 확인하기 위한 분석은 수행한다.
 *; */
SYM_INNER_LABEL(init_el2, SYM_L_LOCAL)
	mov_q	x0, HCR_HOST_NVHE_FLAGS
	msr	hcr_el2, x0
	isb

	init_el2_state

	/* Hypervisor stub */
	adr_l	x0, __hyp_stub_vectors
	msr	vbar_el2, x0
	isb

	/*
	 * Fruity CPUs seem to have HCR_EL2.E2H set to RES1,
	 * making it impossible to start in nVHE mode. Is that
	 * compliant with the architecture? Absolutely not!
	 */
	mrs	x0, hcr_el2
	and	x0, x0, #HCR_E2H
	/*; Iamroot17A 2020.Oct.24
	 *; VHE (Virtualization Host Extension) mode에서 특정 CPU가 갇히는
	 *; 문제를 해결하고자 SCTLR과 SPSR을 다시 설정하는 흐름이 추가됨
	 *; (정상 흐름은 1f 레이블로 이동)
	 *; (참고로 이렇게 복잡해진 부분은 Apple M1에서 문제가 확인되었기 때문)
	 *; >> 관련 commit: 31a32b49b80f79cbb84a9c948c5609c6fc044443
	 *; */
	cbz	x0, 1f

	/* Switching to VHE requires a sane SCTLR_EL1 as a start */
	mov_q	x0, INIT_SCTLR_EL1_MMU_OFF
	msr_s	SYS_SCTLR_EL12, x0

	/*
	 * Force an eret into a helper "function", and let it return
	 * to our original caller... This makes sure that we have
	 * initialised the basic PSTATE state.
	 */
	/*; Iamroot17A 2020.Oct.17
	 *; EL1의 흐름과 같이, SPSR(변경 가능한 PSTATE)에서 EL2의 SP를
	 *; 사용하도록 설정한다.
	 *; 현재 Exception Level이 1이라고 생각하여 spsr_el1을 변경
	 *; */
	mov	x0, #INIT_PSTATE_EL2
	msr	spsr_el1, x0
	/*; Iamroot17A 2020.Oct.17
	 *; 반환 방식은 EL1에서 본 것과 같이 eret으로 반환함
	 *; 단, LR로 eret을 하는 것이 아닌, helper function으로 이동함
	 *; 추후 hvc (hypervisor call)이 있어, 변경된 것으로 보임
	 *; 원래 돌아가야 할 LR은 __cpu_stick_to_vhe에서 ret할 때 사용됨
	 *; */
	adr	x0, __cpu_stick_to_vhe
	msr	elr_el1, x0
	eret

1:
	/*; Iamroot17A 2020.Oct.24
	 *; 이전 리팩토링을 통해, SCTLR 설정은 EL1이던, EL2이던 동일하게
	 *; SCTLR_EL1을 변경하는 것이었음. (M1 문제가 없을 경우 정상 흐름)
	 *; ==v5.9에서는 SCTLR_EL2의 초기값으로 SCTLR_EL2를 변경함==
	 *; EL1의 경우와 동일하게 SCTLR_EL2에 32-bit mode에 대한 endianness를
	 *; 설정한다. 또한 똑같이 EL2에 대한 RES1을 설정한다.
	 *; */
	/*; mov_q	x0, (SCTLR_EL2_RES1 | ENDIAN_SET_EL2) */
	/*; msr	sctlr_el2, x0 */
	mov_q	x0, INIT_SCTLR_EL1_MMU_OFF
	msr	sctlr_el1, x0

	/*; Iamroot17A 2020.Oct.17
	 *; 반환 방식은 EL1에서 본 것과 같이 eret으로 반환함
	 *; 이전에는 현 위치에 SPSR을 변경하는 코드가 있었느나, 리팩토링에서
	 *; 사라졌으며, 아마 init_el2_state 내부에서 수행되었을 것으로 예상됨
	 *; 현재 Exception Level이 2라고 생각하여 elr_el2를 lr로 변경
	 *; */
	msr	elr_el2, lr
	/*; Iamroot17A 2020.Oct.24
	 *; init_kernel_el에서 최종적으로 W0에 선택될 Exception Level을
	 *; 반환해야 한다. (현재 EL2로 선택되었으므로, BOOT_CPU_MODE_EL2 선택)
	 *; */
	mov	w0, #BOOT_CPU_MODE_EL2
	eret

__cpu_stick_to_vhe:
	mov	x0, #HVC_VHE_RESTART
	hvc	#0
	/*; Iamroot17A 2020.Oct.24
	 *; init_kernel_el에서 최종적으로 X0에 선택될 Exception Level을
	 *; 반환해야 한다. (현재 EL2로 선택되었으므로, BOOT_CPU_MODE_EL2 선택)
	 *; */
	mov	x0, #BOOT_CPU_MODE_EL2
	ret
SYM_FUNC_END(init_kernel_el)

/*
 * Sets the __boot_cpu_mode flag depending on the CPU boot mode passed
 * in w0. See arch/arm64/include/asm/virt.h for more info.
 */
SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
	/*; Iamroot17A 2020.Oct.24
	 *; __boot_cpu_mode 주소를 X1에 읽어온다. (정확히는 __boot_cpu_mode[0])
	 *; */
	adr_l	x1, __boot_cpu_mode
	/*; Iamroot17A 2020.Oct.24
	 *; W0(이전의 el2_setup에서 수정한 현재 Boot Exception Level)이
	 *; EL1인 경우 현재 X1이 가진 주소를 그대로 유지 (__boot_cpu_mode[0])
	 *; EL2인 경우 X1의 주소에서 += 4byte를 한다. (__boot_cpu_mode[1])
	 *; (__boot_cpu_mode를 현재 Boot Exception Level로 통일하려 함)
	 *; */
	cmp	w0, #BOOT_CPU_MODE_EL2
	b.ne	1f
	add	x1, x1, #4
	/*; Iamroot17A 2020.Oct.24
	 *; 앞에서 수정한 X1의 주소에 현재 Boot Exception Level로 수정한다.
	 *; __boot_cpu_mode의 초기 값을 확인해보면 서로 반대로 되어 있다.
	 *; set_cpu_boot_mode_flag가 완료된 상태라면 해당 배열이 전부
	 *; 현재 Boot Exception Level로 통일되어 있을 것이다.
	 *; */
1:	str	w0, [x1]			// Save CPU boot mode
	/*; Iamroot17A 2020.Oct.24
	 *; __boot_cpu_mode의 값을 수정한 것을 보장하기 위해 Barrier 사용한다.
	 *; 또한 수정 내역이 cache line에 반영되어 생기는 문제를 방지하기 위해
	 *; d-cache를 invalidate함.
	 *; */
	dmb	sy
	dc	ivac, x1			// Invalidate potentially stale cache line
	ret
SYM_FUNC_END(set_cpu_boot_mode_flag)

/*
 * These values are written with the MMU off, but read with the MMU on.
 * Writers will invalidate the corresponding address, discarding up to a
 * 'Cache Writeback Granule' (CWG) worth of data. The linker script ensures
 * sufficient alignment that the CWG doesn't overlap another section.
 */
	.pushsection ".mmuoff.data.write", "aw"
/*
 * We need to find out the CPU boot mode long after boot, so we need to
 * store it in a writable variable.
 *
 * This is not in .bss, because we set it sufficiently early that the boot-time
 * zeroing of .bss would clobber it.
 */
SYM_DATA_START(__boot_cpu_mode)
	.long	BOOT_CPU_MODE_EL2
	.long	BOOT_CPU_MODE_EL1
SYM_DATA_END(__boot_cpu_mode)
/*
 * The booting CPU updates the failed status @__early_cpu_boot_status,
 * with MMU turned off.
 */
SYM_DATA_START(__early_cpu_boot_status)
	.quad 	0
SYM_DATA_END(__early_cpu_boot_status)

	.popsection

	/*
	 * This provides a "holding pen" for platforms to hold all secondary
	 * cores are held until we're ready for them to initialise.
	 */
SYM_FUNC_START(secondary_holding_pen)
	bl	init_kernel_el			// w0=cpu_boot_mode
	bl	set_cpu_boot_mode_flag
	mrs	x0, mpidr_el1
	mov_q	x1, MPIDR_HWID_BITMASK
	and	x0, x0, x1
	adr_l	x3, secondary_holding_pen_release
pen:	ldr	x4, [x3]
	cmp	x4, x0
	b.eq	secondary_startup
	wfe
	b	pen
SYM_FUNC_END(secondary_holding_pen)

	/*
	 * Secondary entry point that jumps straight into the kernel. Only to
	 * be used where CPUs are brought online dynamically by the kernel.
	 */
SYM_FUNC_START(secondary_entry)
	bl	init_kernel_el			// w0=cpu_boot_mode
	bl	set_cpu_boot_mode_flag
	b	secondary_startup
SYM_FUNC_END(secondary_entry)

SYM_FUNC_START_LOCAL(secondary_startup)
	/*
	 * Common entry point for secondary CPUs.
	 */
	bl	switch_to_vhe
	bl	__cpu_secondary_check52bitva
	bl	__cpu_setup			// initialise processor
	adrp	x1, swapper_pg_dir
	bl	__enable_mmu
	ldr	x8, =__secondary_switched
	br	x8
SYM_FUNC_END(secondary_startup)

SYM_FUNC_START_LOCAL(__secondary_switched)
	adr_l	x5, vectors
	msr	vbar_el1, x5
	isb

	adr_l	x0, secondary_data
	ldr	x2, [x0, #CPU_BOOT_TASK]
	cbz	x2, __secondary_too_slow

	init_cpu_task x2, x1, x3

#ifdef CONFIG_ARM64_PTR_AUTH
	ptrauth_keys_init_cpu x2, x3, x4, x5
#endif

	bl	secondary_start_kernel
	ASM_BUG()
SYM_FUNC_END(__secondary_switched)

SYM_FUNC_START_LOCAL(__secondary_too_slow)
	wfe
	wfi
	b	__secondary_too_slow
SYM_FUNC_END(__secondary_too_slow)

/*
 * The booting CPU updates the failed status @__early_cpu_boot_status,
 * with MMU turned off.
 *
 * update_early_cpu_boot_status tmp, status
 *  - Corrupts tmp1, tmp2
 *  - Writes 'status' to __early_cpu_boot_status and makes sure
 *    it is committed to memory.
 */

	.macro	update_early_cpu_boot_status status, tmp1, tmp2
	mov	\tmp2, #\status
	adr_l	\tmp1, __early_cpu_boot_status
	str	\tmp2, [\tmp1]
	dmb	sy
	dc	ivac, \tmp1			// Invalidate potentially stale cache line
	.endm

/*
 * Enable the MMU.
 *
 *  x0  = SCTLR_EL1 value for turning on the MMU.
 *  x1  = TTBR1_EL1 value
 *
 * Returns to the caller via x30/lr. This requires the caller to be covered
 * by the .idmap.text section.
 *
 * Checks if the selected granule size is supported by the CPU.
 * If it isn't, park the CPU
 */
SYM_FUNC_START(__enable_mmu)
	mrs	x2, ID_AA64MMFR0_EL1
	ubfx	x2, x2, #ID_AA64MMFR0_TGRAN_SHIFT, 4
	cmp     x2, #ID_AA64MMFR0_TGRAN_SUPPORTED_MIN
	b.lt    __no_granule_support
	cmp     x2, #ID_AA64MMFR0_TGRAN_SUPPORTED_MAX
	b.gt    __no_granule_support
	update_early_cpu_boot_status 0, x2, x3
	adrp	x2, idmap_pg_dir
	phys_to_ttbr x1, x1
	phys_to_ttbr x2, x2
	msr	ttbr0_el1, x2			// load TTBR0
	offset_ttbr1 x1, x3
	msr	ttbr1_el1, x1			// load TTBR1
	isb

	set_sctlr_el1	x0

	ret
SYM_FUNC_END(__enable_mmu)

SYM_FUNC_START(__cpu_secondary_check52bitva)
#ifdef CONFIG_ARM64_VA_BITS_52
	ldr_l	x0, vabits_actual
	cmp	x0, #52
	b.ne	2f

	mrs_s	x0, SYS_ID_AA64MMFR2_EL1
	and	x0, x0, #(0xf << ID_AA64MMFR2_LVA_SHIFT)
	cbnz	x0, 2f

	update_early_cpu_boot_status \
		CPU_STUCK_IN_KERNEL | CPU_STUCK_REASON_52_BIT_VA, x0, x1
1:	wfe
	wfi
	b	1b

#endif
2:	ret
SYM_FUNC_END(__cpu_secondary_check52bitva)

SYM_FUNC_START_LOCAL(__no_granule_support)
	/* Indicate that this CPU can't boot and is stuck in the kernel */
	update_early_cpu_boot_status \
		CPU_STUCK_IN_KERNEL | CPU_STUCK_REASON_NO_GRAN, x1, x2
1:
	wfe
	wfi
	b	1b
SYM_FUNC_END(__no_granule_support)

#ifdef CONFIG_RELOCATABLE
SYM_FUNC_START_LOCAL(__relocate_kernel)
	/*
	 * Iterate over each entry in the relocation table, and apply the
	 * relocations in place.
	 */
	ldr	w9, =__rela_offset		// offset to reloc table
	ldr	w10, =__rela_size		// size of reloc table

	mov_q	x11, KIMAGE_VADDR		// default virtual offset
	add	x11, x11, x23			// actual virtual offset
	add	x9, x9, x11			// __va(.rela)
	add	x10, x9, x10			// __va(.rela) + sizeof(.rela)

0:	cmp	x9, x10
	b.hs	1f
	ldp	x12, x13, [x9], #24
	ldr	x14, [x9, #-8]
	cmp	w13, #R_AARCH64_RELATIVE
	b.ne	0b
	add	x14, x14, x23			// relocate
	str	x14, [x12, x23]
	b	0b

1:
#ifdef CONFIG_RELR
	/*
	 * Apply RELR relocations.
	 *
	 * RELR is a compressed format for storing relative relocations. The
	 * encoded sequence of entries looks like:
	 * [ AAAAAAAA BBBBBBB1 BBBBBBB1 ... AAAAAAAA BBBBBB1 ... ]
	 *
	 * i.e. start with an address, followed by any number of bitmaps. The
	 * address entry encodes 1 relocation. The subsequent bitmap entries
	 * encode up to 63 relocations each, at subsequent offsets following
	 * the last address entry.
	 *
	 * The bitmap entries must have 1 in the least significant bit. The
	 * assumption here is that an address cannot have 1 in lsb. Odd
	 * addresses are not supported. Any odd addresses are stored in the RELA
	 * section, which is handled above.
	 *
	 * Excluding the least significant bit in the bitmap, each non-zero
	 * bit in the bitmap represents a relocation to be applied to
	 * a corresponding machine word that follows the base address
	 * word. The second least significant bit represents the machine
	 * word immediately following the initial address, and each bit
	 * that follows represents the next word, in linear order. As such,
	 * a single bitmap can encode up to 63 relocations in a 64-bit object.
	 *
	 * In this implementation we store the address of the next RELR table
	 * entry in x9, the address being relocated by the current address or
	 * bitmap entry in x13 and the address being relocated by the current
	 * bit in x14.
	 *
	 * Because addends are stored in place in the binary, RELR relocations
	 * cannot be applied idempotently. We use x24 to keep track of the
	 * currently applied displacement so that we can correctly relocate if
	 * __relocate_kernel is called twice with non-zero displacements (i.e.
	 * if there is both a physical misalignment and a KASLR displacement).
	 */
	ldr	w9, =__relr_offset		// offset to reloc table
	ldr	w10, =__relr_size		// size of reloc table
	add	x9, x9, x11			// __va(.relr)
	add	x10, x9, x10			// __va(.relr) + sizeof(.relr)

	sub	x15, x23, x24			// delta from previous offset
	cbz	x15, 7f				// nothing to do if unchanged
	mov	x24, x23			// save new offset

2:	cmp	x9, x10
	b.hs	7f
	ldr	x11, [x9], #8
	tbnz	x11, #0, 3f			// branch to handle bitmaps
	add	x13, x11, x23
	ldr	x12, [x13]			// relocate address entry
	add	x12, x12, x15
	str	x12, [x13], #8			// adjust to start of bitmap
	b	2b

3:	mov	x14, x13
4:	lsr	x11, x11, #1
	cbz	x11, 6f
	tbz	x11, #0, 5f			// skip bit if not set
	ldr	x12, [x14]			// relocate bit
	add	x12, x12, x15
	str	x12, [x14]

5:	add	x14, x14, #8			// move to next bit's address
	b	4b

6:	/*
	 * Move to the next bitmap's address. 8 is the word size, and 63 is the
	 * number of significant bits in a bitmap entry.
	 */
	add	x13, x13, #(8 * 63)
	b	2b

7:
#endif
	ret

SYM_FUNC_END(__relocate_kernel)
#endif

SYM_FUNC_START_LOCAL(__primary_switch)
#ifdef CONFIG_RANDOMIZE_BASE
	mov	x19, x0				// preserve new SCTLR_EL1 value
	mrs	x20, sctlr_el1			// preserve old SCTLR_EL1 value
#endif

	adrp	x1, init_pg_dir
	bl	__enable_mmu
#ifdef CONFIG_RELOCATABLE
#ifdef CONFIG_RELR
	mov	x24, #0				// no RELR displacement yet
#endif
	bl	__relocate_kernel
#ifdef CONFIG_RANDOMIZE_BASE
	ldr	x8, =__primary_switched
	adrp	x0, __PHYS_OFFSET
	blr	x8

	/*
	 * If we return here, we have a KASLR displacement in x23 which we need
	 * to take into account by discarding the current kernel mapping and
	 * creating a new one.
	 */
	pre_disable_mmu_workaround
	msr	sctlr_el1, x20			// disable the MMU
	isb
	bl	__create_page_tables		// recreate kernel mapping

	tlbi	vmalle1				// Remove any stale TLB entries
	dsb	nsh
	isb

	set_sctlr_el1	x19			// re-enable the MMU

	bl	__relocate_kernel
#endif
#endif
	ldr	x8, =__primary_switched
	adrp	x0, __PHYS_OFFSET
	br	x8
SYM_FUNC_END(__primary_switch)
