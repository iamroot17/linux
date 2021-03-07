/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2012 ARM Ltd.
 */
#ifndef __ASM_IRQFLAGS_H
#define __ASM_IRQFLAGS_H

#include <asm/alternative.h>
#include <asm/barrier.h>
#include <asm/ptrace.h>
#include <asm/sysreg.h>

/*
 * Aarch64 has flags for masking: Debug, Asynchronous (serror), Interrupts and
 * FIQ exceptions, in the 'daif' register. We mask and unmask them in 'dai'
 * order:
 * Masking debug exceptions causes all other exceptions to be masked too/
 * Masking SError masks irq, but not debug exceptions. Masking irqs has no
 * side effects for other flags. Keeping to this order makes it easier for
 * entry.S to know which exceptions should be unmasked.
 *
 * FIQ is never expected, but we mask it when we disable debug exceptions, and
 * unmask it at all other times.
 */

/*
 * CPU interrupt mask handling.
 */
static inline void arch_local_irq_enable(void)
{
	if (system_has_prio_mask_debugging()) {
		u32 pmr = read_sysreg_s(SYS_ICC_PMR_EL1);

		WARN_ON_ONCE(pmr != GIC_PRIO_IRQON && pmr != GIC_PRIO_IRQOFF);
	}

	asm volatile(ALTERNATIVE(
		"msr	daifclr, #2		// arch_local_irq_enable",
		__msr_s(SYS_ICC_PMR_EL1, "%0"),
		ARM64_HAS_IRQ_PRIO_MASKING)
		:
		: "r" ((unsigned long) GIC_PRIO_IRQON)
		: "memory");

	pmr_sync();
}

/*; Iamroot17A 2020.Dec.12 #1.2
 *; 각 architecture별로 local_irq_disable하게 된다.
 *; >> http://jake.dothome.co.kr/irq-desc/ 참고 (Local IRQ 제어)
 *; */
