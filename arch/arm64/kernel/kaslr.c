// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2016 Linaro Ltd <ard.biesheuvel@linaro.org>
 */

#include <linux/cache.h>
#include <linux/crc32.h>
#include <linux/init.h>
#include <linux/libfdt.h>
#include <linux/mm_types.h>
#include <linux/sched.h>
#include <linux/types.h>
#include <linux/pgtable.h>
#include <linux/random.h>

#include <asm/cacheflush.h>
#include <asm/fixmap.h>
#include <asm/kernel-pgtable.h>
#include <asm/memory.h>
#include <asm/mmu.h>
#include <asm/sections.h>

enum kaslr_status {
	KASLR_ENABLED,
	KASLR_DISABLED_CMDLINE,
	KASLR_DISABLED_NO_SEED,
	KASLR_DISABLED_FDT_REMAP,
};

static enum kaslr_status __initdata kaslr_status;
u64 __ro_after_init module_alloc_base;
u16 __initdata memstart_offset_seed;

static __init u64 get_kaslr_seed(void *fdt)
{
	int node, len;
	fdt64_t *prop;
	u64 ret;

	node = fdt_path_offset(fdt, "/chosen");
	/*; Iamroot17A 2020.Nov.21 #8.3.1
	 *;
	 *; FDT에서 "chosen"을 찾지 못하는 경우 seed 값 얻기 실패
	 *; */
	if (node < 0)
		return 0;

	prop = fdt_getprop_w(fdt, node, "kaslr-seed", &len);
	/*; Iamroot17A 2020.Nov.21 #8.3.2
	 *;
	 *; FDT의 "chosen" 안의 "kaslr-seed" 값을 찾지 못하거나, 해당 값이
	 *; 64bit 길이가 아닌 경우 seed 값 얻기 실패
	 *; */
	if (!prop || len != sizeof(u64))
		return 0;

	ret = fdt64_to_cpu(*prop);
	*prop = 0;
	return ret;
}

static __init const u8 *kaslr_get_cmdline(void *fdt)
{
	static __initconst const u8 default_cmdline[] = CONFIG_CMDLINE;

	if (!IS_ENABLED(CONFIG_CMDLINE_FORCE)) {
		int node;
		const u8 *prop;

		node = fdt_path_offset(fdt, "/chosen");
		if (node < 0)
			goto out;

		prop = fdt_getprop(fdt, node, "bootargs", NULL);
		if (!prop)
			goto out;
		return prop;
	}
out:
	return default_cmdline;
}

/*
 * This routine will be executed with the kernel mapped at its default virtual
 * address, and if it returns successfully, the kernel will be remapped, and
 * start_kernel() will be executed from a randomized virtual offset. The
 * relocation will result in all absolute references (e.g., static variables
 * containing function pointers) to be reinitialized, and zero-initialized
 * .bss variables will be reset to 0.
 */
/*; Iamroot17A 2020.Nov.21 #8.1
 *;
 *; KASLR 적용을 위한 무작위 오프셋을 생성하는 함수이다.
 *; 이번 분석에서는 간략하게 "어떤 경우에 KASLR 적용이 취소되는지"만 분석한다.
 *; KASLR 적용이 취소되지 않으면 어쨋든 무작위 오프셋을 생성한다고 판단한다.
 *; */
