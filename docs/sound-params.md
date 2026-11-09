# Protocolo de parámetros de sonido del Golem

Estado: **especificación, 2026-11-03; decisiones cerradas el 2026-11-04**,
salvo la velocidad de los registros OPL3 y las marcas de espera, que esperan a
las capturas DRO (6.2.4). Implementado en `golemd` 0.3.0 (golem-linux, 2026-11-04):
`GET_INFO`, `PARAM_WRITE`/`PARAM_READ` en las áreas 01, 02 y 10 (secciones 00 y
03), `BLOB` con bancos WOPL/WOPLX y el banco de trabajo. El firmware todavía no
tiene nada. Amplía el protocolo de control Golem v1
([mt32-pi-control.md](mt32-pi-control.md)) sin cambiar nada de lo que ya
existe. Lo que queda abierto está marcado **[pendiente]**.

Objetivo: un solo conjunto de mensajes para leer y escribir los parámetros de
sonido de cada motor del Golem. Lo usan los juegos del Next, un editor (en el
Next o en el navegador con Web MIDI) y los programas de música del PC, por
cualquier transporte: el UART del Next con `GOLEM.DRV`, MIDI por USB o MIDI
por red. Es el mismo protocolo en el firmware (fork de mt32-pi sobre Circle)
y en `golemd` (Alpine Linux).

Los músicos tienen control completo: el mapa nativo de Roland en el MT-32, los
registros y todos los parámetros de instrumento en el OPL3, y lo que FluidSynth
ofrece en General MIDI.

## 1. Lo que ya existe

Todo lo de este apartado está en el firmware golem-1.2.0 (publicado) y, salvo
lo indicado, igual en golem-1.3 y en `golemd`.

### 1.1 Transporte en el Next: `GOLEM.DRV`, ABI 0.3

Funciones de `M_DRVAPI` ([driver-api.md](driver-api.md)): `QUERY` (0),
`ACQUIRE` (1), `WRITE` (2), `STATUS` (3), `DRAIN_STATUS` (4), `RELEASE` (5),
`READ` (6) y `SET_OUTPUT` (7). `WRITE` y `READ` mueven como máximo 16 bytes
por llamada y no esperan. El UART va a 31250 baudios, 8N1, unos 3125 bytes/s
en cada sentido. El driver no interpreta los bytes: el protocolo es cosa del
cliente. Su parte residente ocupa 510 de los 512 bytes posibles (medido el
2026-10-15), y el comando `.GOLEM`, 8020 de 8192.

`STATUS` (función 3 del driver) es el estado del UART. No hay que confundirlo
con `GET_STATUS`, el comando Golem (1.3).

### 1.2 SysEx originales de mt32-pi

`F0 7D 00 F7` (reiniciar), `F0 7D 01 xx F7` (ROM), `F0 7D 02 xx F7`
(SoundFont), `F0 7D 03 xx F7` (motor), `F0 7D 04 xx F7` (estéreo invertido del
MT-32). Sin respuesta. Se conservan.

### 1.3 Protocolo de control Golem v1

```text
petición:  F0 7D 47 4C 4D 01 tt cc [datos] F7
respuesta: F0 7D 47 4C 4D 01 tt rr cc [datos] F7
```

`7D` es el ID de fabricante, `47 4C 4D` la firma `GLM`, `01` la versión,
`tt` la transacción (0–127), `cc` el comando y `rr` el tipo de respuesta.
Sin checksum.

| Comando | Valor | Datos | Desde |
| --- | ---: | --- | --- |
| `GET_STATUS` | `00` | — | 1.0 |
| `SET_SYNTH` | `01` | `00` MT-32, `01` FluidSynth, `02` OPL3 | 1.0 (OPL3: 1.2) |
| `SET_ROM` | `02` | `00` old, `01` new, `02` CM-32L | 1.0 |
| `SET_SOUNDFONT` | `03` | índice de 14 bits, bajo y alto | 1.0 |
| `SET_USB_OUT` | `04` | `00` off, `01` on, `02` bridge, `7F` consulta | 1.1 |
| `SET_PARAM` | `05` | parámetro, valor (`7F` consulta) | 1.1 |
| `SAVE` | `06` | `00` escribir `golem.cfg`, `01` borrarlo | 1.1 |

Respuestas: `ACCEPTED` (`40`), `READY` (`41`), `ERROR` (`42`), `STATUS`
(`43`). Errores: `01` mal formada, `02` versión, `03` comando desconocido,
`04` parámetro, `05` no disponible, `06` fallo de operación.

Parámetros de `SET_PARAM`: `00` volume (0–100), `01` fx, `02` channels, `03`
thru, `04` keys, `05` bank del OPL3 (0–127), `06` loud.

`STATUS` lleva siete bytes: capacidades (14 bits, usados los bits 0–6),
motores disponibles (bit 0 MT-32, 1 FluidSynth, 2 OPL3), motor activo, ROM e
índice de SoundFont (14 bits).

### 1.4 Encaminamiento

- **UART del Next.** Los SysEx Golem y mt32-pi se consumen. Los demás SysEx
  (Roland, GM, GS, XG) van al motor activo y, con `usb_out` en `on` o
  `bridge`, también a los dispositivos USB-MIDI. En `bridge` el motor no los
  recibe.
- **USB-MIDI y Pisound.** Tienen su propio analizador y van siempre al motor.
  Con `thru` vuelven a salir por USB, y con `keys` también van al Next (sin
  bytes de tiempo real). Las peticiones Golem que llegan por aquí **se
  ignoran**. Todas las fuentes USB y el Pisound comparten un búfer: el
  firmware no sabe de cuál vino cada mensaje.
- **Red (RTP-MIDI y UDP, sólo en el firmware).** Entra por **el mismo
  analizador que el UART del Next** (`OnAppleMIDIDataReceived` y
  `OnUDPMIDIDataReceived` llaman a `ParseMIDIBytes`). Una petición Golem por
  red se atiende como si viniera del Next, y **la respuesta sale por el UART,
  hacia el Next**, no por la red.
- Las respuestas Golem salen siempre por el UART del Next.

### 1.5 Lo que la 1.2 ya publicada obliga a conservar

- La trama de `STATUS` mide exactamente 17 bytes: el cliente 1.2 rechaza otra
  longitud (`golem_client.s`). Su contenido no puede crecer.
- El cliente usa las 128 transacciones (`inc a; and $7f`). No hay ningún valor
  de `tt` libre para usos especiales.
- El cliente guarda tramas de respuesta de hasta 20 bytes
  (`GOLEM_RX_FRAME_MAX`). Sólo recibe respuestas a lo que pide, así que no le
  llegan las tramas largas nuevas.
- El firmware responde con como mucho 8 bytes de datos (`GolemMaxPayload`).
  Los volcados necesitan subir ese límite.
- El analizador MIDI del firmware y el de `golemd` guardan SysEx de hasta
  1000 bytes.

### 1.6 MT-32 en Munt: qué se puede leer (comprobado en el código)

Munt 2.7.0 (`munt_2_7_0`, el submódulo del firmware y la versión de `golemd`):

- **DT1 (`12`) funciona**: Munt escribe en su memoria con el mapa de Roland.
- **RQ1 (`11`) no responde.** Munt comprueba el checksum y llama a
  `Synth::readSysex()`, cuyo cuerpo es `// NYI`. La rama principal de Munt
  está igual hoy. Una petición RQ1 no recibe nada.
- Munt sí ofrece `Synth::readMemory(addr, len, data)`. Lee las zonas que
  tienen memoria real: patch y rhythm temporales, timbre temporal, patch
  memory, timbre memory y system. **No lee** el display (`20 00 00`) ni el
  reset (`7F 00 00`): ahí devuelve `FF` y el tipo de zona.
- **Rareza de la timbre memory:** al escribir en `08 00 00`, Munt suma 128 al
  número de timbre (los 128 primeros son los presets A y B de la ROM). Al leer
  no lo suma: `readMemory` en `08 00 00` devuelve el timbre A1 de la ROM, no
  el de memoria. Para leer el timbre de memoria *n* hay que leer en la
  dirección de Munt `0A 00 00` + *n* × `02 00`.

Por tanto, el Golem tiene que contestar RQ1 por su cuenta, con `readMemory`,
y componer el DT1 de respuesta (sección 5).

### 1.7 Estado del motor OPL3

- libADLMIDI v1.6.2.1, la misma en el firmware (submódulo `99c5e03`) y en
  `golemd`. Emulador Nuked (por defecto) o DOSBox, 1 chip por defecto (1–4
  en `golemd`), *soft panning* activado.
