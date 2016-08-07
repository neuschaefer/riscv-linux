#include <asm/thread_info.h>
#include <asm/asm-offsets.h>
#include <asm/asm.h>
#include <linux/init.h>
#include <linux/linkage.h>
#include <asm/thread_info.h>
#include <asm/page.h>
#include <asm/csr.h>

__INIT
ENTRY(_start)
	/*
	 * Before anything else, try to detect if we've been started in machine
	 * mode.  We assume that the kernel image is loaded at
	 * 0xffffffff80000000 in virtual memory and an address with leading
	 * zeroes in physical memory.
	 *
	 * This heuristic won't work on RV32, if both the virtual and the
	 * physical address of the kernel are >= 0x80000000.
	 */
	auipc t0, 0
	bltz t0, .Lvirtual_entry

	/* Jump to 0xffffffff80000000 in S-mode */
	li t0, 0xffffffff80000000
	csrw mepc, t0
	csrr t0, mstatus
	li t1, ~(3<<11)
	and t0, t0, t1
	li t2,  (1<<11)
	or t0, t0, t2
	csrw mstatus, t0
	mret

	/* Load the global pointer (before any use of la) */
.Lvirtual_entry:
1:	auipc gp, %pcrel_hi(_gp)
	addi gp, gp, %pcrel_lo(1b)

	/* Disable FPU to detect illegal usage of
	   floating point in kernel space */
	li t0, SR_FS
	csrc sstatus, t0

#ifdef CONFIG_RV_PUM
	/* Prevent inadvertent access to user memory */
	li t0, SR_PUM
	csrs sstatus, t0
#endif

	/* See if we're the main hart */
	call sbi_hart_id
	bnez a0, .Lsecondary_start

	/* Clear the .bss segment */
	la a0, __bss_start
	li a1, 0
	la a2, __bss_stop
	sub a2, a2, a0
	call memset

	/* Initialize stack pointer */
	la sp, init_thread_union + THREAD_SIZE
	/* Initialize current task_struct pointer */
	la tp, init_task

	tail start_kernel

.Lsecondary_start:
#ifdef CONFIG_SMP
	li a1, CONFIG_NR_CPUS
	bgeu a0, a1, .Lsecondary_park

	la a1, __cpu_up_stack_pointer
	slli a0, a0, LGREG
	add a0, a0, a1

.Lwait_for_cpu_up:
	REG_L sp, (a0)
	beqz sp, .Lwait_for_cpu_up

	/* Initialize task_struct pointer */
	li tp, -THREAD_SIZE
	add tp, tp, sp
	REG_L tp, (tp)

	tail smp_callin
#endif

.Lsecondary_park:
	/* We lack SMP support or have too many harts, so park this hart */
	wfi
	j .Lsecondary_park
END(_start)

__PAGE_ALIGNED_BSS
	/* Empty zero page */
	.balign PAGE_SIZE
ENTRY(empty_zero_page)
	.fill (empty_zero_page + PAGE_SIZE) - ., 1, 0x00
END(empty_zero_page)
