; NESOS Kernel v1.0
; Core kernel services for NESOS
; Links with main NESOS system
; Author: [Your Name]
; Date: 2024-10-22

; =====================
; Kernel Constants
; =====================
K_SUCCESS       = $00       ; Success return code
K_ERROR         = $FF       ; Error return code

; System Call Numbers
SYS_EXIT        = $00       ; Exit current task
SYS_SPAWN       = $01       ; Create new task
SYS_SLEEP       = $02       ; Sleep task
SYS_GETPID      = $03       ; Get current task ID
SYS_YIELD       = $04       ; Yield to next task
SYS_SEND        = $05       ; Send message
SYS_RECV        = $06       ; Receive message
SYS_ALLOC       = $07       ; Allocate memory
SYS_FREE        = $08       ; Free memory
SYS_DRAW        = $09       ; Draw to screen
SYS_INPUT       = $0A       ; Get input state

; Memory Management
PAGE_SIZE       = 256       ; Size of memory page
MAX_PAGES       = 16        ; Maximum allocatable pages
HEAP_START      = $0800     ; Start of heap memory
HEAP_END        = $1800     ; End of heap memory

; Message System
MSG_SIZE        = 16        ; Size of message buffer
MAX_MESSAGES    = 8         ; Maximum pending messages per task
MSG_QUEUE_SIZE  = MAX_TASKS * MAX_MESSAGES

; =====================
; Kernel Zero Page
; =====================
        .org $80           ; Reserve $80-$FF for kernel
k_temp1:        .res 1     ; Kernel temporary storage
k_temp2:        .res 1
k_syscall_num:  .res 1     ; Current system call number
k_syscall_param:.res 2     ; System call parameters
k_msg_count:    .res 1     ; Number of pending messages
k_heap_ptr:     .res 2     ; Current heap pointer

; =====================
; Kernel Data Structures
; =====================
        .org $1000
; Memory Management
page_table:     .res MAX_PAGES      ; Memory page allocation table
page_owner:     .res MAX_PAGES      ; Task ID owning each page

; Message System
msg_queue:      .res MSG_QUEUE_SIZE * MSG_SIZE  ; Message queue
msg_sender:     .res MSG_QUEUE_SIZE ; Sender task IDs
msg_receiver:   .res MSG_QUEUE_SIZE ; Receiver task IDs

; =====================
; Kernel Entry Point
; =====================
KERNEL_INIT:
        ; Initialize kernel subsystems
        JSR INIT_MEMORY_MGR
        JSR INIT_MSG_SYSTEM
        JSR INIT_SCHEDULER
        
        ; Set up system call vector
        LDA #<SYSCALL_HANDLER
        STA $FFFE
        LDA #>SYSCALL_HANDLER
        STA $FFFF
        
        RTS

; =====================
; System Call Handler
; =====================
SYSCALL_HANDLER:
        PHP                 ; Save processor state
        PHA
        TXA
        PHA
        TYA
        PHA
        
        ; Get system call number
        LDA k_syscall_num
        
        ; Jump table for system calls
        ASL A              ; Multiply by 2 for word addresses
        TAX
        LDA syscall_table,X
        STA vector_low
        LDA syscall_table+1,X
        STA vector_high
        JSR dispatch_syscall
        
        ; Restore state and return
        PLA
        TAY
        PLA
        TAX
        PLA
        PLP
        RTI

dispatch_syscall:
        JMP (vector_low)

; System call jump table
syscall_table:
        .dw sys_exit       ; SYS_EXIT
        .dw sys_spawn      ; SYS_SPAWN
        .dw sys_sleep      ; SYS_SLEEP
        .dw sys_getpid     ; SYS_GETPID
        .dw sys_yield      ; SYS_YIELD
        .dw sys_send       ; SYS_SEND
        .dw sys_recv       ; SYS_RECV
        .dw sys_alloc      ; SYS_ALLOC
        .dw sys_free       ; SYS_FREE
        .dw sys_draw       ; SYS_DRAW
        .dw sys_input      ; SYS_INPUT

; =====================
; Memory Manager
; =====================
INIT_MEMORY_MGR:
        ; Clear page tables
        LDA #0
        LDX #MAX_PAGES
@clear_tables:
        STA page_table-1,X
        STA page_owner-1,X
        DEX
        BNE @clear_tables
        
        ; Initialize heap pointer
        LDA #<HEAP_START
        STA k_heap_ptr
        LDA #>HEAP_START
        STA k_heap_ptr+1
        RTS

; Allocate memory page
sys_alloc:
        ; Find free page
        LDX #0
@find_page:
        LDA page_table,X
        BEQ @page_found
        INX
        CPX #MAX_PAGES
        BNE @find_page
        LDA #K_ERROR       ; No free pages
        RTS

@page_found:
        ; Mark page as used
        LDA #$FF
        STA page_table,X
        
        ; Set owner
        LDA current_task
        STA page_owner,X
        
        ; Calculate page address
        TXA
        CLC
        ADC #>HEAP_START
        
        LDA #K_SUCCESS
        RTS

