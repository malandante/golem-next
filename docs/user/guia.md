# golem-next: guía de usuario

*Versión 1.0.0, 8 de octubre de 2026. English version:
[guide.md](guide.md).*

golem-next permite que el ZX Spectrum Next toque música MIDI con calidad de
Roland MT-32 o de General MIDI. El Next envía MIDI por su puerto serie a una
Raspberry Pi con el firmware **Golem** (basado en mt32-pi), que genera el
sonido con **Munt** (emulación de MT-32 / CM-32L) o **FluidSynth** (SoundFonts
General MIDI) y lo devuelve al Next por I²S. El audio sale por el Next: HDMI o
salida analógica.

Lo que se instala en el Next:

- **`GOLEM.DRV`**, el driver de NextZXOS que habla con la Pi. Lo usan todos los
  programas.
- **`.GOLEM`**: reproduce ficheros MIDI, toca notas de prueba y cambia la
  configuración del sintetizador. **`.MT32`** y **`.GM`** son el mismo comando,
  pero antes de tocar ponen la Pi en MT-32 o en General MIDI.
- **`.GSQ`**: reproduce ficheros GSEQ (`.GSQ`), el formato de música
  precompilada que usan los juegos.

## 1. Qué hace falta

- Un ZX Spectrum Next con NextZXOS.
- Una Raspberry Pi con el firmware Golem: el **Golem Sound Module** de Golem
  Retro, o una Pi 3 o Pi 4 propia con el cable adecuado. Las pruebas de esta
  versión se han hecho con una Pi 3.
- **Una fuente de alimentación propia para la Pi.** La Pi no se alimenta del
  Next. Con una fuente insuficiente no recibe MIDI y su LED rojo parpadea.
- **Para sonido MT-32:** las ROM del MT-32 o del CM-32L, que no se incluyen y
  tienes que aportar tú. Sin ellas solo está disponible FluidSynth.
- **Para General MIDI:** al menos un SoundFont (`.sf2` o `.sf3`).

## 2. Conexión

El Golem Sound Module ya viene preparado. Si montas tu propio cable, lee esto
antes de conectar nada:

- **Las alimentaciones van separadas.** Aísla todas las líneas de 5 V y de
  3,3 V entre el Next y la Pi (en la Pi, patillas 2 y 4 de 5 V y 1 y 17 de
  3,3 V). Solo se comparte la masa (GND).
- La conexión va por el **conector Accelerator** del Next, que no es el J15.
  Lleva el UART (MIDI hacia la Pi) y el I²S (audio de vuelta).
- No conectes un cable plano de 40 vías completo sin comprobar la orientación
  y el aislamiento de las alimentaciones.
- **No conectes ni desconectes con los equipos encendidos.**
- Las señales son de 3,3 V. No es un puerto RS-232 ni una entrada MIDI DIN.

Patillas del lado de la Pi (numeración de 40 patillas de la Pi):

| Señal | GPIO | Patilla |
| --- | --- | --- |
| RX de la Pi (MIDI desde el Next) | GPIO15 | 10 |
| TX de la Pi (respuestas Golem) | GPIO14 | 8 |
| BCLK (I²S) | GPIO18 | 12 |
| LRCLK (I²S) | GPIO19 | 35 |
| Datos de audio hacia el Next | GPIO21 | 40 |
| Masa | — | 6 (u otra GND) |
| 5 V y 3,3 V | — | 2, 4, 1, 17: **aisladas, sin conectar** |

*Puerto de joystick:* `.golem output left` o `right` saca el MIDI por la
patilla 7 de ese puerto, para un sintetizador MIDI externo sin Pi. La señal es
de 3,3 V y falta el cable con su esquema: no conectes un cable MIDI DIN al
joystick por tu cuenta. `.golem output left` deja el puerto preparado al
momento y en reposo, y así sigue hasta `.golem output golem` o hasta apagar:
mientras la salida sea por joystick, ese puerto no sirve para jugar (usa el
otro). Si el adaptador MIDI se queda puesto, conviene poner `.golem output
left` en el autoexec: sin él, desde el encendido el Next usa esa patilla para
leer mandos Mega Drive y el sintetizador recibe pulsos cortos que algunos
podrían tomar por datos.

*Dónde se oye:* el sonido del Golem llega al Next en digital y el Next lo
mezcla con el suyo (AY, beeper…). Sale por sus dos salidas:

- **HDMI (recomendada):** la mezcla va en digital a la tele o al amplificador,
  que la convierten con buena calidad. Suena limpio.
