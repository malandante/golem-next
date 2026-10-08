# Banco CSpect → Munt

Este banco expone el UART Pi emulado por CSpect como TCP local y entrega sus
bytes a una captura exacta o al dispositivo MIDI de Windows de Munt. No utiliza
puertos COM virtuales ni instala controladores de kernel.

También valida las órdenes administrativas de Golem como bytes exactos. CSpect
no emula la carga de un motor o SoundFont en mt32-pi; esa aceptación requiere
una Pi 4 real.

Entorno validado el 2026-10-01:

- NextBuild 10, ZX Basic 1.18.7-nb9 y CSpect 3.1.4.0.
- Plugin propio `MT32NextUartBridge.dll`, TCP `127.0.0.1:15320`; la variable
  `MT32_NEXT_UART_PORT` permite aislar otra ejecución.
- Munt con salida MIDI `MT-32 Synth Emulator`.
- ROM de control identificada por Munt como `CTRL_MT32_BLUER` y ROM PCM del
  usuario; las ROMs no forman parte del repositorio.

## Construcción y prueba de humo

Desde la raíz del repositorio:

```powershell
& .\tools\build-cspect-bridge.ps1 -Install

& 'C:\Users\javie\Documents\NextBuildv10\Python\python.exe' `
  'C:\Users\javie\Documents\NextBuildv10\Scripts\nextbuild.py' `
  -b '.\tests\integration\cspect\cspect-uart-probe.bas' -q
```

`-Install` copia el DLL generado junto a `CSpect.exe`; CSpect debe estar cerrado
para reemplazarlo. Sólo un plugin debe poseer estos puertos: si existe
`UARTReplacement.dll`, retirarlo temporalmente de la carpeta de plugins.
Iniciar primero uno de estos receptores:

```powershell
python .\tools\host\capture_uart.py
python .\tools\host\midi_bridge.py
```

Después abrir `cspect-uart-probe.nex` en CSpect. La captura esperada es
`91 3C 64 81 3C 00`: Note On y Note Off en canal MIDI 2. El diagnóstico BASIC
los separa por 25 frames; `MTTEST` mantiene la nota durante 250 frames (unos
cinco segundos) para que la prueba del driver sea claramente audible. El canal
2 coincide con el mapa de recepción predeterminado de un MT-32.

El 2026-10-01 se obtuvo exactamente esa traza y Munt reprodujo la nota. El
primer intento con `PAUSE` colgaba el NEX al entrar en ROM; el fixture definitivo
espera con dos cruces de raster por frame y evita esa dependencia.

## Alcance

La prueba confirma el camino software y el orden binario. No valida pinout,
niveles eléctricos, baud físico, I²S, mezcla del Next, latencia ni jitter reales;
por ello M1 sigue abierto hasta ejecutar la prueba en el hardware.

## Prueba del driver bajo NextZXOS

Construir `GOLEM.DRV` y el cliente independiente:

```powershell
& .\tools\build-driver.ps1
& .\tools\build-test-client.ps1
```

Copiar `build/GOLEM.DRV` a `c:/nextzxos/GOLEM.DRV` y `build/MTTEST` a
`c:/dot/MTTEST` dentro de una copia de la imagen SD. Con la captura o Munt
escuchando, ejecutar desde la línea de comandos del Next:

```text
.install c:/nextzxos/GOLEM.DRV
.mttest
.uninstall c:/nextzxos/GOLEM.DRV
```

`MTTEST` comprueba firma, adquisición, escritura parcial, vaciado con timeout y
liberación. Un resultado correcto deja el borde verde y produce la misma traza
de seis bytes; un error deja el borde rojo. La prueba debe repetirse además con
FIFO llena simulada antes de cerrar M2.

### Presión de FIFO y cero progreso

`MTSTRESS` envía 20 bytes realtime `F8` y sólo termina en verde si el driver le
devuelve al menos una escritura parcial y otra con cero bytes aceptados. Crear
la imagen y arrancar CSpect con el modo de presión opt-in:

```powershell
& .\tools\build-pressure-image.ps1 `
  -OutputImage C:\temp\mt32-pressure.img

$env:MT32_NEXT_UART_STALL_AFTER = '1'
$env:MT32_NEXT_UART_STALL_READS = '4'
& 'C:\Users\javie\Documents\NextBuildv10\Emu\CSpect\CSpect.exe' `
  -w3 -zxnext -nextrom '-mmc=C:\temp\mt32-pressure.img'
```

