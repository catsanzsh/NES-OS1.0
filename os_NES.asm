; NESOS v1.0
; A complete operating system for the NES written in 6502 Assembly
; Author: [Your Name]
; Date: 2024-10-22

        .inesprg 2          ; 32KB PRG ROM
        .ineschr 1          ; 8KB CHR ROM
        .inesmap 0          ; Mapper 0 (NROM)
        .inesmir 1          ; Horizontal mirroring

; =====================
; System Constants
; =====================
MAX_TASKS       = 8         ; Maximum number of concurrent tasks
STACK_SIZE      = 32        ; Stack size per task
TASK_INACTIVE   = $00
TASK_ACTIVE     = $01
TASK_SLEEPING   = $02

; PPU Constants
PPUCTRL         = $2000
PPUMASK         = $2001
PPUSTATUS       = $2002
PPUSCROLL       = $2005
PPUADDR         = $2006
PPUDATA         = $2007

; =====================
; Zero Page Variables
; =====================
        .org $0000
current_task:    .res 1      ; Current running task ID
task_count:      .res 1      ; Number of active tasks
frame_counter:   .res 1      ; Frame counter for timing
temp1:          .res 1      ; Temporary storage
temp2:          .res 1
vector_low:     .res 1      ; For indirect jumping
vector_high:    .res 1

; =====================
; Task Control Block Structure
; =====================
        .org $0200
task_status:    .res MAX_TASKS       ; Status of each task
task_stack_low: .res MAX_TASKS       ; Stack pointer low byte
task_stack_high:.res MAX_TASKS       ; Stack pointer high byte
task_pc_low:    .res MAX_TASKS       ; Program counter low byte
task_pc_high:   .res MAX_TASKS       ; Program counter high byte
task_sleep:     .res MAX_TASKS       ; Sleep counter for each task

; =====================
; System Stack Area
; =====================
        .org $0300
system_stacks:  .res MAX_TASKS * STACK_SIZE

; =====================
; Reset Vector and Interrupt Handlers
; =====================
        .org $8000

RESET:
        SEI                 ; Disable interrupts
        CLD                 ; Clear decimal mode
        LDX #$FF
        TXS                 ; Initialize system stack

        ; Initialize PPU
        JSR INIT_PPU
        
        ; Initialize system
        JSR INIT_MEMORY
        JSR INIT_TASKING
        JSR INIT_GRAPHICS
        JSR INIT_INPUT
        
        ; Start first task
        LDA #0
        STA current_task
        
        ; Enable interrupts
        CLI
        JMP MainLoop

NMI:
        PHA                 ; Save registers
        TXA
        PHA
        TYA
        PHA

        ; Update PPU
        JSR UPDATE_PPU
        
        ; Increment frame counter
        INC frame_counter
        
        ; Update sleep counters
        JSR UPDATE_SLEEP_COUNTERS
        
        PLA                 ; Restore registers
        TAY
        PLA
        TAX
        PLA
        RTI

IRQ:
        RTI

; =====================
; Main System Loop
; =====================
MainLoop:
        JSR POLL_INPUT        ; Read controller input
        JSR SCHEDULE_TASKS    ; Run task scheduler
        JSR UPDATE_GRAPHICS   ; Update graphics
        JMP MainLoop          ; Repeat forever

; =====================
; Task Management
; =====================
INIT_TASKING:
        LDA #0
        STA task_count      ; Clear task counter
        
        ; Initialize task status array
        LDX #MAX_TASKS
@clear_tasks:
        DEX
        LDA #TASK_INACTIVE
        STA task_status,X
        BNE @clear_tasks
        
        ; Create initial task
        LDA #<IDLE_TASK
        LDY #>IDLE_TASK
        JSR CREATE_TASK
        RTS

CREATE_TASK:
        ; Find free task slot
        LDX #0
@find_slot:
        LDA task_status,X
        BEQ @slot_found
        INX
        CPX #MAX_TASKS
        BNE @find_slot
        RTS                 ; No slots available

