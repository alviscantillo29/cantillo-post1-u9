# Laboratorio Unidad 9 — Entrada y Salida Avanzados: Puertos, Polling e Interrupciones en NASM sobre DOSBox

**Estudiante:** Alvis Cantillo (1152332)  
**Repositorio:** `cantillo-post1-u9`

## Objetivo

Este repositorio reúne la implementación en lenguaje ensamblador x86 (16 bits, formato `.COM`) de las dos partes del laboratorio de Entrada y Salida Avanzados sobre DOSBox y NASM. La Parte 1 explora el acceso directo a puertos de E/S (`IN`/`OUT`), el sondeo (*polling*) sobre el controlador de teclado 8042 y el puerto paralelo LPT1, y la espera combinada mediante `OR` a nivel de bit. La Parte 2 aborda la programación del PIC 8259A, la instalación y restauración de vectores en la IVT (`INT 21h` `AH=35h`/`25h`), el encadenamiento (*chaining*) de manejadores de interrupción y la medición de intervalos en tiempo real mediante el contador de *ticks* del BIOS en `0040h:006Ch`.

## Prerrequisitos y Compilación

- **Emulador:** DOSBox 0.74 o superior.
- **Ensamblador:** NASM 2.x accesible desde el `PATH` de DOSBox.

Cada archivo fuente `.ASM` se ensambla en binario plano `.COM` con el siguiente comando dentro de DOSBox:

```bat
nasm -f bin <ARCHIVO>.ASM -o <ARCHIVO>.COM
```

## Parte 1: Acceso Directo a Puertos de E/S

### Descripción de Programas

1. **`TECL.ASM` (`TECL.COM`):** Sondea indefinidamente el bit 0 (`OBF`, *Output Buffer Full*) del registro de estado del controlador 8042 en el puerto `64h`. Cuando `OBF=1`, lee el *scancode* desde el puerto de datos `60h` y lo imprime en hexadecimal por pantalla mediante conversión manual de *nibbles*.
2. **`POLL_T.ASM` (`POLL_T.COM`):** Incorpora un contador de reintentos (`MAX_RETRY`, configurable a `0FFFFh` o `0005h` para forzar *timeout*) mediante la instrucción `LOOP`. Si `CX` alcanza cero antes de que `OBF=1`, informa el vencimiento del tiempo de espera.
3. **`LPT1.ASM` (`LPT1.COM`):** Implementa el protocolo Centronics sobre los puertos `0378h` (datos), `0379h` (estado) y `037Ah` (control). Espera a que el bit 7 (`BUSY#`) esté en `1`, escribe el carácter `'A'` (`41h`) en `0378h`, genera un pulso activo en bajo en el bit 0 (`STROBE`) de `037Ah` durante ~1 µs y restaura `STROBE` a `1`. En DOSBox sin impresora física conectada, `BUSY#` suele permanecer en alto, por lo que el ciclo concluye de inmediato sin errores de acceso a puerto.
4. **`MULTI_ST.ASM` (`MULTI_ST.COM`):** Lee el bit `OBF` (`64h`) en `BL` y el bit `BUSY#` normalizado (`0379h`) en `BH`, combinándolos con `OR` para salir del bucle ante el primer evento disponible e identificar posteriormente qué puerto disparó la condición.

### Decisiones Técnicas — Parte 1

#### Decisión 1: ¿Polling sin límite o polling con timeout configurable?

El bucle de polling sin límite implementado en `TECL.ASM` resulta aceptable únicamente en programas de demostración o rutinas mínimas donde existe certeza de que el periférico responderá —por ejemplo, cuando el propio usuario presiona una tecla frente al equipo—. En cambio, el polling con *timeout* configurable de `POLL_T.ASM` es indispensable en cualquier entorno real o de pruebas donde un dispositivo puede fallar, estar desconectado o tardar más de lo previsto, ya que evita que la aplicación quede bloqueada de forma indefinida. Si `MAX_RETRY` se reduce a un valor excesivamente bajo como `0005h` en lugar de `0FFFFh`, aparece el riesgo de falsos *timeouts*: el programa aborta la espera y reporta ausencia de respuesta aun cuando el controlador 8042 o el periférico funcionan correctamente y solo requerían unos microsegundos adicionales. Asimismo, un contador de reintentos como `CX` mide iteraciones del bucle `.poll`, no tiempo físico transcurrido. El número de iteraciones ejecutadas por segundo varía drásticamente según la frecuencia del procesador o los ciclos configurados en DOSBox, por lo que no constituye una medida temporal confiable, a diferencia de consultar el contador de *ticks* del BIOS en `0040h:006Ch`, que avanza a una tasa fija cercana a 18,2 Hz con independencia de la velocidad de la CPU.

#### Decisión 2: ¿Combinar banderas de dos puertos con OR o verificarlas por separado?

Cuando en DOSBox el puerto paralelo LPT1 (`0379h`) mantiene su bit 7 (`BUSY#`) en `1` de manera permanente porque no hay una impresora física conectada, el bucle `.poll` de `MULTI_ST.ASM` se detiene inmediatamente en la primera iteración sin esperar ninguna pulsación del teclado. En la práctica, esta condición anula la utilidad de la espera combinada: el `OR` entre `BL` y `BH` siempre resulta distinto de cero desde el inicio, impidiendo que el programa permanezca bloqueado aguardando un evento real del teclado. Además, dado que la operación `OR` colapsa dos banderas independientes en un único valor booleano para decidir si salir del bucle, descarta la identidad del dispositivo que generó el evento; por ello resulta obligatorio inspeccionar `BL` y `BH` por separado inmediatamente después de salir de `.poll` para informar con precisión si respondió el teclado, LPT1 o ambos. Por el contrario, si las banderas se combinaran con `AND` en lugar de `OR`, el programa esperaría a que ambas condiciones se cumplieran de forma simultánea. Ese esquema tendría sentido en una sincronización tipo *rendezvous*, por ejemplo, antes de transmitir un carácter al puerto paralelo exigiendo que tanto el usuario haya ingresado una tecla como que la impresora esté lista.

