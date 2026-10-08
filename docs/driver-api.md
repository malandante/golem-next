# ABI experimental de transporte `GOLEM.DRV`

Estado: ABI 0.2 de trabajo para M2/M7. Los números de función pueden cambiar hasta
M6. El ID `$2D` es exclusivamente experimental: no está asignado por NextZXOS y
no debe publicarse como definitivo.

Aunque conserva el nombre histórico, este ABI transporta MIDI 1.0 genérico y
no depende de Munt ni de MT-32. Golem construye los mensajes de canal, SysEx y
órdenes administrativas encima de `WRITE`; el residente no interpreta esos
bytes. Véase [golem-architecture.md](golem-architecture.md).

La llamada sigue `M_DRVAPI`: `C=ID`, `B=función` y `DE` contiene la longitud.
Para comandos punto el puntero entra por `HL`; para programas estándar/NEX entra
por `IX`, y NextZXOS entrega ese valor al driver en `HL`. Un cliente compilado
debe preservar `IX` si su runtime lo usa como frame pointer. Carry limpio indica
éxito; carry activo indica error y `A` contiene el código. `A=0` significa
función no soportada según la convención oficial.

| B | Operación | Entrada | Salida |
|---:|---|---|---|
| 0 | QUERY | — | `BC="MT"`, `DE=$0002`, `HL` capacidades |
| 1 | ACQUIRE | — | Adquiere en exclusiva, configura UART Pi a 31250, 8N1 según NextReg `$11` y activa la recepción I²S de la Pi (NextReg `$A2=$D2`) |
| 2 | WRITE | `HL` buffer visible, `DE` longitud | `BC` aceptados, `HL` avanzado, `DE` restante |
| 3 | STATUS | — | `BC`: bit 0 adquirido, bit 1 TX llena, bit 2 TX vacía, bit 3 RX con datos; siempre del UART Pi |
| 4 | DRAIN_STATUS | — | `BC=$FFFF` si FIFO TX vacía; `0` si no |
| 5 | RELEASE | — | Libera y restaura el estado legible |
| 6 | READ | `HL` destino visible, `DE` capacidad | `BC` recibidos, `HL` avanzado, `DE` restante |

## Requisitos del llamador

- **ROM en MMU0/MMU1.** `RST $08` entra en la ROM de NextZXOS en `$0008`, así que
  durante la llamada `$0000-$3FFF` debe tener la ROM: NextReg `$50` y `$51` a
  `$FF`. Un programa que use esas ranuras para datos (un juego puede hacerlo) debe
  ponerlas a `$FF` antes de la llamada y devolver su mapeo después.
- **Puntero.** Comando punto: `HL`. Programa estándar o NEX: `IX`; NextZXOS lo
  entrega al driver en `HL`. El cliente guarda y restaura `IX` si su runtime lo
  usa (ZX Basic, por ejemplo).
- **Búferes.** Entre `$4000` y `$FFFF` y visibles con el mapeo de la llamada.
  Por debajo de `$4000` la función devuelve `INVALID`. `WRITE` y `READ` se
  detienen antes de pasar de `$FFFF` a `$0000`.
- **Registros.** `AF`, `BC`, `DE` y `HL` son de salida. El residente no toca
  `IX`, `IY` ni el juego alternativo. `MTSTATE` comprueba que `STATUS` los
  conserva a través de `M_DRVAPI`.
- **Interrupciones.** El driver no cambia `DI`/`EI` ni instala rutina IM1. No
  debe llamarse desde una rutina de interrupción: no es reentrante, y una
  interrupción que cambie `$153B` dentro de una llamada no está protegida.