- Bancos: los 79 incluidos (0–78; por defecto el 72, DMXOPL3) y después los
  `.wopl` de `SD:opl3/`, hasta 128 en total. Cambiar de banco crea un
  reproductor nuevo, igual que un GM System On (`F0 7E 7F 09 01 F7`), para que
  no quede nada del anterior.
- Los demás SysEx van a `adl_rt_systemExclusive` (resets GS/XG, volumen
  maestro).
- **No hay** edición de instrumentos ni acceso a registros desde el MIDI.
- libADLMIDI ya trae lo necesario para las dos cosas:
  - `adl_getInstrument`/`adl_setInstrument` sobre los bancos dinámicos.
  - `adl_rt_rawOPL3(chip, reg, valor)` escribe registros `000`–`1FF`
    directamente en el chip.
  - `adl_reserveChipChannels` aparta canales del chip para que el MIDI no los
    use (hay 23 por chip, contando los 5 de ritmo).
  - libADLMIDI siempre pone los chips en modo OPL3. Un flujo de OPL2 tiene que
    poner a 1 los bits `30` de `C0`–`C8`. La función que lo hace no es
    pública, así que lo hará el Golem.
- Las escrituras se aplican al render siguiente. Cada bloque de render es de
  256 muestras (`chunk_size` en el firmware, `period_frames` en `golemd`),
  unos 5,3 ms a 48 kHz.

### 1.8 FluidSynth

FluidSynth 2.3.1 en el firmware y el del sistema en `golemd`. Atiende los CC
estándar, RPN de *pitch bend* y afinación, los NRPN de SoundFont 2.01
(MSB 120, desplazamiento de generadores; comprobado en la versión del
firmware), resets GM/GS/XG y la afinación MIDI (MTS). Los efectos del Golem
están en el perfil `.cfg` de cada SoundFont y en `[fluidsynth]` (reverb:
room, damping, width, level; chorus: voices, level, speed, depth).

## 2. Principios

1. **Se amplía v1, no se sustituye.** Misma trama y misma versión (`01`).
   Los comandos nuevos van del `07` en adelante. Un firmware antiguo contesta
   `ERROR 03` y el cliente sabe que no los tiene. No cambia ningún comando,
   respuesta ni longitud existente.
2. **Mapa nativo cuando lo hay.** El MT-32 usa las direcciones de Roland, por
   RQ1/DT1 directos y también dentro del protocolo Golem. Los bancos OPL3 usan
   WOPL, el formato que ya lee el motor.
3. **Una sola vía de escritura por ajuste.** Lo que ya tiene comando
   (`SET_SYNTH`, `SET_ROM`, `SET_SOUNDFONT`, `SET_USB_OUT`, `SET_PARAM`) se
   escribe con él. El mapa nuevo lo lee, y para `SET_PARAM` es la misma
   dirección (8.1).
4. **Sin espera en el Next.** Todo encaja en `WRITE` y `READ` de 16 bytes y en
   una biblioteca con bomba por cuadro, como GSEQ.
5. **Igual por cualquier puerto.** La respuesta vuelve por el puerto de la
   petición.

## 3. Formato del mensaje

### 3.1 Cabecera

```text
F0 <ID> 47 4C 4D 01 tt cc flags [cuerpo] cs F7
```

- `<ID>`: `7D`, como hasta ahora (decidido el 2026-11-03). La firma `GLM`
  lo distingue de otros usos de `7D`. Si algún día hubiera un ID propio de 3
  bytes (`00 xx yy`), todo lo que va detrás sería idéntico, y el Golem
  aceptaría los dos y contestaría con el de la petición.
- `47 4C 4D 01 tt cc`: como en v1.
- `flags` (nuevo, primer byte de datos de los comandos `07` en adelante):
  - bit 0 = 1: confirmar con `READY` si sale bien. A 0, el éxito no se
    contesta. Sólo vale para las escrituras (`PARAM_WRITE`, `OPL3_REG`,
    `BLOB DATA`): los comandos que devuelven datos o que tardan contestan
    siempre. Los errores se contestan siempre, uno por mensaje como máximo.
  - bits 1–6: reservados, a 0. Un bit desconocido a 1 da `ERROR 04`.
- `cs`: checksum de los comandos nuevos (3.3). Los comandos `00`–`06` siguen
  sin checksum.

### 3.2 Direcciones

Un **área** (1 byte) y una **dirección** de 21 bits en tres bytes de 7 bits,
el más significativo primero (`a2 a1 a0`), como en Roland. Los datos son
bytes de 7 bits. Las longitudes son de 14 bits (bajo, alto, como el índice de
SoundFont de v1).

| Área | Contenido | Sección |
| ---: | --- | --- |
| `00` | MT-32: memoria con el mapa de Roland | 5 |
| `01` | OPL3: instrumentos | 6.3 |
| `02` | OPL3: directorio de bancos y cabecera | 6.4 |
| `03` | OPL3: registros (copia de lo escrito) | 6.2 |
| `04` | MT-32: timbres de la ROM, sólo lectura | 5.4 |
| `10` | Ajustes del Golem: general, MT-32, FluidSynth, OPL3 | 8 y 9 |

### 3.3 Checksum

El de Roland: la suma de todos los bytes desde `flags` hasta el último dato,
más `cs`, es múltiplo de 128.

```text
cs = (128 − (suma mod 128)) mod 128
```

Si no cuadra: `ERROR 07` y no se aplica nada.

### 3.4 Codificación de valores

- 0–127: un byte.
- Más de 7 bits: dos bytes, bajo y alto (14 bits).
- Con signo: desplazado, 64 = 0 (un byte) o 8192 = 0 (dos bytes).
- Bytes de 8 bits (ficheros, registros en bloque): 7 en 8. Cada grupo de hasta
  7 bytes va precedido de un byte con sus bits altos (bit *i* = bit 7 del
  byte *i* del grupo), seguido de los 7 bytes con el bit 7 a 0. El último
  grupo puede ser más corto.

### 3.5 Respuestas

Respuestas nuevas, además de las cuatro de v1:

| Respuesta | Valor | Datos |
| --- | ---: | --- |
| `INFO` | `44` | página de información (4.1) |
| `DATA` | `45` | área, dirección, datos, `cs` |
| `CHANGED` | `46` | reservado para `NOTIFY` (versión posterior) |

- Los comandos rápidos (`PARAM_WRITE`, `PARAM_READ`, `OPL3_REG`,
  `BLOB DATA`/`READ`, `GET_INFO`) **no mandan `ACCEPTED`**: contestan
  directamente `READY`, `DATA`, `INFO` o `ERROR`. Los lentos (`BLOB END`,
  `SLOT`, `OPL3_SESSION`) siguen la regla de v1: `ACCEPTED` y después `READY`
  o `ERROR`. La regla va por número de comando y está fija (decidido el
  2026-11-03). Los comandos `00`–`06` no cambian.
- `ERROR` de los comandos nuevos lleva código y detalle: la posición del
  primer byte rechazado dentro de los datos, en 14 bits (`3FFF`: sin detalle).
  Los comandos `00`–`06` siguen con un byte.

Errores nuevos:

| Código | Significado |
| ---: | --- |
| `07` | checksum incorrecto |
| `08` | dirección desconocida, de sólo lectura o no legible |
| `09` | mensaje o longitud demasiado grandes |
| `0A` | ocupado: el recurso lo tiene otro puerto o sesión |
| `0B` | secuencia: trozo de `BLOB` fuera de orden o tamaño que no cuadra |

### 3.6 Tamaños

- Datos por `PARAM_WRITE`, por `DATA` y por trozo de `BLOB` (descodificado):
  hasta 256 bytes, como los DT1 de Roland. Una trama completa cabe de sobra en
  los 1000 bytes del analizador.
- El máximo real de cada Golem lo da `GET_INFO`. Un cliente con poca memoria
  pide trozos más pequeños.

### 3.7 Puerto de respuesta (cambio respecto a 1.2)

El Golem acepta peticiones Golem y RQ1 por **cualquier** puerto (UART, cada
dispositivo USB, cada sesión de red) y contesta **por el mismo**. Para el Next
no cambia nada: sigue contestándose por el UART. Las respuestas a otros
puertos no se mandan al Next aunque `keys` esté activado. Las peticiones Golem
recibidas por USB siguen sin reenviarse al Next.

Para eso el firmware tiene que separar las fuentes: hoy la red comparte
analizador con el UART y los dispositivos USB comparten búfer (1.4).

## 4. Comandos nuevos