El plugin debe registrar activación tras el primer byte y liberación tras cuatro
consultas de estado. La captura exacta son 20 bytes `F8` seguidos del marcador
`F9` que el autoexec envía después de desinstalar el driver. La prueba pasó el
2026-10-01; después se repitió el smoke test normal sin estas variables y se
conservó exactamente `91 3C 64 81 3C 00 F8`.

### Errores de API e identidad del driver

El cliente instalado `MTAPIERR` cubre doble adquisición (`BUSY`), operaciones
sin adquirir (`NOT_ACQUIRED`), buffer por debajo de `$4000` (`INVALID`), bits de
`STATUS` y reacquisición. Su imagen y oráculo son:

```powershell
& .\tools\build-api-error-image.ps1 `
  -OutputImage C:\temp\mt32-api-errors.img

python .\tools\host\capture_uart.py --expect "f6 f9"
```

Las pruebas de ID se generan por separado:

```powershell
& .\tools\build-id-test-image.ps1 `
  -Mode Absent `
  -OutputImage C:\temp\mt32-id-absent.img

& .\tools\build-id-test-image.ps1 `
  -Mode Collision `
  -OutputImage C:\temp\mt32-id-collision.img
```

Sin driver, `MTNOID` sólo emite `F5` cuando `M_DRVAPI` devuelve carry; el
autoexec añade `F9`, por lo que el oráculo es `F5 F9`. Para la colisión,
`COLLIDE.DRV` ocupa primero `$2D` y `MTCOLLIDE` confirma su firma con `F4`; el
intento posterior de instalar `GOLEM.DRV` debe detener el autoexec sin sustituir
al señuelo ni emitir más bytes. Capturar `F4` con `--settle-timeout 1` comprueba
también la ausencia de bytes extra. Los tres casos pasaron el 2026-10-01.

`capture_uart.py` conserva una pequeña ventana de asentamiento tras recibir el
oráculo y compara la captura completa, no sólo un prefijo.

## Control Golem: motor y SoundFont

La imagen siguiente ejecuta cuatro órdenes mediante el mismo `GOLEM.DRV`: banco
5, FluidSynth, ROM CM-32L y vuelta a Munt. El marcador `F9` se emite después de
desinstalar:

```powershell
& .\tools\build-golem-control-image.ps1 `
  -OutputImage C:\temp\golem-control.img

python .\tools\host\golem_responder.py --inject-stale
```

Después se arranca CSpect con `C:\temp\golem-control.img`. El respondedor
valida las peticiones Golem v1, inyecta primero respuestas con otra transacción
y luego devuelve `ACCEPTED/READY` correctos. El éxito son cuatro
transacciones y el marcador `F9`. Variantes negativas:

```powershell
python .\tools\host\golem_responder.py --error-index 0 --expect-stop
python .\tools\host\golem_responder.py --timeout-index 0 --timeout 80 --expect-stop
```

Desde #4 la orden rechazada o sin respuesta detiene BASIC con un informe de
error, así que `--expect-stop` comprueba que no llegan más peticiones ni el `F9`.
Hasta entonces, el autoexec continuaba con las tres órdenes restantes. Así es
como las tres variantes pasaron el 2026-10-03. Demuestran el camino bidireccional,
correlación, rechazo y timeout dentro de CSpect; una Pi real sigue siendo
necesaria para confirmar síntesis/carga y tiempos. El protocolo está en
[`docs/mt32-pi-control.md`](../../../docs/mt32-pi-control.md).

### Preservación y duración máxima de llamada

Las imágenes específicas se construyen sin modificar la imagen base:

```powershell
& .\tools\build-m2-verification-image.ps1 `
  -Test State `
  -OutputImage C:\temp\mt32-state.img

& .\tools\build-m2-verification-image.ps1 `
  -Test Duration `
  -OutputImage C:\temp\mt32-duration.img
```

`MTSTATE` compara IX/IY, registros alternativos, selector NextReg, `$A0`, `$A2` (y que valga `$D2` durante la adquisición, código de fallo `06`), MMU
4–7, selección UART y formato de trama. La captura exacta `F3 01 F9` demuestra
además que la desinstalación terminó y el autoexec continuó.

Para duración, arrancar el capturador antes de la imagen normal:

```powershell
python .\tools\host\capture_duration.py `
  --expected-mode 0 --expected-speeds 0 1 2 3 --max-lines 32 --quiet
