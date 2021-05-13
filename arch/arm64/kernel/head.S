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
#include <linux/irqchip/arm-gic-v3.h>
#include <linux/pgtable.h>

#include <asm/asm_pointer_auth.h>
#include <asm/assembler.h>
#include <asm/boot.h>
#include <asm/ptrace.h>
#include <asm/asm-offsets.h>
#include <asm/cache.h>
#include <asm/cputype.h>
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

/*; Iamroot17A 2020.Oct.24 #6.1
 *;
 *; 초기 TEXT_OFFSET은 512KB였음. (아마도 ARM32에서 porting한 부분으로 예상)
 *; 해당 512KB를 BSS 영역의 크기로 할당해서 사용했었으나, 현재 무의미해졌음.
 *; KASLR 도입 과정에서 relocatable kernel 개념을 적용하면서 커널의 물리 주소가
 *; 중요하지 않게 됨. (segment align만 잘 맞으면 되는데, 보통 64KB를 기준으로
 *; 하기 때문에 512KB나 0이나 align이 맞게 됨.)
 *; >> 관련 commit: cfa7ede20f133cc81cef01dc3a516dda3a9721ee
 *;
 *; 이전에는 빌드 타임에 무작위로 TEXT_OFFSET을 변경하는 config가 존재했는데,
 *; 현재 커널 이미지를 2MB로 정렬하므로, 무의미해져 해당 config가 제거됨.
 *; >> 관련 commit: 751c263bb74fd36b5fc2589d36abc75042336444
 *; */
#define __PHYS_OFFSET	(KERNEL_START - TEXT_OFFSET)

#if (TEXT_OFFSET & 0xfff) != 0
#error TEXT_OFFSET must be at least 4KB aligned
#elif (PAGE_OFFSET & 0x1fffff) != 0
#error PAGE_OFFSET must be at least 2MB aligned
#elif TEXT_OFFSET > 0x1fffff
#error TEXT_OFFSET must be less than 2MB
#endif

/*
 * Kernel startup entry point.
 * ---------------------------
 *
 * The requirements are:
 *   MMU = off, D-cache = off, I-cache = on or off,
 *   x0 = physical address to the FDT blob.
 *
 * This code is mostly position independent so you call this at
 * __pa(PAGE_OFFSET + TEXT_OFFSET).
 *
 * Note that the callee-saved registers are used for storing variables
 * that are useful before the MMU is enabled. The allocations are described
 * in the entry routines.
 */
/*; Iamroot17A 2020.Oct.17 #1
 *;
 *; 여기가 bootloader에서 올려준 커널 이미지의 최상단 헤더 부분이다.
 *; __HEAD (.head.text section)는 커널 이미지의 시작 부분에 배치되며, primary
 *; CPU가 여기 있는 명령어를 통해 stext(현재 primary_entry로 refactor됨)로
 *; 분기되어야 한다.
 *;
 *; >> /Documentation/arm64/booting.rst 4. Call the kernel image 참고
 *; */
	__HEAD
_head:
	/*
	 * DO NOT MODIFY. Image header expected by Linux boot-loaders.
	 */
#ifdef CONFIG_EFI
	/*
	 * This add instruction has no meaningful effect except that
	 * its opcode forms the magic "MZ" signature required by UEFI.
	 */
	/*; Iamroot17A 2020.Oct.17 #2.1
	 *;
	 *; UEFI를 사용할 경우, Magic number로 "MZ"를 요구함.
	 *; 아래 "add x13, x18, #0x16"은 ARM64 machine code로는 0x4D5A0091임.
	 *; EFI로 부팅되는 경우에는 아래 "b primary_entry"로 진입되는 것이
	 *; 아니라, PE header의 정보를 통해 primary_entry로 진입하게 되지만
	 *; 커널을 EFI 지원으로 빌드했지만 부트로더가 EFI로 부팅하지 않는 경우
	 *; 하위호환성을 지원하기 위해 아래와 같이 구현한 것으로 보임.
	 *; (Magic number를 만족하면서, 커널 초기화 과정에 영향을 주지 않는
	 *;  무의미한 명령어를 배치했다고 생각하면 됨.)
	 *;
	 *; RISC-V에서도 이와 비슷한 방식으로 구현되어 있음. (v5.10-rc1)
	 *; >> 관련 commit: cb7d2dd5612a77a2597c00fce770a52c921e2ea5
	 *; */
	add	x13, x18, #0x16
	b	primary_entry
#else
	b	primary_entry			// branch to kernel start, magic
	.long	0				// reserved
#endif
	le64sym	_kernel_offset_le		// Image load offset from start of RAM, little-endian
	le64sym	_kernel_size_le			// Effective size of kernel image, little-endian
	le64sym	_kernel_flags_le		// Informative flags, little-endian
	.quad	0				// reserved
	.quad	0				// reserved
	.quad	0				// reserved
	.ascii	ARM64_IMAGE_MAGIC		// Magic number
