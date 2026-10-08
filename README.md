# golem-next

MIDI driver, dot commands and a music library for the **ZX Spectrum Next**.
The Next sends MIDI over its UART to a **Golem** (a Raspberry Pi running the
Golem firmware, based on mt32-pi), which plays it with Munt (Roland MT-32 /
CM-32L) or FluidSynth (General MIDI SoundFonts) and sends the audio back to the
Next over I²S.

- **`GOLEM.DRV`**: NextZXOS driver that any program can call (`M_DRVAPI`).
- **`.GOLEM`**: plays MIDI files and test notes and sets the Golem engine, ROM
  set and SoundFont. **`.MT32`** and **`.GM`** do the same but first switch the
  Golem to MT-32 or General MIDI.
- **`.GSQ`** and the **GSEQ library**: precompiled music for games, with
  loops, pause and sound effects, callable from assembler or ZX Basic.

**Download:** the SD package (`golem-next-<version>.zip`, with `SHA256SUMS`) is
on the [releases page](https://github.com/malandante/golem-next/releases). The
Golem firmware and its source are at
[malandante/mt32-pi](https://github.com/malandante/mt32-pi/releases).

**User guide:** [English](docs/user/guide.md) · [español](docs/user/guia.md).
**Release notes:** [RELEASE_NOTES.md](RELEASE_NOTES.md) · **Roadmap:** [what has been done and what comes next](ROADMAP.md).

golem-next is MIT licensed ([LICENSE](LICENSE)). The Golem firmware is a
separate program under GPL-3.0. No Roland ROMs or commercial music are included.

---

*Lo que sigue es la documentación de desarrollo, en español.*

## Documentación

- [Arquitectura y análisis de NextZXOS](docs/architecture.md)
- [ABI del driver](docs/driver-api.md)
- [Formato GSEQ y biblioteca](docs/m6-gseq.md)
- [Arquitectura mínima de Golem](docs/golem-architecture.md)
- [Control bidireccional Golem para mt32-pi](docs/mt32-pi-control.md)
- [Banco CSpect → Munt](tests/integration/cspect/README.md)
- [Pruebas en hardware](tests/hardware/README.md)
- [Demo grabable de Monkey Island](tests/demo/mi1/README.md)

## Componentes

| Componente | Responsabilidad |
| --- | --- |
| `GOLEM.DRV` | Transporte genérico instalable NextZXOS; configura UART y mueve MIDI en ambos sentidos mediante llamadas acotadas. Antes `MT32.DRV` (renombrado el 7 de octubre de 2026, #76); el ID y las constantes `MT32_*` del ABI no cambian. |
| `.GOLEM` | Comando de primer plano: notas, reproducción y selección de motor/SoundFont/ROM. `.MT32` y `.GM` son el mismo comando, pero antes de `play` y `note` piden a un Golem el motor MT-32 o FluidSynth; sin respuesta en 200 ms tocan igualmente. |
| Transporte UART | MIDI binario compatible con MT32-Pi; control de capacidad, errores y configuración del UART del Pi. |
| Retorno I²S | Configuración del audio digital generado por la Pi y recibido/mezclado por el Next. |
| Utilidades y fixtures | Generadores propios de MIDI sintético, inspección de eventos y capturas reproducibles. |
| Documentación y tests | Contratos, pruebas de parser/ABI y procedimientos de validación física. |

```text
GOLEM: archivo → parser SMF → secuenciador
                              ↓ API NextZXOS
                           GOLEM.DRV
                              ↓ UART / MIDI
                Golem Pi 4 / mt32-pi
                    ├── Munt
                    └── FluidSynth
                              ↓ audio I²S
                    FPGA y salida audio Next
```

## Cable externo

**Alimentaciones independientes: aislar todas las líneas de 5V y 3V3 entre Next y Pi. Mantener masa común (GND).** UART e I²S utilizan funciones estándar de los GPIO de la Pi a nivel lógico de 3,3 V; aislar la alimentación 3V3 no significa eliminar esas señales. No conectar un cable completo de 40 vías sin comprobar orientación y aislamiento. El header Accelerator no es el conector J15.

El mapa lógico, los pines del lado Pi y las verificaciones pendientes del lado Next están en [la arquitectura](docs/architecture.md). No se presenta todavía un cable validado para montaje.

### Comprobaciones con mt32-pi

- En `roms/` de la tarjeta de mt32-pi, solo ROMs completas (por ejemplo `mt32_ctrl_1_07.rom`, `mt32_pcm.rom`, `cm32l_ctrl_1_02.rom`, `cm32l_pcm.rom`). Las partidas (`_a`/`_b`, `_h`/`_l`) pueden dejar el emulador sin arrancar; mt32-pi pasa entonces a FluidSynth sin aviso visible si no hay pantalla. Síntomas: SysEx sin efecto, instrumentos equivocados, poco volumen. Una sola ROM de control por variante (old/new), porque se usa la primera que aparezca en el directorio.
- Fuente de alimentación de la Pi suficiente: con una insuficiente no recibe MIDI.
- Para oír la Pi por el Next: `output_device = i2s` en `mt32-pi.cfg`. Desde #6, `GOLEM.DRV` activa la recepción I²S (`$A2=$D2`) al adquirirse; con un driver anterior hace falta `REG 162,210`.
- Prueba rápida de SysEx: un volumen general 0 (`F0 41 10 16 12 10 00 16 00 5A F7`) debe silenciar la nota siguiente.

## Construcción de desarrollo

Con NextBuild 10 instalado en su ruta predeterminada:

```powershell
& .\tools\build-driver.ps1
& .\tools\build-golem.ps1
& .\tools\build-test-client.ps1
& .\tools\build-cspect-bridge.ps1
& .\tools\build-golem-control-image.ps1 -OutputImage C:\temp\golem-control.img
& "$env:USERPROFILE\Documents\NextBuildv10\Python\python.exe" `
  -m unittest discover -s .\tests\host -v
```

Paquete de la SD con hashes (el mismo que publica la CI al etiquetar `v*`):

```powershell
& "$env:USERPROFILE\Documents\NextBuildv10\Python\python.exe" `
  .\tools\release\build_release.py --assembler snasm `
  --assembler-path "$env:USERPROFILE\Documents\NextBuildv10\Emu\CSpect\SNasm.exe" `
  --out C:\temp\golem-dist
```

Deja `C:\temp\golem-dist\golem-next-1.0.0\` y el `.zip`; su `SHA256SUMS` debe
coincidir con el de la release (que se compila con sjasmplus).

La validación sobre Next y Golem físicos, incluido el cableado seguro, la
captura UART/I²S y la comparación automática de CSV, se describe en
[`tests/hardware/README.md`](tests/hardware/README.md).

El driver generado queda en `build/GOLEM.DRV`; el comando se genera como
`build/GOLEM`, `build/MT32` y `build/GM` (mismo código; `CLI_ENGINE` en
`src/dot/golem_cli.s`). Los
clientes de conformidad quedan en `build/MTTEST`, `MTSTRESS`, `MTAPIERR`, `MTNOID`
y `MTCOLLIDE`, además de `MTSTATE` y `MTDURATION`; son experimentales y usan
temporalmente el ID `$2D`, todavía no asignado por NextZXOS.

## Reproducción MIDI experimental

```text
.golem engine mt32
.golem engine fluidsynth
.golem soundfont 0
.golem rom old|new|cm32l
.golem status
.golem note 60 100 2
.golem note 60 100 2 10
.golem play TEST0.MID
.golem play TEST1.MID
.golem play TESTSYX.MID
.golem play TESTSAB.MID
.golem play TESTCAN.MID
.golem play TESTTIM.MID
.mt32 play TEST1.MID     (pide antes el motor MT-32)
.gm play TEST1.MID       (pide antes FluidSynth)
```

`engine`, `soundfont` y `rom` usan el protocolo Golem v1 del fork mt32-pi:
`F0 7D 47 4C 4D 01 tt cc ... F7`. No son Program Change. Cada orden sólo se
declara correcta tras recibir `ACCEPTED` y después `READY` con la misma
transacción, comando y valor; `ERROR` y el timeout se propagan como fallo. El
CLI limita aún SoundFont a `0..127`, aunque el formato reserva 14 bits.

`note` recibe nota MIDI `0..127`, velocidad `1..127`, duración `1..60`
segundos y un canal opcional `1..16` (por defecto, 1). Emite Note Off explícito
y All Notes Off al terminar o al cancelar con SPACE. `status` informa del
driver y, si el driver tiene RX y la sesión está libre, envía `GET_STATUS` y
muestra el motor, la ROM y el SoundFont del Golem (#78); sin respuesta en
200 ms lo dice y termina. Los mensajes de los comandos están en inglés.

`play` admite SMF 0/1 con división PPQN, hasta 24 pistas y 1 MB menos un byte
(1048575 bytes; antes de #14, 32767). Fusiona
pistas por tiempo absoluto, conserva running status por pista, aplica cambios
de tempo y envía eventos de canal y SysEx F0/F7. SPACE cancela la reproducción;
la salida envía All Notes Off, vacía el driver con timeout, libera los
bancos asignados y restaura los MMU. El scheduler de primer plano observa el
contador raster de sólo lectura y reparte sus líneas en pasos exactos de 1 ms;
la matriz `TESTTIM.MID` pasa a 3,5/7/14/28 MHz y 50/60 Hz. Desde #57, `play`
sube la CPU a 28 MHz mientras carga y reproduce, y al salir (también con error o
cancelación) restaura la velocidad del llamador. Todavía debe
compararse con hardware y medirse su jitter físico para cerrar M4. SMF 2 y
división SMPTE se rechazan.

`.golem play` es deliberadamente una herramienta de validación en primer plano.
Antes de congelar la API de M6 se añadirá un secuenciador cooperativo para
juegos: cada llamada `pump/update` tendrá trabajo acotado, enviará sólo eventos
vencidos y devolverá el control sin espera activa.

No se copia código de otros proyectos. La Golem MIDI API es reutilizable por
cualquier juego y mantendrá separado el
transporte físico. No se incluyen ROMs de MT-32 ni contenido de Monkey Island.
Tampoco se incluyen soundtracks ni extractos comerciales usados como evidencia
local.

## Licencia

MIT (ver `LICENSE`), desde el 6 de octubre de 2026: cualquiera puede usar el
driver, los comandos, la futura biblioteca M6 y las especificaciones, también
en juegos cerrados o comerciales, conservando el aviso de autoría. El firmware
de Golem (fork de mt32-pi) sigue siendo GPL-3.0 porque lo hereda. Detalles y
reglas para código de terceros: `docs/licensing.md`.
