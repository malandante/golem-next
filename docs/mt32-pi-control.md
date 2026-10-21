# Control bidireccional Golem para mt32-pi

Estado: protocolo experimental v1 implementado el 2026-10-03 en el fork
`malandante/mt32-pi`, rama `golem-control-protocol-v1`. El ID `$7D` es de
desarrollo; la decisión sobre un ID MIDI de producción queda aplazada.

## Compatibilidad

El fork conserva sin cambios los SysEx oficiales de cinco bytes de mt32-pi
v0.13.1 (`F0 7D 01|02|03 xx F7`). Golem usa un espacio distinguible por la
firma ASCII `GLM`; el tráfico musical y los SysEx Roland pasan transparentes.
Sólo la entrada MIDI serie activa genera respuestas, para que la Pi no replique
órdenes USB/RTP hacia un UART que no las originó.

## Formato

```text
petición:  F0 7D 47 4C 4D 01 tt cc [payload] F7
respuesta: F0 7D 47 4C 4D 01 tt rr cc [payload] F7
```

Todos los campos interiores son datos SysEx de siete bits. `01` es la versión,
`tt` la transacción, `cc` el comando y `rr` el tipo de respuesta.

| Comando | Valor | Payload de petición |
| --- | ---: | --- |
| `GET_STATUS` | `00` | ninguno |
| `SET_SYNTH` | `01` | `00` Munt, `01` FluidSynth, `02` OPL3 (firmware golem-1.2.0) |
| `SET_ROM` | `02` | `00` old, `01` new, `02` CM-32L |
| `SET_SOUNDFONT` | `03` | índice de 14 bits: bajo 7, alto 7 |
| `SET_USB_OUT` | `04` | `00` off, `01` on, `02` bridge, `7F` sólo consulta |
| `SET_PARAM` | `05` | parámetro, valor (`7F` sólo consulta) |
| `SAVE` | `06` | `00` guardar en `golem.cfg`, `01` borrarlo |

| Respuesta | Valor | Payload |
| --- | ---: | --- |
| `ACCEPTED` | `40` | ninguno |
| `READY` | `41` | valor aplicado |
| `ERROR` | `42` | código de error |
| `STATUS` | `43` | capacidades/estado, siete bytes |

Errores: `01` petición mal formada, `02` versión no soportada, `03` comando
desconocido, `04` parámetro inválido, `05` recurso no disponible y `06` fallo
de operación.

El payload de `STATUS` contiene capacidades low/high, disponibilidad de Munt,
FluidSynth y OPL3 (bits 0, 1 y 2), motor activo, ROM activa e índice SoundFont low/high. El valor
`7F` o `3FFF` representa estado no disponible cuando corresponda.