#ifdef CONFIG_EFI
	/*; Iamroot17A 2020.Oct.17 #2.2
	 *;
	 *; UEFI가 동작하는 PE(Portable Executable) 실행파일 형식을 제공하기
	 *; 위해서는 PE Header 시작 전에 64bytes의 DOS header가 필요함.
	 *; PE는 Windows 3.1부터 지원되기 시작했는데, 이때 하위호환성
	 *; (This program cannot be run in DOS mode. 출력)을 위해
	 *; 기존의 DOS MZ header로 시작하였다.
	 *; 현대 PE header 해석을 위해서는 "MZ" magic number 검증과,
	 *; PE의 시작점 offset 확인을 위한 [0x3C, 0x3F] 4byte의 값만 확인한다.
	 *; "pe_header" label과 "_head" label 간의 offset 차이는 현재 0x3C이다.
	 *;
	 *; >> https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files 참고
	 *; >> https://en.wikipedia.org/wiki/Portable_Executable 그림 참고
	 *; */
	.long	pe_header - _head		// Offset to the PE header.

pe_header:
	__EFI_PE_HEADER
#else
	.long	0				// reserved
#endif

	/*; Iamroot17A 2020.Oct.17 #3
	 *;
	 *; 실제 실행 코드는 여기서부터 진행되며, 결론적으로 커널 초기화의 시작
	 *; 지점은 "primary_entry"라고 볼 수 있다. (기존 "stext"에서 refactor)
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
	/*; Iamroot17A 2020.Oct.17 #4
	 *;
	 *; bl: Branch with Link, 다음 실행할 명령어의 PC(Program Counter)의
	 *; 값을 LR(Link Register, ARM64에서는 X30)에 저장하고 argument 위치로
	 *; 분기하는 명령어, ret명령을 통해 LR에 저장된 위치로 복귀 가능
	 *; */
	bl	preserve_boot_args
	bl	el2_setup			// Drop to EL1, w0=cpu_boot_mode
	/*; Iamroot17A 2020.Oct.24 #6
	 *;
	 *; 커널 이미지의 재배치를 위한 offset의 값을 X23에 저장한다.
	 *; 추후 해당 값은 KASLR(Kernel Address Space Layout Randomization)의
	 *; offset으로 변형되는데, 지금은 기본적인 offset으로 설정한다고
	 *; 생각하면 된다. (과거엔 __PHYS_OFFSET이 의미있었으나 지금은
	 *; 커널 이미지 재배치로 인해 의미가 거의 없어진 상태다.)
	 *; 커널 이미지는 2MB 단위로 align되어야 한다. (MIN_KIMG_ALIGN == SZ_2M)
	 *;
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
	/*; Iamroot17A 2020.Oct.17 #5
	 *;
	 *; primary CPU의 general-purpose register의 요구사항은 아래와 같음.
	 *; X0: System RAM에서 FDT(dtb;Device Tree Blob)의 물리 주소
	 *; X1~X3: 0 (Reserved for future use)
	 *;
	 *; 추후 변수를 저장할 boot_args의 주소가 X0에 할당되므로 미리 X21로
	 *; 옮기는 작업을 수행함.
	 *; */
	mov	x21, x0				// x21=FDT

	/*; Iamroot17A 2020.Oct.17 #6
	 *;
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

	/*; Iamroot17A 2020.Oct.17 #7
	 *;
	 *; dmb: Data Memory Barrier, 명령어 경계로 메모리, 캐시 순서 보장
	 *; sy: System Sharable, 시스템 전체
	 *;
	 *; 상단의 boot_args[4]에 X0~X3의 값이 완전히 기록되는 것을 보장하기
	 *; 위해 호출함. (아래 __inval_dcache_area에 의한 stale cache 현상을
	 *; 방지하기 위한 barrier)
	 *;
	 *; >> MMU가 꺼진 상태에서 barrier 사용에 관한 질문
	 *; >> http://www.iamroot.org/xe/index.php?document_srl=213162 참고
	 *; >> https://lore.kernel.org/kernelnewbies/CAEcHRToEjECSNpdocLwtd6M1vC2qEhBa2pziCV5g75d6h86kFQ@mail.gmail.com/T/#m390fd945500591ec444028da325b0d1481175be3
	 *; */
	dmb	sy				// needed before dc ivac with
						// MMU off

	/*; Iamroot17A 2020.Oct.17 #8
	 *;
	 *; "__inval_dcache_area" 호출 시, 기본 인자로 X0, X1을 사용한다.
	 *; "X0": invalidate할 D-cache의 시작 주소
	 *; "X1": invalidate할 D-cache의 크기
	 *; 이미 X0의 주소는 boot_args를 가리키고 있으므로, X1만 수정한다.
	 *; */
	mov	x1, #0x20			// 4 x 8 bytes
	/*; Iamroot17A 2020.Oct.17 #9
	 *;
	 *; Boot시의 CPU 조건이 d-cache가 꺼져있는 상태임에도 해당 영역을
	 *; 비우는 이유는 추후 MMU가 켜진 뒤 Clean & invalidate 시 잘못된
	 *; 데이터가 반영되는 것을 막기 위함이다.
	 *; */
	b	__inval_dcache_area		// tail call
	/*; Iamroot17A 2020.Oct.17 #10
	 *;
	 *; 원래 해당 Procedure가 종료되고 원래 caller(primary_entry)의 위치로
	 *; 돌아가려면 "ret" instruction을 사용해야 한다.
	 *; 게다가 현재 call stack을 사용하고 있지 않으므로, return address는
	 *; 다른 변수에 임시 저장되어야 한다. 하지만 "__inval_dcache_area"
	 *; 내부에서 "ret"를 호출하므로 여기에선 생략했다.
	 *; 만약 tail call 최적화가 없으면 이런 식으로 구성되어야 한다.
	 *;	mov	x28, x30
	 *;	bl	__inval_dcache_area
	 *;	ret	x28
	 *; >> https://en.wikipedia.org/wiki/Tail_call 참고
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
	/*; Iamroot17A2 2020.Dec.19
	 *; 각 배열에 저장하는 과정을 표현하는 어셈블리 코드다.
	 *; ```c
	 *; tbl[index << 3] = tmp1;
	 *; ```
	 *; 현재 64bit이므로 Logical shift-left 3 (주소값 + =8)
	 *; */
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
 *	vend:	virtual address of end of range
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
	add	\iend, \iend, \istart	// iend += (count - 1) * ptrs
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
 *	vstart:	start address to map
 *	vend:	end address to map - we map [vstart, vend]
 *	flags:	flags to use to map last level entries
 *	phys:	physical address corresponding to vstart - physical memory is contiguous
 *	pgds:	the number of pgd entries
 *
 * Temporaries:	istart, iend, tmp, count, sv - these need to be different registers
 * Preserves:	vstart, vend, flags
 * Corrupts:	tbl, rtbl, istart, iend, tmp, count, sv
 */
	.macro map_memory, tbl, rtbl, vstart, vend, flags, phys, pgds, istart, iend, tmp, count, sv
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
	/*; Iamroot17A 2020.Oct.24 #11
	 *;
	 *; 아래 __inval_dcache_area 호출 시 link register(X30)이 overwrite되기
	 *; 때문에 원래 return해야 할 주소(primary_entry의 bl __cpu_setup)를
	 *; X28에 임시 보관한다. (__create_page_tables 마지막에 ret x28로 원래
	 *; 위치에 맞게 복귀하게 된다.)
	 *; */
	mov	x28, lr

	/*
	 * Invalidate the init page tables to avoid potential dirty cache lines
	 * being evicted. Other page tables are allocated in rodata as part of
	 * the kernel image, and thus are clean to the PoC per the boot
	 * protocol.
	 */
	/*; Iamroot17A 2020.Oct.24 #12
	 *;
	 *; init_pg_dir은 부팅되어 MMU on 이후 사용될 초기 커널 이미지가 올라갈
	 *; 커널 주소 영역의 (0xFFFF..으로 시작하는 가상주소) 페이지들을 말한다.
	 *; */
	adrp	x0, init_pg_dir
	/*; Iamroot17A 2020.Oct.24 #13
	 *;
	 *; init_pg_end는 init_pg_dir에서부터 사용될 페이지들의 크기를 offset한
	 *; 끝 주소를 뜻한다. (arch/arm64/kernel/vmlinux.lds.S 참고)
	 *; 해당 크기는 INIT_DIR_SIZE로 정의되어있음.
	 *; (arch/arm64/include/asm/kernel-pgtable.h 참고)
	 *; */
	adrp	x1, init_pg_end
	sub	x1, x1, x0
	/*; Iamroot17A 2020.Oct.24 #14
	 *;
	 *; init page table 영역에 관련된 d-cache를 invalidate 해줌으로서
	 *; 원치 않는 값이 씌여지는 현상을 방지한다.
	 */
	bl	__inval_dcache_area
	/*; Iamroot17A 2020.Oct.24 #15
	 *;
	 *; 왜 __inval_dcache_area 이후에는 "dmb"를 안하냐면
	 *; __inval_dcache_area 안에서 이미 "dsb sy"가 수행되었기 때문이다.
	 *; */

	/*
	 * Clear the init page tables.
	 */
	adrp	x0, init_pg_dir
	adrp	x1, init_pg_end
	sub	x1, x1, x0
	/*; Iamroot17A 2020.Oct.24 #16
	 *;
	 *; 아래 stp 4개 연속으로 있는 것은 Loop unrolling으로 보임.
	 *; (branch에 의한 pipeline stall을 줄이기 위함)
	 *; 보통 loop unrolling 단위는 cache size를 기준으로 함.
	 *; >> https://en.wikipedia.org/wiki/Loop_unrolling 참고
	 *; */
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
	cmp	x5, TCR_T0SZ(VA_BITS)	// default T0SZ small enough?
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
	mov	x5, x3				// __pa(__idmap_text_start)
	adr_l	x6, __idmap_text_end		// __pa(__idmap_text_end)
	/*; Iamroot17A2 2021.Jan.16
	 *;  ffff800010dce000 T __idmap_text_start
	 *;  ffff800010dce7a4 T __idmap_text_end
	 *;  ffff800010000000 T _text
	 *;  ffff800011dc0000 B _end
	 *; */

	map_memory x0, x1, x3, x6, x7, x3, x4, x10, x11, x12, x13, x14

	/*
	 * Map the kernel image (starting with PHYS_OFFSET).
	 */
	adrp	x0, init_pg_dir
	mov_q	x5, KIMAGE_VADDR + TEXT_OFFSET	// compile time __va(_text)
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
	sub	x1, x1, x0
	bl	__inval_dcache_area

	adrp	x0, init_pg_dir
	adrp	x1, init_pg_end
	sub	x1, x1, x0
	bl	__inval_dcache_area

	ret	x28