u64 __init kaslr_early_init(u64 dt_phys)
{
	void *fdt;
	u64 seed, offset, mask, module_range;
	const u8 *cmdline, *str;
	unsigned long raw;
	int size;

	/*
	 * Set a reasonable default for module_alloc_base in case
	 * we end up running with module randomization disabled.
	 */
	module_alloc_base = (u64)_etext - MODULES_VSIZE;
	__flush_dcache_area(&module_alloc_base, sizeof(module_alloc_base));

	/*
	 * Try to map the FDT early. If this fails, we simply bail,
	 * and proceed with KASLR disabled. We will make another
	 * attempt at mapping the FDT in setup_machine()
	 */
	early_fixmap_init();
	fdt = fixmap_remap_fdt(dt_phys, &size, PAGE_KERNEL);
	/*; Iamroot17A 2020.Nov.21 #8.2
	 *;
	 *; FDT에 대한 Fixmap remapping 실패 시, boot args 확인이 불가능하다.
	 *; bootloader가 올려준 seed 값이나, nokaslr 옵션 등을 확인하지 못하기
	 *; 때문에 KASLR이 취소된다.
	 *; */
	if (!fdt) {
		kaslr_status = KASLR_DISABLED_FDT_REMAP;
		return 0;
	}

	/*
	 * Retrieve (and wipe) the seed from the FDT
	 */
	/*; Iamroot17A 2020.Nov.21 #8.3
	 *;
	 *; FDT의 정보를 불러올 수 있다면, argument로 전달된 kaslr-seed의 값을
	 *; 읽어온다. 만약 실패한다면 seed의 값은 0이다.
	 *; FDT에 전달되는 seed의 값은 EFI에서 생성해서 전달되어야 한다.
	 *; >> Documentation/devicetree/binding/chosen.txt 참고
	 *; */
	seed = get_kaslr_seed(fdt);

	/*
	 * Check if 'nokaslr' appears on the command line, and
	 * return 0 if that is the case.
	 */
	cmdline = kaslr_get_cmdline(fdt);
	str = strstr(cmdline, "nokaslr");
	/*; Iamroot17A 2020.Nov.21 #8.4
	 *;
	 *; 만약 boot args에 전달된 command line중 "nokaslr"이 있는 경우
	 *; 부팅 옵션 중에 강제로 KASLR 취소를 요청한 것이다.
	 *; */
	if (str == cmdline || (str > cmdline && *(str - 1) == ' ')) {
		kaslr_status = KASLR_DISABLED_CMDLINE;
		return 0;
	}

	/*
	 * Mix in any entropy obtainable architecturally if enabled
	 * and supported.
	 */

	/*; Iamroot17A 2020.Nov.21 #8.5
	 *;
	 *; 하드웨어적으로 무작위 값을 얻어온다.
	 *; ARM v8.5에서 FEAT_RNG 기능이 추가되었음. (Implementation-Defined)
	 *; */
	if (arch_get_random_seed_long_early(&raw))
		seed ^= raw;

	/*; Iamroot17A 2020.Nov.21 #8.6
	 *;
	 *; 만약 kaslr-seed를 얻지 못했고, 하드웨어적으로도 무작위 시드 값을
	 *; 생성하지 못했다면 seed 값이 0으로 고정되는 것이며, seed 값의 고정은
	 *; 적절한 무작위성을 보장할 수 없으므로 KASLR을 취소한다.
	 *; */
	if (!seed) {
		kaslr_status = KASLR_DISABLED_NO_SEED;
		return 0;
	}

	/*
	 * OK, so we are proceeding with KASLR enabled. Calculate a suitable
	 * kernel image offset from the seed. Let's place the kernel in the
	 * middle half of the VMALLOC area (VA_BITS_MIN - 2), and stay clear of
	 * the lower and upper quarters to avoid colliding with other
	 * allocations.
	 * Even if we could randomize at page granularity for 16k and 64k pages,
	 * let's always round to 2 MB so we don't interfere with the ability to
	 * map using contiguous PTEs
	 */
	mask = ((1UL << (VA_BITS_MIN - 2)) - 1) & ~(SZ_2M - 1);
	/*; mask = 0x00004FFF_FFE00000 */
	offset = BIT(VA_BITS_MIN - 3) + (seed & mask);
	/*; offset = 0x00002000_00000000 + (seed & mask) */
	/*; vmalloc_start + offset <- _text */

	/* use the top 16 bits to randomize the linear region */
	memstart_offset_seed = seed >> 48;

	if (IS_ENABLED(CONFIG_KASAN))
		/*
		 * KASAN does not expect the module region to intersect the
		 * vmalloc region, since shadow memory is allocated for each
		 * module at load time, whereas the vmalloc region is shadowed
		 * by KASAN zero pages. So keep modules out of the vmalloc
		 * region if KASAN is enabled, and put the kernel well within
		 * 4 GB of the module region.
		 */
		return offset % SZ_2G;

	if (IS_ENABLED(CONFIG_RANDOMIZE_MODULE_REGION_FULL)) {
		/*
		 * Randomize the module region over a 2 GB window covering the
		 * kernel. This reduces the risk of modules leaking information
		 * about the address of the kernel itself, but results in
		 * branches between modules and the core kernel that are
		 * resolved via PLTs. (Branches between modules will be
		 * resolved normally.)
		 */
		module_range = SZ_2G - (u64)(_end - _stext);
		module_alloc_base = max((u64)_end + offset - SZ_2G,
					(u64)MODULES_VADDR);
	} else {
		/*
		 * Randomize the module region by setting module_alloc_base to
		 * a PAGE_SIZE multiple in the range [_etext - MODULES_VSIZE,
		 * _stext) . This guarantees that the resulting region still
		 * covers [_stext, _etext], and that all relative branches can
		 * be resolved without veneers.
		 */
		module_range = MODULES_VSIZE - (u64)(_etext - _stext);
		module_alloc_base = (u64)_etext + offset - MODULES_VSIZE;
	}

	/* use the lower 21 bits to randomize the base of the module region */
	module_alloc_base += (module_range * (seed & ((1 << 21) - 1))) >> 21;
	module_alloc_base &= PAGE_MASK;

	__flush_dcache_area(&module_alloc_base, sizeof(module_alloc_base));
	__flush_dcache_area(&memstart_offset_seed, sizeof(memstart_offset_seed));

	return offset;
}

static int __init kaslr_init(void)
{
	switch (kaslr_status) {
	case KASLR_ENABLED:
		pr_info("KASLR enabled\n");
		break;
	case KASLR_DISABLED_CMDLINE:
		pr_info("KASLR disabled on command line\n");
		break;
	case KASLR_DISABLED_NO_SEED:
		pr_warn("KASLR disabled due to lack of seed\n");
		break;
	case KASLR_DISABLED_FDT_REMAP:
		pr_warn("KASLR disabled due to FDT remapping failure\n");
		break;
	}

	return 0;
}
core_initcall(kaslr_init)
