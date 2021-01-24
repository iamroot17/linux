/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * RCU-based infrastructure for lightweight reader-writer locking
 *
 * Copyright (c) 2015, Red Hat, Inc.
 *
 * Author: Oleg Nesterov <oleg@redhat.com>
 */

#ifndef _LINUX_RCU_SYNC_H_
#define _LINUX_RCU_SYNC_H_

#include <linux/wait.h>
#include <linux/rcupdate.h>

/* Structure to mediate between updaters and fastpath-using readers.  */
struct rcu_sync {
	int			gp_state;
	int			gp_count;
	wait_queue_head_t	gp_wait;

	struct rcu_head		cb_head;
};

/**
 * rcu_sync_is_idle() - Are readers permitted to use their fastpaths?
 * @rsp: Pointer to rcu_sync structure to use for synchronization
 *
 * Returns true if readers are permitted to use their fastpaths.  Must be
 * invoked within some flavor of RCU read-side critical section.
 */
static inline bool rcu_sync_is_idle(struct rcu_sync *rsp)
{
	RCU_LOCKDEP_WARN(!rcu_read_lock_any_held(),
			 "suspicious rcu_sync_is_idle() usage");
	/*; Iamroot17A 2021.Jan.23 #3
	*; RCU의 grace period state가 IDLE인지 확인한다.
	*; kernel/rcu/tree.h L366 (gp_state field) 

	*; !READ_ONCE(rsp->gp_state); 의 코드는
	*; RCU_GP_IDLE 값이 0인 것을 이미 알고 사용한 것이다.
	*; 최근 컴파일러의 최적화 성능을 고려할 때,
	*; (READ_ONCE(rsp->gp_state) == GP_IDLE) 로 표현해도
	*; 비슷한 성능의 코드로 변환될 것으로 예상된다.
	*; 따라서 가독성을 고려할 때, (READ_ONCE(rsp->gp_state) == GP_IDLE) 이 표현이
	*; 더 변경하는 것이 더 좋지 않을까라고 생각한다.
	*; */
	return !READ_ONCE(rsp->gp_state); /* GP_IDLE */
}

extern void rcu_sync_init(struct rcu_sync *);
extern void rcu_sync_enter_start(struct rcu_sync *);
extern void rcu_sync_enter(struct rcu_sync *);
extern void rcu_sync_exit(struct rcu_sync *);
extern void rcu_sync_dtor(struct rcu_sync *);

#define __RCU_SYNC_INITIALIZER(name) {					\
		.gp_state = 0,						\
		.gp_count = 0,						\
		.gp_wait = __WAIT_QUEUE_HEAD_INITIALIZER(name.gp_wait),	\
	}

#define	DEFINE_RCU_SYNC(name)	\
	struct rcu_sync name = __RCU_SYNC_INITIALIZER(name)

#endif /* _LINUX_RCU_SYNC_H_ */