`SET_USB_OUT` (firmware golem-1.1.0, capacidad bit 4, #85) decide si el MIDI
del Next sale también por los dispositivos USB-MIDI de la Pi: `on` con el
sinte sonando, `bridge` con el sinte callado. Su `READY` lleva dos bytes:
modo activo y número de dispositivos USB-MIDI. `7F` no cambia nada y acepta
cualquier modo en el `READY`. Un firmware anterior contesta `ERROR 03`.

`SET_PARAM` (firmware golem-1.1.0, capacidad bit 5) cambia un ajuste del
firmware; `.golem set` lo usa. Su `READY` lleva dos bytes: parámetro y valor
vigente. Con valor `7F` no cambia nada y el cliente acepta cualquier valor.

| Parámetro | Valor | Rango | Qué cambia |
| --- | ---: | --- | --- |
| volume | `00` | 0–100 | volumen general de los dos motores (como botones y rueda) |
| fx | `01` | 0/1 | reverberación y chorus de FluidSynth en todos los canales |
| channels | `02` | 0/1 | canales del MT-32: estándar 2–10 o alternativos 1–8 y 10 |
| thru | `03` | 0/1 | la entrada USB-MIDI también hacia los dispositivos USB |
| keys | `04` | 0/1 | la entrada USB-MIDI también hacia el Next por el UART |
| bank | `05` | 0–127 | banco del motor OPL3: 0–78 incluidos, 79 en adelante los `.wopl` de `SD:opl3/` (firmware golem-1.2.0) |
| loud | `06` | 0/1 | sube el sintetizador con un limitador (firmware golem-1.2.0) |

Con `keys` el firmware manda al Next, por el mismo UART que las respuestas
Golem, los mensajes de canal, los de sistema común y los SysEx que llegan por
USB-MIDI o Pisound. Los manda enteros y desde la misma tarea que las
respuestas, así que nunca se intercalan; si no caben en el búfer de
transmisión, se descartan enteros. No manda bytes de tiempo real (`F8`–`FF`).
Un cliente que lee el UART debe apartar las tramas Golem (firma `GLM`) del MIDI.

Un parámetro desconocido o un valor fuera de rango dan `ERROR 04`; `fx` sin
FluidSynth o `channels` sin MT-32, `ERROR 05`. Los ajustes duran hasta apagar
la Pi. El firmware guarda los canales y el volumen del MT-32 y los vuelve a
mandar justo detrás de cada SysEx de reset del MT-32 (`F0 41 1x 16 12 7F …`)
y tras cambiar de ROM; `fx` se mantiene al cambiar de SoundFont.

`SAVE` (firmware golem-1.1.0, capacidad bit 6) escribe `golem.cfg` en la SD
de la Pi con el motor, la ROM, el SoundFont, los canales del MT-32, `usb_out`,
`usb_in_thru` y, en la sección `[golem]`, `volume` y `effects`. Lo escribe en
`golem.tmp` y lo renombra, así que un fallo deja el anterior. El kernel lee
`golem.cfg` después de `mt32-pi.cfg`, con lo que sus valores mandan. `01` lo
borra. `READY` repite la acción; un fallo de la SD da `ERROR 06`.

## Semántica

Una orden administrativa sólo tiene éxito después de `ACCEPTED` y del terminal
`READY` con la misma versión, transacción y comando. `GET_STATUS` termina con
`STATUS`. `ERROR` es terminal incluso si llega antes de `ACCEPTED`. Respuestas
obsoletas o ajenas se ignoran; ausencia de terminal produce timeout del cliente.
Vaciar la FIFO TX nunca equivale a confirmación remota.

`GOLEM.DRV` ABI 0.2 añade `READ=6`, no bloqueante y limitado a 16 bytes. El
driver no conoce esta gramática. `.GOLEM` ensambla peticiones, consume RX y usa
una ventana de 1500 frames; una futura API cooperativa conservará la máquina de
estados pero sustituirá la espera foreground por `update`.

## Evidencia

- Tests host: vectores compartidos con el fork, framing fragmentado, ruido,
  respuesta obsoleta, orden `ACCEPTED→READY`, `ERROR` y timeout.
- CSpect bidireccional: cuatro órdenes completas con `ACK/READY` y marcador
  final; repetida inyectando respuestas de transacción antigua.
- CSpect negativo: `ERROR 05` remoto devuelve el control sin bloqueo.
- CSpect timeout: una petición sin respuesta agota el límite y devuelve el
  control; las tres órdenes siguientes completan y se alcanza el marcador.
- El fork pasó lint y builds Pi 2, Pi 3-64 y Pi 4-64, normales y HDMI, en
  GitHub Actions.

El 2026-10-14 el mismo diálogo funcionó en el Next contra una Raspberry Pi 4
(firmware de malandante/mt32-pi#4): estado, motor, ROM, SoundFont y
`SET_USB_OUT`, comprobado de oído. Pendiente: medir con el analizador el audio
I²S y los tiempos de carga de SoundFont en la Pi 4. CSpect valida software, no el
cable, niveles eléctricos ni el UART físico.
