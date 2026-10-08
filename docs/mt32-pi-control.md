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
| `SET_SYNTH` | `01` | `00` Munt, `01` FluidSynth |
| `SET_ROM` | `02` | `00` old, `01` new, `02` CM-32L |
| `SET_SOUNDFONT` | `03` | índice de 14 bits: bajo 7, alto 7 |

| Respuesta | Valor | Payload |
| --- | ---: | --- |
| `ACCEPTED` | `40` | ninguno |
| `READY` | `41` | valor aplicado |
| `ERROR` | `42` | código de error |
| `STATUS` | `43` | capacidades/estado, siete bytes |

Errores: `01` petición mal formada, `02` versión no soportada, `03` comando
desconocido, `04` parámetro inválido, `05` recurso no disponible y `06` fallo
de operación.

El payload de `STATUS` contiene capacidades low/high, disponibilidad de Munt y
FluidSynth, motor activo, ROM activa e índice SoundFont low/high. El valor
`7F` o `3FFF` representa estado no disponible cuando corresponda.

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

Pendiente: ejecutar el mismo diálogo contra una Pi 4 y medir el cambio real de
motor/SoundFont, audio I²S y tiempos de carga. CSpect valida software, no el
cable, niveles eléctricos ni el UART físico.