```

Para 60 Hz, iniciar CSpect con `-60` y añadir al capturador
`--refresh-hz 60 --scanlines 262`.

Repetir con `MT32_NEXT_UART_STALL_AFTER=0` y
`MT32_NEXT_UART_STALL_READS=1000`, usando `--expected-mode 1`. El autoexec
selecciona sucesivamente 3,5/7/14/28 MHz mediante NextReg `$07`; no depende de
los flags de arranque de CSpect, que NextZXOS puede sobrescribir. El cliente
alinea 32 llamadas al inicio de línea y el marcador registra la velocidad
efectiva leída. A 50 Hz/312 líneas se obtuvo:

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

Son límites superiores de CSpect y no son medidas físicas.

`autoexec-smoke.txt` automatiza instalación, prueba y desinstalación en una
imagen desechable. Tras desinstalar envía directamente el byte realtime `F8`;
por tanto su oráculo completo es `91 3C 64 81 3C 00 F8`. Puede capturarse con
`capture_uart.py --expect "91 3c 64 81 3c 00 f8"`.

`tools/build-smoke-image.ps1` crea una copia de 2 GiB de la imagen de NextBuild,
inyecta los tres artefactos y desactiva el programa de bienvenida sólo en esa
copia. Por seguridad se niega a sobrescribir una imagen ya existente.

## Prueba de `.GOLEM note` y `status`

```powershell
& .\tools\build-player-image.ps1 `
  -M3Suite Note `
  -OutputImage C:\temp\mt32-m3-note.img

& .\tools\build-player-image.ps1 `
  -M3Suite Cancel `
  -OutputImage C:\temp\mt32-m3-cancel.img
```

La suite válida ejecuta `status` (que desde #78 envía antes la consulta
`F0 7D 47 4C 4D 01 tt 00 F7` y, sin respuesta en CSpect, espera 200 ms), los extremos `note 0 1 1 1` y
`note 127 127 1 16`, y `note 60 100 1` para comprobar el canal 1 por defecto.
La captura exacta contiene cada Note On/Off, seguido de la limpieza de los 16
canales (`Bn 7B 00` hasta el 4 de octubre de 2026; desde #3,
`Bn 40 00 Bn 7B 00 Bn 78 00`), y un `F9` posterior a la desinstalación. A 50 Hz las duraciones
observadas para los extremos fueron 0,976/0,998 s; a 60 Hz, 0,999/1,000 s,
dentro de ±50 ms. `capture_timing.py --profile note` mide cada pareja por
separado.

La suite inválida comprueba nota 128, velocidades 0/128, duraciones 0/61,
canales 0/17 y texto sobrante. Ningún caso emite MIDI; el único byte capturado
es el marcador final `F6`. Los `CLS` intermedios evitan la pausa de scroll de
BASIC al imprimir repetidamente el uso.

La suite de cancelación mantiene `note 60 100 60 2`. Con Munt abierto se oyó la
nota sostenida y SPACE produjo `81 3C 00` seguido de All Notes Off en los 16
canales; el corte fue audible y no quedó una nota colgada. `status` describe
sólo sesión/FIFO locales y avisa expresamente de que el UART no verifica la
presencia remota.

## Prueba de `.GOLEM play`

```powershell
& .\tools\build-golem.ps1
& .\tools\generate-midi-fixtures.ps1
& .\tools\build-player-image.ps1 -OutputImage C:\temp\mt32-player.img
```

La imagen instala el driver y ejecuta `.golem play c:/TEST1.MID`. El oráculo es
`C1 00 91 40 64 91 40 00`, seguido de la limpieza de los 16 canales. Desde #3
cada canal recibe `Bn 40 00` (pedal de sustain a cero), `Bn 7B 00` (All Notes
Off) y `Bn 78 00` (All Sound Off). Antes era sólo `Bn 7B 00`, y así constan los
resultados anteriores de este documento. El
fixture es SMF1 y prueba tempo, empate determinista y running status por pista.
`TEST0.MID` es SMF0 y mantiene una nota en el canal 2 durante cinco segundos.

Para seleccionar una prueba concreta al construir la imagen:

```powershell
& .\tools\build-player-image.ps1 `
  -Fixture TESTSYX.MID `
  -OutputImage C:\temp\mt32-sysex.img

& .\tools\build-player-image.ps1 `
  -Fixture TESTCAN.MID `
  -OutputImage C:\temp\mt32-cancel.img

& .\tools\build-player-image.ps1 `
  -Fixture TESTSAB.MID `
  -OutputImage C:\temp\mt32-sysex-ab.img
