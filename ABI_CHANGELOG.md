# Registro de cambios de la ABI de `GOLEM.DRV`

El driver se llamaba `MT32.DRV` hasta el 7 de octubre de 2026 (#76). El cambio
de nombre del fichero no toca la ABI: mismo ID, funciones, constantes `MT32_*`
y `DE=$0002`. Las entradas siguientes conservan el nombre de su fecha.

La ABI se identifica por `DE` en `QUERY` (`MT32_ABI_VERSION`, mayor.menor) y por
las capacidades de `HL`. Contrato completo: [docs/driver-api.md](docs/driver-api.md).
Hasta M6 los números pueden cambiar y el ID `$2D` sigue siendo experimental.

## 0.3, 2026-10-12 (#64)

- Nueva función `SET_OUTPUT=7`: `E=0` conector del Accelerator (Golem), `1`
  joystick izquierdo, `2` derecho. Vale desde el siguiente `ACQUIRE` y mientras
  el driver esté instalado.
- `QUERY` devuelve `DE=$0003`; las capacidades pasan a `L` y `H` lleva el
  valor de NextReg `$0B` que escribirá `ACQUIRE` (`0`, `$A1` o `$B1`).
- Capacidad `MT32_CAP_OUTPUT_SELECT` (`$0004`).
- `ACQUIRE` guarda y escribe NextReg `$0B`; con salida por joystick no toca
  `$A2`. `RELEASE` restaura `$0B`.
- `STATUS` devuelve en `B` el byte de estado del UART (`$133B`) sin tocar,
  con los bits de error de recepción y de *break* (#17); `C` no cambia.

Un cliente de 0.2 no necesita cambios: las funciones 0 a 6 no cambian, el
mayor sigue siendo 0, y quien lea las capacidades de `L` (o de `HL` con el
byte alto a cero, como en 0.2) sólo debe dejar de esperar `H=0`.

## 0.2, revisión del 2026-10-05 (#35)

Sin cambios de interfaz: mismas funciones, números, códigos de error,
capacidades y `DE=$0002`. Cambia el comportamiento:

- `ACQUIRE` guarda NextReg `$A2` y escribe `$D2` (recepción I²S desde la Pi);
  `RELEASE` lo restaura.
- `WRITE`, `STATUS`, `DRAIN_STATUS` y `READ` seleccionan el UART Pi al entrar y
  restauran al salir la selección del llamador. `STATUS` informa siempre del
  UART Pi, también sin adquisición.
- `RELEASE` restaura la selección UART sin escribir bits del divisor: el de la
  Pi queda en 31250 y el del ESP no se toca.

Un cliente de 0.2 no necesita cambios. Si escribía `REG 162,210` (`$A2`) por su
cuenta, puede dejar de hacerlo.

## 0.2, 2026-10-03 (`7fdba12`)

Versión que fijan los primeros clientes.

- Nueva función `READ=6`, no bloqueante, como máximo 16 bytes por llamada.
- `STATUS` añade el bit 3 (RX con datos).
- Capacidad `MT32_CAP_RX_NONBLOCKING` (`$0002`).
- Las funciones 0 a 5 conservan su número.
- Convención de puntero aclarada: `HL` en comandos punto, `IX` en programas.

## 0.1

`QUERY`, `ACQUIRE`, `WRITE` (escritura parcial, máximo 16 bytes),
`STATUS`, `DRAIN_STATUS` y `RELEASE`. Capacidad `MT32_CAP_PARTIAL_WRITE`.
