# Adaptador MIDI para el puerto de joystick (#64)

Adaptador DB9 → MIDI IN y MIDI OUT para usar un sintetizador MIDI externo sin
Golem (`.golem output left|right`). No se exporta al repositorio público.

**Estado (2026-10-15): diseño del prototipo cerrado.** Esquema revisado, plano
de montaje comprobado patilla por patilla contra las hojas de datos del
74HCT125 y del H11L1, piezas pedidas a Mouser. Falta montarlo y hacer las
pruebas del final. Lo que queda abierto es sólo para la versión de venta
(apartado «Para la versión de venta»).

## Lo medido en el Next (2026-10-08 y 2026-10-14)

| Patilla del DB9 | Función con `REG 11` en modo UART | Medido |
| --- | --- | --- |
| 5 | +5 V | 5 V (polímetro) |
| 6 | CTS_n del UART | al aire no bloquea la transmisión |
| 7 | TX del UART | 3,3 V en alto; 31250 baudios exactos (analizador) |
| 8 | Masa | — |
| 9 | RX del UART | 3,1 V en reposo, con resistencia de *pull-up* interna; un puente 7→9 devuelve los bytes |

Consecuencias:

- La salida es de 3,3 V: el bucle MIDI de 5 V necesita una etapa intermedia (búfer).
- La patilla 5 da 5 V: el adaptador se alimenta del propio puerto, sin fuente.
- La entrada ya tiene su *pull-up* a unos 3,3 V dentro del Next. El optoacoplador
  sólo tiene que llevarla a 0 V y nunca le llega tensión desde el adaptador.

## Esquema propuesto

### MIDI OUT (Next → sintetizador)

```
 DB9 pin 7 (TX, 3,3 V) ──► entrada del búfer 74HCT (alimentado a 5 V)
                                  │
                          salida del búfer ──[220 Ω]── DIN pin 5
 DB9 pin 5 (+5 V) ─────────────────────────[220 Ω]── DIN pin 4
 DB9 pin 8 (masa) ───────────────────────────────── DIN pin 2 (malla)
```

- Valores de la especificación MIDI 1.0 para un emisor de 5 V: 220 Ω en la patilla 4
  y 220 Ω en la 5.
- El búfer no invierte. En reposo el UART está en alto: la salida vale 5 V, igual que
  la patilla 4, y no pasa corriente. Un 0 lógico pone la salida a 0 V y pasan unos
  5 mA por el LED del receptor.
- Candidatos a búfer: 74HCT125 o 74HCT244 (no inversores), o dos puertas de un
  74HCT14 en serie. La familia HCT acepta 3,3 V como nivel alto (umbral de 2,0 V)
  con alimentación de 5 V.
- Condensador de 100 nF entre 5 V y masa junto al chip.
- 74HCT125: la patilla OE (activa en bajo) del búfer usado, a masa; las
  entradas de los búferes que no se usan, a masa también, para que no queden
  al aire. Para la placa de producción vale un 74AHCT1G125 (una sola puerta,
  SMD).

### MIDI IN (sintetizador → Next)

```
 DIN pin 4 ──[220 Ω]──┬──► ánodo del LED del optoacoplador
                      │
                   1N4148 (en inverso, protege el LED)
                      │
 DIN pin 5 ───────────┴──► cátodo del LED
 (DIN pin 2 sin conectar: en una entrada MIDI la malla no se une a masa)

 Optoacoplador H11L1: VCC ← DB9 pin 5 (+5 V), GND ← DB9 pin 8,
                      salida (colector abierto) ──► DB9 pin 9 (RX)
```

- Con corriente por el LED (0 lógico MIDI) la salida del H11L1 baja a 0 V. Es la
  polaridad que espera el UART.
- La salida es de colector abierto: sólo tira a masa, y el nivel alto lo pone la
  resistencia interna del Next (3,1 V medidos). A la patilla 9 nunca le llegan 5 V.
- Resistencia de 470 Ω en serie entre la salida del H11L1 y la patilla 9:
  protege la entrada del FPGA si algo se conecta mal. Con el *pull-up*
  interno (de decenas de kΩ) el nivel bajo sigue por debajo de 0,1 V.
