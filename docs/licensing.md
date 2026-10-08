# Licencias de golem-next y Golem

Decisión del 6 de octubre de 2026.

## Qué licencia tiene cada pieza

| Pieza | Licencia | Motivo |
| --- | --- | --- |
| Este repositorio (`malandante/mt32-next`): driver `GOLEM.DRV`, comandos `.MT32`/`.GOLEM`, futura biblioteca M6, especificaciones (API del driver, protocolo Golem, formato de música), herramientas de PC y pruebas | MIT (`LICENSE`) | El objetivo es que sea el estándar de música MT-32 del Next. El driver y la biblioteca M6 acaban dentro de los juegos de otros; con MIT cualquiera puede usarlos también en juegos cerrados o comerciales, sólo conservando el aviso de autoría. |
| Fork de mt32-pi (`malandante/mt32-pi`, firmware de Golem) | GPL-3.0 | Lo hereda de mt32-pi. Al distribuir el firmware (por ejemplo, en el Golem Sound Module) hay que ofrecer el código fuente correspondiente. |
| Código derivado de ScummVM u otro proyecto GPL, si alguna vez hiciera falta | GPL, en una herramienta aparte | Sólo para herramientas de PC (extractores de música de juegos originales) que no se enlazan en ningún juego. Nunca dentro del driver ni de la biblioteca M6. |
| Juegos que usan golem-next | La que decida su autor | Son código propio. Usar el driver o la biblioteca MIT no impone nada. |

Titular de los derechos: Javier Aguilar Saavedra (seudónimo malandante), que
publica bajo la marca Golem Retro. La marca no está registrada y no es una
entidad jurídica, así que el aviso de copyright va a nombre de la persona; si
algún día se crea una empresa, los derechos pueden cederse a ella.

La GPL no es la opción «menos restrictiva» entre las libres: obliga a publicar
bajo GPL todo programa distribuido que incluya el código. Para una biblioteca
que se enlaza dentro de cada juego eso habría echado atrás a quien quiera
vender un juego cerrado, y habría jugado contra la adopción como estándar. La
LGPL tampoco encaja: con binarios enlazados estáticamente (`.nex`, código Z80)
obliga a permitir reenlazar el juego, algo impracticable aquí.

## Regla para iMUSE y otros sistemas de terceros

La biblioteca M6 y el driver no pueden contener código traducido de proyectos
GPL. El comportamiento de iMUSE se reimplementa desde fuentes que no imponen
licencia: la patente US 5,315,057 (caducada), documentación pública y la
observación del comportamiento de implementaciones existentes. Si se estudia
el código de ScummVM, las notas de diseño describen comportamiento, no copian
estructura ni código, y se citan las fuentes.

## Lo que no entra en el repositorio

ROMs de Roland, SoundFonts sin licencia redistribuible, música o datos de
juegos comerciales (Monkey Island, KQ5) ni extractos de
ellos. El usuario aporta sus propios originales; las herramientas los
convierten en su máquina.

Esto recoge criterios generales, no asesoramiento legal. Para el producto
comercial (firmware GPL distribuido en hardware, marca Golem y logotipos de
terceros) conviene una revisión profesional antes de vender.
