# Demostración grabable de MI_1.MID

`record-mi1-demo.cmd` prepara y ejecuta una sesión desechable del banco
CSpect→Munt. El archivo comercial no se copia al repositorio: se lee desde
`%USERPROFILE%\Documents\mt32-pi\mimp\MI_1.MID` y sólo se inserta en una copia
temporal de la imagen NextZXOS.

## Uso

1. Cerrar cualquier instancia previa de CSpect.
2. Comprobar que Munt tiene configuradas las ROM de MT-32 y una salida de audio.
3. En **Configuración de Windows → Juegos → Capturas**, activar la grabación de
   audio y desactivar **Silenciar el audio del sistema y de las aplicaciones al
   grabar un juego**. En versiones antiguas de Game Bar, el ajuste equivalente
   es **Configuración → Capturando → Audio para grabar → Todo**. El modo que
   graba sólo el juego no captura Munt porque el sintetizador y CSpect son
   aplicaciones distintas.
4. Hacer doble clic en `record-mi1-demo.cmd`. CSpect se abre a escala 3× y con
   el teclado normal del PC activado.
5. Hacer clic dentro de CSpect y pulsar `Win+Alt+R` para iniciar la captura. Es
   importante empezar a grabar después de enfocar CSpect, porque Game Bar fija
   la aplicación capturada al comenzar.
6. Cuando aparezca el prompt de NextZXOS, escribir visiblemente:

```text
.install c:/nextzxos/GOLEM.DRV
.mt32 play c:/MI_1.MID
```

7. SPACE cancela la reproducción de forma limpia. Detener la grabación con
   `Win+Alt+R` y cerrar CSpect.

El lanzador compila los binarios actuales, crea la imagen en `%TEMP%`, inyecta
`GOLEM.DRV`, `.MT32`, `.GOLEM` y `MI_1.MID`, abre Munt si no estaba ejecutándose,
inicia en segundo plano el puente MIDI y espera a que se cierre CSpect. Después
envía un `panic` MIDI a los 16 canales, detiene sólo los procesos que él haya
iniciado y elimina imagen y logs. Cada
doble clic comienza por tanto desde una copia limpia, sin conservar el driver
instalado ni el estado de la sesión anterior.

Munt, sus ROM y su configuración no se borran. Si Munt ya estaba abierto, el
lanzador lo reutiliza y no lo cierra.

## Rutas alternativas

Las instalaciones no estándar pueden indicarse mediante variables de entorno:

```cmd
set MT32_NEXT_MI1_MIDI=D:\MIDI\MI_1.MID
set MT32_NEXT_NEXTBUILD=D:\NextBuildv10
set MT32_NEXT_MUNT_EXE=D:\Munt\mt32emu-qt.exe
```

El lanzador se detiene sin alterar archivos si detecta otro CSpect abierto, un
MIDI que supera el límite actual, el plugin UART ausente o
`UARTReplacement.dll` en conflicto.