| Comando | Valor | Cuerpo (tras `flags`) | Respuesta |
| --- | ---: | --- | --- |
| `GET_INFO` | `07` | página | `INFO` |
| `PARAM_WRITE` | `08` | área, `a2 a1 a0`, datos | `READY` (si se pide) |
| `PARAM_READ` | `09` | área, `a2 a1 a0`, longitud (14 bits) | `DATA` |
| `OPL3_REG` | `0A` | escrituras empaquetadas | `READY` (si se pide) |
| `OPL3_SESSION` | `0B` | abrir o cerrar acceso a registros | `ACCEPTED`, `READY` |
| `BLOB` | `0C` | subir o bajar un fichero (banco, perfil, volcado) | según la operación |
| `SLOT` | `0D` | guardar, recuperar, listar o borrar en la SD de la Pi | `ACCEPTED`, `READY` |
| `NOTIFY` | `0E` | reservado: suscribirse a cambios (versión posterior) | — |

Todos llevan `flags` al principio y `cs` al final. En `GET_STATUS` se añade el
**bit 7 de capacidades**: «tiene `GET_INFO`». Es el único cambio de `STATUS` y
no cambia su longitud.

### 4.1 `GET_INFO`

Cuerpo: número de página. Respuesta `INFO`: página, datos, `cs`.

Página `00`:

| Byte | Contenido |
| ---: | --- |
| 0–1 | revisión del protocolo: mayor `1`, menor `1` (esta especificación) |
| 2 | plataforma: `00` firmware Circle, `01` `golemd` Linux |
| 3–5 | versión del firmware o de `golemd`: mayor, menor, parche |
| 6 | motores presentes (bits como `STATUS`) |
| 7–8 | funciones (14 bits): 0 áreas de parámetros, 1 RQ1 del MT-32, 2 instrumentos OPL3, 3 registros OPL3, 4 subir WOPL, 5 bajar WOPL, 6 slots, 7 `NOTIFY`, 8 reservado (ID propio), 9 timbres de ROM |
| 9–10 | SysEx de entrada máximo, bytes (14 bits) |
| 11–12 | datos máximos por mensaje (14 bits); 256 |
| 13 | trozos de `BLOB` sin confirmar que acepta (ventana) |
| 14 | chips OPL3 |
| 15 | canales de 4 operadores |
| 16 | slots por motor |
| 17–18 | número de SoundFonts (14 bits) |
| 19 | número de bancos OPL3 |

Página `01`: nombre y versión en ASCII (`golem-1.4.0`, `golemd 0.3.0`).
Una página que no existe da `ERROR 04`.

### 4.2 `PARAM_WRITE`

Escribe de 1 a 256 bytes seguidos de un área, como un DT1. El Golem comprueba
el mensaje entero antes de aplicarlo:

- Área o dirección desconocida, o de sólo lectura: `ERROR 08`. No se aplica
  nada.
- Un valor fuera de rango: `ERROR 04`, con su posición. No se aplica nada.
- Excepción, el área `00` (MT-32): los valores se recortan como hace Munt (y
  el MT-32 real) con su tabla de máximos, sin error.

### 4.3 `PARAM_READ` y `DATA`

Pide de 1 a 256 bytes. `DATA` devuelve área, dirección, los bytes y `cs`.
Si algo del tramo no se puede leer: `ERROR 08`. Para leer más, más peticiones:
la lectura la lleva el cliente, así el Golem nunca manda más de lo que el
cliente puede recibir.

### 4.4 `BLOB`

Ficheros enteros en bytes de 8 bits, empaquetados 7 en 8. Cuerpo: operación y
sus datos.

| Op. | Nombre | Datos | Respuesta |
| ---: | --- | --- | --- |
| `00` | `BEGIN` | tipo, destino, tamaño (21 bits) | `READY` con `00` |
| `01` | `DATA` | secuencia (14 bits), datos empaquetados (hasta 256 descodificados) | `READY` con `01` y la secuencia (si se pide) |
| `02` | `END` | — | `ACCEPTED`, después `READY` con `02`, o `ERROR`, al aplicarlo |
| `03` | `ABORT` | — | `READY` con `03` |
| `04` | `READ` | tipo, origen, posición (21 bits), longitud (14 bits, hasta 256) | `DATA`: `04`, posición, bytes empaquetados, `cs`. Con longitud 0: `04`, tamaño total (21 bits), `cs` |

Tipos: `01` banco OPL3 WOPL o WOPLX, `02` reservado (un instrumento OPL3 suelto),
`03` perfil de efectos FluidSynth (texto `.cfg`), `04` volcado MT-32
(`.SYX`, mensajes DT1 seguidos). Destino u origen: `00` el de trabajo (lo que
suena), `01`–`7F` el slot *n* (4.6).

Una lectura que empieza en la posición 0 (o pide el tamaño) toma una copia
nueva del fichero; las siguientes leen de esa copia, para que una lectura larga
vea un fichero coherente aunque algo cambie a la vez.

Hay un `BLOB` abierto por puerto. Mientras dura, el puerto puede seguir
mandando MIDI. Los trozos van en orden. El cliente puede adelantar tantos sin
confirmar como diga la ventana de `GET_INFO`.

### 4.5 `OPL3_REG` y `OPL3_SESSION`

En 6.2.

### 4.6 `SLOT`

Contenido de sonido guardado en la SD de la Pi, en la carpeta de datos del
Golem (`golem/slots/<motor>/NNN.<ext>`). Es aparte de `SAVE`, que guarda
ajustes en `golem.cfg`.

Cuerpo: operación (`00` guardar, `01` recuperar, `02` nombre, `03` borrar),
motor (`00` MT-32, `01` FluidSynth, `02` OPL3), slot (1–127) y, al guardar,
nombre (hasta 16 caracteres ASCII).

| Motor | Qué se guarda | Fichero |
| --- | --- | --- |
| MT-32 | patch memory, timbre memory, rhythm setup y system | `.syx` (DT1) |
| OPL3 | el banco de trabajo | `.wopl` |
| FluidSynth | el perfil de efectos del SoundFont activo | `.cfg` |

Recuperar un slot de MT-32 manda sus DT1 a Munt. Uno de OPL3 lo convierte en
el banco de trabajo. `02` sin nombre devuelve el nombre en el `READY`, o
`ERROR 05` si el slot está vacío.

Un juego no debe depender de los slots: los de cada Golem son distintos. Lleva
su banco en su propia SD y lo sube (sección 7).

## 5. MT-32

### 5.1 RQ1 y DT1 nativos

El Golem contesta las peticiones RQ1 de Roland igual que un MT-32, para que
funcionen los editores y librerías de MT-32 que ya existen:

```text
petición:  F0 41 10 16 11 a2 a1 a0 s2 s1 s0 cs F7
respuesta: F0 41 10 16 12 a2 a1 a0 datos… cs F7
```

- Sólo con el MT-32 como motor activo. Con otro motor, el RQ1 va a ese motor
  como hoy (y no se contesta).
- Dispositivo `10` (unidad 17). Las lecturas con direcciones relativas a canal
  (dispositivo igual al canal) no se contestan (decidido el 2026-11-04): las
  escrituras así siguen funcionando, porque las hace Munt.
- Sólo devuelve la parte válida del tramo pedido, recortada al final de su
  zona, como dice el manual de Roland («only the valid data»).
- En mensajes DT1 de hasta 256 bytes de datos, separados más de 20 ms, como
  pide la implementación MIDI del MT-32 para los DT1 largos.
- Zonas no legibles o direcciones fuera del mapa: no contesta.
- Lo implementa el Golem con `readMemory`, sin cambiar Munt. Se puede proponer
  después a Munt.
- Con `usb_out` en `bridge`, el RQ1 sale por USB y el Golem no contesta: el
  sinte externo es el que suena. Con `on` contestan los dos (el externo, por
  su puerto USB).

### 5.2 El mismo mapa en el protocolo Golem

El área `00` es la memoria del MT-32 con las direcciones de Roland tal cual.
`PARAM_WRITE` en el área `00` equivale a un DT1 y `PARAM_READ` a un RQ1, pero
con confirmación, error y transacción. No hay otro mapa. Funciona aunque el
MT-32 no sea el motor activo, para preparar sus sonidos antes de cambiar. Sin
ROMs: `ERROR 05`.

### 5.3 Qué se puede leer y escribir

Direcciones de Munt 2.7.0 (las del MT-32; la CM-32L y la LAPC-I usan las
mismas con más timbres de ritmo):

