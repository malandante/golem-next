# Banco físico Next ↔ Golem

Este procedimiento convierte las pruebas ya ejecutadas en CSpect en evidencia
del enlace real. No se cierra M1 ni M4 por escucha subjetiva: se conservan la
captura lógica, el audio y un registro reproducible.

## 1. Equipo

- ZX Spectrum Next, Raspberry Pi 4 Golem y sus fuentes independientes.
- Cable corto verificado conductor a conductor. Sólo señales y GND común:
  **no conectar 5 V ni 3,3 V entre placas**.
- Analizador lógico USB de 3,3 V con al menos seis canales, muestreo mínimo
  recomendado de 10 MS/s y decodificadores UART e I²S. El equipo de referencia
  elegido es **Innomaker LA1010**: 16 canales, umbral ajustable y 50 MS/s con
  seis canales activos. Sus 20 pinzas incluidas evitan comprar sondas aparte.
- PC con Logic 2, PulseView/sigrok o equivalente.
- Para validar audio y latencia completa: interfaz de audio USB. Un osciloscopio
  es útil, pero no sustituye la captura de bytes y tiempos.

El analizador es un observador pasivo. Sus entradas se conectan en paralelo a
Next TX, Next RX, BCLK, LRCLK, DATA y GND; no se intercala en el enlace. La
salida analógica del Next se graba aparte.

### Perfil LA1010 de referencia

En KingstVIS habilitar seis canales para obtener 50 MS/s y usar esta asignación:

| Canal | Señal |
| --- | --- |
| CH0 | Next TX → Pi RX |
| CH1 | Pi TX → Next RX |
| CH2 | I²S BCLK |
| CH3 | I²S LRCLK |
| CH4 | I²S DATA |
| CH5 | Reserva/marca de prueba |

Fijar el umbral a 1,65 V para lógica de 3,3 V. Conectar primero GND y después
las señales, usando cables de sonda cortos; no usar las salidas PWM del LA1010.
Para UART seleccionar manualmente 31250 baud, 8 bits, 1 stop, sin paridad, LSB
primero y sin inversión; no utilizar autodetección como evidencia del baud.

Guardar siempre la sesión original `.kvdat` y exportar los resultados
decodificados como CSV, en hexadecimal. KingstVIS incluye timestamp, secuencia y
datos en esa exportación. Si sus encabezados no coinciden con la detección
automática, `analyze_uart_capture.py` acepta `--time-column` y `--value-column`.
La sesión original permite corregir posteriormente un decoder mal configurado
sin repetir la ejecución física.

## 2. Reglas de seguridad

1. Apagar y desconectar ambas fuentes antes de cambiar un conductor o sonda.
2. Identificar el pin 1 y verificar el mapa del conector Accelerator en el
   esquema de la revisión concreta del Next. Los números físicos publicados en
   `docs/architecture.md` corresponden únicamente al conector de la Pi.
3. Medir continuidad señal a señal, GND común y aislamiento de 5 V/3,3 V.
4. No conectar en caliente ni dejar una placa apagada recibiendo señales de la
   otra. No utilizar un cable plano completo sin mapa comprobado.

## 3. Configuración que se debe registrar

Copiar `RESULT_TEMPLATE.md` para cada sesión y anotar commits de golem-next y
Golem, versión de core/NextZXOS, modelo/revisión de placas, configuración de la
Pi, ROM/SoundFont, longitud del cable, frecuencia de muestreo y formato de los
decodificadores. Fotografiar el cableado antes de encender.

Configurar el UART como 31250 baud, 8N1, sin paridad ni control de flujo. La Pi
es inicialmente maestra I²S y el Next receptor. Configurar el decodificador I²S
con los valores observados, no asumir que 48 kHz o una anchura concreta ya han
sido validados.

## 4. Secuencia de pruebas

### H0 — continuidad y niveles

Con las placas apagadas, completar la tabla eléctrica de la plantilla. Encender
sin ejecutar música y comprobar con instrumento de alta impedancia que ninguna
señal supera el dominio de 3,3 V. Si hay una duda de orientación o alimentación,
detener aquí la sesión.

