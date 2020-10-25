/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Cache maintenance
 *
 * Copyright (C) 2001 Deep Blue Solutions Ltd.
 * Copyright (C) 2012 ARM Ltd.
 */

#include <linux/errno.h>
#include <linux/linkage.h>
#include <linux/init.h>
#include <asm/assembler.h>
#include <asm/cpufeature.h>
#include <asm/alternative.h>
#include <asm/asm-uaccess.h>

/*
 *	caches_clean_inval_pou_macro(start,end) [fixup]
 *
 *	Ensure that the I and D caches are coherent within specified region.
 *	This is typically used when code has been written to a memory region,
 *	and will be executed.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 *	- fixup   - optional label to branch to on user fault
 */
.macro	caches_clean_inval_pou_macro, fixup
alternative_if ARM64_HAS_CACHE_IDC
	dsb     ishst
	b       .Ldc_skip_\@
alternative_else_nop_endif
	mov     x2, x0
	mov     x3, x1
	dcache_by_line_op cvau, ish, x2, x3, x4, x5, \fixup
.Ldc_skip_\@:
alternative_if ARM64_HAS_CACHE_DIC
	isb
	b	.Lic_skip_\@
alternative_else_nop_endif
	invalidate_icache_by_line x0, x1, x2, x3, \fixup
.Lic_skip_\@:
.endm

/*
 *	caches_clean_inval_pou(start,end)
 *
 *	Ensure that the I and D caches are coherent within specified region.
 *	This is typically used when code has been written to a memory region,
 *	and will be executed.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START(caches_clean_inval_pou)
	caches_clean_inval_pou_macro
	ret
SYM_FUNC_END(caches_clean_inval_pou)

/*
 *	caches_clean_inval_user_pou(start,end)
 *
 *	Ensure that the I and D caches are coherent within specified region.
 *	This is typically used when code has been written to a memory region,
 *	and will be executed.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START(caches_clean_inval_user_pou)
	uaccess_ttbr0_enable x2, x3, x4

	caches_clean_inval_pou_macro 2f
	mov	x0, xzr
1:
	uaccess_ttbr0_disable x1, x2
	ret
2:
	mov	x0, #-EFAULT
	b	1b
SYM_FUNC_END(caches_clean_inval_user_pou)

/*
 *	icache_inval_pou(start,end)
 *
 *	Ensure that the I cache is invalid within specified region.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START(icache_inval_pou)
alternative_if ARM64_HAS_CACHE_DIC
	isb
	ret
alternative_else_nop_endif

	invalidate_icache_by_line x0, x1, x2, x3
	ret
SYM_FUNC_END(icache_inval_pou)

/*
 *	dcache_clean_inval_poc(start, end)
 *
 *	Ensure that any D-cache lines for the interval [start, end)
 *	are cleaned and invalidated to the PoC.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START_PI(dcache_clean_inval_poc)
	dcache_by_line_op civac, sy, x0, x1, x2, x3
	ret
SYM_FUNC_END_PI(dcache_clean_inval_poc)

/*
 *	dcache_clean_pou(start, end)
 *
 * 	Ensure that any D-cache lines for the interval [start, end)
 * 	are cleaned to the PoU.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START(dcache_clean_pou)
alternative_if ARM64_HAS_CACHE_IDC
	dsb	ishst
	ret
alternative_else_nop_endif
	dcache_by_line_op cvau, ish, x0, x1, x2, x3
	ret
SYM_FUNC_END(dcache_clean_pou)

/*
 *	dcache_inval_poc(start, end)
 *
 * 	Ensure that any D-cache lines for the interval [start, end)
 * 	are invalidated. Any partial lines at the ends of the interval are
 *	also cleaned to PoC to prevent data loss.
 *
 *	- start   - kernel start address of region
 *	- end     - kernel end address of region
 */
SYM_FUNC_START_LOCAL(__dma_inv_area)
SYM_FUNC_START_PI(dcache_inval_poc)
	/* FALLTHROUGH */