- Se descarta el 6N138 como alternativa: su salida necesita una resistencia
  de carga de pocos kΩ para ser rápida, y aquí sólo está el *pull-up* débil
  del Next.
- Condensador de 100 nF en el VCC del optoacoplador.

## Forma (decidido 2026-10-15)

- Del Next sale un **cable**, no una caja pinchada en el puerto: el conector
  del lado del Next es un **DB9 hembra acodado** (salida a 90°).
- Va en el **puerto izquierdo** (`.golem output left`) con el cable saliendo
  **hacia la izquierda**: no tapa el puerto derecho y deja libre el lado
  derecho de la mesa para el ratón (la mayoría es diestra; NextDAW y otros
  programas usan ratón). Una sola versión del cable; la salida hacia
  delante se descarta por estorbar. Quien juegue con joystick usa el puerto
  derecho; comprobar cómo se elige el puerto del joystick en NextZXOS para
  explicarlo en la guía.
- El puerto izquierdo es el marcado **JOY 1** en la placa (foto de Javier,
  2026-10-15, Next issue 4). Delante del Next sólo queda el conector acodado
  y el cable pegado hacia la izquierda; la caja del adaptador se deja en la
  mesa al lado izquierdo del Next, donde no estorba.
- Cable de unos **15 cm** del DB9 a la caja.
- La caja queda en la mesa con la placa: prototipo en placa de topos; para
  vender, placa a medida con los dos DIN hembra soldados en ella.
- Carcasa del DB9: candidata CONEC `165X13219X` (plástico, 9 pos., "2
  entries, hinged": salida por el extremo, paralela al panel, o recta;
  43 × 19 × 15,5 mm, sin tornillos). Sin stock en Mouser el 2026-10-15; el
  prototipo va sin carcasa (DB9 TE `5-747905-5` con termorretráctil).
  Alternativa para producción: cable DB9 serie ya acodado (salida izquierda)
  cortado por el otro extremo.
- Pedido Mouser del prototipo (2026-10-15, para 2 unidades): SN74HCT125N,
  H11L1M, zócalos Mill-Max de 14 y 8, SDS-50J, 1N4148, Yageo 1/4 W 220/470 Ω,
  KEMET C320C104K5R5TA, Adafruit Perma-Proto 1609, Hammond 1591BSBK,
  TE 5-747905-5, y 10 Hirose DF11-12DP-2DS(52) para el enlace.
- Prototipo: **cable fijo** a la placa (el pedido no lleva DB9 macho para la
  caja), sin carcasa en el DB9: TE `5-747905-5` con termorretráctil.

## El cable (prototipo)

Cuatro hilos de unos 15 cm del DB9 hembra a la placa; sirve cualquier cable
de 4 conductores (mejor apantallado, p. ej. de un cable serie viejo, con la
malla a la patilla 8). Las patillas 1–4 y 6 del DB9 quedan sin soldar.

| DB9 hembra (al Next) | Señal | En la placa |
| --- | --- | --- |
| 5 | +5 V | raíl + izquierdo, fila 24 (círculo 9) |
| 7 | TX del Next | b4 (círculo 1) |
| 8 | Masa | raíl − izquierdo, fila 21 (círculo 8) |
| 9 | RX del Next | j22 (círculo 7) |

Numeración del DB9: la grabada en el plástico junto a cada copa de soldar.
Mirando las copas por detrás, la fila de 5 lleva 1–5 y la de 4 lleva 6–9,
pero comprueba siempre el número grabado: es el mismo error de espejo que
con el cable del Golem.

Del cable a la caja: agujero de 5 mm en un lateral corto, con un nudo o una
brida por dentro para que un tirón no arranque las soldaduras.

## Los DIN

Los SDS-50J son de circuito impreso (acodados) y sus patillas no caen en la
rejilla de 2,54 mm. En el prototipo van **pegados por dentro** a la pared
larga de la caja (agujero de unos 16 mm para la boca, termofusible o epoxi)
y unidos a la placa con hilos:

