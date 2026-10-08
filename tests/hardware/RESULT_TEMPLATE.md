# Resultado de sesión física golem-next / Golem

## Identificación

| Campo | Valor |
| --- | --- |
| Fecha/hora y operador | |
| Commit golem-next | |
| Commit Golem/mt32-pi | |
| Next: modelo y revisión | |
| Core y NextZXOS | |
| Pi: modelo y revisión | |
| Imagen/configuración Golem | |
| ROM set / SoundFont + SHA-256 | |
| Analizador, versión y muestreo | |
| Interfaz de audio y formato | |
| Cable y longitud | |
| Ruta de evidencias | |

## Comprobación previa con ambas placas apagadas

| Comprobación | Medida / resultado | PASS/FAIL |
| --- | --- | --- |
| Pin 1/orientación contrastados | | |
| Next TX → Pi GPIO15/pin 10 | | |
| Pi GPIO14/pin 8 → Next RX | | |
| Pi GPIO18/pin 12 → Next BCLK | | |
| Pi GPIO19/pin 35 → Next LRCLK | | |
| Pi GPIO21/pin 40 → Next DATA | | |
| GND común | | |
| 5 V aislado | | |
| 3,3 V aislado | | |
| Ausencia de cortos a alimentación | | |
| Foto del cableado guardada | | |

## Resultados

| Prueba | Configuración | Esperado | Observado | Evidencia | PASS/FAIL |
| --- | --- | --- | --- | --- | --- |
| H0 niveles | | Dominio 3,3 V | | | |
| H1 smoke UART | | `91 3C 64 81 3C 00` | | | |
| H2 MTTEST/ABI | | Oráculo exacto | | | |
| H2 TEST1 | | Oráculo exacto | | | |
| H2 TESTSYX | | Oráculo exacto | | | |
| H2 cancelación | | Limpieza completa | | | |
| H3 Golem Munt | | ACCEPTED→READY + audio | | | |
| H3 Golem FluidSynth | | ACCEPTED→READY + audio | | | |
| H3 error/timeout | | Recuperación limpia | | | |
| H4 50 Hz / 3,5 MHz | | Eventos temporales | | | |
| H4 50 Hz / 7 MHz | | Eventos temporales | | | |
| H4 50 Hz / 14 MHz | | Eventos temporales | | | |
| H4 50 Hz / 28 MHz | | Eventos temporales | | | |
| H4 60 Hz / 3,5 MHz | | Eventos temporales | | | |
| H4 60 Hz / 7 MHz | | Eventos temporales | | | |
| H4 60 Hz / 14 MHz | | Eventos temporales | | | |
| H4 60 Hz / 28 MHz | | Eventos temporales | | | |
| H5 I²S | | Formato compatible | | | |
| H5 audio estéreo | | Limpio/canales correctos | | | |
| H5 latencia total | | Medición publicada | | | |
| H6 robustez | | Recuperación sin bloqueo | | | |

## Incidencias y conclusión

Anotar también resultados fallidos; no sustituirlos por una repetición posterior.

- Incidencias:
- Límites observados:
- Decisión M1:
- Decisión M4:
- Acciones siguientes:
