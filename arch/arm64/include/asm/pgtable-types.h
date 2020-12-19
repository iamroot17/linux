/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Page table types definitions.
 *
 * Copyright (C) 2014 ARM Ltd.
 * Author: Catalin Marinas <catalin.marinas@arm.com>
 */

#ifndef __ASM_PGTABLE_TYPES_H
#define __ASM_PGTABLE_TYPES_H

#include <asm/types.h>

/*; Iamroot17A 2020.Dec.19 #5.1.1
 *;
 *; page table에 대한 type은 아래와 같은 방식으로 정의된다.
 *; 1. 각 page table / page의 주소를 기록할 수 있는 자료형을 typedef로 정의.
 *;    각 자료형은 architecture에 따라 주소의 크기가 변경될 수 있음
 *; 2. 해당 type 변수 1개만 멤버로 갖는 struct를 typedef로 정의.
 *;    이전 typedef된 자료형에, 다른 이름의 멤버 변수를 사용함으로서
 *;    다른 level의 주소에 대해 type casting이 불가능하도록 함.
 *; 3. 각각 getter, setter 역할을 하는 macro를 이용하도록 함.
 *;    macro의 read/write는 type casting이 가능하되, 직접적으로 struct 간
 *;    casting은 불가능 하게 함.
 *; >> Documentation/process/coding-style.rst 참고 (5 Typedefs 부분)
 *; */
typedef u64 pteval_t;
typedef u64 pmdval_t;
typedef u64 pudval_t;
typedef u64 p4dval_t;
typedef u64 pgdval_t;

/*
 * These are used to make use of C type-checking..
 */
typedef struct { pteval_t pte; } pte_t;
#define pte_val(x)	((x).pte)
#define __pte(x)	((pte_t) { (x) } )

#if CONFIG_PGTABLE_LEVELS > 2
typedef struct { pmdval_t pmd; } pmd_t;
#define pmd_val(x)	((x).pmd)
#define __pmd(x)	((pmd_t) { (x) } )
#endif

#if CONFIG_PGTABLE_LEVELS > 3
typedef struct { pudval_t pud; } pud_t;
#define pud_val(x)	((x).pud)
#define __pud(x)	((pud_t) { (x) } )
#endif

typedef struct { pgdval_t pgd; } pgd_t;
#define pgd_val(x)	((x).pgd)
#define __pgd(x)	((pgd_t) { (x) } )

typedef struct { pteval_t pgprot; } pgprot_t;
#define pgprot_val(x)	((x).pgprot)
#define __pgprot(x)	((pgprot_t) { (x) } )

#if CONFIG_PGTABLE_LEVELS == 2
#include <asm-generic/pgtable-nopmd.h>
#elif CONFIG_PGTABLE_LEVELS == 3
#include <asm-generic/pgtable-nopud.h>
#elif CONFIG_PGTABLE_LEVELS == 4
#include <asm-generic/pgtable-nop4d.h>
#endif

#endif	/* __ASM_PGTABLE_TYPES_H */