@slot_found:
        ; Initialize task control block
        LDA #TASK_ACTIVE
        STA task_status,X
        
        ; Set up task's initial PC
        STA task_pc_low,X
        STY task_pc_high,X
        
        ; Set up task's stack
        TXA
        ASL A              ; Multiply by STACK_SIZE
        ASL A
        ASL A
        ASL A
        ASL A
        CLC
        ADC #<system_stacks
        STA task_stack_low,X
        LDA #>system_stacks
        ADC #0
        STA task_stack_high,X
        
        INC task_count
        RTS

SCHEDULE_TASKS:
        ; Save current task's context if any
        LDX current_task
        LDA task_status,X
        CMP #TASK_ACTIVE
        BNE @find_next
        
        ; Save current stack pointer
        TSA
        STA task_stack_low,X
        
@find_next:
        ; Find next runnable task
        INX
        CPX #MAX_TASKS
        BNE @check_task
        LDX #0
        
@check_task:
        LDA task_status,X
        CMP #TASK_ACTIVE
        BEQ @task_found
        INX
        CPX #MAX_TASKS
        BNE @check_task
        LDX #0              ; Default to task 0 if none found
        
@task_found:
        STX current_task
        
        ; Restore task's context
        LDA task_stack_low,X
        TAS                 ; Set stack pointer
        
        ; Jump to task's PC
        LDA task_pc_low,X
        STA vector_low
        LDA task_pc_high,X
        STA vector_high
        JMP (vector_low)

; =====================
; Memory Management
; =====================
INIT_MEMORY:
        ; Clear RAM
        LDA #0
        LDX #0
@clear_ram:
        STA $0000,X
        STA $0100,X
        STA $0200,X
        STA $0300,X
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $0700,X
        INX
        BNE @clear_ram
        RTS

; =====================
; Graphics System
; =====================
INIT_PPU:
        ; Wait for PPU warmup
        LDX #2
@warmup:
        LDA PPUSTATUS
        DEX
        BNE @warmup
        
        ; Initialize PPU registers
        LDA #%10000000     ; Enable NMI
        STA PPUCTRL
        LDA #%00011110     ; Enable sprites and background
        STA PPUMASK
        RTS

UPDATE_PPU:
        ; Handle PPU updates during VBlank
        LDA PPUSTATUS      ; Reset PPU address latch
        
        ; Update scroll position
        LDA #0
        STA PPUSCROLL
        STA PPUSCROLL
        
        RTS

; =====================
; Input System
; =====================
POLL_INPUT:
        ; Read controller 1
        LDA #1
        STA $4016
        LDA #0
        STA $4016
        
        LDX #8
@read_cont:
        LDA $4016
        LSR A
        ROL temp1
        DEX
        BNE @read_cont
        
        LDA temp1          ; Store controller state
        STA CTRL1_INPUT
        RTS

; =====================
; Idle Task
; =====================
IDLE_TASK:
        ; Do nothing, just wait
        NOP
        JMP IDLE_TASK

; =====================
; Utility Functions
; =====================
UPDATE_SLEEP_COUNTERS:
        LDX #0
@check_task:
        LDA task_status,X
        CMP #TASK_SLEEPING
        BNE @next_task
        
        DEC task_sleep,X
        BNE @next_task
        
        ; Wake up task
        LDA #TASK_ACTIVE
        STA task_status,X
        
@next_task:
        INX
        CPX #MAX_TASKS
        BNE @check_task
        RTS

; =====================
; Data Section
; =====================
        .org $E000
CTRL1_INPUT:    .res 1      ; Controller 1 input buffer
PALETTE_DATA:   .res 32     ; Palette data buffer

; =====================
; Interrupt Vectors
; =====================
        .org $FFFA
        .dw NMI            ; NMI vector
        .dw RESET          ; Reset vector
        .dw IRQ            ; IRQ/BRK vector
