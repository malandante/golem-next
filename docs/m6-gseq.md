# M6 fase 1: formato GSEQ y biblioteca de reproducción

Propuesta del 6 de octubre de 2026 para la release 1.0 (#62, #15). Estado:
**aprobada el 6 de octubre de 2026** como base de la implementación; las
preguntas abiertas del final siguen sin decidir y los detalles pueden ajustarse
al implementar (cualquier cambio se anota aquí con fecha).

**Nombre:** GSEQ significa *Golem Sequence*, y los ficheros llevan la extensión
`.GSQ`. Decidido el 6 de octubre de 2026: el formato es el estándar de música
de Golem Retro para el Next. El formato y la biblioteca son MIT y valen para
cualquier sintetizador MIDI conectado por el cable, no sólo para el Golem Sound
Module.

Fase 1 de M6: reproducir una secuencia, bucles, pausar y reanudar, parar con
limpieza y enviar eventos directos (efectos), con trabajo acotado por llamada
y sin esperas. Las fases 2 y 3 (música interactiva al estilo
iMUSE) reutilizarán este formato: sus registros están reservados
desde ahora para que los ficheros de la fase 1 sigan valiendo.

Parte de un reproductor anterior para un juego (plazos en cuadros de 20 ms,
un solo banco) y corrige sus límites: plazos en milisegundos, más de un banco,
bucles y espacio para crecer.

## Decisiones de partida

- **Todo lo fijo se resuelve en el PC.** El conversor mezcla las pistas, pasa
  ticks a milisegundos con el mapa de tempo, valida los SysEx y escribe cada
  mensaje con su estado explícito. La Next sólo compara plazos y copia bytes.
- **La biblioteca no adquiere el driver.** El cliente hace `ACQUIRE` y
  `RELEASE` de `GOLEM.DRV`; así puede mantenerlo adquirido toda la partida y
  compartirlo con otros usos, como los efectos de sonido.
- **El reloj lo da el cliente** (apartado «Reloj»). La biblioteca no instala
  interrupciones ni lee el raster.
- **Una escritura al driver como máximo por llamada**, de 16 bytes como
  mucho. Ninguna llamada espera.
- **Licencia MIT**, sin código derivado de proyectos GPL.

## Formato GSEQ (extensión `.GSQ`)

Todos los enteros de varios bytes van en little-endian, salvo los VLQ.

### Cabecera (32 bytes)

| Offset | Tamaño | Campo |
| --- | --- | --- |
| 0 | 4 | Firma `GSEQ` |
| 4 | 1 | Versión mayor: 1. Una biblioteca rechaza mayores que no conoce |
| 5 | 1 | Versión menor: 0. Las menores sólo añaden cosas ignorables |
| 6 | 2 | Tamaño de la cabecera en bytes (32). Los datos empiezan ahí |
| 8 | 2 | Marcas: bit 0 = la secuencia tiene bucle; el resto, 0 |
| 10 | 2 | Máscara de canales usados (bit n = canal MIDI n+1). Dice al juego qué canales quedan libres para efectos |
| 12 | 3 | Longitud de los datos en bytes (hasta 16 MB) |
| 15 | 1 | Perfil de destino: 0 cualquiera, 1 MT-32 / CM-32L, 2 General MIDI. Informativo: la biblioteca no cambia por él; sirve para que el juego elija la versión de la música según el motor activo (añadido el 2026-10-06, `--target`) |
| 16 | 4 | Duración en ms (instante del registro de fin) |
| 20 | 3 | Offset del bucle dentro de los datos: el registro siguiente al de inicio de bucle (orden `$02`); 0 si no hay |
| 23 | 1 | Reservado, 0 |
| 24 | 4 | Instante del inicio del bucle en ms (el del registro `$02`); el delta del registro en el offset del bucle cuenta desde aquí |
| 28 | 2 | Suma de comprobación: suma de 16 bits de todos los bytes de datos |
| 30 | 2 | Reservado, 0 |

### Registros

Cada registro es un **delta** y un **tipo**, seguidos de su contenido:

- **Delta:** milisegundos desde el registro anterior, en VLQ (1 a 4 bytes, como
  en SMF; máximo 2^28−1 ms). El primero cuenta desde el inicio.
- **Tipo `$80`–`$EF`: mensaje de canal** con su estado explícito, seguido de 1
  byte de datos (`$Cx`, `$Dx`) o 2 (los demás). Datos de 7 bits. No hay running
  status en el fichero.
- **Tipo `$F0`: SysEx.** Longitud en VLQ y luego los bytes que van detrás de
  `$F0`, el último siempre `$F7`. Todos los intermedios son de 7 bits. Hasta
  65535 bytes. El conversor ya lo ha validado; la biblioteca vuelve a comprobar
  longitud y límites antes de enviar el primer byte.
- **Tipo `$FF`: control.** Un byte de orden, la longitud de los parámetros en
  VLQ y los parámetros. Una orden desconocida se salta entera gracias a la
  longitud, así que las versiones menores pueden añadir órdenes.
- Cualquier otro tipo (`$00`–`$7F`, `$F1`–`$FE`) es un error de formato.

### Órdenes de control

| Orden | Fase | Significado |
| --- | --- | --- |
| `$00` | 1 | **Fin.** Sin parámetros. Si la cabecera marca bucle, la reproducción sigue en el offset del bucle y el reloj de la secuencia vuelve al instante de inicio del bucle; si no, la secuencia termina |
| `$01` | 1 | **Aviso** para el juego: un byte con un número. La biblioteca lo deja en una variable que el cliente puede leer (ver API); no hace nada más |
| `$02` | 1 | **Inicio de bucle.** Sin parámetros. Marca el punto al que se vuelve; al reproducirlo no hace nada. Lo escribe el conversor cuando hay bucle (añadido el 2026-10-06 al implementar el conversor) |
| `$10`–`$1F` | 2 | Reservado: marcas y disparadores de iMUSE |
| `$20`–`$2F` | 2 | Reservado: hooks (salto, transposición, partes, volumen, programa) con sus Note Off precalculados |
| `$30`–`$3F` | 2–3 | Reservado: asignación y estado de partes |
| `$40`–`$4F` | 3 | Reservado: velocidad, fundidos, instantáneas para scan |
| `$70`–`$7F` | — | Libres para el cliente; la biblioteca los ignora |

La fase 1 trata como «saltar sin hacer nada» todo lo que no sea `$00` y `$01` (incluido `$02`).

### Reglas que garantiza el conversor

- Los registros están en orden de tiempo y los empates conservan el orden de
  la fuente (pista menor primero, como `.MT32 play`).
- Termina siempre con un registro de fin.
- En un bucle, al llegar al fin no queda ninguna nota sonando, salvo que se
  pida expresamente; si quedan, el conversor avisa.
- Los SysEx van completos y validados.
- Opcional: **pausa tras SysEx** (`--sysex-gap N` ms, desde que acaba de salir
  por el cable a 3125 bytes/s). Un MT-32 real la necesita (ScummVM usa 20–70
  ms); con mt32-pi suele sobrar. Si el siguiente evento cae antes, el
  conversor lo retrasa y avisa: es un cambio de tiempo real y debe ser visible.
- Avisa si en algún tramo la música pide más de 3125 bytes/s, porque en la Next
  llegaría tarde.

## Conversor (`tools/host/gseq.py`)

- Implementado en `tools/host/gseq.py` (2026-10-06), con pruebas en
  `tests/host/test_gseq.py` y un decodificador que comprueba el fichero como lo
  hará la biblioteca. Uso: `python tools/host/gseq.py musica.mid -o MUSICA.GSQ
  [--loop | --loop-start-ms N] [--sysex-gap N] [--report informe.json]`.
- Un SysEx partido en paquetes F0 + F7 dentro de una pista se une en uno solo
  y se envía en el instante del primer paquete, con aviso. Los escapes F7 sueltos
  no se admiten en v1.
- Entrada en fase 1: SMF 0/1 con PPQN. Los ticks se convierten a ms absolutos
  con el mapa de tempo y aritmética exacta (fracciones), se redondean al ms
  más próximo y se escriben como deltas, así que el error no se acumula.
- Bucles: por opciones (`--loop-start-ms`, o «desde el principio») o por
  eventos marker del SMF con el texto `loopStart` y `loopEnd`.
- Salida: el `.GSQ` y un informe (bytes, duración, canales, avisos de caudal y
  de notas colgadas en el bucle).
- También acepta una lista de mensajes con su tiempo (JSON), que es lo que
  producen los extractores de música de juegos. Así el empaquetador es
  común y cada extractor sólo tiene que entender su formato de origen.
- Pruebas en `tests/host/` con fixtures sintéticos, igual que las demás
  herramientas.

## Biblioteca en la Next (`src/lib/gseq.s`)

### Memoria

- **Secuencia:** en bancos de 8 KB cuyo número de banco da el cliente en una
  tabla. La biblioteca lee por una ranura MMU que elige el cliente (`$50`–`$57`)
  y la restaura antes de devolver el control en cada llamada.
- **Estado:** unos 150 bytes dentro de la propia biblioteca (el cliente la
  incluye donde quiera) y un búfer de salida de 16 bytes que da el cliente,
  visible para el driver (por encima de `$4000`). El mensaje directo se guarda
  en la biblioteca y se copia a ese búfer al enviarlo.
- **Teclas pulsadas para reanudar (opcional):** 2048 bytes (16 canales × 128
  notas, velocidad de cada una). Si el cliente no da búfer, la
  reanudación no vuelve a atacar las notas que sonaban.

### Reloj

Cada llamada recibe en `DE` la hora actual en milisegundos, un contador de 16
bits que da vueltas. La biblioteca sólo usa diferencias módulo 65536, así que
basta con llamarla al menos una vez cada 30 s; por dentro lleva el tiempo de la
secuencia en 32 bits.

Para quien no tenga reloj propio, la biblioteca trae una rutina opcional que
se llama una vez por cuadro (por ejemplo, desde la interrupción) y suma la
duración real del cuadro en ms con 8 bits de fracción. La duración se mide al
iniciar contando líneas, como `.MT32 play` desde #50 (20,26 ms a 50 Hz y
17,20 ms a 60 Hz en el Next medido). Con ese reloj la resolución es de un
cuadro. Uno más fino, interpolando con el raster, queda para más adelante si
hace falta.