- **Interrupción de cuadro (#10).** NextZXOS atiende `M_DRVAPI` con las
  interrupciones desactivadas, así que una llamada que coincide con la
  interrupción de cuadro la pierde. Medido en un Next por HDMI (`MTFRAME`,
  2026-10-05): la interrupción llega hacia la línea 247 a 50 Hz y la 223 a
  60 Hz, y una llamada la bloquea durante hasta 3–5 líneas (`STATUS`) o 11 líneas,
  unos 0,7 ms (`WRITE` de 16 bytes; 18 líneas antes de acortar los bucles en
  #53), a 3,5 MHz; a 28 MHz, 1–2 líneas. Un cliente
  que se sincronice con `HALT` o cuente cuadros con la interrupción debe hacer
  sus llamadas justo después de la interrupción y terminarlas antes de unas 20
  líneas previas a la siguiente (con margen, antes de la línea 220 a 50 Hz o 200
  a 60 Hz a 3,5 MHz). `.MT32` no depende de la interrupción: mide el tiempo con
  el raster.
- **UART.** Entre llamadas, el cliente o un tercero puede seleccionar el ESP:
  cada función vuelve a seleccionar la Pi y deja la selección como la encontró.
- **NextRegs.** Mientras está adquirido, el driver ha cambiado `$A0` (UART a la
  Pi) y `$A2` (I²S de la Pi). `RELEASE` los restaura, junto con el selector de
  NextReg.

Cambios de versión: [ABI_CHANGELOG.md](../ABI_CHANGELOG.md).

`WRITE`, `STATUS`, `DRAIN_STATUS` y `READ` seleccionan el UART Pi al entrar y
restauran al salir la selección que tuviera el llamador, sin escribir bits del
divisor. Así, otro usuario del UART (por ejemplo, el ESP) puede cambiar la
selección entre llamadas sin desviar el MIDI. La ventana dentro de una misma
llamada no está protegida frente a interrupciones que cambien `$153B`.

`WRITE` no espera espacio, no retiene el puntero y acepta como máximo 16 bytes
por llamada. El cliente conserva y reintenta sólo el sufijo no aceptado; los
valores devueltos de `HL/DE` apuntan directamente a ese sufijo. El
buffer debe comenzar entre `$4000` y `$FFFF`; la llamada se detiene antes de
envolver a `$0000`.

`READ` tiene la misma semántica acotada: copia como máximo 16 bytes ya
presentes en la FIFO RX y retorna inmediatamente, incluido `BC=0`. Nunca lee
el puerto RX si el bit de disponibilidad está limpio, por lo que cero real no
se confunde con FIFO vacía. `HL/DE` describen el sufijo restante igual que en
`WRITE`. Las capacidades de `QUERY` son bit 0 escritura parcial y bit 1 RX no
bloqueante. La interpretación de ACK, transacciones y timeouts pertenece al
cliente Golem, no al residente.


Errores actuales: `1=ocupado`, `2=no adquirido`, `3=parámetro inválido`.

`MTSTRESS` es el cliente de presión separado. Con el plugin CSpect configurado
para declarar FIFO llena después del primer byte, exige observar una aceptación
parcial y al menos una llamada con `BC=0`, reintenta el mismo sufijo y verifica
por captura que los 20 bytes llegan una sola vez y en orden.

`MTAPIERR` valida `BUSY`, `NOT_ACQUIRED`, `INVALID`, `STATUS` y reacquisición;
sólo emite `F6` si todos los resultados coinciden. `MTNOID` comprueba el carry de
`M_DRVAPI` sin driver instalado. `MTCOLLIDE` y el señuelo `COLLIDE.DRV` verifican
que `.install` no reemplaza un propietario previo del ID experimental. Los
marcadores directos F4/F5 pertenecen sólo al arnés CSpect, no al ABI.

`MTSTATE` comprueba que `STATUS` preserva IX/IY y registros alternativos y que
el ciclo ACQUIRE/RELEASE restaura el selector NextReg, NextReg `$A0` y `$A2`,
MMU 4–7, selección UART y formato de trama, y que `$A2` vale `$D2` mientras el
driver está adquirido. Su oráculo exacto es `F3 01 F9`, incluido el
marcador posterior a la desinstalación.

`MTDURATION` alinea 32 llamadas `WRITE` al inicio de una línea raster y mide el
máximo de cruces, registrando también la velocidad efectiva de CPU. Las matrices
CSpect produjeron estos límites superiores:

| Frecuencia | CPU | 16 bytes | FIFO llena |
| --- | --- | --- | --- |
| 50 Hz/312 líneas | 3,5 MHz | 24 cruces; <1,603 ms | 17 cruces; <1,154 ms |
| 50 Hz/312 líneas | 7 MHz | 12 cruces; <0,834 ms | 5 cruces; <0,385 ms |
| 50 Hz/312 líneas | 14 MHz | 7 cruces; <0,513 ms | 2 cruces; <0,193 ms |
| 50 Hz/312 líneas | 28 MHz | 4 cruces; <0,321 ms | 2 cruces; <0,193 ms |
| 60 Hz/262 líneas | 3,5 MHz | 24 cruces; <1,591 ms | 17 cruces; <1,145 ms |
| 60 Hz/262 líneas | 7 MHz | 12 cruces; <0,827 ms | 5 cruces; <0,382 ms |
| 60 Hz/262 líneas | 14 MHz | 6 cruces; <0,446 ms | 2 cruces; <0,191 ms |
| 60 Hz/262 líneas | 28 MHz | 4 cruces; <0,319 ms | 2 cruces; <0,191 ms |

Son 32 muestras por ruta, velocidad y frecuencia, y límites del emulador, no
del hardware.

## Limitación objetiva de restauración

El core permite leer selección UART y formato de trama, pero los 14 bits bajos
del divisor de baud se escriben por el puerto RX y no son legibles. `RELEASE`
restaura NextReg `$A0` y `$A2`, selección UART, formato de trama y selector
NextReg, pero deja el divisor del UART Pi en 31250. Para que ese 31250 sea
coherente, `RELEASE` no escribe ningún bit del divisor: ni los 14 bajos ni los 3
altos del puerto de selección. El divisor del ESP nunca se toca. Al liberar se
restaura `$A2`, así que la cola de reverberación de la Pi deja de oírse por el
Next en ese momento. Hasta disponer de arbitraje externo,
ningún cliente debe asumir restauración completa de un baud previo desconocido.

Referencia normativa: [DriverIDs.txt](https://gitlab.com/thesmog358/tbblue/-/blob/master/docs/nextzxos/DriverIDs.txt) del repositorio `tbblue`, el manual
`NextZXOS_and_esxDOS_APIs.pdf` y los ejemplos de driver del repositorio oficial
`tbblue`. La tabla no reserva todavía una clase MIDI; antes
de M6 hay que solicitar el ID al mantenedor indicado allí.
