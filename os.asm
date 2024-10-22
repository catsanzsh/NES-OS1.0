; Simple NES OS
; Handles basic initialization, interrupts, and system management
.segment "HEADER"
  .byte "NES",$1A      ; iNES header identifier
  .byte $02            ; 2x 16KB PRG ROM
  .byte $01            ; 1x 8KB CHR ROM
  .byte $01            ; Mapper 0, vertical mirroring
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00
.segment "VECTORS"
  .addr nmi_handler, reset_handler, irq_handler
.segment "CHARS"
  .incbin "charset.chr"   ; Include character set (you'll need to create this)
.segment "ZEROPAGE"
  frame_counter: .res 1   ; Frame counter
  system_state:  .res 1   ; System state
  cursor_x:      .res 1   ; Cursor X position
  cursor_y:      .res 1   ; Cursor Y position
.segment "CODE"
.proc reset_handler
  SEI             ; Disable interrupts
  CLD             ; Clear decimal mode
  LDX #$FF
  TXS             ; Set up stack
  ; Wait for first VSYNC
  :
    BIT $2002
    BPL :-
  ; Clear RAM
  LDA #$00
  TAX
  :
    STA $0000,X
    STA $0100,X
    STA $0200,X
    STA $0300,X
    STA $0400,X
    STA $0500,X
    STA $0600,X
    STA $0700,X
    INX
    BNE :-
  ; Initialize PPU
  LDA #%10010000  ; Enable NMI, sprites from Pattern Table 0
  STA $2000
  LDA #%00011110  ; Enable sprites, background
  STA $2001
  ; Initialize system variables
  LDA #$00
  STA frame_counter
  STA system_state
  STA cursor_x
  STA cursor_y
  JMP main_loop
.endproc
.proc nmi_handler
  ; Save registers
  PHA
  TXA
  PHA
  TYA
  PHA
  ; Update frame counter
  INC frame_counter
  ; Update PPU
  LDA #$00
  STA $2003
  LDA #$02
  STA $4014       ; OAM DMA transfer
  ; Restore registers
  PLA
  TAY
  PLA
  TAX
  PLA
  RTI
.endproc
.proc irq_handler
  RTI
.endproc
.proc main_loop
  ; Main system loop
  JSR update_display
  JSR check_input
  JMP main_loop
.endproc
.proc update_display
  ; Wait for VBLANK
  :
    BIT $2002
    BPL :-
  ; Update PPU address for nametable
  LDA #$20
  STA $2006
  LDA #$00
  STA $2006
  ; Draw system status
  LDX #$00
  :
    LDA status_text,X
    STA $2007
    INX
    CPX #$20
    BNE :-
  RTS
.endproc
.proc check_input
  ; Read controller 1
  LDA #$01
  STA $4016
  LDA #$00
  STA $4016
  ; Read buttons
  LDA $4016       ; A
  LSR A
  BCS handle_a
  LDA $4016       ; B
  LSR A
  BCS handle_b
  LDA $4016       ; Select
  LDA $4016       ; Start
  LSR A
  BCS handle_start
  RTS
.endproc
.proc handle_a
  ; Handle A button press
  RTS
.endproc
.proc handle_b
  ; Handle B button press
  RTS
.endproc
.proc handle_start
  ; Handle Start button press
  RTS
.endproc
.segment "RODATA"
status_text:
  .byte "NES OS V1.0 READY       "
.segment "CHR"
  .res 8192       ; Character ROM data update it to 3.5 sonnet
