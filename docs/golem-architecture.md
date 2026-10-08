# Arquitectura mínima de Golem MIDI

Estado: decisión de alcance del 2026-10-03. Esta ampliación conserva el camino
MT-32 ya validado; no lo sustituye ni reabre sus decisiones cerradas.

## Objetivo v1

Golem es un módulo externo basado en Raspberry Pi 4 que recibe MIDI 1.0 en
tiempo real desde ZX Spectrum Next y genera audio mediante exactamente dos
motores:

- Munt, con MT-32 y CM-32L;
- FluidSynth, con SoundFonts SF2/SF3.

No forman parte de v1 Nuked SC-55, OPL/FM/DX7, síntesis en Z80N, streaming PCM,
reproducción autónoma de archivos en la Pi ni un backend NextPi interno.

## Capas

```text
juego / secuenciador cooperativo
        |
        | Golem MIDI API: mensajes MIDI y selección administrativa
        v
cliente Z80N pequeño (helpers sobre escritura MIDI cruda)
        |
        | M_DRVAPI: ACQUIRE / WRITE y READ parciales / STATUS / RELEASE
        v
GOLEM.DRV, transporte UART 31250 8N1
        |
        | MIDI 1.0 + SysEx administrativo Golem v1
        v
Golem Pi 4 + mt32-pi v0.13.1
        |                         |
        v                         v
Munt (MT-32/CM-32L)       FluidSynth (SF2/SF3)
        \_________________________/
                    |
                    v
              retorno de audio I2S
```

La frontera importante ya existe: el driver residente no sabe qué sintetizador
hay al otro lado. Sólo configura y alimenta el UART en ambas direcciones. El
parser SMF, el parser de respuestas, los timeouts y la política de motor
pertenecen al cliente.

## Qué se conserva

- El ABI experimental previo conserva sus números; `READ=6` se añade al final.
- Escrituras y lecturas parciales de hasta 16 bytes, sin espera dentro del driver.
- MIDI binario estándar, SysEx transparente y ancho de banda de 31250 bit/s.
- `.MT32 play`, sus fixtures, el scheduler de 1 ms y todas las regresiones
  Munt/MT-32.
- El banco CSpect→TCP y las capturas exactas. Munt sigue siendo el primer camino
  de integración y demostración.
- La separación entre transporte y secuenciación. La futura reproducción en
  juego seguirá siendo cooperativa y con presupuesto acotado.

## Nombres y compatibilidad

Desde el 7 de octubre de 2026 (#76) el repositorio se llama **golem-next** y el
driver **`GOLEM.DRV`**. La capa que verán los juegos se denomina **Golem MIDI
API**. El ID experimental del driver y las constantes `MT32_*` del ABI no
cambian: renombrarlas antes de congelar el ABI sólo rompería a los clientes.

El comando principal es `.GOLEM`, que no toca el motor del sintetizador.
`.MT32` y `.GM` son el mismo comando con una diferencia: antes de `play` y
`note` piden a un Golem el motor MT-32 o FluidSynth (`SET_SYNTH`) y esperan a
que esté listo. Si nada responde ACCEPTED en 10 cuadros (200 ms a 50 Hz), o el
driver no tiene RX, se toma por un sintetizador externo y tocan igualmente; un
ERROR del Golem detiene el comando. Los tres salen de `src/dot/golem_cli.s` con
`CLI_ENGINE` 0, 1 y 2.

## API pública prevista

La primitiva es el envío de un prefijo MIDI crudo mediante `WRITE`. Las
funciones de alto nivel se implementarán como helpers pequeños, no como nuevas
funciones residentes del driver:

```text
golem_init / golem_release
golem_try_send(buffer, length)       -> bytes aceptados
golem_try_receive(buffer, capacity)  -> bytes recibidos
golem_update                         -> estado de transacción
golem_note_on / golem_note_off
golem_program_change
golem_control_change
golem_pitch_bend
golem_sysex
golem_select_mt32 / golem_select_fluidsynth
golem_select_soundfont(index)
```

`try_send` conserva la semántica no bloqueante. Una librería de cliente podrá
ofrecer además `pump/update`, con trabajo acotado y sin espera activa, para
integrarse en el bucle de un juego. La convención exacta de registros y memoria
se congelará en M6, junto con el ID oficial de NextZXOS.

Las selecciones de motor y banco son órdenes administrativas de Golem expresadas
como SysEx de mt32-pi. No son Program Change y no deben ocultarse dentro de los
archivos musicales.

## Conmutación confirmada

El fork `malandante/mt32-pi` incorpora un canal de control bidireccional sobre
el mismo UART MIDI. Una petición lleva firma `GLM`, versión, transacción y
comando. La Pi responde `ACCEPTED` antes de ejecutar y termina con `READY` o
`ERROR`; `GET_STATUS` termina con `STATUS`. Golem sólo acepta respuestas cuya
versión, transacción y comando coincidan, y no confunde TX vacío con éxito.

El residente expone RX sin bloquear; la espera acotada y el parser permanecen
fuera. El CLI de diagnóstico usa una ventana de 1500 frames (25–30 s), adecuada
para una carga desde SD. La futura API cooperativa avanzará la misma máquina de
estados mediante `update`, sin detener el bucle del juego.

## SoundFonts reproducibles

mt32-pi escanea los SoundFonts válidos al arrancar y los ordena
lexicográficamente. La SD de Golem debe fijar nombres con prefijos estables, por
ejemplo `000-GeneralUser.sf2`, `010-Orchestral.sf2`, y generar un manifiesto con
índice, nombre, licencia y SHA-256.

El protocolo Golem codifica el índice en dos bytes de siete bits y cubre todo el
catálogo actual de hasta 512 SoundFonts. El CLI conserva provisionalmente el
límite 0–127 hasta ampliar y probar su analizador decimal; no es un límite del
wire format.

## SD de producto

La imagen reproducible fijará una versión y hash de mt32-pi, configuración para
Pi 4, entrada UART GPIO, audio I2S, motor/banco predeterminado y manifiesto de
SoundFonts. No contendrá ROMs Roland ni SoundFonts sin licencia redistribuible.
FluidSynth deberá arrancar legalmente sin ROMs. Munt se habilitará únicamente
cuando el usuario aporte ROMs compatibles.

## Decisiones pendientes antes de congelar la API

1. Fijar Pi 4 de 2 o 4 GB después de medir SoundFonts objetivo; no afecta al
   protocolo del Next.
2. Ampliar el analizador CLI a índices 0–511 y probar los extremos del catálogo.
3. Obtener un ID de driver NextZXOS y congelar la convención de llamada en M6.
4. Seleccionar SoundFonts redistribuibles y completar revisión de licencias.
   mt32-pi es GPLv3 y su logotipo no puede usarse comercialmente sin permiso;
   Golem no debe usar ese logotipo y su distribución debe cumplir la licencia.
5. Fijar la versión del fork mt32-pi. El upstream indica que probablemente no habrá
   más releases, por lo que la imagen no debe depender de actualizaciones
   futuras implícitas.

La política de publicación será no crear una release etiquetada como pública
hasta validar ambos caminos en hardware. El repositorio y su historia existente
no se reescriben.