SYM_FUNC_END(__create_page_tables)

/*
 * The following fragment of code is executed with the MMU enabled.
 *
 *   x0 = __PHYS_OFFSET
 */
/*; Iamroot17A2 2021.Jan.02
 *;  ffff800011b00000 D init_stack
 *;  ffff800011b00000 D init_thread_union
 *;  ffff800011b04000 D __end_init_task <-- sp start(align: 0x8000)
 *; */
SYM_FUNC_START_LOCAL(__primary_switched)
	adrp	x4, init_thread_union
	add	sp, x4, #THREAD_SIZE
	adr_l	x5, init_task
	msr	sp_el0, x5			// Save thread_info

#ifdef CONFIG_ARM64_PTR_AUTH
	__ptrauth_keys_init_cpu	x5, x6, x7, x8
#endif

	/*; Iamroot17A 2020.Nov.21 #1
	 *;
	 *; Vector table의 주소를 VBAR_EL1에 등록한다.
	 *; VBAR_EL1: Vector Base Address Register
	 *; */
	adr_l	x8, vectors			// load VBAR_EL1 with virtual
	msr	vbar_el1, x8			// vector table address
	isb

	/*; Iamroot17A 2020.Nov.21 #2
	 *;
	 *; ARM64 Procedure Call Standard에 맞춰 stack frame을 생성한다.
	 *; X30(Link Register)와 X29(Frame Pointer)의 값을 설정한다.
	 *; >> 관련 commit: 60699ba18b69ff210ed0304bc23f6c9d11d27a72
	 *; */
	stp	xzr, x30, [sp, #-16]!
	mov	x29, sp

	/*; Iamroot17A 2020.Nov.21 #3
	 *;
	 *; Shadow Call Stack은 Stack buffer overflow 등의 공격에서 return
	 *; address를 보호하기 위해 사용되는 기법이다.
	 *; 해당 기법의 원리를 간단하게 설명하면, 기존의 call stack을 사용하는
	 *; 방식에서 추가적으로 shadow call stack 영역을 추가하여, call stack
	 *; 연산시 접근 가능한 address 등을 입력하여 Stack buffer overflow를
	 *; 감지하거나 예방하는 등으로 활용된다.
	 *; >> https://en.wikipedia.org/wiki/Shadow_stack 참고
	 *; >> https://clang.llvm.org/docs/ShadowCallStack.html 참고
	 *; (defconfig에서 n이며, compiler가 지원해야하므로 자세한 분석 생략)
	 *; */
#ifdef CONFIG_SHADOW_CALL_STACK
	adr_l	scs_sp, init_shadow_call_stack	// Set shadow call stack
#endif

	/*; Iamroot17A 2020.Nov.21 #4
	 *;
	 *; X21(preserve_boot_args()에서 보관한 FDT의 물리 주소)을
	 *; __fdt_pointer에 보관한다.
	 *; >> arch/arm64/kernel/setup.c 의 __fdt_pointer 선언 참고
	 *; */
	str_l	x21, __fdt_pointer, x5		// Save FDT pointer

	/*; Iamroot17A 2020.Nov.21 #5
	 *;
	 *; 커널의 가상주소 오프셋을 계산한다.
	 *; (커널의 시작 가상 주소 - 커널의 시작 물리 주소)
	 *; X0는 __primary_switched()로 진입하기 전에 이미 __PHYS_OFFSET 값을
	 *; 설정한 상태다.
	 *; (__primary_switch에서 변경했으며 KASLR 적용 전/후 모두 동일함)
	 *; >> Iamroot17A 2020.Nov.21 #5.1 참고 (커널의 시작 가상 주소)
	 *; >> Iamroot17A 2020.Oct.24 #6.1 참고 (커널의 시작 물리 주소)
	 *;
	 *; __PHYS_OFFSET과 kimage_vaddr은 compile time에서의 정의가 같다.
	 *; 다만 __PHYS_OFFSET을 읽어올 때 ADRP를 통해 읽어오기 때문에 X0는
	 *; 물리 주소를 나타내게 되는 것이다.
	 *; */
	ldr_l	x4, kimage_vaddr		// Save the offset between
	sub	x4, x4, x0			// the kernel virtual and
	str_l	x4, kimage_voffset, x5		// physical mappings

	// Clear BSS
	/*; Iamroot17A 2020.Nov.21 #6
	 *;
	 *; 기존에는 BSS 영역 초기화 시 반복문을 사용했는데, 이제는 memset()을
	 *; 사용하고 있다. __pi_memset()은 Position Independent한 memset()으로,
	 *; ARM64 어셈블리로 구현되어있다.
	 *; X0: source, 초기화할 메모리 시작 주소
	 *; X1: character, 초기화할 값
	 *; X2: number, 초기화할 byte의 개수
	 *; >> 관련 commit: 2a803c4db615d85126c5c7afd5849a3cfde71422
	 *;
	 *; __pi_memset() 원본 정의가 없는 이유는 매크로를 통해 심볼이 생성됨
	 *; >> arch/arm64/lib/memset.S 참고
	 *; */
	adr_l	x0, __bss_start
	mov	x1, xzr
	adr_l	x2, __bss_stop
	sub	x2, x2, x0
	bl	__pi_memset
	dsb	ishst				// Make zero page visible to PTW

#ifdef CONFIG_KASAN
	bl	kasan_early_init
#endif
#ifdef CONFIG_RANDOMIZE_BASE
	/*; Iamroot17A 2020.Nov.21 #7
	 *;
	 *; 커널 이미지 재배치를 위한 offset이 KASLR이 적용된 상태인지 확인한다.
	 *; 1) KASLR이 아직 적용되지 않았다면, X23의 값은 bootloader가 올려준
	 *;    커널 이미지 물리 주소의 하위 비트만 살려둔 상태기 때문에
	 *;    MIN_KIMG_ALIGN의 상위 비트들은 모두 0일 것이다.
	 *;    즉 label 0:로 branch하지 못하고, kaslr_early_init 관련 흐름으로
	 *;    실행되게 된다. (ret를 통해 다시 __primary_switch()로 복귀해서,
	 *;    KASLR을 적용한 상태로 init_pg_dir을 다시 생성하고 relocation하여
	 *;    __primary_switched가 재호출되어 이 지점으로 돌아오게 된다.
	 *; 2) 만약 KASLR이 적용된 상태라면, 위와 다르게 상위 비트가 모두 1로
	 *;    변경되는 것으로 보이며, label 0:로 branch하여 start_kernel()로
	 *;    진입하는 흐름을 수행한다.
	 *; >> Iamroot17A 2020.Oct.24 #6 참고 (X23 초기 설정 부분)
	 *; */
	tst	x23, ~(MIN_KIMG_ALIGN - 1)	// already running randomized?
	b.ne	0f
	/*; Iamroot17A 2020.Nov.21 #8
	 *;
	 *; kaslr_early_init을 호출한다. 해당 함수의 인자로 FDT의 주소를
	 *; 사용하므로, ARM64 Procedure Call Standard에 따라 해당 인자를 X0에
	 *; 넣고 호출한다.
	 *; */
	mov	x0, x21				// pass FDT address in x0
	bl	kaslr_early_init		// parse FDT for KASLR options
	/*; Iamroot17A 2020.Nov.21 #9
	 *;
	 *; kaslr_early_init()에서 KASLR 적용 여부가 취소된 경우, 커널 이미지
	 *; 재배치를 위한 offset이 무작위로 생성되지 않았으며, init_pg_dir
	 *; 재생성 및 relocation이 무의미해진다. 이 경우 그냥 label 0:로
	 *; branch하여 start_kernel()로 진입한다.
	 *; */
	cbz	x0, 0f				// KASLR disabled? just proceed
	/*; Iamroot17A 2020.Nov.21 #10
	 *;
	 *; kaslr_early_init에서 return한 무작위 offset 값으로 X23을 변경하고
	 *; KASLR을 적용하기 위해 return한다. (__primary_switch()서 마저 수행함)
	 *; */
	orr	x23, x23, x0			// record KASLR offset
	ldp	x29, x30, [sp], #16		// we must enable KASLR, return
	ret					// to __primary_switch()
0:
#endif
	/*; Iamroot17A 2020.Nov.21 #11
	 *;
	 *; ARM64 Procedure Call Standard에 맞춰 LR과 FP를 설정한다.
	 *; start_kernel() 기준으로 caller가 없는 것 처럼 설정해야 하기 때문에
	 *; 모두 0으로 설정된다.
	 *; */
	add	sp, sp, #16
	mov	x29, #0
	mov	x30, #0
	b	start_kernel
SYM_FUNC_END(__primary_switched)

	.pushsection ".rodata", "a"
/*; Iamroot17A 2020.Nov.21 #5.1
 *;
 *; _text의 값은 .head.text의 시작 주소이며, 커널의 시작 가상 주소를 나타낸다.
 *; TEXT_OFFSET은 이전에 분석하였듯 현재 큰 의미를 갖지 못하며,
 *; 커널의 가상 주소 계산 과정에서 서로 상쇄된다.
 *; >> arch/arm64/kernel/vmlinux.lds.S 내 _text 정의 참고
 *; >> Iamroot17A 2020.Oct.24 #6.1 참고 (TEXT_OFFSET 히스토리)
 *; */
SYM_DATA_START(kimage_vaddr)
	.quad		_text - TEXT_OFFSET
SYM_DATA_END(kimage_vaddr)
EXPORT_SYMBOL(kimage_vaddr)
	.popsection

/*
 * end early head section, begin head code that is also used for
 * hotplug and needs to have the same protections as the text region
 */
	.section ".idmap.text","awx"

/*
 * If we're fortunate enough to boot at EL2, ensure that the world is
 * sane before dropping to EL1.
 *
 * Returns either BOOT_CPU_MODE_EL1 or BOOT_CPU_MODE_EL2 in w0 if
 * booted in EL1 or EL2 respectively.
 */
SYM_FUNC_START(el2_setup)
	/*; Iamroot17A 2020.Oct.17 #11
	 *;
	 *; SPsel 레지스터의 설정 값을 1로 변경 (스택 포인터로 EL0를 쓸 것인지,
	 *; 혹은 EL1/EL2를 사용할 것인지 선택)
	 *; */
	msr	SPsel, #1			// We want to use SP_EL{1,2}
	/*; Iamroot17A 2020.Oct.17 #12
	 *;
	 *; 현재 Exception Level을 가져와서, 해당 값이 EL2일 경우 EL2에 맞게
	 *; 코드 실행, 아닐 경우 EL1에 맞게 수행하고 현재 procedure 종료.
	 *; */
	mrs	x0, CurrentEL
	cmp	x0, #CurrentEL_EL2
	b.eq	1f
	/*; Iamroot17A 2020.Oct.24 #1
	 *;
	 *; SCTLR_EL1에 32-bit mode에 대한 endianness를 설정한다. (64-bit은
	 *; Little-endian으로 고정됨.) RES1은 SCTLR_EL1의 field bit 중
	 *; reserved 값 중 기본 값을 1로 설정한 field들을 말한다. (추후 해당
	 *; field가 다른 용도로 사용될 것을 고려하여 RES0 혹은 RES1을 결정.)
	 *; 일부 RES1 필드는 ARMv8.x extension에서 사용된다.
	 *;
	 *; 상수 값인 64-bit를 직접 MSR로 집어넣지 못하기 때문에 X0에 넣으며,
	 *; X0에도 64-bit를 직접 집어넣지 못하므로 mov_q 매크로를 사용한다.
	 *; */
	mov_q	x0, (SCTLR_EL1_RES1 | ENDIAN_SET_EL1)
	msr	sctlr_el1, x0
	/*; Iamroot17A 2020.Oct.24 #2
	 *;
	 *; el2_setup procedure에서 최종적으로 W0에 선택될 Exception Level을
	 *; 반환해야 한다. (현재 EL1으로 선택되었으므로, BOOT_CPU_MODE_EL1 선택)
	 *; */
	mov	w0, #BOOT_CPU_MODE_EL1		// This cpu booted in EL1
	/*; Iamroot17A 2020.Oct.24 #3
	 *;
	 *; ISB: Instruction Synchronization Barrier
	 *; 해당 명령어를 경계로 이전의 Instruction이 모두 수행되게 한다.
	 *; (미리 pipeline되어 있던 아래쪽 Instruction들을 모두 flush 시킴.)
	 *; Context change operation 수행 시 호출되는 경우가 대표적.
	 *; 현재 Head.S 기준으로는 MSR로 특정 설정을 변경했을 때, 이를
	 *; 반영하지 않은 Instruction들이 수행되는 것을 막기 위해 barrier를
	 *; 거는 것으로 보임.
	 *; */
	isb
	ret

	/*; Iamroot17A 2020.Oct.17 #13
	 *;
	 *; 본 분석에서는 EL2 (Hypervisor mode)로 동작하는 흐름은 분석하지
	 *; 않는다. 단, EL1에서 처리하는 코드와 같은 내용이 어디에서 처리되는지
	 *; 유사한 흐름을 확인하기 위한 분석은 수행한다.
	 *; */
	/*; Iamroot17A 2020.Oct.24 #4
	 *;
	 *; EL1의 경우와 같이 SCTLR_EL2에 32-bit mode에 대한 endianness를
	 *; 설정한다. 또한 똑같이 RES1을 설정한다.
	 *; */
1:	mov_q	x0, (SCTLR_EL2_RES1 | ENDIAN_SET_EL2)
	msr	sctlr_el2, x0

#ifdef CONFIG_ARM64_VHE
	/*
	 * Check for VHE being present. For the rest of the EL2 setup,
	 * x2 being non-zero indicates that we do have VHE, and that the
	 * kernel is intended to run at EL2.
	 */
	mrs	x2, id_aa64mmfr1_el1
	ubfx	x2, x2, #ID_AA64MMFR1_VHE_SHIFT, #4
#else
	mov	x2, xzr
#endif

	/* Hyp configuration. */
	mov_q	x0, HCR_HOST_NVHE_FLAGS
	cbz	x2, set_hcr
	mov_q	x0, HCR_HOST_VHE_FLAGS
set_hcr:
	msr	hcr_el2, x0
	isb

	/*
	 * Allow Non-secure EL1 and EL0 to access physical timer and counter.
	 * This is not necessary for VHE, since the host kernel runs in EL2,
	 * and EL0 accesses are configured in the later stage of boot process.
	 * Note that when HCR_EL2.E2H == 1, CNTHCTL_EL2 has the same bit layout
	 * as CNTKCTL_EL1, and CNTKCTL_EL1 accessing instructions are redefined
	 * to access CNTHCTL_EL2. This allows the kernel designed to run at EL1
	 * to transparently mess with the EL0 bits via CNTKCTL_EL1 access in
	 * EL2.
	 */
	cbnz	x2, 1f
	mrs	x0, cnthctl_el2
	orr	x0, x0, #3			// Enable EL1 physical timers
	msr	cnthctl_el2, x0
1:
	msr	cntvoff_el2, xzr		// Clear virtual offset

#ifdef CONFIG_ARM_GIC_V3
	/* GICv3 system register access */
	mrs	x0, id_aa64pfr0_el1
	ubfx	x0, x0, #ID_AA64PFR0_GIC_SHIFT, #4
	cbz	x0, 3f

	mrs_s	x0, SYS_ICC_SRE_EL2
	orr	x0, x0, #ICC_SRE_EL2_SRE	// Set ICC_SRE_EL2.SRE==1
	orr	x0, x0, #ICC_SRE_EL2_ENABLE	// Set ICC_SRE_EL2.Enable==1
	msr_s	SYS_ICC_SRE_EL2, x0
	isb					// Make sure SRE is now set
	mrs_s	x0, SYS_ICC_SRE_EL2		// Read SRE back,
	tbz	x0, #0, 3f			// and check that it sticks
	msr_s	SYS_ICH_HCR_EL2, xzr		// Reset ICC_HCR_EL2 to defaults

3:
#endif

	/* Populate ID registers. */
	mrs	x0, midr_el1
	mrs	x1, mpidr_el1
	msr	vpidr_el2, x0
	msr	vmpidr_el2, x1

#ifdef CONFIG_COMPAT
	msr	hstr_el2, xzr			// Disable CP15 traps to EL2
#endif

	/* EL2 debug */
	mrs	x1, id_aa64dfr0_el1
	sbfx	x0, x1, #ID_AA64DFR0_PMUVER_SHIFT, #4
	cmp	x0, #1
	b.lt	4f				// Skip if no PMU present
	mrs	x0, pmcr_el0			// Disable debug access traps
	ubfx	x0, x0, #11, #5			// to EL2 and allow access to
4:
	csel	x3, xzr, x0, lt			// all PMU counters from EL1

	/* Statistical profiling */
	ubfx	x0, x1, #ID_AA64DFR0_PMSVER_SHIFT, #4
	cbz	x0, 7f				// Skip if SPE not present
	cbnz	x2, 6f				// VHE?
	mrs_s	x4, SYS_PMBIDR_EL1		// If SPE available at EL2,
	and	x4, x4, #(1 << SYS_PMBIDR_EL1_P_SHIFT)
	cbnz	x4, 5f				// then permit sampling of physical
	mov	x4, #(1 << SYS_PMSCR_EL2_PCT_SHIFT | \
		      1 << SYS_PMSCR_EL2_PA_SHIFT)
	msr_s	SYS_PMSCR_EL2, x4		// addresses and physical counter
