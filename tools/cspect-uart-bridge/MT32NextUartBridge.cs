using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Plugin;

namespace MT32Next.CSpect
{
    /// <summary>
    /// Exposes the ZX Spectrum Next Pi UART inside CSpect as a local TCP stream.
    /// The host-side bridge connects to 127.0.0.1:15320.
    /// </summary>
    public sealed class MT32NextUartBridge : iPlugin
    {
        private const ushort UartTx = 0x133b;
        private const ushort UartRx = 0x143b;
        private const ushort UartControl = 0x153b;
        private const int DefaultTcpPort = 15320;

        private readonly ConcurrentQueue<byte> receiveQueue = new ConcurrentQueue<byte>();
        private readonly ConcurrentQueue<byte> transmitQueue = new ConcurrentQueue<byte>();
        private readonly object connectionLock = new object();
        private TcpListener listener;
        private TcpClient client;
        private NetworkStream stream;
        private Thread worker;
        private volatile bool stopping;
        private bool piSelected;
        private int tcpPort = DefaultTcpPort;
        private int prescaler = 234;
        private byte prescalerTop;
        private int stallAfterBytes = -1;
        private int configuredStallReads;
        private int stallReadsRemaining;
        private int transmittedBytes;
        private bool stallLogged;

        public List<sIO> Init(iCSpect cspect)
        {
            var ports = new List<sIO>
            {
                new sIO(UartTx, eAccess.Port_Write),
                new sIO(UartTx, eAccess.Port_Read),
                new sIO(UartRx, eAccess.Port_Write),
                new sIO(UartRx, eAccess.Port_Read),
                new sIO(UartControl, eAccess.Port_Write),
                new sIO(UartControl, eAccess.Port_Read)
            };

            try
            {
                int configuredPort;
                var portText = Environment.GetEnvironmentVariable("MT32_NEXT_UART_PORT");
                if (int.TryParse(portText, out configuredPort)
                    && configuredPort > 0 && configuredPort <= 65535)
                    tcpPort = configuredPort;
                stallAfterBytes = ReadNonNegativeEnvironment("MT32_NEXT_UART_STALL_AFTER", -1);
                configuredStallReads = ReadNonNegativeEnvironment("MT32_NEXT_UART_STALL_READS", 0);
                ResetPressure();
                listener = new TcpListener(IPAddress.Loopback, tcpPort);
                listener.Start(1);
                worker = new Thread(NetworkLoop) { IsBackground = true, Name = "MT32-NEXT UART bridge" };
                worker.Start();
                Console.WriteLine("MT32-NEXT UART bridge: listening on 127.0.0.1:" + tcpPort);
                if (stallAfterBytes >= 0 && configuredStallReads > 0)
                    Console.WriteLine(
                        "MT32-NEXT UART bridge: pressure after " + stallAfterBytes
                        + " byte(s) for " + configuredStallReads + " status read(s)");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("MT32-NEXT UART bridge: " + ex.Message);
            }

            return ports;
        }

        public bool Write(eAccess type, int port, int id, byte value)
        {
            switch (port)
            {
                case UartControl:
                    piSelected = (value & 0x40) != 0;
                    if ((value & 0x10) != 0)
                    {
                        prescalerTop = (byte)(value & 0x07);
                        prescaler = (prescaler & 0x3fff) | (prescalerTop << 14);
                    }
                    return true;

                case UartRx:
                    if ((value & 0x80) == 0)
                        prescaler = (prescaler & 0x1ff80) | (value & 0x7f);
                    else
                        prescaler = (prescaler & 0x1c07f) | ((value & 0x7f) << 7);
                    return true;

                case UartTx:
                    if (piSelected)
                        Send(value);
                    return true;

                default:
                    return false;
            }
        }

