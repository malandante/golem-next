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

*Para una versión 1.x:* la salida MIDI por el puerto de joystick, para usar un
sintetizador MIDI externo sin Pi. El Next ya saca MIDI por ahí, a
3,3 V, pero falta el cable y su esquema: no conectes un cable MIDI DIN al
joystick por tu cuenta.

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

## 4. Instalar en el Next

1. Copia `GOLEM.DRV` a `c:/nextzxos/` y los comandos `GOLEM`, `MT32`, `GM` y `GSQ` a
   `c:/dot/`.
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
| `.golem play fichero.mid` | Reproduce un MIDI (SMF 0 o 1, hasta 24 pistas y 1 MB). SPACE lo cancela. |
| `.golem note <nota> <vel> <seg> [canal]` | Toca una nota de prueba: nota 0–127, velocidad 1–127, 1–60 segundos, canal 1–16 (1 si no se indica). |
| `.golem status` | Comprueba el driver y pregunta al Golem su motor, ROM y SoundFont, p. ej. «Golem: engine MT-32; ROM new; SoundFont 0». Si no contesta en 0,2 s dice «no answer». |
| `.golem engine mt32` / `fluidsynth` | Cambia el motor de la Pi: MT-32 (Munt) o General MIDI (FluidSynth). |
| `.golem soundfont <0-127>` | Elige el SoundFont de FluidSynth por número. |
| `.golem rom old` / `new` / `cm32l` | Elige las ROM: MT-32 antiguo, MT-32 nuevo o CM-32L. |

- `.mt32` y `.gm` aceptan las mismas órdenes. Antes de `play` y `note` piden a
  la Pi el motor MT-32 o FluidSynth y esperan a que esté listo; si ya lo está,
  no cambia nada. Si no contesta nada en 0,2 segundos (por ejemplo, un
  sintetizador MIDI externo), tocan igualmente. `.golem` no cambia el motor.
  Por ejemplo, `.gm play cancion.mid` para un MIDI General MIDI y
  `.mt32 play juego.mid` para uno de MT-32.
- Antes de cada canción, `play` limpia el sintetizador: suelta el pedal, corta
  las notas y deja el volumen de cada canal a 100. Al terminar o cancelar
  también corta todas las notas.
- `engine`, `soundfont` y `rom` esperan a que la Pi confirme el cambio, como
  mucho unos 30 segundos, porque un SoundFont tarda en cargarse. SPACE
  cancela la espera, pero la Pi puede aplicar el cambio igualmente.
- `soundfont` también funciona con el motor en MT-32: deja preparado ese
  SoundFont, que se oirá al pasar a `engine fluidsynth`. Da error si no existe
  un SoundFont con ese número, si no hay ninguno en la SD o si no se puede
  cargar.
- **No toques música mientras la Pi cambia de SoundFont:** durante la carga
  no atiende el puerto y podría perder datos.
- Los errores se devuelven a BASIC como informes de error normales (por
  ejemplo «Golem: GOLEM.DRV missing or incompatible»), así que se pueden tratar con
  `ON ERROR`. Los mensajes de los comandos están en inglés.

### `.gsq`

```
.gsq musica.gsq
```

Reproduce un fichero GSEQ. **P** pausa y reanuda; **SPACE** para. La pausa
calla de verdad el MT-32 y al reanudar vuelve a tocar las notas que estaban
sonando.

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

Para programadores: la biblioteca de reproducción (`src/lib/gseq.s`, con un
enlace para ZX Basic en `src/lib/gseq.bas`) está descrita en
[`docs/m6-gseq.md`](../m6-gseq.md).

## 7. Problemas frecuentes

| Síntoma | Qué mirar |
| --- | --- |
| «Golem: GOLEM.DRV missing or incompatible» | El driver no está instalado (`.install`, apartado 4). |
| No suena nada | `output_device = i2s` en `mt32-pi.cfg`; fuente de la Pi (si el LED rojo parpadea, es insuficiente); cable y masa común. |
| Suena, pero los instrumentos no son los del MT-32 o los SysEx no hacen nada | Las ROM no han cargado y la Pi está en FluidSynth: revisa que sean completas y solo una de control por variante. Prueba `.golem engine mt32`, o toca con `.mt32 play`. |
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