static inline void arch_local_irq_disable(void)
{
	/*; Iamroot17A 2020.Dec.12 #1.3
	 *; 아래 if문은 defconfig로 빌드 된 binary에서 없는 것이 확인됨
	 *; */
	if (system_has_prio_mask_debugging()) {
		u32 pmr = read_sysreg_s(SYS_ICC_PMR_EL1);

		WARN_ON_ONCE(pmr != GIC_PRIO_IRQON && pmr != GIC_PRIO_IRQOFF);
	}

	/*; Iamroot17A 2020.Dec.12 #1.4
	 *; Inline assembly: C 코드에서 assembly code를 직접 명시하기 위해
	 *; 표현하는 방법. 기존 C의 변수와 연계하는 작업이 필요함.
	 *; >> http://jake.dothome.co.kr/inline-assembly/ 참고
	 *; */
	/*; Iamroot17A 2020.Dec.12 #1.5
	 *; ALTERNATIVE: 조건에 따른 분기를 하지 않으면서 instruction을
	 *; 상황에 따라 교체하기 위해 사용하는 macro.
	 *; 1) boot시 하위 호환성 유지를 위해 가장 기본적인 instruction을 사용
	 *; 2) boot되는 CPU(primary)는 기본적인 instruction을 사용 (이하 old)
	 *; 3) start_kernel() => .... => apply_alternatives_all() 호출시
	 *;    ALTERNATIVE()에 정의된 old instruction들이 같은 역할의 다른
	 *;    instruction(이하 new)로 변경됨. (특정 조건을 만족하는 경우)
	 *;    (특정 조건은 보통 CPU extension의 지원 여부를 말하는 듯)
	 *; 4) 나머지 secondary CPU들은 교체된 new instruction을 사용하게 됨.
	 *; >> http://jake.dothome.co.kr/alternative/ 참고
	 *; */
	asm volatile(ALTERNATIVE(
		/*; Iamroot17A 2020.Dec.12 #1.6
		 *; D A I F 중 I flag만 1로 설정 => IRQ mask => IRQ 익셉션 비활성화
		 *; >> https://developer.arm.com/documentation/ddi0595/2020-12/AArch64-Registers/DAIF--Interrupt-Mask-Bits 참고
		 *; Iamroot17 2021.Feb.27 #3
		 *; DAIFSet을 설정하므로, I flag를 제외한 D A F flags는 기본값을
		 *; 유지하게 된다. (모든 flag의 기본 값은 1이다)
		 *; >> ARM Ref. Manual F.c D1.7 Process state, PSTATE 참고
		 *; (Priority Masking이 지원되지 않을때는 DAIF flag 변경)
		 *; */
		"msr	daifset, #2		// arch_local_irq_disable",
		/*; Iamroot17A 2020.Dec.12 #1.6.1
		 *; Priority Mask Register로 기본 IRQ만 disable하고,
		 *; NMI에 사용하는 IRQ는 통과시키는 기법을 사용한다.
		 *; >> https://developer.arm.com/docs/ddi0601/c/aarch64-system-registers/icc_pmr_el1 참고
		 *; */
		__msr_s(SYS_ICC_PMR_EL1, "%0"),
		/*; Iamroot17A 2020.Dec.12 #1.6.2
		 *; Pseudo-NMI(Non-Maskable Interrupt) 지원 여부 확인
		 *; CPU가 GIC(Generic Interrupt Controller)v3 이상일 경우
		 *; NMI 기술과 비슷하게 흉내낼 수 있음.
		 *; >> 관련 commit: b90d2b22afdc7ce150a9ee7a8d82378bcfc395a5
		 *; >> arch/arm64/Kconfig ARM64_PSEUDO_NMI 참고
		 *; >> arch/arm64/kernel/cpufeature.c 참고
		 *; >> arch/arm64/include/asm/cpucaps.h 참고
		 *; */
		ARM64_HAS_IRQ_PRIO_MASKING)
		:
		: "r" ((unsigned long) GIC_PRIO_IRQOFF)
		: "memory");
}

/*
 * Save the current interrupt enable state.
 */
static inline unsigned long arch_local_save_flags(void)
{
	unsigned long flags;

	asm volatile(ALTERNATIVE(
		"mrs	%0, daif",
		__mrs_s("%0", SYS_ICC_PMR_EL1),
		ARM64_HAS_IRQ_PRIO_MASKING)
		: "=&r" (flags)
		:
		: "memory");

	return flags;
}

static inline int arch_irqs_disabled_flags(unsigned long flags)
{
	int res;

	asm volatile(ALTERNATIVE(
		"and	%w0, %w1, #" __stringify(PSR_I_BIT),
		"eor	%w0, %w1, #" __stringify(GIC_PRIO_IRQON),
		ARM64_HAS_IRQ_PRIO_MASKING)
		: "=&r" (res)
		: "r" ((int) flags)
		: "memory");

	return res;
}

static inline int arch_irqs_disabled(void)
{
	return arch_irqs_disabled_flags(arch_local_save_flags());
}

static inline unsigned long arch_local_irq_save(void)
{
	unsigned long flags;

	flags = arch_local_save_flags();

	/*
	 * There are too many states with IRQs disabled, just keep the current
	 * state if interrupts are already disabled/masked.
	 */
	if (!arch_irqs_disabled_flags(flags))
		arch_local_irq_disable();

	return flags;
}

/*
 * restore saved IRQ state
 */
static inline void arch_local_irq_restore(unsigned long flags)
{
	asm volatile(ALTERNATIVE(
		"msr	daif, %0",
		__msr_s(SYS_ICC_PMR_EL1, "%0"),
		ARM64_HAS_IRQ_PRIO_MASKING)
		:
		: "r" (flags)
		: "memory");

	pmr_sync();
}

#endif /* __ASM_IRQFLAGS_H */
