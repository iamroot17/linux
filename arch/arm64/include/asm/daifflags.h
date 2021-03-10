/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2017 ARM Ltd.
 */
#ifndef __ASM_DAIFFLAGS_H
#define __ASM_DAIFFLAGS_H

#include <linux/irqflags.h>

#include <asm/arch_gicv3.h>
#include <asm/barrier.h>
#include <asm/cpufeature.h>
#include <asm/ptrace.h>

#define DAIF_PROCCTX		0
#define DAIF_PROCCTX_NOIRQ	PSR_I_BIT
#define DAIF_ERRCTX		(PSR_I_BIT | PSR_A_BIT)
#define DAIF_MASK		(PSR_D_BIT | PSR_A_BIT | PSR_I_BIT | PSR_F_BIT)


/* mask/save/unmask/restore all exceptions, including interrupts. */
static inline void local_daif_mask(void)
{
	WARN_ON(system_has_prio_mask_debugging() &&
		(read_sysreg_s(SYS_ICC_PMR_EL1) == (GIC_PRIO_IRQOFF |
						    GIC_PRIO_PSR_I_SET)));

	asm volatile(
		"msr	daifset, #0xf		// local_daif_mask\n"
		:
		:
		: "memory");

	/* Don't really care for a dsb here, we don't intend to enable IRQs */
	if (system_uses_irq_prio_masking())
		gic_write_pmr(GIC_PRIO_IRQON | GIC_PRIO_PSR_I_SET);

	trace_hardirqs_off();
}

static inline unsigned long local_daif_save_flags(void)
{
	unsigned long flags;

	flags = read_sysreg(daif);

	if (system_uses_irq_prio_masking()) {
		/* If IRQs are masked with PMR, reflect it in the flags */
		if (read_sysreg_s(SYS_ICC_PMR_EL1) != GIC_PRIO_IRQON)
			flags |= PSR_I_BIT;
	}

	return flags;
}

static inline unsigned long local_daif_save(void)
{
	unsigned long flags;

	flags = local_daif_save_flags();

	local_daif_mask();

	return flags;
}

static inline void local_daif_restore(unsigned long flags)
{
	bool irq_disabled = flags & PSR_I_BIT;

	WARN_ON(system_has_prio_mask_debugging() &&
		!(read_sysreg(daif) & PSR_I_BIT));

	/*; Iamroot17 2021.Feb.27 #1
	 *; DAIF의 값을 변경하여 IRQ 활성화/비활성화를 설정할 때,
	 *; 현재 커널 환경이 Priority Masking을 지원한다면,
	 *; PMR(Priority Masking Register)를 변경하며, 상황에 따라 I flag를
	 *; 입력된 값에서 수정하여 설정하기도 한다.
	 *; Priority Masking: IRQ 중 PMR보다 우선순위가 낮은 (값이 큰)
	 *;                   Interrupt는 무시하는 방식
	 *; (현재 분석의 기준이 되는 defconfig에서는 priority masking을 지원하지
	 *;  않으나, 지원할 경우 어떤 처리가 필요한지에 대해 간략하게 분석함)
	 *; */
	if (!irq_disabled) {
		trace_hardirqs_on();

		if (system_uses_irq_prio_masking()) {
			/*; Iamroot17 2021.Feb.27 #1.1
			 *; 설정할 DAIF가 IRQ를 활성화하고, priority masking을
			 *; 지원하는 경우, GIC의 PMR 값을 IRQ를 켰을 때의 값으로
			 *; 설정한다. (GIC_PRIO_IRQON == 0xE0)
			 *; */
			gic_write_pmr(GIC_PRIO_IRQON);
			pmr_sync();
		}
	} else if (system_uses_irq_prio_masking()) {
		/*; Iamroot17 2021.Feb.27 #1.2
		 *; 설정할 DAIF가 IRQ를 비활성화 하더라도, priority masking이
		 *; 지원된다면, (system_uses_irq_prio_masking()으로 확인)
		 *; 상황에 따라 DAIF의 I flag 값을 변경한다.
		 *; */
		u64 pmr;

		if (!(flags & PSR_A_BIT)) {
			/*
			 * If interrupts are disabled but we can take
			 * asynchronous errors, we can take NMIs
			 */
			/*; Iamroot17 2021.Feb.27 #1.2.1
			 *; SError(System Error)를 처리하는 경우, pseudo-NMI를
			 *; 적용하는 것으로 판단하여, DAIF에서 I flag를
			 *; 변경한다. (0 => IRQ 익셉션 활성화)
			 *; GIC의 PMR 값을 IRQ를 끈 상태의 값으로 설정한다.
			 *; NMI의 priority는 0x20이므로 NMI IRQ를 처리하게 한다.
			 *; (GIC_PRIO_IRQOFF == 0x60)
			 *; >> drivers/irqchip/irq-gic-v3.c 참고 (GIC_INT_NMI_PRI)
			 *; */
			flags &= ~PSR_I_BIT;
			pmr = GIC_PRIO_IRQOFF;
		} else {
			/*; Iamroot17 2021.Feb.27 #1.2.2
			 *; SError를 처리하지 않으므로 pseudo-NMI를 적용하지
			 *; 않는 것으로 판단한다.
			 *; 기존에는 PMR을 IRQON IRQOFF로 구분했는데, I가 set된
			 *; 경우(NMI까지 비활성화 할 때)를 구분하기 위해
			 *; GIC_PRIO_PSR_I_SET을 사용하여 구분한다.
			 *; (GIC_PRIO_IRQON | GIC_PRIO_PSR_I_SET == 0xF0)
			 *; >> 관련 commit: bd82d4bd21880b7c4d5f5756be435095d6ae07b5
			 *; */
			pmr = GIC_PRIO_IRQON | GIC_PRIO_PSR_I_SET;
		}

		/*
		 * There has been concern that the write to daif
		 * might be reordered before this write to PMR.
		 * From the ARM ARM DDI 0487D.a, section D1.7.1
		 * "Accessing PSTATE fields":
		 *   Writes to the PSTATE fields have side-effects on
		 *   various aspects of the PE operation. All of these
		 *   side-effects are guaranteed:
		 *     - Not to be visible to earlier instructions in
		 *       the execution stream.
		 *     - To be visible to later instructions in the
		 *       execution stream
		 *
		 * Also, writes to PMR are self-synchronizing, so no
		 * interrupts with a lower priority than PMR is signaled
		 * to the PE after the write.
		 *
		 * So we don't need additional synchronization here.
		 */
		gic_write_pmr(pmr);
	}

	/*; Iamroot17 2021.Feb.27 #2
	 *; PMR 값의 변경과 DAIF 값 변경 사이의 순서가 변경되는 문제를
	 *; 예상할 수도 있지만, DAIF 값 변경(PSTATE의 값 변경)은 명령어 동기화
	 *; 역할을 수행하며, PMR의 값 변경 또한 자체적으로 동기화하기 때문에
	 *; 추가적인 동기화가 불필요하다.
	 *; */
	write_sysreg(flags, daif);

	if (irq_disabled)
		trace_hardirqs_off();
}

/*
 * Called by synchronous exception handlers to restore the DAIF bits that were
 * modified by taking an exception.
 */
static inline void local_daif_inherit(struct pt_regs *regs)
{
	unsigned long flags = regs->pstate & DAIF_MASK;

	/*
	 * We can't use local_daif_restore(regs->pstate) here as
	 * system_has_prio_mask_debugging() won't restore the I bit if it can
	 * use the pmr instead.
	 */
	write_sysreg(flags, daif);
}
#endif