; Free memory page
sys_free:
        ; Find page to free
        LDX k_syscall_param
        
        ; Verify ownership
        LDA page_owner,X
        CMP current_task
        BNE @error
        
        ; Mark page as free
        LDA #0
        STA page_table,X
        STA page_owner,X
        
        LDA #K_SUCCESS
        RTS
@error:
        LDA #K_ERROR
        RTS

; =====================
; Message System
; =====================
INIT_MSG_SYSTEM:
        LDA #0
        STA k_msg_count
        RTS

; Send message
sys_send:
        LDX k_msg_count
        CPX #MSG_QUEUE_SIZE
        BCS @queue_full
        
        ; Store message
        LDY #0
@copy_msg:
        LDA (k_syscall_param),Y
        STA msg_queue,X
        INY
        CPY #MSG_SIZE
        BNE @copy_msg
        
        ; Store sender and receiver
        LDA current_task
        STA msg_sender,X
        LDA k_syscall_param+1
        STA msg_receiver,X
        
        INC k_msg_count
        LDA #K_SUCCESS
        RTS
@queue_full:
        LDA #K_ERROR
        RTS

; Receive message
sys_recv:
        ; Find message for current task
        LDX #0
@find_msg:
        CPX k_msg_count
        BCS @no_message
        
        LDA msg_receiver,X
        CMP current_task
        BEQ @msg_found
        
        INX
        BNE @find_msg

@msg_found:
        ; Copy message to user buffer
        LDY #0
@copy_msg:
        LDA msg_queue,X
        STA (k_syscall_param),Y
        INY
        CPY #MSG_SIZE
        BNE @copy_msg
        
        ; Remove message from queue
        JSR remove_message
        
        LDA #K_SUCCESS
        RTS
@no_message:
        LDA #K_ERROR
        RTS

; Remove message from queue
remove_message:
        ; Shift remaining messages
        PHX
@shift_loop:
        CPX k_msg_count
        BCS @done_shift
        
        INX
        LDY #0
@copy_next:
        LDA msg_queue,X
        STA msg_queue-1,X
        INY
        CPY #MSG_SIZE
        BNE @copy_next
        
        LDA msg_sender,X
        STA msg_sender-1,X
        LDA msg_receiver,X
        STA msg_receiver-1,X
        
        JMP @shift_loop

@done_shift:
        DEC k_msg_count
        PLX
        RTS

; =====================
; Task Management
; =====================
; Exit current task
sys_exit:
        LDX current_task
        LDA #TASK_INACTIVE
        STA task_status,X
        DEC task_count
        JMP SCHEDULE_TASKS

; Spawn new task
sys_spawn:
        LDA k_syscall_param
        LDY k_syscall_param+1
        JSR CREATE_TASK
        RTS

; Sleep current task
sys_sleep:
        LDX current_task
        LDA k_syscall_param
        STA task_sleep,X
        LDA #TASK_SLEEPING
        STA task_status,X
        JMP SCHEDULE_TASKS

; Get current task ID
sys_getpid:
        LDA current_task
        RTS

; Yield to next task
sys_yield:
        JMP SCHEDULE_TASKS

; =====================
; Graphics Services
; =====================
; Draw to screen
sys_draw:
        ; Parameters:
        ; X position: k_syscall_param
        ; Y position: k_syscall_param+1
        ; Pattern: pointed to by (k_temp1)
        
        ; Calculate PPU address
        LDA PPUSTATUS      ; Reset PPU address latch
        
        LDA k_syscall_param+1
        ASL A
        ASL A
        ASL A
        ORA #$20           ; Nametable 0
        STA PPUADDR
        
        LDA k_syscall_param
        STA PPUADDR
        
        ; Copy pattern
        LDY #0
@copy_pattern:
        LDA (k_temp1),Y
        STA PPUDATA
        INY
        CPY #8             ; 8x8 tile
        BNE @copy_pattern
        
        LDA #K_SUCCESS
        RTS

; =====================
; Input Services
; =====================
; Get input state
sys_input:
        LDA CTRL1_INPUT
        STA (k_syscall_param)
        LDA #K_SUCCESS
        RTS

; =====================
; Kernel API Macros
; =====================
.macro SYSCALL num, param1=0, param2=0
        LDA #num
        STA k_syscall_num
        .if param1 != 0
        LDA #<param1
        STA k_syscall_param
        .endif
        .if param2 != 0
        LDA #>param2
        STA k_syscall_param+1
        .endif
        BRK
.endmacro

; Example usage:
; SYSCALL SYS_SPAWN, task_address
; SYSCALL SYS_SLEEP, sleep_ticks
; SYSCALL SYS_SEND, message_buffer, target_task

; =====================
; Helper Functions
; =====================
; Convert task ID to stack pointer
GET_TASK_STACK:
        ASL A              ; Multiply by STACK_SIZE
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<system_stacks
        TAX
        LDA #>system_stacks
        ADC #0
        TAY
        RTS

; End of Kernel