/*
 *	__dma_inv_area(start, end)
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
	/*; Iamroot17A 2020.Oct.17 #9.1
	 *; == v5.9의 경우 현재 함수가 __inval_dcache_area였음 ==
	 *; 당시 함수의 인자 형태는 아래와 같았음.
	 *; X0는 Invalidate 할 D-Cache의 시작주소를 전달했으며
	 *; X1은 Invalidate 할 D-Cache의 크기를 나타냈다.
	 *; 여기에서 `add x1, x1, x0`를 함으로서 X1을 Invalidate할
	 *; 끝 주소로 변경했으나, 현재는 이미 X1이 변경된 상태로 호출됨
	 *; */
	/*; add	x1, x1, x0 */
	/*; Iamroot17A 2020.Oct.17 #9.2
	 *; d-cache line 크기를 이용하여 x1(끝 주소)의 align여부를 확인한다.
	 *; */
	dcache_line_size x2, x3
	sub	x3, x2, #1
	tst	x1, x3				// end cache line aligned?
	/*; Iamroot17A 2020.Oct.17 #9.3
	 *; X1을 d-cache 크기에 맞게 align한다.
	 *; */
	bic	x1, x1, x3
	/*; Iamroot17A 2020.Oct.17 #9.4
	 *; X1 (Invalidate 할 영역의 끝 주소)이 align된 주소가 아니라면
	 *; Clean & Invalidate를 한다. (invalidate 하기 전에 수정한 값이
	 *; 적용될 수 있게 해주고 Invalidate 처리한다.)
	 *; branch시 1f는 아래 방향으로(forward) 1 label을 찾아 분기하라는 뜻
	 *; 1b는 위 방향으로(backward) 1 label을 찾아 분기하라는 뜻
	 *; */
	b.eq	1f
	dc	civac, x1			// clean & invalidate D / U line
	/*; Iamroot17A 2020.Oct.17 #9.5
	 *; X0 (Invalidate 할 영역의 시작 주소)이 align되어있는지 확인하고,
	 *; 해당 영역이 align되어있지 않다면 Clean & Invalidate를 한다.
	 *; (이전의 X1의 align 확인 및 Clean & Invalidate와 같은 맥락)
	 *; */
1:	tst	x0, x3				// start cache line aligned?
	bic	x0, x0, x3
	b.eq	2f
	dc	civac, x0			// clean & invalidate D / U line
	b	3f
	/*; Iamroot17A 2020.Oct.17 #9.6
	 *; d-cache size 단위로 invalidate하고, x1(끝 주소)까지 반복한다.
	 *; */
2:	dc	ivac, x0			// invalidate D / U line
3:	add	x0, x0, x2
	cmp	x0, x1
	b.lo	2b
	dsb	sy
	ret
SYM_FUNC_END_PI(dcache_inval_poc)
SYM_FUNC_END(__dma_inv_area)

/*
 *	dcache_clean_poc(start, end)
 *
 * 	Ensure that any D-cache lines for the interval [start, end)
 * 	are cleaned to the PoC.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START_LOCAL(__dma_clean_area)
SYM_FUNC_START_PI(dcache_clean_poc)
	/* FALLTHROUGH */

/*
 *	__dma_clean_area(start, end)
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
	dcache_by_line_op cvac, sy, x0, x1, x2, x3
	ret
SYM_FUNC_END_PI(dcache_clean_poc)
SYM_FUNC_END(__dma_clean_area)

/*
 *	dcache_clean_pop(start, end)
 *
 * 	Ensure that any D-cache lines for the interval [start, end)
 * 	are cleaned to the PoP.
 *
 *	- start   - virtual start address of region
 *	- end     - virtual end address of region
 */
SYM_FUNC_START_PI(dcache_clean_pop)
	alternative_if_not ARM64_HAS_DCPOP
	b	dcache_clean_poc
	alternative_else_nop_endif
	dcache_by_line_op cvap, sy, x0, x1, x2, x3
	ret
SYM_FUNC_END_PI(dcache_clean_pop)

/*
 *	__dma_flush_area(start, size)
 *
 *	clean & invalidate D / U line
 *
 *	- start   - virtual start address of region
 *	- size    - size in question
 */
SYM_FUNC_START_PI(__dma_flush_area)
	add	x1, x0, x1
	dcache_by_line_op civac, sy, x0, x1, x2, x3
	ret
SYM_FUNC_END_PI(__dma_flush_area)

/*
 *	__dma_map_area(start, size, dir)
 *	- start	- kernel virtual start address
 *	- size	- size of region
 *	- dir	- DMA direction
 */
SYM_FUNC_START_PI(__dma_map_area)
	add	x1, x0, x1
	cmp	w2, #DMA_FROM_DEVICE
	b.eq	__dma_inv_area
	b	__dma_clean_area
SYM_FUNC_END_PI(__dma_map_area)

/*
 *	__dma_unmap_area(start, size, dir)
 *	- start	- kernel virtual start address
 *	- size	- size of region
 *	- dir	- DMA direction
 */
SYM_FUNC_START_PI(__dma_unmap_area)
	add	x1, x0, x1
	cmp	w2, #DMA_TO_DEVICE
	b.ne	__dma_inv_area
	ret
SYM_FUNC_END_PI(__dma_unmap_area)