- **Minijack del Next:** la conversión a analógico la hace el propio Next con
  un convertidor muy sencillo. Con sonidos flojos (la cola de una nota, la
  reverberación) se oye un chisporroteo que cambia según la nota. Es del
  Next, no del Golem: con el firmware original de mt32-pi pasa igual.
- **Para tocar con teclado,** la tele suele retrasar el sonido (entre 50 y
  150 ms) para sincronizarlo con la imagen. Activa el **modo juego** de la
  tele en la entrada del Next.

## 3. Preparar la Pi

1. Descarga la release del firmware Golem en github.com/malandante/mt32-pi/releases
   y copia su contenido en una tarjeta SD vacía en FAT32. El código fuente del
   firmware (GPL-3.0) está en ese mismo repositorio.
2. En `mt32-pi.cfg`, **cambia solo estos valores** y deja el resto como está:

   ```ini
   [midi]
   gpio_baud_rate = 31250
   gpio_thru = off

   [audio]
   output_device = i2s
   sample_rate = 48000
   ```

   Sin `output_device = i2s` el sonido no llega al Next.
3. **ROM del MT-32** en la carpeta `roms/`: solo ROM completas (por ejemplo
   `mt32_ctrl_1_07.rom` y `mt32_pcm.rom`, o `cm32l_ctrl_1_02.rom` y
   `cm32l_pcm.rom`) y una sola ROM de control por variante. Las ROM partidas
   (`_a`/`_b`, `_h`/`_l`) pueden impedir que arranque el MT-32. En ese caso
   mt32-pi pasa a FluidSynth sin avisar.
4. **SoundFonts** en `soundfonts/`. Se numeran por orden alfabético, así que
   conviene ponerles un prefijo fijo: `000-GeneralUser.sf2`, `001-…`.
5. **Lo que elijas con `.golem` no se guarda.** El motor, la ROM y el SoundFont
   que cambies desde el Next duran hasta que la Pi se apaga o se reinicia;
   después vuelve a lo que diga `mt32-pi.cfg`: `default_synth` en `[system]`
   (`mt32` o `soundfont`), `rom_set` en `[mt32emu]` (`old`, `new`, `cm32l` o
   `any`) y `soundfont` en `[fluidsynth]` (el número). Cambia ahí los valores si
   quieres otros por defecto. El motor no importa si usas `.mt32` o `.gm`, que lo
   eligen cada vez.

## 4. Instalar en el Next

1. Copia `GOLEM.DRV` a `c:/nextzxos/`, los comandos `GOLEM`, `MT32`, `GM`, `GSQ` y
   `MIDIMON` a `c:/dot/` y la ayuda `GOLEM.GDE` (carpeta `docs/guides` del paquete) a
   `c:/docs/guides/`. Con `.guide golem` se ve en el Next.
2. Instala el driver:

   ```
   .install "c:/nextzxos/GOLEM.DRV"
   ```

3. Para no tener que instalarlo cada vez, añádelo al programa de arranque
   `c:/nextzxos/autoexec.bas`. Si no existe, escribe en NextBASIC la línea
   siguiente y guárdala con `SAVE "c:/nextzxos/autoexec.bas"`. Si ya existe,
   cárgalo, añade la línea y guárdalo igual:

   ```
   10 .install "c:/nextzxos/GOLEM.DRV"
   ```

4. Para quitarlo: `.uninstall "c:/nextzxos/GOLEM.DRV"`.

El driver activa por sí mismo la entrada de audio I²S de la Pi cuando un
programa lo usa, y la deja como estaba al terminar. Usa el identificador
experimental `$2D`; el definitivo se pedirá a los responsables de NextZXOS.

## 5. Comandos

### `.golem`, `.mt32` y `.gm`