| DIN | Patilla | En la placa |
| --- | --- | --- |
| OUT | 5 | a11 (círculo 2) |
| OUT | 4 | a14 (círculo 3) |
| OUT | 2 (malla) | raíl − izquierdo, fila 23 (círculo 4) |
| IN | 5 | a16 (círculo 5) |
| IN | 4 | a20 (círculo 6) |
| IN | 2 y la carcasa metálica | sin conectar |

Marca OUT e IN en la caja. Numeración: la del plano del SDS-50J, no la de
memoria (en un DIN de 5 las patillas no van en orden alrededor del arco:
1-4-2-5-3).

## Montaje del prototipo en la Perma-Proto (2026-10-15)

Plano: `montaje-perma-proto.png` (fuente `.svg`, generado por
`tools/hardware/joystick_midi_layout.py`). Adafruit Perma-Proto de media placa:
filas de 5 agujeros unidos (a–e y f–j) y raíles + y − a cada lado.

| Pieza | Agujeros |
| --- | --- |
| Zócalo 14 (74HCT125), muesca arriba | filas 3–9, columnas e y f; patilla 1 en e3 |
| Zócalo 8 (H11L1 en las 3 filas de arriba), muesca arriba | filas 15–18; patilla 1 en e15 |
| Puentes + | raíl + izq. ↔ raíl + der. (fila 1); a6, a12, j3, j4, j7, j15 al raíl + |
| Puentes − | raíl − izq. ↔ raíl − der. (fila 2); a3, a7, a9, j5, j8, j16 al raíl − |
| R2 220 Ω | c5 – c11 |
| R1 220 Ω | d12 – d14 |
| R3 220 Ω | c15 – c20 |
| R4 470 Ω | i17 – i22 |
| D1 1N4148 | b15 (franja) – b16 |
| C1 100 nF | raíl + der. – raíl − der., fila 6 (junto al 74HCT125) |
| C2 100 nF | h15 – h16 |
| Hilos | DB9-7 → b4; DB9-9 → j22; DB9-8 → raíl −; DB9-5 → raíl +; DIN OUT-5 → a11; DIN OUT-4 → a14; DIN OUT-2 → raíl −; DIN IN-5 → a16; DIN IN-4 → a20 |

Raíles: el plano dibuja − fuera y + dentro a cada lado. Si la placa los
marca al revés, sigue las marcas impresas (+ rojo, − azul) y no la posición
del dibujo.

Orden de montaje: zócalos; puentes de los raíles (filas 1 y 2) y de las
patillas de los chips; resistencias, D1, C1 y C2; hilos del DB9 y de los DIN.
Los chips, al final, después de las comprobaciones.

Comprobaciones antes de poner los chips: con el polímetro, 5 V entre los
raíles + y − al conectar el DB9 al Next; continuidad de cada hilo con su
fila; ningún puente entre + y −. Numeración de los DIN: la del plano del
SDS-50J (o la grabada en el conector), no la de memoria.

## Lista de piezas (por adaptador)

| Pieza | Cantidad | Nota |
| --- | --- | --- |
| DB9 hembra (al puerto del Next) | 1 | TE 5-747905-5 en el prototipo |
| DIN de 5 patillas, hembra | 2 | OUT e IN |
| 74HCT125 (o 74HCT244 / 74HCT14) | 1 | búfer de salida |
| H11L1 | 1 | optoacoplador de entrada |
| 1N4148 | 1 | protección del LED |
| Resistencias de 220 Ω | 3 | dos en OUT, una en IN |
| Resistencia de 470 Ω | 1 | en serie con la patilla 9 |
| Condensadores de 100 nF | 2 | desacoplo |
| Zócalos DIP de 14 y de 8 | 1 + 1 | el H11L1 (6 patillas) va en el de 8 |
| Placa Adafruit Perma-Proto (media) | 1 | 1609 |
| Caja Hammond 1591BSBK | 1 | 112 × 62 × 31 mm por fuera |
| Cable de 4 hilos | 15 cm | |

## Por comprobar al montar el prototipo

