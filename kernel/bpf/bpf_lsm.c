// SPDX-License-Identifier: GPL-2.0

/*
 * Copyright (C) 2020 Google LLC.
 */

#include <linux/filter.h>
#include <linux/bpf.h>
#include <linux/btf.h>
#include <linux/lsm_hooks.h>
#include <linux/bpf_lsm.h>
#include <linux/kallsyms.h>
#include <linux/bpf_verifier.h>

/* For every LSM hook that allows attachment of BPF programs, declare a nop
 * function where a BPF program can be attached.
 */
/*; Iamroot17A 2020.Dec.19 #1.1.2
 *;
 *; BPF로 Linux Security Module을 연결할 수 있게 최소한의 기능을 하는 함수
 *; 정의를 자동 생성한다. 해당 함수의 symbol이 필수적으로 생성되어야 하므로
 *; noinline을 이용해 강제로 심볼로 생성되게 한다.
 *; BPF: Berkeley Packet Filter, 원래는 네트워크에서 패킷을 필터링 하기 위해
 *;  개발된 기술이다. 커널 내 각 함수의 특정 지점에서 사용자가 지정한 코드를
 *;  실행할 수 있게 하는 기술로, 현재 trace, performance 등의 용도에서 활발히
 *;  사용되고 있다.
 *; >> https://en.wikipedia.org/wiki/Berkeley_Packet_Filter 참고
 *; >> https://lwn.net/Articles/759188/ 참고 (BPF를 활용한 IR 디코딩)
 *; */
#define LSM_HOOK(RET, DEFAULT, NAME, ...)	\
noinline RET bpf_lsm_##NAME(__VA_ARGS__)	\
{						\
	return DEFAULT;				\
}

/*; ex. lsm_hook_defs.h의 앞부분 자동 생성 예시
 *; ```c
 *; noinline int bpf_lsm_binder_set_context_mgr(struct task_struct *mgr)
 *; {
 *;	return 0;
 *; }
 *; noinline int bpf_lsm_binder_transaction(struct task_struct *from, struct task_struct *to)
 *; {
 *;	return 0;
 *; }
 *; ```
 *; */
#include <linux/lsm_hook_defs.h>
#undef LSM_HOOK

#define BPF_LSM_SYM_PREFX  "bpf_lsm_"

int bpf_lsm_verify_prog(struct bpf_verifier_log *vlog,
			const struct bpf_prog *prog)
{
	if (!prog->gpl_compatible) {
		bpf_log(vlog,
			"LSM programs must have a GPL compatible license\n");
		return -EINVAL;
	}

	if (strncmp(BPF_LSM_SYM_PREFX, prog->aux->attach_func_name,
		    sizeof(BPF_LSM_SYM_PREFX) - 1)) {
		bpf_log(vlog, "attach_btf_id %u points to wrong type name %s\n",
			prog->aux->attach_btf_id, prog->aux->attach_func_name);
		return -EINVAL;
	}

	return 0;
}

const struct bpf_prog_ops lsm_prog_ops = {
};

const struct bpf_verifier_ops lsm_verifier_ops = {
	.get_func_proto = tracing_prog_func_proto,
	.is_valid_access = btf_ctx_access,
};