### Llamadas

Convención como la del driver: registros de entrada, carry activo y `A` con
el código si hay error. No usa `IY` (la ROM la necesita en las
interrupciones) y conserva `IX`.

| Rutina | Entrada | Efecto |
| --- | --- | --- |
| `gs_init` | `HL` = búfer de salida de 16 bytes, `A` = registro MMU para leer (`$50`–`$57`), `DE` = tabla de teclas (2048 bytes) o 0 | Prepara el estado |
| `gs_open` | `HL` = tabla de bancos (número de bancos y lista) | Comprueba cabecera, versión, longitudes y suma; queda parada al principio |
| `gs_start` | `DE` = ahora | Limpia el sintetizador (como la parada) y empieza a sonar desde el principio; el tiempo de la canción arranca cuando la limpieza ha salido |
| `gs_pump` | `DE` = ahora, `B` = presupuesto | Envía lo que ya toca, en hasta `B` escrituras de 16 bytes (0 cuenta como 1; agrupa varios mensajes de canal cortos si caben). Hace otra escritura sólo si el driver aceptó todos los bytes de la anterior y queda algo por enviar, así que con poca música cuesta lo mismo con cualquier presupuesto. Nunca espera. Devuelve en `A` el estado |
| `gs_pause` | `DE` = ahora | Congela el tiempo, termina el mensaje a medias y después envía CC7=0, CC123=0 y CC120=0 en los 16 canales, a lo largo de las siguientes llamadas a `gs_pump` |
| `gs_resume` | `DE` = ahora | Desplaza el origen por lo que duró la pausa, devuelve a cada canal su último CC7 (100 si la música no lo fijó) y, si hay búfer, vuelve a atacar las notas que sonaban |
| `gs_stop` | — | Termina el mensaje a medias (un SysEx empezado se completa) y envía CC64=0, CC123=0, CC120=0 y CC7=100 por canal en las llamadas siguientes; al acabar queda en «parada» |
| `gs_send` | `HL` = mensaje, `B` = longitud (≤16) | Evento directo (efecto). Sale en la siguiente llamada, antes que la música pendiente, pero nunca dentro de un SysEx de la música. Carry si el búfer directo está ocupado |
| `gs_query` | — | `A` = estado y `HL` = bloque con estado, código de error, último aviso (orden `$01`), vueltas de bucle (16 bits) y tiempo de la secuencia en ms (32 bits) y perfil de destino. Z activo si no queda nada por enviar (ni bytes, ni SysEx a medias, ni limpieza, ni mensaje directo) |