| Orden | Qué hace |
| --- | --- |
| `.golem play fichero.mid [banco]` | Reproduce un MIDI (SMF 0 o 1, hasta 24 pistas y 1 MB). SPACE lo cancela. Un número tras el fichero elige antes el banco OPL3, como `.golem bank`: `.opl3 play doom.mid 72`. |
| `.golem note <nota> <vel> <seg> [canal]` | Toca una nota de prueba: nota 0–127, velocidad 1–127, 1–60 segundos, canal 1–16 (1 si no se indica). Con el motor MT-32 usa los canales 2–10: el 1 no suena. |
| `.golem status` | Comprueba el driver y pregunta al Golem su motor, ROM y SoundFont, p. ej. «Golem: engine MT32; ROM new; SoundFont 0»; con el motor OPL3 también su banco («engine OPL3; bank 72; …»). Si no contesta en 0,2 s dice «no answer». «RX errors» indica que se han recibido bytes con error. |
| `.golem engine mt32` / `fluidsynth` / `opl3` | Cambia el motor de la Pi: MT-32 (Munt), General MIDI (FluidSynth) o General MIDI con síntesis FM OPL3, el sonido de una Sound Blaster 16 (libADLMIDI; firmware golem-1.2.0). |
| `.golem soundfont <0-127>` | Elige el SoundFont de FluidSynth por número. |
| `.golem bank <0-127>` | Banco de instrumentos del motor OPL3 (72, DMXOPL3, al arrancar). Del 0 al 78 vienen incluidos; algunos para probar: 0 The Fat Man (AIL), 58 y 59 The Fat Man para Windows 9x (2 y 4 operadores), 72 DMXOPL3. Bancos propios: ficheros WOPL (hechos o convertidos con OPL3 Bank Editor) en la carpeta `opl3` de la SD de la Pi, numerados desde el 79 por orden alfabético. Cambiar de banco corta las notas y devuelve los instrumentos al inicial. Firmware golem-1.2.0. |
| `.golem rom old` / `new` / `cm32l` | Elige las ROM: MT-32 antiguo, MT-32 nuevo o CM-32L. |
| `.golem output golem` / `left` / `right` | Elige por dónde sale el MIDI: el Golem (conector del Accelerator, lo normal) o la patilla 7 del puerto de joystick izquierdo o derecho, para un sintetizador externo. Sin palabra, dice cuál está elegida. |
| `.golem usb off` / `on` / `bridge` | Reenvío a dispositivos USB-MIDI conectados a la Pi (interfaz USB-DIN, otro sinte). `on`: suena el Golem y también el USB; `bridge`: sólo el USB, el Golem calla; `off`: sólo el Golem. Sin palabra, dice el modo y cuántos dispositivos USB-MIDI hay. Necesita el firmware golem-1.1.0 o posterior; con uno anterior dice «firmware too old». |
| `.golem set volume <0-100>` | Volumen general de los dos motores (100 al arrancar); el mismo que cambian los botones o la rueda de un HAT de la Pi. |
| `.golem set fx on` / `off` | Reverberación y chorus de FluidSynth en todos los canales. `off` da un sonido seco para tocar un teclado. |
| `.golem set channels std` / `alt` | Canales del MT-32: `std`, partes en 2–10, como un MT-32 real; `alt`, 1–8 y ritmo en el 10, para teclados fijos en el canal 1. |
| `.golem set thru on` / `off` | Un teclado USB en la Pi toca también los dispositivos USB-MIDI (ver `usb`). |
| `.golem set keys on` / `off` | Un teclado USB en la Pi manda también lo que se toca al Next, para los programas que leen MIDI (el Golem lo sigue tocando). |
| `.golem set loud on` / `off` | Sube el volumen del Golem sin distorsión (un limitador sujeta los picos). Por HDMI el Golem solo puede sonar la mitad de fuerte que el PCM del Next; esto equilibra la música y los efectos de un juego. Los pasajes muy suaves también suben un poco. Firmware golem-1.2.0. |
| `.golem save` / `save clear` | Guarda los ajustes actuales del Golem (motor, ROM, SoundFont, `set` y `usb`) para el próximo arranque, en `golem.cfg`, junto a `mt32-pi.cfg` en la SD de la Pi, que se lee después de `mt32-pi.cfg`. `clear` borra ese fichero. |
| `.golem reset` | Devuelve el sinte a su estado de fábrica: manda el «reset» de MT-32 y el «GM System On». Borra lo que hayan cargado los SysEx de canciones anteriores (instrumentos, ritmos, efectos). |

- `.mt32`, `.gm` y `.opl3` aceptan las mismas órdenes. Antes de `play` y
  `note` piden a la Pi el motor MT-32, FluidSynth u OPL3 y esperan a que esté listo; si ya lo está,
  no cambia nada. Si no contesta nada en 0,2 segundos (por ejemplo, un
  sintetizador MIDI externo), tocan igualmente. `.golem` no cambia el motor.
  Por ejemplo, `.gm play cancion.mid` para un MIDI General MIDI y
  `.mt32 play juego.mid` para uno de MT-32.