5:
	mov	x1, #(MDCR_EL2_E2PB_MASK << MDCR_EL2_E2PB_SHIFT)
	orr	x3, x3, x1			// If we don't have VHE, then
	b	7f				// use EL1&0 translation.
6:						// For VHE, use EL2 translation
	orr	x3, x3, #MDCR_EL2_TPMS		// and disable access from EL1
7:
	msr	mdcr_el2, x3			// Configure debug traps

	/* LORegions */
	mrs	x1, id_aa64mmfr1_el1
	ubfx	x0, x1, #ID_AA64MMFR1_LOR_SHIFT, 4
	cbz	x0, 1f
	msr_s	SYS_LORC_EL1, xzr
1:

	/* Stage-2 translation */
	msr	vttbr_el2, xzr

	cbz	x2, install_el2_stub

	/*; Iamroot17A 2020.Oct.24 #5
	 *;
	 *; el2_setup procedure에서 최종적으로 W0에 선택될 Exception Level을
	 *; 반환해야 한다. (현재 EL2로 선택되었으므로, BOOT_CPU_MODE_EL2 선택)
	 *; */
	mov	w0, #BOOT_CPU_MODE_EL2		// This CPU booted in EL2
	isb
	ret

SYM_INNER_LABEL(install_el2_stub, SYM_L_LOCAL)
	/*
	 * When VHE is not in use, early init of EL2 and EL1 needs to be
	 * done here.
	 * When VHE _is_ in use, EL1 will not be used in the host and
	 * requires no configuration, and all non-hyp-specific EL2 setup
	 * will be done via the _EL1 system register aliases in __cpu_setup.
	 */
	mov_q	x0, (SCTLR_EL1_RES1 | ENDIAN_SET_EL1)
	msr	sctlr_el1, x0

	/* Coprocessor traps. */
	mov	x0, #0x33ff
	msr	cptr_el2, x0			// Disable copro. traps to EL2

	/* SVE register access */
	mrs	x1, id_aa64pfr0_el1
	ubfx	x1, x1, #ID_AA64PFR0_SVE_SHIFT, #4
	cbz	x1, 7f

	bic	x0, x0, #CPTR_EL2_TZ		// Also disable SVE traps
	msr	cptr_el2, x0			// Disable copro. traps to EL2
	isb
	mov	x1, #ZCR_ELx_LEN_MASK		// SVE: Enable full vector
	msr_s	SYS_ZCR_EL2, x1			// length for EL1.

	/* Hypervisor stub */