Estados: parada, sonando, en pausa, parando (limpieza en curso), terminada y
error. Un registro mal formado en la Next lleva a «error»: se completa el
mensaje que estuviera saliendo, se hace la misma limpieza que en una parada y
se informa del código.

### Coste por llamada

Medido el 6 de octubre de 2026 en el arnés de Z80 (T-states exactos de la CPU,
sin contar la llamada al driver, que el arnés emula), con un GSEQ de estrés de
110 KB: 31 321 mensajes cortos en ráfagas de 1 a 8 por milisegundo, SysEx de
300 bytes, 640 teclas sostenidas y una pausa con reanudación. El driver se mide
aparte con su arnés: un WRITE de 16 bytes cuesta 1780 T.

| Caso | Antes | Ahora |
|---|---|---|
| `gs_pump` sin nada que enviar | ~700–1000 T | igual |
| `gs_pump` llenando 16 bytes de mensajes cortos (lo habitual con música densa) | ~16 000 T | ~13 500 T |
| `gs_pump`, peor caso observado | 30 423 T | 17 120 T |
| Leer un delta (`gs_read_delta`) | ~1300 T | ~200 T (1 byte) |
| Copiar 16 bytes de SysEx | ~12 000 T | ~8100 T |
| Paso de pausa/parada/reanudación | hasta 10 649 T | igual |