- `play` reinicia el sinte antes de cada canción, como `.golem reset`, para
  que no se arrastren los SysEx de la anterior (una canción que necesita
  instrumentos propios los manda ella misma). `note` no reinicia.
- Antes de cada canción, `play` limpia el sintetizador: suelta el pedal, corta
  las notas y deja el volumen de cada canal a 100. Al terminar o cancelar
  también corta todas las notas.
- Un teclado MIDI conectado al USB de la Pi (directo o con una interfaz
  USB-MIDI) toca el sinte del Golem a la vez que el Next. Se oye a partir del
  primer comando del Golem que use el driver (`play`, `note`, `output`); para
  oírlo desde el encendido, pon `.golem output golem` en el autoexec. Los dos comparten
  los 16 canales: si el teclado usa un canal que la canción también usa, se
  mezclan, y al acabar la canción su limpieza corta también las notas del
  teclado. Con el motor FluidSynth (General MIDI) pon el teclado en el
  canal 16, el que menos usan las canciones GM; el 10 es percusión. Con el
  motor MT-32 sólo suenan los canales 2–10 (el 1 y el 11–16 no suenan) y una
  canción de MT-32 suele usarlos todos: toca en uno que esa canción no use,
  o con el Next parado.
- Muchos teclados sencillos no dejan cambiar el canal y tocan siempre en el
  **1**. Con FluidSynth suena; con el MT-32 no. Para tocarlo con el MT-32:
  `.golem set channels alt` (la parte 1 pasa al canal 1), y otra vez `std`
  para los juegos y canciones de MT-32, que esperan el canal 2.
- Para tocar el teclado con un piano seco, sin reverberación ni chorus
  (FluidSynth): `.golem set fx off`; `on` los devuelve. Si un instrumento
  sigue sonando con chorus, lo trae el propio SoundFont: `chorus = off` en
  `mt32-pi.cfg`. Para otros programas y reproductores están también
  `DRY.MID` y `EFFECTS.MID` (carpeta `midi` del paquete), pero su efecto
  sólo dura hasta el siguiente `play`.
- Los ajustes de `set` sobreviven a `play`, a `reset` y al «reset» que mandan
  las canciones, y duran hasta que se apaga la Pi (o más, con `.golem save`). Al arrancar el volumen es
  100 y el resto sale de `mt32-pi.cfg` (`reverb`/`chorus`, `midi_channels`,
  `usb_in_thru`). Una canción todavía puede cambiar el volumen del MT-32 por
  su cuenta. Sin valor, `set` sólo informa: `.golem set volume` →
  «Golem: volume 80». Necesita el firmware golem-1.1.0 o posterior.
- `.golem` solo muestra un resumen de una línea; la ayuda completa es
  `.guide golem`.
- `engine`, `soundfont` y `rom` esperan a que la Pi confirme el cambio, como
  mucho unos 30 segundos, porque un SoundFont tarda en cargarse. SPACE
  cancela la espera, pero la Pi puede aplicar el cambio igualmente.
- `soundfont` también funciona con el motor en MT-32: deja preparado ese
  SoundFont, que se oirá al pasar a `engine fluidsynth`. Da error si no existe
  un SoundFont con ese número, si no hay ninguno en la SD o si no se puede
  cargar.
- **No toques música mientras la Pi cambia de SoundFont:** durante la carga
  no atiende el puerto y podría perder datos.
- `output` vale para todo lo que use el driver (`.golem`, `.gsq` y los
  juegos) hasta reiniciar o desinstalar el driver; para dejarlo fijo, ponlo en
  el autoexec después de `.install`. Mientras la salida sea por joystick, ese
  puerto no funciona como joystick (el otro sí), suene música o no. Con salida por
  joystick, `.mt32` y `.gm` no preguntan al Golem y tocan directamente.
- Los errores se devuelven a BASIC como informes de error normales (por
  ejemplo «Golem: GOLEM.DRV missing or incompat.»), así que se pueden tratar con
  `ON ERROR`. Los mensajes de los comandos están en inglés.

### `.gsq`

```
.gsq musica.gsq
```

Reproduce un fichero GSEQ. **P** pausa y reanuda; **SPACE** para. La pausa
calla de verdad el MT-32 y al reanudar vuelve a tocar las notas que estaban
sonando.

### `.midimon`

```
.midimon
```