```

`TESTSYX.MID` divide un mensaje de display MT-32 entre eventos F0 y F7. Su
salida exacta, antes de la limpieza, es
`F0 41 10 16 12 20 00 00 54 45 53 54 20 F7`; no deben aparecer en el cable
las longitudes ni los deltas propios del SMF.

### Retorno a BASIC después de `play` (issue #1)

Hasta el 4 de octubre de 2026 ninguna imagen de `play` comprobaba que el
comando volviera a BASIC: `autoexec-player.txt` termina en `STOP` sin marcador
y la suite negativa sólo prueba los rechazos, que salen antes de reproducir.
`-ReturnCheck` añade `.uninstall` y un `F9` escrito desde BASIC después de la
reproducción; el marcador sólo aparece si `.GOLEM play` volvió correctamente.

```powershell
& .\tools\build-player-image.ps1 -ReturnCheck `
  -OutputImage C:\temp\mt32-return.img
python .\tools\host\capture_uart.py --capture-timeout 60 --oracle test1-return
```

El oráculo `test1-return` es el de `test1` seguido de `F9`. También admite
`-Fixture` y `-MidiFile` (por ejemplo BASS104.MID local, fuera del repositorio);
en ese caso el último byte capturado debe ser `F9`.

### Memoria de BASIC intacta (issue #2)

`-MemoryCheck` crea una cadena BASIC de 9000 bytes que cubre `$6000-$7FFF`,
ejecuta `.golem status`, `.golem note 60 100 1` y `.golem play c:/TEST1.MID`, y
después recorre la cadena. Escribe `F9` si sigue intacta y `F8` si algún byte
cambió, e imprime en pantalla cuántos bytes cambiaron. Con el buffer y la pila
en el banco 5, como estaban antes de #2, debe salir `F8`.

```powershell
& .\tools\build-player-image.ps1 -MemoryCheck -OutputImage C:\temp\mt32-memory.img
```

El oráculo `memory` empieza por esa consulta de `status` (la transacción `tt`
se acepta con cualquier valor), y sigue con la nota y su limpieza, seguida de la traza de TEST1 con
la suya y de `F9`: `capture_uart.py --capture-timeout 60 --oracle memory`. El recorrido final dura unos segundos, así que conviene dar a
la captura un margen de 60 s.

### Comparación audible SysEx

`TESTSAB.MID` toca dos veces la misma nota de órgano durante cuatro segundos.
Entre ambas envía un DT1 Roland que cambia `Key Shift` de la parte 1 de 24 a 36
y al final lo restaura a 24. Ejecutar la misma imagen dos veces, cambiando sólo
el puente host:

```powershell
python .\tools\host\midi_bridge.py --sysex drop --quiet
python .\tools\host\midi_bridge.py --sysex pass --quiet
```

Con `drop` ambas notas deben sonar iguales; con `pass`, la segunda debe subir
una octava. La prueba pasó auditivamente el 2026-10-02.

También se validó material real local de King’s Quest V. El SMF1 original mide
646786 bytes y contiene 165 Roland DT1/37630 bytes de payload, todos con checksum
válido. `midi_excerpt.py --seconds 30` generó un extracto local de 23293 bytes
con 74 SysEx; las pasadas A/B enviaron las mismas 828 órdenes cortas y la versión
con SysEx produjo los timbres originales claramente distinguibles. Original,
extracto y manifiesto permanecen fuera de Git.

`TESTCAN.MID` selecciona un órgano y mantiene un acorde C/G/C durante 10
segundos. Tras oírlo claramente, pulsar SPACE en CSpect. La traza debe contener
los tres Note On (`91 30 64`, `91 37 64`, `91 3C 64`) seguidos directamente de
la limpieza `B0..BF 7B 00`, sin los Note Off `81` programados al final. Esto
distingue un corte activo de la mera desaparición de la cola de un sonido con
decay. Ambas pruebas se completaron el 2026-10-01.

La validación se hace en dos pasadas sobre la misma imagen: una sin tocar el
teclado debe producir los tres Note Off al cumplirse los 10 segundos; otra con
SPACE a mitad del acorde debe omitirlos y pasar directamente a All Notes Off.
Así se compara la cancelación contra un control positivo con idéntico timbre.

## Suite de errores (issue #4)

