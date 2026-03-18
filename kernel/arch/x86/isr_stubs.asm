; kernel/arch/x86/isr_stubs.asm
; ISR and IRQ stubs — save CPU state, call C handler, restore and return
;
; .text has to be declared first, before any macros or globals

section .text

global idt_load
extern isr_handler
extern irq_handler
extern syscall_dispatch

; load the IDT register — called from idt_init() in idt.c
idt_load:
    mov  eax, [esp + 4]     ; grab the idtr pointer passed from C
    lidt [eax]
    ret

; ── macros ────────────────────────────────────────────────────────────────────

; for exceptions that don't push an error code — we push a dummy 0
; so the stack layout always matches registers_t
%macro ISR_NOERR 1
global isr%1
isr%1:
    cli
    push dword 0        ; dummy error code
    push dword %1       ; interrupt number
    jmp  isr_common
%endmacro

; for exceptions that DO push an error code (CPU does it automatically)
; we just push the interrupt number on top
%macro ISR_ERR 1
global isr%1
isr%1:
    cli
    push dword %1       ; interrupt number (error code already on stack)
    jmp  isr_common
%endmacro

; ── CPU exceptions 0-31 ───────────────────────────────────────────────────────
; which ones push error codes is defined by the CPU spec
ISR_NOERR  0    ; divide by zero
ISR_NOERR  1    ; debug
ISR_NOERR  2    ; NMI
ISR_NOERR  3    ; breakpoint
ISR_NOERR  4    ; overflow
ISR_NOERR  5    ; bound range exceeded
ISR_NOERR  6    ; invalid opcode
ISR_NOERR  7    ; device not available
ISR_ERR    8    ; double fault          (has error code)
ISR_NOERR  9    ; coprocessor overrun
ISR_ERR   10    ; invalid TSS           (has error code)
ISR_ERR   11    ; segment not present   (has error code)
ISR_ERR   12    ; stack fault           (has error code)
ISR_ERR   13    ; general protection    (has error code)
ISR_ERR   14    ; page fault            (has error code)
ISR_NOERR 15    ; reserved
ISR_NOERR 16    ; x87 FPU error
ISR_ERR   17    ; alignment check       (has error code)
ISR_NOERR 18    ; machine check
ISR_NOERR 19    ; SIMD FP exception
ISR_NOERR 20
ISR_NOERR 21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_NOERR 29
ISR_NOERR 30
ISR_NOERR 31

; ── common exception path ─────────────────────────────────────────────────────
; at this point the stack looks like:
;   [ss, useresp]  — only if coming from ring 3
;   eflags, cs, eip  — pushed by CPU
;   err_code, int_no — pushed by our stub
isr_common:
    pusha               ; push edi,esi,ebp,esp,ebx,edx,ecx,eax

    mov  ax, ds
    push eax            ; save data segment

    mov  ax, 0x10       ; switch to kernel data segment
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax

    push esp            ; pass pointer to registers_t as argument
    call isr_handler
    add  esp, 4         ; clean up the esp argument

    pop  eax            ; restore saved data segment
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax

    popa                ; restore general purpose registers
    add  esp, 8         ; skip int_no and err_code
    sti
    iret

; ── IRQ stubs (hardware interrupts 0-15, mapped to vectors 32-47) ─────────────
%macro IRQ 2
global irq%1
irq%1:
    cli
    push dword 0        ; no error code for IRQs
    push dword %2       ; vector number (32-47)
    jmp  irq_common
%endmacro

IRQ  0, 32    ; timer
IRQ  1, 33    ; keyboard
IRQ  2, 34    ; cascade (PIC2)
IRQ  3, 35    ; COM2
IRQ  4, 36    ; COM1
IRQ  5, 37    ; LPT2
IRQ  6, 38    ; floppy
IRQ  7, 39    ; LPT1
IRQ  8, 40    ; RTC
IRQ  9, 41
IRQ 10, 42
IRQ 11, 43
IRQ 12, 44    ; PS/2 mouse
IRQ 13, 45    ; FPU
IRQ 14, 46    ; primary ATA
IRQ 15, 47    ; secondary ATA

; same save/restore pattern as isr_common, calls irq_handler instead
irq_common:
    pusha

    mov  ax, ds
    push eax

    mov  ax, 0x10
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax

    push esp
    call irq_handler
    add  esp, 4

    pop  eax
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax

    popa
    add  esp, 8
    sti
    iret

; ── int 0x80 — syscall entry point ────────────────────────────────────────────
; user programs call 'int 0x80' to request kernel services
; same save/restore pattern, routes to syscall_dispatch in C
global isr128
isr128:
    cli
    push dword 0        ; dummy error code
    push dword 128      ; vector number

    pusha
    mov  ax, ds
    push eax

    mov  ax, 0x10
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax

    push esp
    call syscall_dispatch
    add  esp, 4

    pop  eax
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax

    popa
    add  esp, 8
    sti
    iret

; marks the stack as non-executable — must be last, after all code
section .note.GNU-stack noalloc noexec nowrite progbits