7:	adr_l	x0, __hyp_stub_vectors
	msr	vbar_el2, x0

	/* spsr */
	mov	x0, #(PSR_F_BIT | PSR_I_BIT | PSR_A_BIT | PSR_D_BIT |\
		      PSR_MODE_EL1h)
	msr	spsr_el2, x0
	msr	elr_el2, lr
	mov	w0, #BOOT_CPU_MODE_EL2		// This CPU booted in EL2
	eret
SYM_FUNC_END(el2_setup)

/*
 * Sets the __boot_cpu_mode flag depending on the CPU boot mode passed
 * in w0. See arch/arm64/include/asm/virt.h for more info.
 */
SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
	/*; Iamroot17A 2020.Oct.24 #7
	 *;
	 *; __boot_cpu_mode 주소를 X1에 읽어온다. (정확히는 __boot_cpu_mode[0])
	 *; */
	adr_l	x1, __boot_cpu_mode
	/*; Iamroot17A 2020.Oct.24 #8
	 *;
	 *; W0(이전의 el2_setup에서 수정한 현재 Boot Exception Level)이
	 *; EL1인 경우 현재 X1이 가진 주소를 그대로 유지 (__boot_cpu_mode[0])
	 *; EL2인 경우 X1의 주소에서 += 4byte를 한다. (__boot_cpu_mode[1])
	 *; (__boot_cpu_mode를 현재 Boot Exception Level로 통일하려 함)
	 *; */
	cmp	w0, #BOOT_CPU_MODE_EL2
	b.ne	1f
	add	x1, x1, #4
	/*; Iamroot17A 2020.Oct.24 #9
	 *;
	 *; 앞에서 수정한 X1의 주소에 현재 Boot Exception Level로 수정한다.
	 *; __boot_cpu_mode의 초기 값을 확인해보면 서로 반대로 되어 있다.
	 *; set_cpu_boot_mode_flag가 완료된 상태라면 해당 배열이 전부
	 *; 현재 Boot Exception Level로 통일되어 있을 것이다.
	 *; */
