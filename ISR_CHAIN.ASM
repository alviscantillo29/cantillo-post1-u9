; ISR_CHAIN.ASM — ISR con encadenamiento (chaining) hacia el handler original
; Compila: nasm -f bin ISR_CHAIN.ASM -o ISR_CHAIN.COM

[BITS 16]
[ORG 0x100]

section .data
contador    DW 0
MAX_KEYS    EQU 5
old_isr     DD 0
msg_inicio  DB "ISR_CHAIN activo. Presione 5 teclas (el eco DOS sigue funcionando)...", 0Dh, 0Ah, "$"
msg_fin     DB 0Dh, 0Ah, "ISR_CHAIN restaurado. Fin del programa.$"

section .text
start:
    MOV AH, 09h
    MOV DX, msg_inicio
    INT 21h

    ; Guardar vector original INT 09h
    MOV AX, 3509h
    INT 21h
    MOV [old_isr],   BX
    MOV [old_isr+2], ES

    ; Instalar ISR encadenado
    PUSH DS
    MOV  AX, CS
    MOV  DS, AX
    MOV  DX, mi_isr_chain
    MOV  AX, 2509h
    INT  21h
    POP  DS

    STI

.esperar:
    ; Leer teclado via DOS sin bloquear para comprobar el eco normal mientras contamos
    MOV AH, 0Bh         ; verificar si hay tecla en buffer DOS
    INT 21h
    TEST AL, AL
    JZ  .check_count
    MOV AH, 01h         ; leer y hacer eco por pantalla
    INT 21h

.check_count:
    MOV AX, [contador]
    CMP AX, MAX_KEYS
    JL  .esperar

    ; Restaurar handler original
    CLI
    LDS DX, [old_isr]
    MOV AX, 2509h
    INT 21h
    STI

    MOV AH, 09h
    MOV DX, msg_fin
    INT 21h
    MOV AH, 4Ch
    INT 21h

; -- ISR con encadenamiento ------------------------------------------
mi_isr_chain:
    PUSH AX
    PUSH DS

    MOV  AX, CS
    MOV  DS, AX
    INC  WORD [contador]    ; registrar evento sin consumir el scancode de 60h

    POP  DS
    POP  AX

    ; Encadenar con el handler original (simular INT: PUSHF + far CALL)
    PUSHF
    CALL FAR [CS:old_isr]   ; el handler original lee 60h, actualiza buffer BIOS y envia EOI
    IRET
