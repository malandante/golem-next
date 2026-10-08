# Sesión física del 8 de octubre de 2026: MIDI por el puerto de joystick (#64)

## Configuración

| Dato | Valor |
| --- | --- |
| golem-next | `main` en `4aed645` (#78 fusionado): `GOLEM.DRV`, `.GOLEM` |
| Core del Next | 3.02.01 (`REG 1` = 50 = `$32`, `REG 14` = 1) |
| Vídeo | 50 Hz, HDMI |
| Modo | `REG 11,161` (`$A1`): E/S de joystick activa, UART en el puerto izquierdo, UART de la Pi |
| Analizador | Innomaker LA1010, KingstVIS; CH0 en la patilla 7 del joystick izquierdo, GND en la patilla 8 |
| Muestreo | 1 MHz (32 muestras por bit) |
| Decodificador | UART 31250 baudios, 8N1, LSB primero, sin inversión, sin autobaud |

La Pi y su cable no se tocaron. Con el UART desviado al joystick, la Pi no recibe
nada, así que estas capturas miden la salida del Next, no el Golem.

## Resultados

| Captura | Orden | Resultado |
| --- | --- | --- |
| `joy-nota-165.csv` | `.golem note 60 100 1 1`, umbral 1,65 V | 150 bytes exactos: `90 3C 64`, `80 3C 00` y la limpieza de 16 canales. Note On → Note Off: 999,6 ms. |
| `joy-nota-400.csv` | La misma orden, umbral 4,0 V | Sólo errores de trama: el nivel alto no llega a 4 V. **La patilla 7 da 3,3 V.** |
| `joy-test1.csv` | `.golem play "c:/TEST1.MID"` | **PASS**: oráculo `test1`, 344 bytes exactos (`joy-test1.json`). |
| `joy-testsyx.csv` | `.golem play "c:/TESTSYX.MID"` | **PASS**: oráculo `testsyx`, 350 bytes exactos (`joy-testsyx.json`). |
| `joy-testtim-50hz.csv` | `FOR i=1 TO 10: .golem play "c:/TESTTIM.MID": NEXT i` | **PASS**: 10 repeticiones (perfil `smf`) dentro de ±50 ms (`joy-testtim-50hz.json`). |
| `joy-testtim-60hz.csv` | `10 REG 5,REG 5+4: FOR i=1 TO 10: .golem play "c:/TESTTIM.MID": NEXT i: REG 5,REG 5-4` y `RUN` | **PASS** en las 7 repeticiones capturadas (`joy-testtim-60hz.json`); la captura no tiene más (ver abajo). |
| `joy-testtim-60hz-b.csv` | La misma, con `POKE 23692,255` antes del bucle y de cada `play` | **PASS**: 10 repeticiones dentro de ±50 ms (`joy-testtim-60hz-b.json`). |

- **Baudios:** entre bytes seguidos, 320,04 µs de media (320 a 321 µs) en las cuatro
  capturas válidas, unos 31 246 baudios. La diferencia con 31 250 (0,013 %) está
  dentro de la resolución de 1 µs y del reloj del analizador. No hay ningún error
  de trama ni de paridad a 1,65 V.
- **Temporización a 50 Hz:**
  - El peor error absoluto (p95) es de 2,15 ms y la variación entre las diez
    repeticiones, de 0,13 ms pico a pico.
  - El error es estable: unos −2,1 ms en los Note Off y unos −1,1 ms en los Note On
    que los siguen en el mismo milisegundo, que salen 0,96 ms (tres bytes) más tarde.
    Es un desfase fijo respecto al primer evento de cada repetición, no inestabilidad.
  - Desde #57, `play` va siempre a 28 MHz, así que la matriz de velocidades de H4 se
    reduce a 50 y 60 Hz.
- **Temporización a 60 Hz:**
  - El desfase constante es de −11,1 ms (−10,1 ms en los Note On) y la variación entre
    repeticiones, de 0,012 ms pico a pico en las 10 repeticiones de la segunda captura
    (0,013 ms en las 7 de la primera).
  - Los intervalos entre eventos son exactos: de C off a D off, 400,05 ms (400
    esperados), y de D off a E off, 999,95 ms (1000 esperados).
  - El analizador mide cada evento respecto al primero de la repetición, así que un
    primer Note On que sale tarde aparece como el mismo error negativo en todos los
    demás. Es un retraso del arranque (unos 11 ms, dos tercios de un cuadro de
    16,7 ms; unos 2 ms a 50 Hz), no un error de tempo.
  - La captura sólo tiene 7 de las 10 repeticiones: el último byte llega a los
    18,8 s de los 30 grabados. Las 7 están completas. Los mensajes «Golem: loading»
    y «playback finished» llenaron la pantalla y NextBASIC se detuvo en «Scroll?»;
    con la pantalla apagada a 60 Hz no se vio a tiempo. No es un fallo del
    reproductor. La segunda captura (`joy-testtim-60hz-b.csv`) repite la tanda con
    `POKE 23692,255` (la variable SCR CT de la ROM), que evita la pregunta, y tiene
    las 10 repeticiones.

## Conclusiones para #64

1. El core 3.02.01 tiene el registro `$0B`, y `REG 11,161` saca el UART de la Pi por la
   patilla 7 del joystick izquierdo, con los mismos bytes y tiempos que por la
   cabecera.
2. La salida es de **3,3 V**: el cable a DIN MIDI tiene que seguir la variante de
   3,3 V de la especificación MIDI o llevar un buffer (p. ej. 74HCT alimentado a 5 V).
   Antes de diseñarlo hay que medir qué tensión da la patilla 5 del joystick.
3. CTS_n (patilla 6) estaba al aire y no bloqueó la transmisión.

## No incluido

- Las sesiones `.kvdat` están en el PC del usuario, en `C:\golem-evidencia\`.
- Lado de la Pi (H3, respuestas del Golem, y H5, I²S): no se pudo sondear con los dos
  conectores ocupados por el cable. Queda pendiente con un adaptador en T.