Desde #4, un `.GOLEM` que falla devuelve a NextZXOS un informe de error propio
(carry activo, `A=0`, texto con el bit 7 en el último carácter). BASIC se
detiene y muestra el mensaje, igual que con cualquier otro comando, en lugar de
continuar como si hubiera funcionado. Por eso ya no se pueden encadenar varios
casos negativos en un mismo autoexec: las antiguas `-NegativeSuite` y
`-M3Suite Invalid` se han sustituido por un script que crea una imagen por caso
y lo ejecuta todo:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& .\tools\run-error-suite.ps1
```

Cada caso negativo escribe `F4` desde BASIC, ejecuta un único comando que debe
fallar y después escribe `F8`. La línea del `F8` sólo se alcanza si el comando
volvió sin error. La captura esperada es `F4`, más el MIDI que el propio comando
envíe antes de fallar, y nunca `F8`.

| Caso | Comando | Informe esperado | Bytes tras `F4` |
| --- | --- | --- | --- |
| `smf-format2`, `smf-smpte`, `smf-truncated`, `smf-vlq` | `play BADFMT2/BADSMPTE/BADTRNC/BADVLQ.MID` | `Golem: unsupported SMF (0/1, 24 tracks)` | ninguno |
| `smf-badsyx` | `play BADSYX.MID` | `Golem: invalid SMF event` | `F0 41 10 16 F7` y limpieza completa |
| `file-missing` | `play NOFILE.MID` | `Golem: cannot open file` | ninguno |
| `usage-*` (9 casos) | `note` fuera de rango, cola extra, `status extra` | `Golem: invalid usage` | ninguno |
| `no-driver` | `status` sin `.install` | `Golem: GOLEM.DRV missing or incompatible` | ninguno |

Controles incluidos: `ok-return` (`-ReturnCheck`) y `ok-memory`
(`-MemoryCheck`) siguen terminando en `F9`. `golem-ok` es la imagen de control
Golem con respuestas correctas. `golem-error` y `golem-timeout` usan
`golem_responder.py --expect-stop`: la orden que recibe `ERROR` o ninguna
respuesta debe ser la última que llega, sin más peticiones ni `F9`.

El script se niega a empezar si hay otro CSpect abierto, si falta
`MT32NextUartBridge.dll` o si está `UARTReplacement.dll`. Guarda imágenes,
capturas, registros y `summary.txt`/`summary.json` en `-WorkDir` (por defecto,
una carpeta nueva en `%TEMP%`). Admite `-Only <casos>` para repetir solo unos
cuantos. Tarda unos 10 minutos: unos 25 s por caso, y el timeout de Golem
espera 1500 cuadros.

`BADSYX.MID` contiene un F0 sin F7 terminal. El F7 que se añade antes de la
limpieza evita que la limpieza se interprete como datos del SysEx.

## Medición temporal del scheduler

`TESTTIM.MID` programa notas a 0,0, 0,5, 0,9 y 1,9 segundos, con un cambio de
tempo a 400000 µs por negra y vuelta a 500000. Construir su imagen y arrancar el
capturador antes de CSpect:

```powershell
& .\tools\build-player-image.ps1 `
  -Fixture TESTTIM.MID `
  -OutputImage C:\temp\mt32-timing.img

& 'C:\Users\javie\Documents\NextBuildv10\Python\python.exe' `
  .\tools\host\capture_timing.py `
  --capture-timeout 20 `
  --tolerance 0.04 `
  --output C:\temp\timing.csv
```

La tolerancia funcional software es ±50 ms; incluye CSpect, el plugin, TCP y la
planificación de Windows, y no se presenta como tolerancia física. El scheduler
actual usa pasos exactos de 1 ms distribuidos sobre 312 líneas por cuadro a
50 Hz y 786 líneas cada tres cuadros a 60 Hz.

La matriz se ejecuta con `-CpuSpeed 0..3` para seleccionar 3,5/7/14/28 MHz y
con la misma imagen en arranque normal y con `-60`. El 2026-10-02 pasaron las
ocho combinaciones. A 50 Hz el error absoluto máximo fue 4 ms. A 60 Hz/3,5 MHz
la llegada TCP mostró un máximo reproducible de 26 ms y agrupación por lotes;
en turbo fue menor. Esta observación no distingue jitter del emulador, plugin o
host, así que M4 sigue abierto hasta capturar el UART del hardware real.

Para una prueba local no redistribuible puede añadirse un MIDI propio:

```powershell
& .\tools\build-player-image.ps1 `
  -OutputImage C:\temp\mt32-player.img `
  -MidiFile C:\ruta\cancion.mid
```

El archivo se inyecta como `c:/USER.MID`; el script rechaza más de 1048575 bytes
(el límite de `play` desde #14; antes, 32767).
El 2026-10-01 se probó así un SMF1 de 29608 bytes y 17 pistas: el puente registró
miles de eventos y Munt produjo audio. El archivo comercial no se guarda en el
repositorio.