Peor caso con el driver: unos 19 000 T, el 3,4 % de un cuadro de 50 Hz a
28 MHz (560 000 T) y el 27 % a 3,5 MHz.

Las dos mejoras: los bytes se leen de un tramo ya mapeado (hasta el final del
banco o de los datos) sin comprobar el final ni calcular el banco en cada
byte, y un delta de un byte se guarda tal cual en vez de desplazar 32 bits
siete veces. Los bytes enviados son idénticos y los instantes difieren como
mucho 1 ms en todas las pruebas.

**Ritmo y presupuesto** (decidido el 6 de octubre de 2026): con una escritura
de 16 bytes por llamada, un juego que llama una vez por cuadro saca 800
bytes/s, la cuarta parte del cable (3125 bytes/s). Para la música normal
sobra (KQ5 son 109 bytes/s de media), pero las ráfagas se alargan: la de
inicio de KQ5 (18,5 KB de SysEx) tardaría 23 s en vez de 6. Por eso `gs_pump`
recibe en `B` cuántas escrituras puede hacer. Medido en el arnés con un cliente
que llama una vez cada 20 ms:

| Fichero | Presupuesto 1 | Presupuesto 4 | Cable (cliente en bucle) |
|---|---|---|---|
| 75 KB de SysEx | 93,9 s | 24,8 s | 24,1 s |
| Estrés de 110 KB, 20,5 s de música | 103,6 s | 26,2 s | 25,6 s |
| Peor llamada (sin el driver) | 16 048 T | 59 832 T | — |

Con presupuesto 4 y las cuatro escrituras del driver (4 × 1780 T), el peor
caso son unos 67 000 T, el 12 % de un cuadro a 28 MHz; sólo ocurre mientras
hay una ráfaga que enviar. Un juego con poco margen pasa 1 (y llama más veces
si lo necesita); uno con margen pasa 4 y le basta una llamada por cuadro. El
cliente `.GSQ` llama en bucle y pasa 1.

## Clientes y pruebas

1. **Cliente de prueba propio:** un comando punto (por ejemplo `.GSQ fichero`)
   que carga el `.GSQ` en bancos como `.MT32 play`, lleva el reloj de cuadro y
   llama a `gs_pump` en un bucle, con P para pausa y S para parar. Sirve de
   segundo cliente de M6 y de herramienta para el hardware.
2. **Un juego en ZX Basic:** sustituye su reproductor por la biblioteca, con un
   enlace para ZX Basic (rutinas en ensamblador incluidas desde un `.bas`).
3. **Arnés:** comparar los bytes y los instantes de salida con los que calcula
   el conversor, también con el UART limitado a 3125 bytes/s, pausas, paradas a
   media SysEx y bucles.

## Implementación (6 de octubre de 2026)

