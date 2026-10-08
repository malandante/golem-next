' golem-next CSpect UART probe
' Sends MIDI Note On, waits 500 ms, then sends Note Off through the Pi UART.
'
' Expected byte trace: 91 3C 64 81 3C 00
' This is an integration probe, not the GOLEM.DRV implementation.
'
'!org=24576

#define NEX

#include <nextlib.bas>

const UART_TX_STATUS as uinteger = $133b
const UART_BAUD as uinteger      = $143b
const UART_CONTROL as uinteger   = $153b
const UART_FRAME as uinteger     = $163b

sub UartWrite(value as ubyte)
    ' Bit 1 is set while the 64-byte TX FIFO is full.
    while (in(UART_TX_STATUS) band 2) <> 0
    wend
    out UART_TX_STATUS, value
end sub

paper 0 : ink 7 : border 0 : cls
print "golem-next CSPECT UART PROBE"

' Enable the Pi UART on GPIO 14/15 and use the Pi wiring direction.
NextReg($a0, $30)

' Select the Pi UART and write the upper prescaler bits (zero here).
' CSpect HDMI timing is treated as 27 MHz for this first probe:
' 27,000,000 / 31,250 = 864 = $0360.
out UART_CONTROL, $50

' Write the lower 14 prescaler bits: low 7 first, then high 7 with bit 7 set.
out UART_BAUD, $60
out UART_BAUD, $86

' Reset UART FIFOs, then select 8 data bits, no parity, one stop bit.
out UART_FRAME, $98
out UART_FRAME, $18

print "TX: 91 3C 64"
UartWrite($91)
UartWrite($3c)
UartWrite($64)

' NEX programs must not call the ROM PAUSE routine. Crossing two raster
' lines per iteration guarantees that each iteration advances one frame.
dim frame as ubyte
for frame = 1 to 25
    WaitRaster(192)
    WaitRaster(193)
next frame

print "TX: 81 3C 00"
UartWrite($81)
UartWrite($3c)
UartWrite($00)

print "DONE"

do
    pause 1
loop