### H1 — UART unidireccional y bytes exactos

Instalar `GOLEM.DRV` y ejecutar primero el smoke test. Decodificar Next TX→Pi RX
y exportar CSV con timestamp y byte. Debe observarse exactamente:

```text
91 3C 64 81 3C 00
```

Ejemplo para Logic 2 cuando `Value` se exporta en hexadecimal:

```powershell
python .\tools\host\analyze_uart_capture.py .\evidence\h1.csv `
  --radix hex --oracle smoke `
  --report .\evidence\h1.json
```

El propio decodificador debe mostrar 31250 baud, 8 bits, una parada, sin errores
de framing/paridad. Conservar además una captura de forma de onda que incluya
varios bits; el CSV de bytes no demuestra por sí solo el baud físico.

### H2 — regresión de driver y reproductor

Repetir las pruebas exactas de `MTTEST`, `TEST1.MID`, `TESTSYX.MID`, suite
negativa, cancelación y limpieza. Recortar cada captura al intervalo de la
prueba y compararla con los oráculos incorporados `mttest`, `test1`, `testsyx`,
`negative` o `badsyx`. No incluir MIDI comerciales en el repositorio.

Para capturas bidireccionales en un único CSV puede seleccionarse el sentido:

```powershell
python .\tools\host\analyze_uart_capture.py .\evidence\h2.csv `
  --direction-column Direction --direction TX --radix hex `
  --oracle test1 --report .\evidence\h2-test1.json
```

Si el analizador usa otros encabezados, indicarlos con `--time-column` y
`--value-column`. `--time-unit s|ms|us|ns` evita ambigüedades.

#### MIDI de más de 32 KB (#14)

Desde el 5 de octubre de 2026, `play` carga el archivo entero en bancos de 8 KiB
(hasta 1048575 bytes) y lee cada byte a través del MMU 7. Para probarlo sin
depender de un MIDI comercial está `tests/fixtures/METROBIG.MID` (158806 bytes),
generado con `make_metronome.py --pad-kb 150`. Es `METRO120.MID` con una pista de
texto de unos 150 KB delante: los clics quedan pasados los 64 KB y el reproductor
salta entre dos zonas del archivo en cada pulso. Debe sonar exactamente igual
que `METRO120.MID`, sin desfase respecto a un metrónomo externo. Después, un
MIDI real grande (por ejemplo, la banda sonora de KQ5, de 646786 bytes) debe
sonar completo. Anotar cuánto tarda en empezar (la carga desde la SD) y si
aparece «faltan bancos de memoria».

### H3 — control bidireccional de Golem

Ejecutar `.GOLEM` contra el fork real y capturar ambos sentidos. Verificar que
cada transacción conserva comando y valor y que la respuesta es
`ACCEPTED→READY`, o `ERROR` cuando se inyecta un fallo controlado. Probar timeout
deteniendo el servicio receptor mediante un modo de prueba; no desconectar el
cable en caliente. Confirmar por audio el cambio Munt/FluidSynth y el SoundFont,
pero usar la captura UART como oráculo del protocolo.

### H4 — temporización física

Ejecutar `TESTTIM.MID` diez veces en una captura continua para cada combinación
de 3,5/7/14/28 MHz, primero a 50 Hz y después a 60 Hz. El timestamp de cada byte
debe ser el del inicio del byte UART. Para cada una de las ocho capturas:

```powershell
python .\tools\host\analyze_uart_capture.py .\evidence\h4-50-3_5.csv `
  --radix hex --profile smf --runs 10 --tolerance-ms 50 `
  --report .\evidence\h4-50-3_5.json
```

La tolerancia de 50 ms es un techo funcional provisional, no el objetivo final.
Cada JSON conserva las diez repeticiones; con los ocho JSON y CSV calcularemos
error sistemático, dispersión, máximo y percentiles antes de fijar el criterio
físico de M4. Si una ejecución se contamina por intervención manual se conserva
y se marca, no se borra silenciosamente.

Cuando estén las ocho capturas, generar el resumen común:

