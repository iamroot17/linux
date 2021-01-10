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

/*; Iamroot17A 2020.Dec.19 #6
 *;
 *; __lse_ll_sc_body() 매크로에 따르면 system_uses_lse_atomics()을 통해 LSE 지원
 *; 여부를 확인하고, 조건에 따라 LSE방식으로 호출할 지, LL/SC방식으로 호출할지
 *; 결정하게 된다. 실제 지원 여부는 runtime에 결정되기 때문에 어떤 방식의
 *; atomic operation 구현이 사용될 지는 알 수 없다.
 *;
 *; inline assembly에서 단일 instruction의 경우 ALTERNATIVE 매크로를 사용하여
 *; 명령어를 교체할 수 있지만, atomic operation의 구현은 여러 instruction을
 *; 사용하며, 길이가 다르기 때문에 교체하기 복잡하다.
 *;
 *; static key라는 기술은 이와 같이 runtime에 발생하는 branch의 부하를 줄이기
 *; 위해 사용된다.
 *; >> http://jake.dothome.co.kr/static-keys/ 참고
 *; >> include/linux/jump_label.h 참고 (static_branch_likely 정의 상단 설명 부분)
 *; >> arch/arm64/include/asm/jump_label.h 참고 (static key 기술을 통한 branch 코드)
 *; */
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