- **Biblioteca:** `src/lib/gseq.s`. Los estados son `GS_STOPPED`, `GS_PLAYING`,
  `GS_PAUSED`, `GS_ENDED` y `GS_ERROR`; los códigos de error, `GS_ERR_*`. En cada
  llamada a `gs_pump`, por orden: reintentar los bytes que el driver no aceptó,
  seguir con un SysEx a medias, el mensaje directo, la limpieza de pausa,
  parada o reanudación, y por último la música vencida (hasta 8 registros o 16
  bytes). Pausa: CC7=0, CC123=0 y CC120=0 de un canal por llamada (9 bytes).
  El MT-32 es de 1987 y no reconoce All Sound Off (CC120): en el Next con
  mt32-pi, el 2026-10-06, la pausa sólo con CC120 dejaba sonar las notas. El
  volumen a 0 las calla al momento y CC123 las suelta; CC120 se mantiene para
  sintetizadores que sí lo entienden. Reanudar devuelve el CC7 que llevaba
  cada canal (la biblioteca lo apunta al enviarlo; 100 si no se fijó), 5
  canales por llamada. Parada: 12 bytes (CC64=0, CC123=0, CC120=0 y
  CC7=100, el volumen de encendido) de un canal por llamada. La misma limpieza
  va antes de cada canción: el mt32-pi tiene alimentación propia y conserva
  las notas de una sesión cortada (el 2026-10-06, apagar el Next en mitad de
  una nota hizo que esa nota volviera a sonar al cargar KQ5 en la siguiente
  sesión) o los canales a volumen 0 tras pausa y parada. Son 192 bytes, unos
  60 ms en el cable; el reloj de la canción no corre mientras se envían, y la
  primera nota puede salir hasta ~20 ms tarde mientras se vacía la FIFO. Reanudación: recorre 64 entradas de la tabla
  de teclas por llamada y vuelve a atacar hasta 5.
- **Cliente `.GSQ fichero`:** `src/dot/gsq.s`, en `build-test-client.ps1`.
  Carga el fichero en bancos, corre a 28 MHz y lleva un reloj de ms con el
  raster (líneas de 224 o 228 T según el número de líneas por cuadro). P pausa
  y reanuda; SPACE para. 4271 bytes con la biblioteca incluida. Los puntos de carga se
  imprimen con la MMU4 del llamador, no con un banco del fichero.
- **Arnés Z80** (UART limitado a 3125 bytes/s, tiempo según la velocidad de la
  CPU): `TEST1`, `TESTSYX`, `TESTSAB`, `TESTSPL` y `TESTTIM` convertidos dan
  exactamente los bytes del decodificador más la limpieza, con un error de
  tiempo de 0–4 ms; un GSEQ de 75 KB con SysEx de hasta 9000 bytes da sus 74545
  bytes exactos, al ritmo del cable. Un bucle de 1000 ms se repite exacto hasta
  pulsar SPACE. Pausa en mitad de una nota: CC120 en los 16 canales, silencio,
  y al reanudar vuelve a atacar la nota y la apaga a su tiempo musical. Parar
  en mitad de un SysEx lo completa (`F7`) antes de la limpieza. Un fichero con
  la suma alterada se rechaza al abrirlo; un registro inválido con suma
  correcta para con limpieza y el informe de error. Sin fugas de bancos y con
  MMU 3–7, IY y la memoria de BASIC intactos.
- **Un juego completo en el Next (6 de octubre de 2026):** integrado con la
  biblioteca en un banco mapeado en el slot 2, las canciones leídas por el
  slot 1 y los efectos por `gs_send` con sus canales fuera de las limpiezas.
  En el Next con mt32-pi: la pausa calla sin notas enganchadas y reanuda con el
  volumen, los cambios de canción y los efectos funcionan. Queda validado el
  enlace de ZX Basic en hardware. El coste por llamada está medido (ver «Coste
  por llamada»).

## Enlace para ZX Basic (6 de octubre de 2026)

ZX Basic (Boriel, el compilador de NextBuild) no puede incluir `gseq.s`
directamente: su ensamblador no tiene la sintaxis de SNasm/sjasmplus. Y un
juego grande tiene muy poca memoria fija libre. Por eso la biblioteca
también se distribuye como **banco de 8 KB cargable**, y el enlace es un `.bas`
pequeño que lo mapea, lo llama y lo desmapea.

- **Banco:** `src/lib/gseq_bank.s`, con un fichero por dirección de slot
  (`gseq_4000.s` … `gseq_e000.s`) porque el código no es reubicable;
  `tools/build-gseq-bank.ps1` genera `GSEQ4000.BIN` … `GSEQE000.BIN`. Ocupa
  5179 bytes e incluye el búfer de salida, una copia de la tabla de bancos y la
  tabla de teclas, así que el programa sólo aporta el banco. Empieza por una
  tabla de saltos (entrada × 3: init, open, start, pump, pause, resume, stop,
  send, query) y lleva «GSEQ», 1, 0 en el desplazamiento 27. Sirve también
  para C o cualquier lenguaje que pueda mapear un banco y hacer `CALL`.
