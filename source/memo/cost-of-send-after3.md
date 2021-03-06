the cost of erlang:send_after/3
===============================


When you want to do something "after N seconds" in Erlang, the best way to do it is said to be `erlang:send_after/3` . But how many memory does it take? How many computation cost does it take?

# Entry point

`erlang:send_after/3` can be found as bif at [bif.tab](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/bif.tab#L203) . The entry point is at [erl_bif_timer.c](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/erl_bif_timer.c#L493) . This function just calls `setup_bif_timer()`, which is [in the same file](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/erl_bif_timer.c#L390). This allocates `ErtsBifTimer` 

```c
	btm = (ErtsBifTimer *) erts_alloc(ERTS_ALC_T_LL_BIF_TIMER,
					 sizeof(ErtsBifTimer));
```

which is defined in [the same file](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/erl_bif_timer.c#L41) . This does not include such a big struct other than `ErlTimer tm;` ( [defined in erl_time.h](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/erl_time.h#L33) ). Given the struct size is 256B, then registering 10^6 timers costs about 256MB (re-calculate it, please!) . Needs calculation, but and, it is put into timer wheel.

```c
    tab_insert(btm);
    ASSERT(btm == tab_find(ref));
    btm->tm.active = 0; /* MUST be initalized */
    erts_set_timer(&btm->tm,
		  (ErlTimeoutProc) bif_timer_timeout,
		  (ErlCancelProc) bif_timer_cleanup,
		  (void *) btm,
		  timeout);
```

`bif_timer_timeout` is a callback of timeout, and `btm->tm` is `ErlTimer` struct.

# Before/After setting timer

[erts_set_timer in time.c](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/time.c#L397) is very interesting. Just before setting timer, it moves clock forward by calling `erts_deliver_time()` .

```c
void
erts_set_timer(ErlTimer* p, ErlTimeoutProc timeout, ErlCancelProc cancel,
	      void* arg, Uint t)
{

    erts_deliver_time();
    erts_smp_mtx_lock(&tiw_lock);
    if (p->active) { /* XXX assert ? */
	erts_smp_mtx_unlock(&tiw_lock);
	return;
    }
    p->timeout = timeout;
    p->cancel = cancel;
    p->arg = arg;
    p->active = 1;
    insert_timer(p, t);
    erts_smp_mtx_unlock(&tiw_lock);
#if defined(ERTS_SMP)
    if (t <= (Uint) ERTS_SHORT_TIME_T_MAX)
	erts_sys_schedule_interrupt_timed(1, (erts_short_time_t) t);
#endif
}
```

In `insert_timer(p, t);` actually timer is registered, but right after it the erts scheduler is interrupted by [writing "!"](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/sys/common/erl_poll.c#L472) `write(2)` with into scheduler interruption pipe.

# Setting timer actually

`insert_timer` is in [time.c](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/time.c#L347) . `tiw` might be read as "timer wheel" ? maybe. It's actually timer wheel, which has 65536 slots (actually `TIW_SLOTS` ) . Each slot is for single millisecond and keeps all timers that should be invoked in the single milliseconds. Each slot is just a linked list via pointer and generic prev/next pointer linking.

```c
   /* calculate slot */
    tm = (ticks + tiw_pos) % TIW_SIZE;
    p->slot = (Uint) tm;
    p->count = (Uint) (ticks / TIW_SIZE);

    /* insert at head of list at slot */
    p->next = tiw[tm];
    p->prev = NULL;
    if (p->next != NULL)
	p->next->prev = p;
    tiw[tm] = p;

```

# Invoking the timer

`erts_bump_timer` is the function where these timers are triggered. This function is called by several scheduling logic incling `schedule()` like [here](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/erl_process.c#L3012):

```c
        dt = erts_do_time_read_and_reset();
	if (dt) erts_bump_timer(dt);
```

`erts_bump_timer_internal` is the core part of popping out timed out timers from the timer wheel slot [timer.c](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/time.c#L227). Popping out all timer entries to `timeout_head` and calls all callbacks.

```c
    /* Call timedout timers callbacks */
    while (timeout_head) {
	p = timeout_head;
	timeout_head = p->next;
	/* Here comes hairy use of the timer fields!
	 * They are reset without having the lock.
	 * It is assumed that no code but this will
	 * accesses any field until the ->timeout
	 * callback is called.
	 */
	p->next = NULL;
	p->prev = NULL;
	p->slot = 0;
	(*p->timeout)(p->arg);
    }
```

For `erlang:send_after/3` the callback is [bif_timer_timeout](https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/beam/erl_bif_timer.c#L302) . This function calls `erts_queue_message`, which finally stacks the message into target process's msg_q.



# Conclusion

The memory consumption is in order of ~100Bytes per timer. The computation cost is in order of traversing the linked list, whose length is in the same order with Timers stored in each milliseconds.

Suppose 10K timers continuously stored on memory then the length of each queue is 10K / 65536 by average. This is because each timer slot can be accessed by offset.


## Note

In *nix [gettimeofday(2) is used for clock.] (https://github.com/erlang/otp/blob/OTP-17.0/erts/emulator/sys/unix/erl_unix_sys.h#L162) This clock cannot be trusted so much because it leaps back but Erlang remembers the former answer of it and if the time diff is negative, the wrong time is ignored and nothing changes.