0. **Encaje en la caja:** que la Perma-Proto (82,5 × 53 mm) entre entre los
   tetones de los tornillos de la 1591BSBK y que quede altura para los DIN.
   Si no entra, se recorta la placa por debajo de la fila 25 (no se usa).
1. **Corriente de la patilla 5:** el consumo previsto es de unos 15 mA. Hay que ver
   si el puerto tiene fusible o límite.
2. **Flancos de la entrada:** con el analizador en la patilla 9, que el *pull-up*
   interno suba el nivel lo bastante rápido a 31250 baudios. Si no, añadir una
   resistencia de *pull-up* a 3,3 V obtenida en el adaptador.
3. **Salida:** captura en el DIN OUT y prueba audible con un sintetizador real.
4. **Entrada:** un teclado MIDI en el DIN IN y lectura con `READ` del driver (aún sin
   programa cliente que la use).
5. **CTS_n (patilla 6):** dejarla sin conectar, como en las pruebas.
6. **Patilla 7 fuera del modo UART (lo más importante):** cuando el puerto
   vuelve a modo joystick (`.golem output golem`, el driver liberado o el
   Next recién encendido), ¿qué hace la patilla 7? En el Next sirve también
   de línea de selección de los mandos Mega Drive. Si conmuta, el sinte
   recibe basura; si queda fija en alto, no pasa nada. Medir con el
   analizador en cada modo de joystick de NextZXOS (Kempston, MD...) con el
   adaptador puesto y un programa que lea el joystick. El 2026-10-13, tras
   volver a `golem`, el analizador no vio bytes, pero no se probó con un
   juego leyendo mandos MD.
   **Medido el 2026-10-15** (LA1010 en modo lógico a 1 MHz, patilla 7 de
   JOY 1, `REG 5` = 91 = `$5B`): fuera del modo UART la patilla 7 está en
   alto con **ráfagas de 4 pulsos a 0 de 9 µs (periodo 18 µs) cada ~2,3 ms**,
   la interrogación del mando Mega Drive de 6 botones. Las hay en reposo,
   tras `.golem output left` (sin tocar), tras `.golem output golem` y también
   con `REG 5,83` (supuesto Kempston). Durante `.golem note` (driver adquirido,
   JOY 1 en modo UART) la línea queda **plana en alto** salvo los bytes MIDI.
   Una primera lectura a escala de segundos parecía "quieta": hay que ampliar.
   Un receptor MIDI que valida el bit de arranque a mitad de bit (16 µs)
   descartaría los pulsos, pero no todos lo hacen. Solución elegida: el driver
   deja JOY 1 en modo UART mientras la salida sea `left`/`right`, no sólo
   mientras toca; `.golem output golem` lo devuelve a joystick. Entre el
   encendido y el primer `.golem output left` las ráfagas siguen llegando
   (recomendar ponerlo en el autoexec).
   **Resuelto** en el driver (PR #101, ABI 0.3 revisada) y comprobado en el
   Next el 2026-10-15: tras `.golem output left` la línea queda plana; tras
   `.golem output golem` el mando vuelve a funcionar en JOY 1. Con el
   adaptador montado, repetir la captura en el DIN OUT.
8. **Joystick en JOY 2 con la salida en JOY 1:** comprobar que un juego
   Kempston se controla con el mando en el puerto derecho mientras JOY 1 está
   en modo UART (elegir el modo de JOY 2 en el menú de NextZXOS o con `REG 5`),
   y explicarlo en la guía.
7. **Entrada por el driver:** la prueba del puente 7→9 leyó los bytes; falta
   decidir cómo un programa recibe MIDI de un teclado por este puerto (con el
   Golem ya lo hace `lib/midiin`).

## Para la versión de venta (no bloquea el prototipo)

- Placa a medida con los dos DIN soldados en ella y el búfer en SMD
  (74AHCT1G125).
- DB9 acodado con salida a la izquierda: carcasa CONEC `165X13219X` cuando
  haya stock, o cable DB9 ya acodado cortado por un extremo.
- Cable fijo con pasacables o DB9 macho en la caja y cable desmontable:
  decidir con el precio de las dos opciones.