```powershell
python .\tools\host\summarize_physical_timing.py `
  .\evidence\h4-50-*.json .\evidence\h4-60-*.json `
  --json-output .\evidence\h4-summary.json `
  --markdown-output .\evidence\h4-summary.md
```

El resumen separa error respecto al tiempo musical esperado de jitter entre
repeticiones; no se describirá uno con las cifras del otro.

### H5 — I²S y audio

Capturar BCLK, LRCLK y DATA durante notas conocidas. Registrar frecuencia de
muestreo, relación BCLK/LRCLK, bits por slot, alineación, polaridad y orden de
canales. Verificar silencio, izquierda, derecha y estéreo. Grabar WAV desde la
salida del Next sin normalización ni efectos y comprobar ausencia de clipping,
distorsión, canales cruzados o cortes.

Para medir latencia extremo a extremo, una misma captura debe contener Next TX
y una señal derivada de la salida analógica (osciloscopio o analizador mixto).
La diferencia entre inicio de Note On y comienzo de audio incluye UART, síntesis,
I²S y mezcla del Next.

### H6 — robustez

Probar arranque en frío, Pi tardía/ausente, adquisiciones repetidas, presión de
FIFO mediante modo de prueba determinista del fork, cancelación durante SysEx,
reproducción larga y un juego bajo carga. Tras cada fallo, ejecutar un smoke test
limpio y comprobar ausencia de notas colgadas, bloqueo o estado persistente.

## 5. Criterio de cierre

- Cero bytes perdidos, duplicados, reordenados o con error de trama.
- UART 31250 8N1 medido y protocolo Golem correlacionado correctamente.
- Resultados de las ocho combinaciones 50/60 Hz y turbo publicados con captura
  cruda; el límite de jitter definitivo se acuerda después de esa línea base.
- I²S compatible, estéreo correcto y audio limpio mezclado por el Next.
- Estado y recursos restaurados después de fin, cancelación, error y timeout.
- Commits, configuración, hashes, CSV/JSON, sesión del analizador y WAV quedan
  asociados al resultado. Los ficheros comerciales permanecen fuera de Git.

## 6. Qué puede hacerse a distancia

Una vez conectadas las sondas y abierta una aplicación de analizador que permita
exportación, el PC puede guardar las capturas y ejecutar estas comparaciones.
Codex puede analizar los CSV/JSON/WAV accesibles en el equipo y automatizar las
matrices. El usuario sólo necesita realizar físicamente el cableado seguro,
encender/apagar cuando corresponda y confirmar lo que se oye. El análisis no
requiere que el Next se presente al PC como USB ni que el PC forme parte del
camino musical.

## Líneas por cuadro e interrupciones perdidas (`MTFRAME`, #7 y #10)

`.MTFRAME` (en `C:/DOT`, con `GOLEM.DRV` instalado) mide en el Next real y
restaura al terminar la velocidad de CPU, la pantalla y el driver:

1. `lineas/cuadro`: la línea raster más alta, muestreada a 28 MHz durante ocho
   cuadros, más uno, y si el vídeo va a 50 o 60 Hz (#7).
2. `5 s UART`: envía 15625 bytes `$F8` a 31250 baudios (320 µs cada uno, 5 s
   exactos si el divisor es correcto) y cuenta los cuadros y líneas que pasan
   hasta vaciar la FIFO. Cuadros por segundo = (cuadros + líneas/líneas por
   cuadro) / (bytes × 0,00032). Es la referencia de tiempo absoluto para #7.
3. Para 3,5/7/14/28 MHz y para `STATUS` y `WRITE` (16 bytes `$F8`, reloj MIDI que
   el MT-32 ignora): en cada línea raster L hace una llamada al llegar a L y
   comprueba que `FRAMES` (`$5C78`, que incrementa la rutina IM1 de la ROM) ha
   avanzado uno al volver a L en el cuadro siguiente. Imprime cuántas líneas
   perdieron la interrupción y su rango (#10). El ancho del rango por 64 µs es
   lo que la llamada mantiene las interrupciones bloqueadas, y su posición
   indica dónde cae la interrupción de cuadro. Dura unos 50 s a 50 Hz.

```basic
.install "c:/nextzxos/GOLEM.DRV"
.mtframe
```

Resultados del 2026-10-05 (Next por HDMI, temporización de la máquina por
defecto):

- Líneas por cuadro: 311 a 50 Hz y 264 a 60 Hz (el scheduler suponía 312 y
  262). Esto no desvía el tempo: el contador da la vuelta con el mismo módulo
  que se suma, así que cada cuadro cuenta como 312 (o 262) líneas y vale 20 ms
  (o 16,67 ms). Lo que sí importa es la duración real del cuadro, que mide la
  línea `5 s UART`.
- Interrupción de cuadro en la línea ~247 (50 Hz) y ~223 (60 Hz). Una llamada que
  la cubre la pierde. Líneas de bloqueo por llamada: `STATUS` 3/2/0-1/1 y
  `WRITE` hasta 18/8/3/2 a 3,5/7/14/28 MHz (≈1,2 ms como máximo a 3,5 MHz). El
  driver no desactiva interrupciones; lo hace NextZXOS durante `M_DRVAPI`.

Primera ejecución, 2026-10-05 (versión anterior, con llamadas en bucle): 311
líneas a 50 Hz y 263 a 60 Hz (el scheduler suponía 312/262), y `FRAMES` contó
entre el 26 % y el 87 % de los cuadros según velocidad y orden, es decir, se
perdían interrupciones durante las llamadas.

## Velocidad de carga (`MTLOAD`, #57)

`.MTLOAD <fichero>` lee el fichero entero ocho veces y mide cada pasada con
`FRAMES` (50 o 60 por segundo); no usa el driver ni el puerto MIDI. Pasadas:
8 KiB por llamada en `$E000` a 28 MHz (lo que hace `play` desde #14); 8, 16 y
32 KiB y 512 bytes por llamada en `$8000` a 28 MHz; 8 KiB en `$E000` a 3,5 y
7 MHz; y otra vez la primera, para ver si la tarjeta va más rápida en caliente.
Después reserva y libera hasta 80 bancos con `IDE_BANK`. KB/s de cada pasada =
KB × 50 / cuadros (×60 a 60 Hz). Si la suma de cuadros («Total cuadros») no
cuadra con un cronómetro, `FRAMES` se para mientras se lee la SD y los números
son por defecto. Restaura MMU 3–7, velocidad y selector, y libera los bancos.

Resultado del 2026-10-05 con la banda sonora de KQ5 (646786 bytes, 631 KB), a
50 Hz, con un cronómetro de unos 30 s para el total (1363 cuadros ≈ 27,6 s:
`FRAMES` sigue contando mientras se lee la SD):

| Pasada | Cuadros | KB/s aprox. |
| --- | --- | --- |
| 8 KiB en `$E000`, 28 MHz | 100 | 310 |
| 8 KiB en `$8000`, 28 MHz | 66 | 470 |
| 16 KiB en `$8000`, 28 MHz | 66 | 470 |
| 32 KiB en `$8000`, 28 MHz | 99 | 315 |
| 512 bytes en `$8000`, 28 MHz | 73 | 425 |
| 8 KiB en `$E000`, 3,5 MHz | 567 | 55 |
| 8 KiB en `$E000`, 7 MHz | 291 | 107 |
| 8 KiB en `$E000`, 28 MHz (repetida) | 100 | 310 |
| `IDE_BANK` ×80 | 1 | — |

Conclusiones: manda la CPU (5,7 veces más lento a 3,5 MHz); leer en
`$C000-$FFFF` cuesta un 50 % más que en `$8000` (la pasada de 32 KiB, que
cubre las dos zonas, queda en medio); el tamaño de cada llamada casi no
importa; reservar bancos no cuesta nada y la tarjeta no va más rápida en
caliente. Con la carga de #14 (8 KiB en `$E000` a 28 MHz), KQ5 debería cargar
en unos 2 s: los segundos de silencio que siguen son la introducción del
propio MIDI (`tools/host/smf_intro.py`). Desde #57, `play` lee cada banco en
`$8000` (MMU 4).
