/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _ASM_ARCHRANDOM_H
#define _ASM_ARCHRANDOM_H

#ifdef CONFIG_ARCH_RANDOM

#include <linux/bug.h>
#include <linux/kernel.h>
#include <asm/cpufeature.h>

static inline bool __arm64_rndr(unsigned long *v)
{
	bool ok;

	/*
	 * Reads of RNDR set PSTATE.NZCV to 0b0000 on success,
	 * and set PSTATE.NZCV to 0b0100 otherwise.
	 */
	asm volatile(
		__mrs_s("%0", SYS_RNDR_EL0) "\n"
	"	cset %w1, ne\n"
	: "=r" (*v), "=r" (ok)
	:
	: "cc");

	return ok;
}

static inline bool __must_check arch_get_random_long(unsigned long *v)
{
	return false;
}

static inline bool __must_check arch_get_random_int(unsigned int *v)
{
	return false;
}

static inline bool __must_check arch_get_random_seed_long(unsigned long *v)
{
	/*
	 * Only support the generic interface after we have detected
	 * the system wide capability, avoiding complexity with the
	 * cpufeature code and with potential scheduling between CPUs
	 * with and without the feature.
	 */
	if (!cpus_have_const_cap(ARM64_HAS_RNG))
		return false;

	return __arm64_rndr(v);
}


static inline bool __must_check arch_get_random_seed_int(unsigned int *v)
{
	unsigned long val;
	bool ok = arch_get_random_seed_long(&val);

	*v = val;
	return ok;
}

static inline bool __init __early_cpu_has_rndr(void)
{
	/* Open code as we run prior to the first call to cpufeature. */
	unsigned long ftr = read_sysreg_s(SYS_ID_AA64ISAR0_EL1);
	return (ftr >> ID_AA64ISAR0_RNDR_SHIFT) & 0xf;
}

static inline bool __init __must_check
arch_get_random_seed_long_early(unsigned long *v)
{
	WARN_ON(system_state != SYSTEM_BOOTING);

	/*; Iamroot17A 2020.Nov.21 #8.5.1
	 *;
	 *; AA64ISAR0_EL1.RNDR을 확인하여 해당 CPU가 하드웨어적으로 난수를
	 *; 생성할 수 있는지 확인한다.
	 *; */
	if (!__early_cpu_has_rndr())
		return false;

	/*; Iamroot17A 2020.Nov.21 #8.5.2
	 *;
	 *; 하드웨어적 난수 생성이 지원되는 경우, RNDR 레지스터를 통해
	 *; 난수를 받는다.
	 *; */
	return __arm64_rndr(v);
}
#define arch_get_random_seed_long_early arch_get_random_seed_long_early

#else

static inline bool __arm64_rndr(unsigned long *v) { return false; }
static inline bool __init __early_cpu_has_rndr(void) { return false; }

#endif /* CONFIG_ARCH_RANDOM */
#endif /* _ASM_ARCHRANDOM_H */