## Parte 2: ISR Personalizado y Programación del PIC 8259A

### Descripción de Programas

1. **`ISR_KB.ASM` (`ISR_KB.COM`):** Obtiene el vector original de `INT 09h` (`IRQ1`) con `INT 21h AH=35h`, instala `mi_isr` con `AH=25h`, espera 5 pulsaciones de tecla leyendo y descartando el *scancode* de `60h`, envía `EOI` (`20h`) al puerto `20h` del PIC maestro y restaura el vector original antes de finalizar.
2. **`MASK_KB.ASM` (`MASK_KB.COM`):** Lee el *Interrupt Mask Register* (IMR) del puerto `21h`, enmascara `IRQ1` activando el bit 1 (`OR AL, 02h`), espera ~3 segundos (55 *ticks* mediante `INT 1Ah AH=00h`) durante los cuales las pulsaciones no generan respuesta visible, y restaura el IMR original.
3. **`ISR_CHAIN.ASM` (`ISR_CHAIN.COM`):** Implementa el encadenamiento de interrupciones incrementando un contador propio y delegando el procesamiento completo al manejador original mediante `PUSHF` seguido de `CALL FAR [CS:old_isr]`, preservando el eco normal de DOS.
4. **`ISR_TIME.ASM` (`ISR_TIME.COM`):** Lee directamente la palabra baja del contador de *ticks* del sistema en `0040h:006Ch`, calcula la diferencia respecto a la interrupción anterior (`SUB BX, [ticks_prev]`), envía el `EOI` al puerto `20h` antes de imprimir por pantalla y muestra el número de *ticks* transcurridos (~18 *ticks* por segundo).

### Decisiones Técnicas — Parte 2

#### Decisión 1: ¿En qué punto del ISR debe ir el EOI?

Si el comando *End of Interrupt* (`EOI`, valor `20h` en el puerto `20h`) se envía al final del ISR después de imprimir mensajes mediante `INT 21h` —como ocurre en `ISR_KB.ASM`—, el PIC 8259A mantiene el bit correspondiente en su registro *In-Service* (`ISR`) activo durante todos los milisegundos que tarda la salida por pantalla. Durante ese intervalo, el PIC queda impedido de despachar cualquier otra interrupción de igual o menor prioridad (como otros periféricos o incluso eventos posteriores), incrementando su latencia de atención. En los ISR del laboratorio no se ejecuta `STI` antes del `IRET`, por lo que el flag `IF` del procesador permanece en `0` durante toda la rutina; en consecuencia, enviar el `EOI` de forma temprana —justo después de leer el puerto `60h` y actualizar `ticks_prev` en `ISR_TIME.ASM`, pero antes de imprimir— no provoca que la misma `IRQ1` reentre recursivamente, pues las interrupciones enmascarables siguen bloqueadas en la CPU hasta el `IRET`. La diferencia radica en que liberar al PIC tempranamente permite que el controlador registre y prepare otras `IRQ` pendientes sin retardo innecesario. La práctica recomendada es precisamente la de `ISR_TIME.ASM`: enviar el `EOI` tan pronto concluye la interacción crítica con el hardware y dejar el procesamiento lento para después.

#### Decisión 2: ¿Polling o interrupción para el mismo dispositivo?

Aunque el sondeo activo de `TECL.ASM` y la rutina de interrupción de `ISR_KB.ASM` cumplen el mismo objetivo funcional en el laboratorio, su comportamiento difiere radicalmente en aplicaciones reales. El bucle `.poll` de `TECL.ASM` consume el 100 % de los ciclos de CPU en espera activa (*busy-wait*) mientras no exista un *scancode* disponible en el puerto `60h`, lo cual resulta inaceptable en cualquier programa DOS que deba animar gráficos, reproducir audio, actualizar temporizadores o atender otro periférico de forma concurrente. Desde el punto de vista de la latencia, el ISR de `ISR_KB.ASM` responde de manera más determinista e inmediata ante una pulsación, porque el controlador 8042 activa `IRQ1` y el PIC 8259A interrumpe a la CPU al concluir la instrucción en curso; en contraste, un programa real que utilice *polling* sufre una latencia variable que depende de cuán frecuentemente el bucle principal vuelva a consultar el puerto `64h`. Para un dispositivo lento y esporádico como el teclado, donde pueden transcurrir segundos o minutos sin actividad, mantener la CPU atrapada en un *busy-wait* desperdicia capacidad de cómputo de forma injustificada, por lo que el enfoque por interrupciones es el diseño estándar y el *polling* se reserva para esperas breves o entornos sin soporte de interrupciones.

## Evidencia y Capturas (`capturas/`)

El directorio `capturas/` está destinado a almacenar al menos 2 capturas de pantalla por cada uno de los 10 *checkpoints* verificados en DOSBox (compilación con `nasm -f bin` y ejecución de `TECL.COM`, `POLL_T.COM`, `LPT1.COM`, `MULTI_ST.COM`, `ISR_KB.COM`, `MASK_KB.COM`, `ISR_CHAIN.COM` e `ISR_TIME.COM`).
