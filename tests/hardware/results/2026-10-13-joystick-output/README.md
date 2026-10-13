# Sesión física del 13 de octubre de 2026: `.golem output` (#64, PR #89)

## Configuración

| Dato | Valor |
| --- | --- |
| golem-next | rama `feat/joystick-output` en `62fb871`: `GOLEM.DRV` de 598 bytes (ABI 0.3), `.GOLEM` de 7878 bytes |
| Vídeo | 50 Hz, HDMI |
| Golem | Raspberry Pi con el cable de 40 pines de siempre, motor MT-32 |
| Analizador | Innomaker LA1010; CH0 en la patilla 7 del joystick, GND en la patilla 8; 1 MHz; UART 31250 8N1, umbral 1,65 V |

Antes, en CSpect con el mismo driver: `MTSTATE` (`F3 01 F9`), `MTAPIERR` (`F6 F9`),
`MTSTRESS` (20 × `F8` + `F9`), `MTNOID` (`F5 F9`) y `MTCOLLIDE` (sólo `F4`): PASS.

## Resultados

| Paso | Orden | Resultado |
| --- | --- | --- |
| 1 | `.golem output` | «Golem (Accelerator header)», el valor al instalar. |
| 2 | `.golem output left`, `.golem note 60 100 1 1` | `joy-left.csv`: 150 bytes exactos (`90 3C 64`, `80 3C 00` y la limpieza de 16 canales), sin errores de trama, 320–321 µs entre bytes. |
| 3 | `.golem output right`, la misma nota | `joy-right.csv`: los mismos 150 bytes por la patilla 7 del joystick derecho. |
| 4 | `.golem status` | Muestra la salida elegida y «no answer (off or external synth)», lo esperado con el MIDI fuera de la Pi. |
| 5 | `.golem output golem`, `.golem note 60 100 2 2` | Suena en el Golem; por la patilla 7 no sale nada. Los `.mid` también suenan. |

- En el paso 5 se probó primero `.golem note 60 100 2`, en el canal 1, y no sonó: el
  MT-32 no recibe por el canal 1 (sus partes van del 2 al 10). No es un fallo; la
  guía lo dice ahora junto a `note`.
- En el paso 4, `status` mostró «left joystick port». No consta si se ejecutó tras
  volver a `left`; el simulador comprueba que `QUERY` devuelve `$B1` (derecho) tras
  `SET_OUTPUT 2`.

## Observación abierta

De Note On a Note Off van 1009,5 ms en las dos capturas (el 8 de octubre, a 50 Hz
y con `REG 11,161` en lugar del driver: 999,6 ms). Está dentro del margen de
±50 ms de `note`. Queda por ver de dónde salen esos 10 ms de más.