- **Enlace:** `src/lib/gseq.bas` (MIT). `GsSetLibrary(banco, NextReg del slot)`,
  `GsInit(NextReg de la ventana de datos, teclas, canales)` (comprueba la firma),
  `GsOpen()` con la tabla en `gsBankTable`, `GsStart`, `GsPump(ahora,
  presupuesto)`, `GsPause`, `GsResume`, `GsStop`, `GsSend(dirección, longitud)`
  y `GsQuery()` (copia el bloque de información en `gsInfo` y pone `gsBusy`).
  Devuelven el estado o 255 con el código en `gsError`; un error de registro
  durante la reproducción deja el estado `GS_ERROR` y el código en
  `gsInfo(1)`.
- **Reglas de memoria:** cada llamada mapea el banco en su slot y después
  devuelve lo que había. Cada entrada del banco pone la ROM en MMU0/1 durante
  la llamada (lo exige GOLEM.DRV) y después deja lo que hubiera, y `gs_pump`
  devuelve la ventana de datos a su contenido antes de cada WRITE. Así el
  código que llama puede estar paginado en el slot 1 y la ventana puede ser el
  slot 0 o 1. Ni la pila, ni la rutina de interrupción, ni la tabla de bancos,
  ni el mensaje de `GsSend` pueden estar en MMU0/1, en el slot del banco ni en
  la ventana de datos. `GS_MAX_BANKS` (por defecto 224) limita la tabla de
  bancos para quien vaya justo de memoria fija.
- **Canales de la limpieza** (6 de octubre de 2026):
  `gs_set_channels` (en el banco, `HL` de init; en el enlace, el tercer
  parámetro de `GsInit`, 0 = todos) dice qué canales pueden tocar las
  limpiezas de inicio, pausa, reanudación y parada. Un juego puede reservar
  canales para sus efectos, enviados con `gs_send`; si la pausa de la música les
  pusiera CC7=0, también callaría los efectos. En el arnés, con los canales 4 y
  5 fuera, la limpieza de inicio y fin y la de pausa los saltan (126 bytes en
  vez de 144) y la reanudación no les restaura el volumen.
- **Secuencias en mitad de un banco** (6 de octubre de 2026):
  `gs_open` recibe en `DE` dónde empieza la secuencia dentro del primer banco
  (0–8191), y `GsOpen(desplazamiento)` lo pasa. Varias secuencias cortas, o una
  secuencia y otros datos (por ejemplo, una paleta delante), pueden compartir
  bancos.
- **IX:** NextZXOS toma el búfer de `HL` en un comando punto y de `IX` en un
  programa. `gs_pump` pone ahora los dos antes del WRITE;
  el enlace conserva el `IX` de ZX Basic.
- **Prueba en el arnés:** `tests/zxbasic/gseq_test.bas` compilado con ZX Basic
  1.18.7 como comando punto, con el banco y el fichero precargados, el driver
  leyendo el búfer de `IX` y un reloj de ms. TEST1, TESTSYX, TESTSPL y un
  GSEQ de 75 KB en 10 bancos dan exactamente los bytes esperados; el de estrés
  con pausa a los 3 s, reanudación a los 4 s y un `GsSend` a los 6 s da
  silencio de 3,07 a 4,00 s y el efecto a los 6,03 s. Un fichero con la suma
  mal da `GS_ERR_CHECKSUM` al abrir, un registro inválido deja `GS_ERROR` con
  `GS_ERR_RECORD` en `gsInfo(1)`, y un banco sin la firma da
  `GS_ERR_LIBRARY` (7, propio del enlace) sin llamar a nada.
- **Disposición de un juego en el arnés:** el arnés modela también MMU0–2 y
  hace fallar el driver si no hay ROM en MMU0/1. El programa de prueba
  compilado en $8000, con la pila en el slot 3, la biblioteca en el slot 2
  (`GSEQ4000.BIN`), la ventana en el slot 1 y la secuencia a 1024 bytes del
  principio de su banco da los bytes exactos de TEST1 y del GSEQ de 75 KB, sin
  ninguna llamada al driver sin ROM; con la biblioteca anterior el mismo caso
  falla con `GS_ERR_DRIVER`, que es lo que la prueba debe detectar.

## Preguntas abiertas

- **Varias secuencias a la vez** (música y jingles): en fase 1, una sola. Los
  efectos van por `gs_send`. La fase 3 de iMUSE trae varios reproductores.
