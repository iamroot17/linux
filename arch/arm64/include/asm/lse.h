/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __ASM_LSE_H
#define __ASM_LSE_H

#include <asm/atomic_ll_sc.h>

#ifdef CONFIG_ARM64_LSE_ATOMICS

#define __LSE_PREAMBLE	".arch_extension lse\n"

#include <linux/compiler_types.h>
#include <linux/export.h>
#include <linux/jump_label.h>
#include <linux/stringify.h>
#include <asm/alternative.h>
#include <asm/atomic_lse.h>
#include <asm/cpucaps.h>

extern struct static_key_false cpu_hwcap_keys[ARM64_NCAPS];
extern struct static_key_false arm64_const_caps_ready;

static inline bool system_uses_lse_atomics(void)
{
	return (static_branch_likely(&arm64_const_caps_ready)) &&
		static_branch_likely(&cpu_hwcap_keys[ARM64_HAS_LSE_ATOMICS]);
}

/*; Iamroot17A 2020.Dec.12 #5.1
 *;
 *; 현재 빌드 config 설정에 따라 atomic operator의 구현을 (LSE or LL/SC)방식
 *; 혹은 LL/SC방식을 선택하게 된다. (가능하면 LSE 방식을 선호함)
 *; LSE(Large System Extension) : ARMv8.1 extension의 mandatory 기능
 *;  좀 더 개선된 atomic instruction (내부적으로 hardware lock/unlock 사용) 지원
 *;  CAS(Compare and swap) instruction 지원
 *; LL/SC(Load-Linked and Conditional-Store)
 *;  Load시 해당 주소에 접근했다는 표식을 한 뒤, 연산 이후 Store할 때
 *;  해당 표식이 아닐경우 Store가 실패하는 방식이다.
 *;  (해당 표식은 다른 CPU에서 Load/Store 시 변경되므로 atomic하게 완료되지
 *;   않았다면 Store가 실패하기 때문에 다시 LL/SC를 반복하여 시도하게 되어 있음)
 *; */
#define __lse_ll_sc_body(op, ...)					\
({									\
	system_uses_lse_atomics() ?					\
		__lse_##op(__VA_ARGS__) :				\
		__ll_sc_##op(__VA_ARGS__);				\
})

/* In-line patching at runtime */
#define ARM64_LSE_ATOMIC_INSN(llsc, lse)				\
	ALTERNATIVE(llsc, __LSE_PREAMBLE lse, ARM64_HAS_LSE_ATOMICS)

#else	/* CONFIG_ARM64_LSE_ATOMICS */

static inline bool system_uses_lse_atomics(void) { return false; }

#define __lse_ll_sc_body(op, ...)		__ll_sc_##op(__VA_ARGS__)

#define ARM64_LSE_ATOMIC_INSN(llsc, lse)	llsc

#endif	/* CONFIG_ARM64_LSE_ATOMICS */
#endif	/* __ASM_LSE_H */