1:	str	w0, [x1]			// This CPU has booted in EL1
	/*; Iamroot17A 2020.Oct.24 #10
	 *;
	 *; Data memory barrier, 기존 분석 참고
	 *; >> Iamroot17A 2020.Oct.17 #7 참고
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
	/*; Iamroot17A 2020.Oct.24 #7.1
	 *;
	 *; 아래 ".popsection"까지 (__boot_cpu_mode, __early_cpu_boot_status)
	 *; 선언된 symbol에 대하여 ".mmuoff.data.write" section으로 설정한다.
	 *; 해당 section의 설정을 linker script에서 확인하면 2KB로 align되어
	 *; 있는 것을 확인할 수 있다. ("aw"는 Alloc, Write임을 나타내는 flag)
	 *;
	 *; align을 해 주는 이유는 아키텍처마다 읽어오는 기본 크기(WORD)에
	 *; 맞게 주소를 배치하여 메모리 접근 속도를 최적화하기 위함이다.
	 *; ARM64의 경우 align이 되어 있지 않은 경우 alignment fault가 발생한다.
	 *; >> ARMv8 Architecture Reference Manual, B2.5 참고
	 *;	- Instruction: 언제나 fault 발생
	 *;	- Data, Device Memory: 언제나 fault 발생
	 *;		(현재 MMU off 상태이므로 모두 device memory 취급)
	 *;	- Data, Normal Memory: 거의 다 발생
	 *; */
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
	bl	el2_setup			// Drop to EL1, w0=cpu_boot_mode
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
	bl	el2_setup			// Drop to EL1
	bl	set_cpu_boot_mode_flag
	b	secondary_startup