| Desde | Hasta | Contenido | Lectura | Escritura |
| --- | --- | --- | --- | --- |
| `03 00 00` | `03 01 0F` | patch temporal: partes 1–8 y ritmo, 9 × 16 bytes | sí | sí |
| `03 01 10` | `03 03 63` | rhythm setup temporal, 85 teclas × 4 bytes | sí | sí |
| `04 00 00` | `04 0F 2F` | timbre temporal, partes 1–8, 8 × 246 bytes (paso `01 76`) | sí | sí |
| `05 00 00` | `05 07 7F` | patch memory 1–128, 8 bytes cada uno | sí | sí |
| `08 00 00` | `08 7F 7F` | timbre memory 1–64, 256 bytes cada uno (paso `02 00`) | sí (1.6) | sí |
| `10 00 00` | `10 00 16` | system: afinación, reverb, reservas de parciales, canales MIDI, volumen maestro (23 bytes) | sí | sí |
| `20 00 00` | — | display: texto en la pantalla | no | sí |
| `7F 00 00` | — | reset de todos los parámetros | no | sí |

Notas:

- Leer la timbre memory necesita la corrección de 1.6.
- Las escrituras del Golem al MT-32 (volumen, canales tras un reset) no cambian
  con esto.
- Los ajustes del Golem del motor MT-32 (ROM, ganancias, *resampler*) no están
  en el mapa de Roland, sino en el área `10` (sección 8).

### 5.4 Timbres de la ROM

Decidido el 2026-11-04. Munt guarda los presets A1–B64 y los timbres de
ritmo de la ROM, y `readMemory` los lee. El área `04`, de sólo lectura, deja
que un editor copie un preset a la memoria y lo modifique: timbre *n*
(0–191: A1–B64 y después los de ritmo) en *n* × `02 00`, 256 bytes cada uno,
con el mismo formato que la timbre memory. Salen de la ROM del usuario, en su
propio aparato. En el MT-32 real no se pueden leer: es una extensión del
Golem, fuera del mapa de Roland.

### 5.5 Estado (2026-11-08)