Muestra en hexadecimal, uno por línea, cada mensaje MIDI que llega al Next
(`90 3C 64` es una nota), hasta pulsar SPACE. Para ver un teclado USB en el
Golem, antes `.golem set keys on`; para un teclado DIN en la entrada MIDI IN
del adaptador del joystick, `.golem output left` (o `right`). Las respuestas
del propio Golem no se muestran. Sirve para comprobar un teclado, su canal y
sus controles.

## 6. Convertir música a GSEQ

Los juegos usan GSEQ: música MIDI convertida en el PC a un formato que el Next
reproduce con muy poco trabajo. El conversor está en `tools/host/gseq.py` y
necesita Python 3:

```
python tools/host/gseq.py musica.mid -o MUSICA.GSQ
python tools/host/gseq.py tema.mid -o TEMA.GSQ --loop
python tools/host/gseq.py tema.mid -o TEMA.GSQ --loop-start-ms 4000 --report informe.json
```

- `--loop` repite toda la canción; `--loop-start-ms N` vuelve al
  milisegundo N. Si el MIDI tiene marcadores `loopStart` y `loopEnd`, se usan
  esos.
- `--sysex-gap N` separa N ms los mensajes que siguen a un SysEx. Hace falta
  con un MT-32 real, no con mt32-pi.
- `--target mt32|gm` anota para qué sintetizador es la música.
- El conversor avisa si un pasaje necesita más de lo que da el cable (3125
  bytes por segundo) o si al volver al principio del bucle quedan notas
  sonando.

Para programadores: cómo usar el driver y la biblioteca GSEQ desde BASIC,
ZX Basic o ensamblador está en la guía de programación
([`programming.md`](../programming.md), en inglés). El formato y el diseño de
la biblioteca, en [`m6-gseq.md`](../m6-gseq.md).

## 7. Problemas frecuentes

| Síntoma | Qué mirar |
| --- | --- |
| Chisporroteo en las colas de las notas o en la reverberación, sólo por el minijack del Next | Es el convertidor analógico del Next. Escucha por HDMI. |
| Al tocar un teclado, el sonido llega tarde por la tele | Retraso de la tele: activa su modo juego en la entrada del Next. |
| El teclado no suena con el MT-32 pero sí con FluidSynth | El teclado toca en el canal 1, que el MT-32 no usa: `.golem set channels alt` (apartado 5). |
| «Golem: GOLEM.DRV missing or incompat.» | El driver no está instalado (`.install`, apartado 4). |
| No suena nada | `output_device = i2s` en `mt32-pi.cfg`; fuente de la Pi (si el LED rojo parpadea, es insuficiente); cable y masa común. |
| Suena, pero los instrumentos no son los del MT-32 o los SysEx no hacen nada | Las ROM no han cargado y la Pi está en FluidSynth: revisa que sean completas y solo una de control por variante. Prueba `.golem engine mt32`, o toca con `.mt32 play`. |
| Una canción suena con instrumentos raros después de otra, pero bien si se toca sola | La anterior cargó SysEx (instrumentos propios) y siguen en el sinte. `play` ya reinicia el sinte; si la tocas desde otro programa, pon `.golem reset` antes. |
| Un juego de PC tarda mucho en empezar a sonar | Muchas músicas de Sierra y otros empiezan con varios segundos de SysEx y silencio. La carga del fichero en sí dura un par de segundos. |
| En otros programas, la pausa deja notas enganchadas | El MT-32 de 1987 no reconoce el mensaje «All Sound Off» (CC120). `.gsq` y la biblioteca GSEQ pausan bajando el volumen y soltando las notas. |
| Tras apagar el Next a mitad de una nota, esa nota vuelve a sonar al cargar la siguiente música | La Pi tiene su propia alimentación y conserva ese sonido; ningún mensaje MIDI lo borra. Para los programas antes de apagar, o reinicia la Pi. |
| `engine` o `soundfont` acaban en «Golem: transport error or timeout» | La Pi no ha respondido: comprueba que lleva el firmware Golem (no el mt32-pi original) y la línea TX de la Pi en el cable. |

## 8. Licencias

- **golem-next** (driver, comandos, biblioteca y herramientas): licencia MIT.
  Puedes usarlo en programas comerciales o cerrados si conservas el aviso de
  autoría.
- **Firmware Golem:** GPL-3.0, como mt32-pi, del que deriva. Su código fuente
  está en github.com/malandante/mt32-pi.
- No se incluyen ROM de Roland ni música comercial.

Copyright (c) 2026 Javier Aguilar Saavedra (malandante), Golem Retro.