SYM_FUNC_END(secondary_entry)

SYM_FUNC_START_LOCAL(secondary_startup)
	/*
	 * Common entry point for secondary CPUs.
	 */
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
	ldr	x1, [x0, #CPU_BOOT_STACK]	// get secondary_data.stack
	cbz	x1, __secondary_too_slow
	mov	sp, x1
	ldr	x2, [x0, #CPU_BOOT_TASK]
	cbz	x2, __secondary_too_slow
	msr	sp_el0, x2
	scs_load x2, x3
	mov	x29, #0
	mov	x30, #0

#ifdef CONFIG_ARM64_PTR_AUTH
	ptrauth_keys_init_cpu x2, x3, x4, x5
#endif

	b	secondary_start_kernel
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
	cmp	x2, #ID_AA64MMFR0_TGRAN_SUPPORTED
	b.ne	__no_granule_support
	update_early_cpu_boot_status 0, x2, x3
	adrp	x2, idmap_pg_dir
	phys_to_ttbr x1, x1
	phys_to_ttbr x2, x2
	msr	ttbr0_el1, x2			// load TTBR0
	offset_ttbr1 x1, x3
	msr	ttbr1_el1, x1			// load TTBR1
	isb
	msr	sctlr_el1, x0
	isb
	/*
	 * Invalidate the local I-cache so that any instructions fetched
	 * speculatively from the PoC are discarded, since they may have
	 * been dynamically patched at the PoU.
	 */
	ic	iallu
	dsb	nsh
	isb
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
	/*; Iamroot17A 2020.Nov.21 #10.1
	 *;
	 *; KASLR을 적용하기 위해서 다시 return하면 여기부터 실행된다.
	 *; 먼저 MMU를 다시 비활성화하고 다시 페이지 테이블을 생성한다.
	 *; MMU 비활성화 이후 다시 물리 주소 기반으로 수행되도록
	 *; Instruction Barrier를 수행한다.
	 *; (per_disable_mmu_workaround도 Instruction Barrier를 수행하지만
	 *;  특수한 경우에만 필요한 것으로 보임.)
	 *; */
	pre_disable_mmu_workaround
	msr	sctlr_el1, x20			// disable the MMU
	isb
	bl	__create_page_tables		// recreate kernel mapping

	/*; Iamroot17A 2020.Nov.21 #10.2
	 *;
	 *; MMU 비활성화 이전에 생성되었던 TLB entry들을 모두 invalidate한다.
	 *; */
	tlbi	vmalle1				// Remove any stale TLB entries
	dsb	nsh

	msr	sctlr_el1, x19			// re-enable the MMU
	isb
	ic	iallu				// flush instructions fetched
	dsb	nsh				// via old mapping
	isb

	bl	__relocate_kernel
	/*; Iamroot17A 2020.Nov.21 #10.3
	 *;
	 *; 다시 relocate하고 __primary_switched()를 호출한다.
	 *; 이전과 달리 KASLR이 적용되어있으므로 다시 복귀하지 않고
	 *; start_kernel()로 진입하게 될 것이다.
	 *; */
#endif
#endif
	ldr	x8, =__primary_switched
	adrp	x0, __PHYS_OFFSET
	br	x8
SYM_FUNC_END(__primary_switch)