Hecho en el firmware (PR #15 del fork) y en `golemd` 0.4.1+, con el mismo
código (`golem/mt32mem`, que sólo sabe el mapa, las rarezas de Munt y los
formatos de los mensajes):

- **Áreas `00` y `04`**, con la tabla de 5.3 y la corrección de 1.6. Una
  escritura es un DT1 a la unidad 17, en orden con la música, y pasa por el
  mismo camino que el DT1 de una canción (los canales y el volumen que guarda
  el Golem siguen valiendo). Una lectura aplica antes lo que haya en la cola de
  Munt, para ver las escrituras anteriores: las notas que estuvieran en cola
  suenan hasta un periodo de audio antes. Un tramo puede cruzar zonas
  contiguas (patch y rhythm temporales); un byte fuera del mapa da `ERROR 08`
  con su posición y no se escribe nada.
- **RQ1 nativo** desde el Next (UART), con el MT-32 como motor activo y
  `usb_out` distinto de `bridge`: DT1 de hasta 256 bytes, sólo la parte
  válida, cortada al final de su zona, uno tras otro con el tiempo que tarda
  en salir más 20 ms. En el firmware salen desde la tarea principal; en
  `golemd`, desde un hilo propio, así que mientras tanto se sigue leyendo el
  MIDI del Next. **Pendiente:** contestar RQ1 que llegue por USB o por red
  (3.7); hoy no se contesta.
- **Área `10`, sección `01`** (8.2). El *resampler* `0` (ninguno) sólo se
  acepta si la salida es de 32 kHz; si no, `ERROR 04`. Como los del OPL3,
  estos ajustes no los guarda `SAVE` todavía.
- **`BLOB` tipo `04`**: el volcado son 71 DT1 a la unidad 17, en este orden:
  la timbre memory (64 mensajes de 246 bytes, en `08 nn 00`), la patch
  memory (4 de 256), el rhythm setup (256 y 84) y el system (23): 17 841
  bytes. Al subir uno, se comprueba entero (checksum, unidad, modelo, que todo
  caiga en el mapa) antes de mandar nada; un fallo da `ERROR 04` (formato) u
  `08` (fuera del mapa).
- `GET_INFO` marca las funciones 1 (RQ1) y 9 (timbres de ROM) cuando hay ROMs.
- Probado en el PC contra un modelo de la memoria de Munt hecho con sus reglas
  (zonas que recortan la lectura, DT1 que sigue en la zona siguiente, la
  timbre memory movida 128 timbres al escribir). Sin ROMs en CI, de `golemd`
  real sólo se comprueba que contesta `ERROR 05`. **Falta probarlo con ROMs.**
- En el Next, `.gparam get 00 …`/`set 00 …` leen y escriben el área `00`, y
  `.gparam save mt32 FICHERO` / `put mt32 FICHERO` bajan y suben el volcado.

## 6. OPL3

### 6.1 Dos niveles

- **Instrumento:** el juego o el músico sube un banco (o algunos
  instrumentos) y toca con notas MIDI. Es lo que hace falta casi siempre, y lo
  más barato por el cable: una nota son 3 bytes.
- **Registros:** para juegos que programan el chip a mano (código portado de
  PC, efectos hechos registro a registro). Cuesta mucho más ancho de banda
  (6.2.4).

Las áreas de instrumentos y bancos (01 y 02) funcionan siempre que el motor
OPL3 exista, para preparar los sonidos antes de cambiar a él. Los registros
(sesión y `OPL3_REG`) necesitan el OPL3 como motor activo (`SET_SYNTH 02`); si
no, `ERROR 05`.
Dos motores a la vez (por ejemplo MT-32 y OPL3) queda para más adelante,
sin caso de uso claro todavía (decidido el 2026-11-03). El caso que sí se ve es
el **muestreador PCM en el Golem** (ideas, «PCM en el Golem»): suena junto al
motor activo, así que necesita la misma mezcla de dos fuentes. Cuando se
diseñe, la regla de «el OPL3 tiene que ser el motor activo» puede cambiar sin
tocar las direcciones de esta especificación.

### 6.2 Registros

#### 6.2.1 Sesión

`OPL3_SESSION`, cuerpo:

```text
op (00 abrir, 01 cerrar), chip (0–3), modo, compatibilidad, máscara de canales (4 bytes)
```

- Modo `00` compartido: el MIDI sigue sonando en los canales no reservados.
  Sólo se aceptan registros de operador y de canal de los canales reservados.
- Modo `01` exclusivo: todo el chip para la sesión. Se aceptan también los
  registros globales (`01`, `08`, `BD`, `104`, `105`). El MIDI al OPL3 se
  ignora mientras dure.
- Compatibilidad `00` OPL3, `01` OPL2: el Golem pone a 1 los bits `30` de las
  escrituras en `C0`–`C8` (sin ellos el canal no suena en modo OPL3), ignora
  los registros del banco alto (`100`–`1FF`) e ignora `105`.
- Máscara: 23 bits (canales 0–17 y los 5 de ritmo, 18–22), 4 bytes de 7 bits,
  el más bajo primero. `READY` devuelve la máscara concedida.
- Hay una sesión por chip. La abre un puerto y sólo ese puerto escribe. Otro
  puerto recibe `ERROR 0A`.
- Al cerrar (o si se cierra el puerto, o con GM System On o cambio de banco),
  el Golem apaga las notas de los canales reservados y los devuelve al MIDI.
- Temporizadores (`02`–`04`): se ignoran. **No hay lectura del registro de
  estado**, así que la detección de AdLib por temporizador no funciona: el
  juego detecta el Golem con `GET_INFO`.

#### 6.2.2 `OPL3_REG`

Cuerpo: `n` escrituras de 3 bytes, en orden.

```text
b0 = registro, bits 0–6
b1 = bits 0–1: registro, bits 7–8 (bit 8 = banco alto)
     bit 2: valor, bit 7
     bits 3–4: chip (0–3)
     bit 5: 0 (reservado: marca de espera, [pendiente])
     bit 6: 0
b2 = valor, bits 0–6
```

Las escrituras de un mensaje se aplican juntas antes del render siguiente, en
el orden en que llegan. La resolución de tiempo es un bloque de render
(~5,3 ms) más el tiempo de transmisión. **[pendiente]** marcas de espera
dentro del mensaje (bit 5) para repartir escrituras en el tiempo con precisión
de muestra, a cambio de latencia. Se decide con las capturas DRO de 6.2.4, que
guardan el momento de cada escritura.

Una escritura rechazada (canal no reservado, registro global en modo
compartido) se descarta. Las demás se aplican, y si se pidió confirmación, el
`ERROR 08` lleva la posición de la primera rechazada.

#### 6.2.3 Área `03`: copia de los registros

Dirección `cc rh rl`: chip, bits 7–8 del registro y bits 0–6. Cada registro
ocupa **dos** bytes de datos (bits 0–6 y bit 7), y la longitud cuenta bytes.
`PARAM_READ` devuelve lo último escrito por la sesión, no el estado del chip:
libADLMIDI no lee registros, y los que escribe el MIDI no se copian.
`PARAM_WRITE` en el área `03` equivale a `OPL3_REG`, con las mismas reglas de
sesión.

#### 6.2.4 Ancho de banda

A 31250 baudios caben 3125 bytes/s: 62,5 por cuadro a 50 Hz y 52 a 60 Hz.
Una trama `OPL3_REG` mide 11 + 3·*n* bytes con el ID `7D` (13 + 3·*n* con un
ID de 3 bytes).

| Envío | Escrituras por segundo, cable entero |
| --- | ---: |
| una escritura por mensaje (14 bytes) | 223 |
| un mensaje por cuadro a 50 Hz (17 escrituras, 62 bytes) | 850 |
| un mensaje por cuadro a 60 Hz (13 escrituras) | 780 |
| mensajes de 64 escrituras (203 bytes) | 985 |

Eso es sin música por el mismo cable. Una trama de 62 bytes tarda 19,8 ms en
pasar. Cuántas escrituras por segundo hace un juego real hay que medirlo
(**[pendiente]**, con capturas DRO de DOSBox de los juegos que interesen): un
driver de música de AdLib puede tener picos mucho más altos que estas cifras,
sobre todo al arrancar acordes.

Lo que tiene que hacer la biblioteca del Next (sección 10) para que quepa:

- Guardar una copia de los 512 registros de cada chip y no mandar los que no
  cambian.
- Juntar las escrituras de un cuadro en un solo mensaje.
- **No juntar** dos escrituras de `B0`–`B8` (o `1B0`–`1B8`) que cambian el bit
  de *key-on* dentro del mismo cuadro: un apagado y encendido seguidos es un
  ataque nuevo, y quedarse con el último valor lo perdería. Igual con los bits
  de ritmo de `BD`.

Decidido el 2026-11-03: de momento 31250 baudios con estas técnicas, y
medir con capturas DRO antes de elegir otra cosa. Las opciones para después:
subir el UART por encima de 31250 (los dos UART tienen divisores para mucho más; falta probar el
cable y los niveles a esa velocidad; la salida por joystick seguiría en 31250
para los sintes MIDI) o usar SPI con el Golem Link v0.2.

### 6.3 Área `01`: instrumentos

Dirección `bb pp oo`:

- `bb`: banco. `00`–`3F` son los bancos melódicos y `40`–`7F` los de
  percusión, en el orden del banco de trabajo (área `02`): el del fichero
  WOPL, o, en un banco incluido, por número (MSB y LSB), así que el `00` es el
  General MIDI.
- La dirección es lineal: leer o escribir más de 128 bytes sigue en el
  programa siguiente.
- `pp`: programa (melódico) o nota (percusión), 0–127.
- `oo`: posición dentro del instrumento, `00`–`7F`.

Cada instrumento ocupa 128 bytes, uno por parámetro, con los campos de WOPL
versión 3 descodificados:

| Pos. | Parámetro | Valores | Campo WOPL |
| ---: | --- | --- | --- |
| `00` | modo de voz | 0 2 operadores, 1 4 operadores, 2 pseudo-4 (dos voces de 2) | `inst_flags` bits 0–1 |
| `01` | vacío (no suena) | 0/1 | `inst_flags` bit 2 |
| `02` | percusión del modo ritmo | 0 no, 1 bombo, 2 caja, 3 tom, 4 platillo, 5 charles | `inst_flags` bits 3–5 |
| `03` | nota fija | 0/1 | `inst_flags` bit 6 |
| `04` | nota de percusión / nota fija | 0–127 | `percussion_key_number` |
| `05` | desplazamiento de nota, voz 1 | semitonos, 64 = 0 | `note_offset1` |
| `06` | desplazamiento de nota, voz 2 | semitonos, 64 = 0 | `note_offset2` |
| `07` | desplazamiento de velocidad | 64 = 0 | `midi_velocity_offset` |
| `08` | desafinación de la voz 2 (pseudo-4) | 64 = 0, unidades DMX | `second_voice_detune` |
| `09` | *feedback*, par 1 | 0–7 | `fb_conn1_C0` bits 1–3 |
| `0A` | conexión, par 1 | 0 FM, 1 AM | `fb_conn1_C0` bit 0 |
| `0B` | *feedback*, par 2 | 0–7 | `fb_conn2_C0` bits 1–3 |
| `0C` | conexión, par 2 | 0 FM, 1 AM | `fb_conn2_C0` bit 0 |
| `0D`–`0E` | retardo con la tecla pulsada | ms, 14 bits | `delay_on_ms` |
| `0F`–`10` | retardo tras soltarla | ms, 14 bits | `delay_off_ms` |
| `11` | afinación fina, voz 1 (WOPLX, fase 2) | céntimos, 64 = 0 | extensión |
| `12` | afinación fina, voz 2 (WOPLX, fase 2) | céntimos, 64 = 0 | extensión |
| `13` | curva de velocidad (WOPLX, fase 2) | 0 la del banco, 1–127 curvas del Golem | extensión |
| `14`–`1F` | reservado | 0 | — |
| `20`–`2F` | operador 1: portadora de la voz 1 | bloque de operador | `operators[0]` |
| `30`–`3F` | operador 2: moduladora de la voz 1 | | `operators[1]` |
| `40`–`4F` | operador 3: portadora de la voz 2 | | `operators[2]` |
| `50`–`5F` | operador 4: moduladora de la voz 2 | | `operators[3]` |
| `60`–`7F` | nombre | 32 caracteres ASCII, 0 al final | `inst_name` |

El orden de los operadores es el de WOPL (portadora y después moduladora),
comprobado en la conversión de libADLMIDI (`adlmidi_cvt.hpp`).

Bloque de operador:

| Pos. | Parámetro | Valores | Registro |
| ---: | --- | --- | --- |
| +0 | trémolo (AM) | 0/1 | `20` bit 7 |
| +1 | vibrato | 0/1 | `20` bit 6 |
| +2 | tipo de envolvente (sostenida) | 0/1 | `20` bit 5 |
| +3 | KSR | 0/1 | `20` bit 4 |
| +4 | multiplicador | 0–15 | `20` bits 0–3 |
| +5 | KSL | 0–3, los bits del registro tal cual: 0 = 0, 1 = 3, 2 = 1,5, 3 = 6 dB/octava | `40` bits 6–7 |
| +6 | nivel total | 0–63 (0 = el más fuerte) | `40` bits 0–5 |
| +7 | ataque | 0–15 | `60` bits 4–7 |
| +8 | caída | 0–15 | `60` bits 0–3 |
| +9 | nivel de sostenido | 0–15 | `80` bits 4–7 |
| +A | relajación | 0–15 | `80` bits 0–3 |
| +B | forma de onda | 0–7 | `E0` bits 0–2 |
| +C–+F | reservado | 0 | — |

Un cambio se aplica a las notas siguientes. Las que ya suenan siguen con el
instrumento anterior, como en libADLMIDI.

Lo que se pidió y WOPL no tiene:

- **Panorama:** no es del instrumento. El OPL3 sólo tiene izquierda, derecha o
  las dos por canal (`C0` bits 4–5, en el nivel de registros). En el nivel MIDI
  es el CC 10 por canal, que libADLMIDI reparte con *soft panning*.
- **Afinación fina:** WOPL sólo tiene el desplazamiento en semitonos y la
  desafinación de la segunda voz. Va en la extensión WOPLX (sección 7,
  posiciones `11`–`12`).
- **Sensibilidad a la velocidad:** WOPL sólo tiene el desplazamiento por
  instrumento y el modelo de volumen del banco (6.4). La curva por instrumento
  va en WOPLX (posición `13`).

libADLMIDI no tiene ninguna de las dos por instrumento: el Golem las aplica
antes del motor (corrige la velocidad de cada nota y suma la afinación al
*pitch bend* del canal). Es la fase 2: el formato y las direcciones quedan
definidos ya, y un Golem que todavía no las aplica las guarda y las devuelve
igual.

### 6.4 Área `02`: directorio de bancos y cabecera

| Dirección | Contenido |
| --- | --- |
| `00 bb 00` | presente (sólo lectura), 0/1 |
| `00 bb 01` | MSB del banco (*bank select*) |
| `00 bb 02` | LSB del banco |
| `00 bb 10`–`2F` | nombre, 32 caracteres |
| `01 00 00` | trémolo profundo 0/1 (cabecera WOPL; `BD` bit 7) |
| `01 00 01` | vibrato profundo 0/1 (`BD` bit 6) |
| `01 00 02` | modelo de volumen 0–9, el valor de WOPL (0 genérico … 9 HMI) |
| `01 00 03` | bancos melódicos (sólo lectura) |
| `01 00 04` | bancos de percusión (sólo lectura) |

Crear o quitar bancos se hace subiendo un WOPL (`BLOB`), no por el mapa.

### 6.5 Banco de trabajo

Decidido el 2026-11-03:

- El banco subido o editado es el **banco de trabajo**. Sobrevive a GM System
  On, al barrido de parada y a los resets: el reproductor nuevo se crea con él
  y no con el banco configurado.
- Sólo lo sustituye una orden explícita: `SET_PARAM bank` (`.golem bank N`),
  un `BLOB` o recuperar un slot. Quien quiera otro banco lo pide. Pedir el
  mismo número de banco también lo sustituye: así se vuelve al banco tal cual.
- Se pierde al apagar, salvo que se guarde en un slot.
- El Golem lo tiene en memoria como un WOPLX, con las ediciones aplicadas.
  Así se mantiene la defensa de la 1.2 (un reproductor nuevo al parar, con GM
  System On y al cambiar de banco, porque `adl_setBank` sobre un reproductor
  en marcha deja ajustes del banco anterior y a veces quedaba una nota
  sonando), sin perder lo subido. Cargar el banco desde memoria lleva
  milisegundos.
- `.opl3 play` admite un banco opcional, para ahorrar una orden:
  `.opl3 play cancion.mid 58` equivale a `.golem bank 58` seguido de la
  reproducción. Sin número, suena el banco de trabajo. `.GOLEM` está casi
  lleno (8020 de 8192 bytes): habrá que hacerle sitio.
- Lo que quedaba sonando en el OPL3 al parar (revisado el 2026-11-04) eran
  tres cosas distintas, todas resueltas en la 1.2.0:
  1. **Una nota pulsada, a volumen normal.** Con SPACE pulsado, la limpieza
     del Next se paraba la primera vez que esperaba al driver y sólo llegaba a
     los canales 0–6. Lo encontró la captura del firmware de diagnóstico;
     corregido en golem-next `1201f8d`.
  2. **Colas largas de algunos instrumentos** (banco 58, programa 107, unos
     10 s). All Sound Off (CC 120) de libADLMIDI sólo calla las notas que
     siguen pulsadas (`noteUpdateAll` con `Upd_OffMute`); una voz ya soltada
     termina su relajación entera. Reproducido en el PC: los programas 98 y
     107 del banco 58 siguen sonando flojo 3 s después de All Sound Off, GM
     System On, `adl_panic` o `adl_rt_resetState`; `adl_reset` o un
     reproductor nuevo los callan. Arreglo: un reproductor nuevo al parar y
     con GM System On (firmware `0d1fa5b`). Según la norma MIDI, All Sound Off
     tendría que callarlas: se puede comunicar al autor de libADLMIDI.
  3. **Un pitido o zumbido débil a la altura de la última nota, que no se iba
     solo** (ni con `.golem reset`; sólo al cambiar de banco). Con todas las
     envolventes cerradas, una voz da −1 en vez de 0 en la mitad negativa de
     su seno (así es el YMF262, y Nuked lo imita); con la voz a un lado, ese
     bit llegaba al DAC. Lo encontró la captura del MIDI recibido. Arreglo:
     un búfer que no pasa de 1 bit sale a cero (`IdleLevel` en
     `include/synth/opl3midi.h` del firmware y en `opl3synth.cpp` de
     `golemd`). Probado en hardware con la 1.2.0: nada sonando tras parar en
     muchos momentos.

### 6.6 Ajustes del motor

En el área `10`, sección `03` (8.3). Los que crean un reproductor nuevo
(emulador, chips, canales de 4 operadores) cortan las notas, con el fundido de
5 ms de la 1.3.

## 7. Formato de banco

**Formato del Golem: WOPLX** (decidido el 2026-11-03), un superconjunto de
WOPL versión 3, el de libADLMIDI y del editor de bancos OPL3 de Wohlstand.

### 7.1 WOPLX

Un WOPLX es un **WOPL versión 3 normal** (misma firma `WOPL3-BANK`, versión 3,
mismos bancos e instrumentos) seguido de un bloque de extensión:

| Campo | Tamaño | Contenido |
| --- | --- | --- |
| firma | 4 | `GLMX` |
| versión | 2 | 1 (big-endian, como los campos de WOPL) |
| longitud | 4 | bytes de registros que siguen |
| registros | variable | tipo (1), longitud (2), datos |
| CRC-32 | 4 | IEEE, de la firma al último registro |

Registro de tipo `01`, extras de un instrumento: tipo de banco (0 melódico,
1 percusión), número de banco en el fichero (2), programa o nota (1) y
subcampos (identificador, longitud, valor):

| Subcampo | Valor |
| ---: | --- |
| `01` | afinación fina de la voz 1, céntimos con signo (1 byte) |
| `02` | afinación fina de la voz 2, ídem |
| `03` | curva de velocidad: 0 la del banco, 1–127 curvas del Golem |

Sólo se escriben los instrumentos que usan algún extra. Un lector que no
conoce un tipo de registro o un subcampo lo salta. Si el CRC no cuadra, el
Golem ignora el bloque entero y usa el banco como WOPL.

Compatibilidad, comprobada en `src/wopl/wopl_file.c` de libADLMIDI v1.6.2.1:
el lector lee la cabecera, los bancos y los instrumentos y no mira lo que va
detrás. Por eso el firmware actual, `golemd` y cualquier programa con
libADLMIDI cargan un WOPLX como WOPL. El lector rechaza versiones mayores que
la 3: el bloque no puede ir en la cabecera.

- El fichero se sigue llamando `.wopl`, para que cualquier programa lo abra.
  WOPLX es el nombre del formato.
- Si el OPL3 Bank Editor guarda un WOPLX, lo más probable es que pierda el
  bloque (falta comprobarlo). La herramienta del Golem avisa cuando un banco
  ha perdido sus extras.
- Las curvas de velocidad del Golem (qué hace cada número) se definen en la
  fase 2.

### 7.2 Dónde está cada banco

- **En la SD del Next:** el juego lleva su `.wopl` y lo sube al empezar con
  `BLOB`. Tamaño de un banco melódico más uno de percusión: 16983 bytes, 19410
  empaquetados, unos **6,5 s** por el cable con la música parada. Si un juego
  sólo usa unos pocos instrumentos, puede subirlos por el área `01`: 143 bytes
  por instrumento (unos 46 ms).
- **En la SD de la Pi:** `SD:opl3/` (como ahora) y los slots.
- **Importación** (decidido el 2026-11-03): el Golem sólo entiende
  WOPL/WOPLX. Los demás formatos se convierten fuera, con dos herramientas que
  hacen lo mismo, para que el ecosistema del Next no dependa del PC:
  - `golembank.py` en el PC, como `gseq.py` (`tools/host/golembank.py`,
    hecho el 2026-11-04): `new` crea un banco vacío, `add` mete un `.SBI` como
    programa o como percusión (`--drum`, `--key`) y `list` dice qué hay.
    Conserva el bloque WOPLX tal cual. Comprobado: libADLMIDI carga sus
    bancos y toca los instrumentos.
  - Un comando punto propio en el Next (no cabe en `.GOLEM`, que va por 8020
    de 8192 bytes) que mete `.SBI` en un `.wopl` de la SD sin necesitar el
    Golem conectado.
  - Primero `.SBI`, un instrumento de 2 operadores con sus 11 registros y su
    nombre. Después sus variantes de 4 operadores y otros formatos.
- **Contenido:** el Golem no distribuye bancos sacados de juegos comerciales.
  Los incluidos son los de libADLMIDI. El usuario aporta los suyos.

## 8. Área `10`: ajustes del Golem

Dirección `ss 00 pp`: sección y parámetro. Secciones: `00` general, `01`
MT-32, `02` FluidSynth (en 9) y `03` OPL3.

### 8.1 Sección `00`: general (incluye `SET_PARAM`)

| `pp` | Ajuste | Valores | Escritura |
| ---: | --- | --- | --- |
| `00` | volumen | 0–100 | sí; igual que `SET_PARAM 00` |
| `01` | fx | 0/1 | sí; `SET_PARAM 01` |
| `02` | canales del MT-32 | 0 estándar, 1 alternativos | sí; `SET_PARAM 02` |
| `03` | thru | 0/1 | sí; `SET_PARAM 03` |
| `04` | keys | 0/1 | sí; `SET_PARAM 04` |
| `05` | banco OPL3 | 0–127 | sí; `SET_PARAM 05` |
| `06` | loud | 0/1 | sí; `SET_PARAM 06` |
| `07`–`1F` | reservado para futuros `SET_PARAM`, con el mismo número | | |
| `20` | motor activo | como `SET_SYNTH` | no: `SET_SYNTH` |
| `21` | ROM del MT-32 | como `SET_ROM` | no: `SET_ROM` |
| `22`–`23` | SoundFont | 14 bits | no: `SET_SOUNDFONT` |
| `24` | `usb_out` | 0–2 | no: `SET_USB_OUT` |
| `25` | dispositivos USB-MIDI | 0–127 | no |
| `26` | motores disponibles | bits de `STATUS` | no |
| `27` | entrada de sonido del Next activa | 0/1 | no |
| `30` | ganancia de loudness | ×10, 10–160 | sí |
| `31` | estéreo invertido de toda la salida | 0/1 | sí |
| `32`–`33` | ganancia de la entrada del Next | ×100, 0–1600 | sí |
| `34` | slot de arranque del MT-32 | 0 ninguno, 1–127 | sí; lo guarda `SAVE` |
| `35` | slot de arranque del OPL3 | 0 ninguno, 1–127 | sí; lo guarda `SAVE` |
| `40` | salida de audio | 0 auriculares, 1 HDMI, 2 I²S | no: configuración, al arrancar |

Slots de arranque (decidido el 2026-11-04): al encender, el Golem recupera
esos slots. El del MT-32 dura hasta el primer reset del MT-32 (`play` y los
juegos lo mandan antes de cada canción): sirve sobre todo para tocar con un
teclado. El del OPL3 pasa a ser el banco de trabajo inicial (6.5). FluidSynth
no lo necesita: ya carga el perfil de cada SoundFont. Sin slot de arranque,
todo funciona como ahora.

`SET_PARAM` *n* y escribir `00 00 n` son el mismo ajuste: misma regla, mismo
valor guardado por `SAVE`. Los ajustes `20`–`27` se leen aquí y se cambian
sólo con su comando de siempre, que es el que hace la carga y confirma.

### 8.2 Sección `01`: motor MT-32

| `pp` | Ajuste | Valores |
| ---: | --- | --- |
| `00`–`01` | ganancia | ×100, 14 bits |
| `02`–`03` | ganancia de la reverb | ×100, 14 bits |
| `04` | calidad del *resampler* | 0 ninguno … 4 el mejor |
| `05` | estéreo invertido | 0/1 |
| `06` | reverb | 0 la que diga la música (por defecto), 1 forzada apagada, 2 forzada encendida |

La reverb forzada (`06`, decidido el 2026-11-04) usa la anulación de Munt
(`setReverbOverridden` y `setReverbEnabled`): ignora los SysEx de reverb de la
música mientras no sea 0. No toca `fx`, que sigue siendo sólo de FluidSynth
como se publicó en la 1.2.

### 8.3 Sección `03`: motor OPL3

| `pp` | Ajuste | Valores |
| ---: | --- | --- |
| `00` | emulador | 0 Nuked, 1 DOSBox |
| `01` | chips | 1–4 |
| `02` | canales de 4 operadores | 0 automático, 1–6 por chip |
| `03`–`04` | ganancia | ×100, 14 bits |
| `05` | *soft panning* | 0/1 |
| `06` | modo ritmo (percusión del chip) | 0 según el banco, 1 sí, 2 no |
| `07` | asignación de canales | 0 automática, y los modos de libADLMIDI |

## 9. General MIDI / FluidSynth

Lo mínimo, porque casi todo ya va por MIDI estándar:

- **Por canal, con MIDI estándar** (ya funciona, no hace falta nada nuevo):
  volumen (CC 7), panorama (CC 10), expresión (CC 11), envío a reverb (CC 91)
  y a chorus (CC 93), pedales (CC 64–67), RPN 0–2 (*bend*, afinación) y los
  NRPN de SoundFont 2.01 para desplazar generadores (filtro, envolventes),
  más resets GM/GS/XG y afinación MTS.
- **SoundFont:** `SET_SOUNDFONT`, como ahora.
- **Efectos globales:** área `10`, sección `02`. Escribirlos cambia lo que
  suena. `SLOT` (motor FluidSynth) o `BLOB` (tipo `03`) los guarda como el
  perfil `.cfg` del SoundFont.

| `pp` | Ajuste | Codificación (14 bits salvo indicación) | Rango |
| ---: | --- | --- | --- |
| `00` | reverb | 0/1 | — |
| `01`–`02` | room size | ×1000 | 0–1000 |
| `03`–`04` | damping | ×1000 | 0–1000 |
| `05`–`06` | width | ×100 | 0–10000 |
| `07`–`08` | level | ×1000 | 0–1000 |
| `09` | chorus | 0/1 | — |
| `0A` | chorus voices | un byte | 0–99 |
| `0B`–`0C` | chorus level | ×1000 | 0–10000 |
| `0D`–`0E` | chorus speed | ×1000 (Hz) | 100–5000 |
| `0F`–`10` | chorus depth | ×10 (ms) | 0–2560 |
| `11` | tipo de chorus | 0 seno, 1 triángulo | — |
| `12`–`13` | polifonía | — | 1–16383 |
| `14`–`15` | ganancia | ×1000 | 0–10000 |

`fx` (8.1, `SET_PARAM 01`) sigue siendo el interruptor general que ya existe:
apagado, no suenan ni la reverb ni el chorus, digan lo que digan `00` y `09`,
que son los del perfil.

### 9.1 Estado (2026-11-08)

Hecho en el firmware (PR #17 del fork) y en `golemd`, con el mismo código
(`golem/fxparams`):

- La sección `02` entera, con los rangos de la tabla. Los valores se guardan
  en las unidades del protocolo, así que lo que se escribe se lee igual. Un
  valor de 14 bits se puede escribir por mitades; si al juntarlas se sale de
  rango, `ERROR 04` en el byte que lo completa y no cambia nada.
- `BLOB` tipo `03`: el perfil en el formato de los `.cfg` de SoundFont de
  mt32-pi (`clave = valor`, `#` y `;` para comentarios, secciones
  ignoradas), con dos claves nuevas que el Golem también lee en los perfiles
  de la SD: `chorus_type` (`sine`, `triangle`) y `polyphony`. Al bajarlo da
  lo que suena; al subirlo, empieza por lo que suena, así que las claves que
  no lleve se quedan como estaban. Una clave desconocida o un valor fuera de
  rango dan `ERROR 04` y no se aplica nada.
- Lo escrito dura hasta que se cambia de SoundFont, que vuelve a su perfil.
  No lo guarda `SAVE`; para eso queda `SLOT`, o copiar el `.cfg` bajado a la
  SD de la Pi junto al SoundFont.
- **Cambio:** con `fx` encendido, la reverb y el chorus siguen ahora a `00`
  y `09` (antes `fx on` los encendía los dos).
- Probado en el PC (`tests/test_fxparams.cpp`) y en `golemd` con FluidSynth
  de verdad (`tests/test_params.py` con un SoundFont).
- En el Next: `.gparam get 10 8000 16`, `.gparam set 10 8000 …`,
  `.gparam save fx FICHERO` y `.gparam put fx FICHERO`.

## 10. API del lado del Next

### 10.1 En una biblioteca, no en `GOLEM.DRV`

El residente del driver ocupa 510 de 512 bytes, y la arquitectura ya decidió
que no interpreta el protocolo ([golem-architecture.md](golem-architecture.md)).
La API es una biblioteca de cliente (MIT, como GSEQ y la de entrada MIDI)
encima de `WRITE` y `READ`, en `.s` para ensamblador y `.bas` para ZX Basic.
El driver no cambia. Tampoco cabe en `.GOLEM`. Decidido el 2026-11-04.

### 10.2 Llamadas

| Rutina | Qué hace |
| --- | --- |
| `gp_init` | áreas de trabajo y tamaños (10.3) |
| `gp_info` | pide `GET_INFO`; deja la página 0 en un bloque |
| `gp_write` | área, dirección, datos, longitud, confirmar sí o no |
| `gp_read` | área, dirección, destino, longitud |
| `gp_blob_put` / `gp_blob_get` | sube o baja un fichero desde bancos de 8 KiB |
| `gp_slot` | guardar, recuperar, nombre o borrar |
| `gp_opl_open` / `gp_opl_close` | sesión de registros |
| `gp_opl_write` | registro y valor en la copia; se manda con la bomba |
| `gp_update` | la bomba: una vez por cuadro, con presupuesto de `WRITE` como `GsPump`; arma tramas, lee respuestas, cuenta tiempos de espera |
| `gp_result` | estado de la última operación: en curso, hecha, error y código |

Nada espera dentro: cada operación se lanza y se termina en `gp_update`. Hay
una operación con respuesta en curso por vez, más el flujo de `OPL3_REG`, que
no espera respuesta.

### 10.3 Memoria

| Búfer | Tamaño | Para qué |
| --- | --- | --- |
| salida | 16 bytes, entre `$4000` y `$FFFF` | `WRITE` |
| trama de salida | 64 bytes (más para mensajes largos) | la trama que se está mandando |
| recepción | 16 bytes | `READ` |
| trama de respuesta | 20 + longitud máxima de lectura (276 para 256) | `DATA` e `INFO` |
| copia de registros OPL3 | 512 bytes por chip | sólo con sesión de registros |

Un juego con poca memoria lee en trozos pequeños (por ejemplo 32 bytes, con una
trama de respuesta de 52).

### 10.4 Tiempos

- A 31250 baudios llegan unos 63 bytes por cuadro a 50 Hz. Con lecturas de 16
  bytes hacen falta cuatro `READ` por cuadro para no perder una respuesta
  larga.
- Tiempo de espera: 10 cuadros para los comandos rápidos, 1500 para los
  lentos (`BLOB END`, `SLOT`), como `.golem` con los SoundFonts.
- Cada `WRITE` de 16 bytes bloquea la interrupción de cuadro hasta unos
  0,7 ms a 3,5 MHz ([driver-api.md](driver-api.md)): las mismas reglas de
  GSEQ.

### 10.5 Con GSEQ en el mismo cable

Decidido el 2026-11-04:

- Con GSEQ, una sola bomba manda en el UART: la de GSEQ. La biblioteca no
  llama a `WRITE`: entrega sus mensajes a la cola de GSEQ.
- GSEQ reparte el presupuesto de cada cuadro: primero la música, después lo
  demás en lo que sobre, sin cortar nunca un mensaje.
- La cola de GSEQ tiene que aceptar mensajes largos (hoy `gs_send` admite
  hasta 16 bytes y una trama `OPL3_REG` de un cuadro mide hasta 62).
- Sin GSEQ (un editor, un juego sin música MIDI), la biblioteca usa su propia
  bomba, `gp_update`.
- La lectura (`READ`) la hace quien tenga la bomba y pasa las respuestas Golem
  a la biblioteca, igual que la biblioteca de entrada MIDI las aparta.

### 10.6 Estado (2026-11-06)

- `src/lib/gparam.s` (MIT): `gp_init`, `gp_set_sender`, `gp_info`,
  `gp_write`, `gp_read`, `gp_blob_put`, `gp_blob_get`, `gp_update`, `gp_feed`
  y `gp_result`. `GP_MAX_DATA` (1-256) se define antes de incluirla: tres
  búferes de `GP_MAX_DATA` más un séptimo más 24 bytes. Probada en el
  simulador contra un modelo del protocolo (`tools/ci/gparam_model.py`) y
  contra golemd real (`tools/ci/test_gparam.py --golemd`), que tiene el mismo
  código que el firmware.
- Los ficheros (`BLOB`) van en bancos de 8 KB, con tamaños y posiciones de 24
  bits: DMXOPL3, el banco 72 que suena al arrancar, ocupa 116 KB como WOPL (11
  bancos melódicos y 3 de percusión); los bancos 0-71 son de unos 17 KB.
- `.GPARAM` (`src/dot/gparam.s`), para probar en el hardware y cargar bancos
  OPL3 desde la tarjeta del Next: `info`, `get`, `set`, `put` (sube un WOPL de
  hasta 512 KB: queda como banco de trabajo) y `save` (baja el banco de
  trabajo, hasta 128 KB) y `sbi` (un instrumento `.SBI` de 2 operadores
  como programa del banco melódico 0 o como nota del de percusión 0: la
  herramienta nativa de la decisión 5; da el mismo registro que
  `golembank.py add`, comprobado con el decodificador del firmware).
- `gs_send_long` en GSEQ (10.5): un mensaje de cualquier longitud, entero,
  cuando ya ha salido la música que tocaba; una vez empezado va antes que
  todo. `gp_set_sender` lo toma tal cual. Probado con la biblioteca enviando a
  través de GSEQ mientras suena una canción: la música sale byte a byte igual.
- ZX Basic: la biblioteca como banco cargable de 8 KB
  (`src/lib/gparam_bank.s`, `GPAR4000.BIN`...`GPARE000.BIN` con
  `tools/build-gparam-bank.ps1`, firma "GPAR" en +27) y `src/lib/gparam.bas`
  (`GpInit`, `GpInfo`, `GpRequest`, `GpWrite`, `GpRead`, `GpFileBlock`,
  `GpBlobPut`, `GpBlobGet`, `GpUpdate`, `GpResult`). Escribe y lee con
  `GOLEM.DRV` por su cuenta: no es para usarla mientras suena GSEQ. Probada
  compilada con ZX Basic 1.18.7 en el simulador (`tools/ci/test_gparam_bas.py`).
- Pendiente: `gp_slot` y la sesión de registros OPL3 (`gp_opl_*`, espera a la
  captura DRO).

## 11. Transportes

Son siempre los mismos mensajes. Sólo cambia el puerto de la respuesta (3.7).
Estado de hoy:

| Transporte | Firmware | `golemd` |
| --- | --- | --- |
| UART del Next (`GOLEM.DRV`) | peticiones y respuestas | igual |
| USB-MIDI (un interfaz en la Pi) | MIDI sí; peticiones Golem ignoradas | igual |
| Red: RTP-MIDI y UDP | MIDI sí; las peticiones se contestan por el UART (1.4) | no hay |

`golemd` tendrá red portando el código RTP-MIDI y UDP del firmware
(`src/net/applemidi.cpp`, `src/net/udpmidi.cpp`, GPL-3), con sockets de
Linux en lugar de los de Circle (decidido el 2026-11-04). Un servicio y una
configuración, sin programas aparte. Como el del firmware, atiende un
ordenador a la vez y sólo recibe: el envío de MIDI por RTP, que hace falta
para contestar a un editor por la red (3.7), se añade a los dos.

Un editor en el navegador habla con un puerto MIDI del sistema. Hasta el Golem
llega por RTP-MIDI por red, por un interfaz USB-MIDI del PC conectado a uno de
la Pi, o, más adelante, con la Pi como dispositivo USB (sólo en Linux).

Lo que manda otro puerto se mezcla con lo del Next, y gana la última
escritura. `NOTIFY` (un puerto se suscribe y recibe `CHANGED` cuando otro
cambia algo, para que el editor siga al juego) queda para una versión
posterior (decidido el 2026-11-04). Hasta entonces, el editor vuelve a leer
los valores cuando le hace falta. El comando `0E` y la respuesta `46` quedan
reservados. Por el UART nunca se mandará sin suscripción.

## 12. Versionado y compatibilidad

- Trama y versión `01` intactas. Revisión del protocolo 1.1 en `GET_INFO`.
- Detección: bit 7 de las capacidades de `STATUS` y después `GET_INFO`. Sin
  ese bit, el firmware es 1.3 o anterior y no tiene nada de esto.
- Los clientes 1.2 no cambian: no mandan comandos nuevos, `STATUS` sigue con
  17 bytes, y no reciben tramas nuevas porque no las piden.
- Los SysEx originales de mt32-pi y los de Roland, GM, GS y XG siguen igual.
  RQ1 pasa de no contestar a contestar.

Choques con lo que existe, para decidir:

2. **Peticiones y respuestas por USB y red.** Por USB se ignoran. Por red se
   atienden pero la respuesta va al Next por el UART, mezclada con lo que el
   Next espera. Cambiarlo (3.7) no afecta a lo que el Next manda, y quita ese
   cruce.
3. **`GolemMaxPayload` = 8** en el firmware. Hay que subirlo para `DATA` e
   `INFO`, y comprobar que el búfer de transmisión serie aguanta una trama de
   unos 270 bytes.
4. **GM System On y el banco de trabajo** (6.5). Decidido: el reproductor
   nuevo se crea con el banco de trabajo.
5. **`ACCEPTED` en los comandos rápidos** (3.5). Decidido: no lo mandan.

## Fuentes

- Código: Munt 2.7.0 (`mt32emu/src/Synth.cpp`, `MemoryRegion.h`,
  `Structures.h`), libADLMIDI v1.6.2.1 (`include/adlmidi.h`,
  `src/wopl/wopl_file.c`, `src/adlmidi_cvt.hpp`), FluidSynth 2.3.1
  (`src/synth/fluid_synth.c`), el fork de mt32-pi (`src/mt32pi.cpp`,
  `src/synth/opl3synth.cpp`) y `golemd`.
- Manual del Roland MT-32, implementación MIDI (DT1 de hasta 256 bytes,
  intervalos de 20 ms, «only the valid data»).
- [MIDI Association: SysEx ID policies, 15 de octubre de 2025](https://midi.org/new-midi-association-sysex-id-policies-as-of-oct-15-2025).