        public byte Read(eAccess type, int port, int id, out bool isValid)
        {
            isValid = true;
            switch (port)
            {
                case UartControl:
                    return (byte)((piSelected ? 0x40 : 0x00) | prescalerTop);
                case UartTx:
                    byte rxAvailable = (byte)(receiveQueue.IsEmpty ? 0x00 : 0x01);
                    if (ShouldReportFull())
                        return (byte)(rxAvailable | 0x02);
                    return (byte)(rxAvailable | 0x10);
                case UartRx:
                    byte value;
                    return receiveQueue.TryDequeue(out value) ? value : (byte)0x00;
                default:
                    isValid = false;
                    return 0xff;
            }
        }

        public void Quit()
        {
            stopping = true;
            CloseClient();
            if (listener != null)
            {
                try { listener.Stop(); } catch { }
                listener = null;
            }
            if (worker != null && worker.IsAlive)
                worker.Join(1000);
            Console.WriteLine("MT32-NEXT UART bridge: stopped");
        }

        public void Reset()
        {
            byte ignored;
            while (receiveQueue.TryDequeue(out ignored)) { }
            while (transmitQueue.TryDequeue(out ignored)) { }
            piSelected = false;
            prescaler = 234;
            prescalerTop = 0;
            ResetPressure();
        }

        public void Tick() { }
        public void OSTick() { }
        public bool KeyPressed(int id) { return false; }

        private void NetworkLoop()
        {
            while (!stopping)
            {
                try
                {
                    if (client == null)
                    {
                        if (listener != null && listener.Pending())
                        {
                            var accepted = listener.AcceptTcpClient();
                            accepted.NoDelay = true;
                            lock (connectionLock)
                            {
                                client = accepted;
                                stream = accepted.GetStream();
                            }
                            Console.WriteLine("MT32-NEXT UART bridge: host connected");
                        }
                    }
                    else
                    {
                        NetworkStream current;
                        lock (connectionLock) { current = stream; }
                        byte outgoing;
                        while (current != null && transmitQueue.TryDequeue(out outgoing))
                            current.WriteByte(outgoing);
                        while (current != null && current.DataAvailable)
                        {
                            int value = current.ReadByte();
                            if (value < 0)
                            {
                                CloseClient();
                                break;
                            }
                            receiveQueue.Enqueue((byte)value);
                        }
                        if (client != null && client.Client.Poll(0, SelectMode.SelectRead)
                            && client.Client.Available == 0)
                        {
                            CloseClient();
                            Console.WriteLine("MT32-NEXT UART bridge: host disconnected");
                        }
                    }
                }
                catch (SocketException) { CloseClient(); }
                catch (ObjectDisposedException) { if (!stopping) CloseClient(); }
                catch (Exception ex)
                {
                    Console.Error.WriteLine("MT32-NEXT UART bridge: " + ex.Message);
                    CloseClient();
                }
                Thread.Sleep(2);
            }
        }

        private void Send(byte value)
        {
            transmitQueue.Enqueue(value);
            transmittedBytes++;
        }

        private bool ShouldReportFull()
        {
            if (!piSelected || stallAfterBytes < 0 || configuredStallReads <= 0
                || transmittedBytes < stallAfterBytes || stallReadsRemaining <= 0)
                return false;
            if (!stallLogged)
            {
                stallLogged = true;
                Console.WriteLine(
                    "MT32-NEXT UART bridge: pressure active after "
                    + transmittedBytes + " transmitted byte(s)");
            }
            stallReadsRemaining--;
            if (stallReadsRemaining == 0)
                Console.WriteLine("MT32-NEXT UART bridge: pressure released");
            return true;
        }

        private void ResetPressure()
        {
            transmittedBytes = 0;
            stallReadsRemaining = configuredStallReads;
            stallLogged = false;
        }

        private static int ReadNonNegativeEnvironment(string name, int fallback)
        {
            int parsed;
            var text = Environment.GetEnvironmentVariable(name);
            return int.TryParse(text, out parsed) && parsed >= 0 ? parsed : fallback;
        }

        private void CloseClient()
        {
            lock (connectionLock)
            {
                if (stream != null)
                {
                    try { stream.Dispose(); } catch { }
                    stream = null;
                }
                if (client != null)
                {
                    try { client.Close(); } catch { }
                    client = null;
                }
            }
        }
    }
}
