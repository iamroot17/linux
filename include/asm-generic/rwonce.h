/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Prevent the compiler from merging or refetching reads or writes. The
 * compiler is also forbidden from reordering successive instances of
 * READ_ONCE and WRITE_ONCE, but only when the compiler is aware of some
 * particular ordering. One way to make the compiler aware of ordering is to
 * put the two invocations of READ_ONCE or WRITE_ONCE in different C
 * statements.
 *
 * These two macros will also work on aggregate data types like structs or
 * unions.
 *
 * Their two major use cases are: (1) Mediating communication between
 * process-level code and irq/NMI handlers, all running on the same CPU,
 * and (2) Ensuring that the compiler does not fold, spindle, or otherwise
 * mutilate accesses that either do not require ordering or that interact
 * with an explicit memory barrier or atomic instruction that provides the
 * required ordering.
 */
#ifndef __ASM_GENERIC_RWONCE_H
#define __ASM_GENERIC_RWONCE_H

#ifndef __ASSEMBLY__

#include <linux/compiler_types.h>
#include <linux/kasan-checks.h>
#include <linux/kcsan-checks.h>

/*
 * Yes, this permits 64-bit accesses on 32-bit architectures. These will
 * actually be atomic in some cases (namely Armv7 + LPAE), but for others we
 * rely on the access being split into 2x32-bit accesses for a 32-bit quantity
 * (e.g. a virtual address) and a strong prevailing wind.
 */
/*; Iamroot17A 2020.Nov.28 #9.3
 *;
 *; WRITE_ONCE에서 compiletime_assert_rwonce_type(x)를 수행하게 되는데,
 *; 해당 내용은 WRITE_ONCE할 변수가 CPU에서 1 cycle로 write 할 수 있는 변수인지
 *; 확인한다. (__native_word(t)는 char, short, int, long의 크기인지 확인)
 *; atomic한 64bit 값 변경을 위해 long long의 경우가 추가된 것으로 보임.
 *; >> 관련 commit: 9e343b467c70379e66b8b771d96f03ae23eba351
 *; */
#define compiletime_assert_rwonce_type(t)					\
	compiletime_assert(__native_word(t) || sizeof(t) == sizeof(long long),	\
		"Unsupported access size for {READ,WRITE}_ONCE().")

/*
 * Use __READ_ONCE() instead of READ_ONCE() if you do not require any
 * atomicity. Note that this may result in tears!
 */
#ifndef __READ_ONCE
#define __READ_ONCE(x)	(*(const volatile __unqual_scalar_typeof(x) *)&(x))
#endif

#define READ_ONCE(x)							\
({									\
	compiletime_assert_rwonce_type(x);				\
	__READ_ONCE(x);							\
})

/*; Iamroot17A 2020.Nov.28 #9.4
 *;
 *; 기능 자체는 x = val; 과 같음. 하지만 앞에 volatile을 붙여줌으로서
 *; 일종의 memory barrier와 같은 효과를 받는 것으로 보임. (컴파일러 최적화 방지)
 *; */
#define __WRITE_ONCE(x, val)						\
do {									\
	*(volatile typeof(x) *)&(x) = (val);				\
} while (0)

/*; Iamroot17A 2020.Nov.28 #9.2
 *;
 *; 함수/매크로 앞에 "__"이 붙은 경우 실제 함수/매크로의 기능을 수행하는 부분을
 *; 뜻한다. (아래 예시의 경우 WRITE_ONCE는 compile time 검증을 먼저 하고 실제
 *; atomic한 write는 __WRITE_ONCE에서 수행되는 것을 확인할 수 있다.
 *; */
#define WRITE_ONCE(x, val)						\
do {									\
	compiletime_assert_rwonce_type(x);				\
	__WRITE_ONCE(x, val);						\
} while (0)

static __no_sanitize_or_inline
unsigned long __read_once_word_nocheck(const void *addr)
{
	return __READ_ONCE(*(unsigned long *)addr);
}

/*
 * Use READ_ONCE_NOCHECK() instead of READ_ONCE() if you need to load a
 * word from memory atomically but without telling KASAN/KCSAN. This is
 * usually used by unwinding code when walking the stack of a running process.
 */
#define READ_ONCE_NOCHECK(x)						\
({									\
	compiletime_assert(sizeof(x) == sizeof(unsigned long),		\
		"Unsupported access size for READ_ONCE_NOCHECK().");	\
	(typeof(x))__read_once_word_nocheck(&(x));			\
})

static __no_kasan_or_inline
unsigned long read_word_at_a_time(const void *addr)
{
	kasan_check_read(addr, 1);
	return *(unsigned long *)addr;
}

#endif /* __ASSEMBLY__ */
#endif	/* __ASM_GENERIC_RWONCE_H */
