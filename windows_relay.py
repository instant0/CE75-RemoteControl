"""
Windows TCP <-> Named Pipe relay for Cheat Engine remote control.

Run this on Windows (from cmd, PowerShell, or WSL via python.exe).
It listens on TCP port 8888 and relays to Cheat Engine's named pipe.

Usage:
    python windows_relay.py [--port PORT] [--pipe PIPE_NAME]

Requires: Python 3.6+ (no extra dependencies, uses ctypes for Win32 API)
"""
import argparse
import socket
import struct
import threading
import ctypes
import ctypes.wintypes
from ctypes import wintypes

PIPE_DEFAULT = r"\\.\pipe\UEScanRemote"
TCP_PORT = 8888
BUFFER_SIZE = 65536

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_FLAG_OVERLAPPED = 0x40000000
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 0x00000102
ERROR_PIPE_BUSY = 231
ERROR_IO_PENDING = 997
ERROR_PIPE_CONNECTED = 535
NMPWAIT_USE_DEFAULT_WAIT = 0
INFINITE = 0xFFFFFFFF

kernel32.CreateFileW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
    ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE
]
kernel32.CreateFileW.restype = wintypes.HANDLE

kernel32.ReadFile.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p
]
kernel32.ReadFile.restype = wintypes.BOOL

kernel32.WriteFile.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p
]
kernel32.WriteFile.restype = wintypes.BOOL

kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL

kernel32.WaitNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
kernel32.WaitNamedPipeW.restype = wintypes.BOOL

kernel32.SetNamedPipeHandleState.argtypes = [
    wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD),
    ctypes.POINTER(wintypes.DWORD), ctypes.POINTER(wintypes.DWORD)
]
kernel32.SetNamedPipeHandleState.restype = wintypes.BOOL

kernel32.FlushFileBuffers.argtypes = [wintypes.HANDLE]
kernel32.FlushFileBuffers.restype = wintypes.BOOL

kernel32.DisconnectNamedPipe.argtypes = [wintypes.HANDLE]
kernel32.DisconnectNamedPipe.restype = wintypes.BOOL

kernel32.CancelIoEx.argtypes = [wintypes.HANDLE, ctypes.c_void_p]
kernel32.CancelIoEx.restype = wintypes.BOOL


class PipeConn:
    def __init__(self, pipename):
        self.pipename = pipename
        self.handle = INVALID_HANDLE_VALUE
        self._close_lock = threading.Lock()

    def connect(self, retries=10, delay=1.0):
        for attempt in range(1, retries + 1):
            self.handle = kernel32.CreateFileW(
                self.pipename, GENERIC_READ | GENERIC_WRITE, 0,
                None, OPEN_EXISTING, 0, None
            )
            if self.handle != INVALID_HANDLE_VALUE:
                return True
            err = ctypes.get_last_error()
            if attempt < retries:
                import time
                time.sleep(delay)
        return False

    def read_exact(self, size):
        result = b""
        while len(result) < size:
            buf = ctypes.create_string_buffer(size - len(result))
            bytes_read = wintypes.DWORD(0)
            if not kernel32.ReadFile(self.handle, buf, size - len(result),
                                      ctypes.byref(bytes_read), None):
                err = ctypes.get_last_error()
                if err == ERROR_IO_PENDING:
                    continue
                return None
            result += buf.raw[:bytes_read.value]
            if bytes_read.value == 0:
                return None
        return result

    def write_all(self, data):
        bytes_written = wintypes.DWORD(0)
        total = 0
        while total < len(data):
            chunk = data[total:]
            if not kernel32.WriteFile(self.handle, chunk, len(chunk),
                                       ctypes.byref(bytes_written), None):
                return False
            total += bytes_written.value
        return True

    def close(self):
        with self._close_lock:
            if self.handle != INVALID_HANDLE_VALUE:
                kernel32.CancelIoEx(self.handle, None)
                kernel32.CloseHandle(self.handle)
                self.handle = INVALID_HANDLE_VALUE


def relay(tcp_conn, pipename):
    print(f"[relay] New connection from {tcp_conn.getpeername()}", flush=True)
    pipe = PipeConn(pipename)
    if not pipe.connect():
        print(f"[relay] Failed to connect to pipe '{pipename}'", flush=True)
        try:
            tcp_conn.sendall(b"ERROR: Cannot connect to CE pipe\n")
        except OSError:
            pass
        tcp_conn.close()
        return
    print(f"[relay] Connected to pipe '{pipename}'", flush=True)

    def tcp_to_pipe():
        try:
            while True:
                header = tcp_conn.recv(4)
                if not header or len(header) < 4:
                    break
                length = struct.unpack("<I", header)[0]
                data = tcp_conn.recv(length)
                while len(data) < length:
                    chunk = tcp_conn.recv(length - len(data))
                    if not chunk:
                        break
                    data += chunk
                if not pipe.write_all(header + data):
                    break
        except (OSError, ConnectionError):
            pass
        finally:
            pipe.close()

    def pipe_to_tcp():
        try:
            while True:
                header = pipe.read_exact(4)
                if not header:
                    break
                length = struct.unpack("<I", header)[0]
                data = pipe.read_exact(length) if length > 0 else b""
                if data is None:
                    break
                try:
                    tcp_conn.sendall(header + data)
                except OSError:
                    break
        finally:
            pipe.close()

    t1 = threading.Thread(target=tcp_to_pipe, daemon=True)
    t2 = threading.Thread(target=pipe_to_tcp, daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    try:
        tcp_conn.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    tcp_conn.close()


def main():
    parser = argparse.ArgumentParser(
        description="TCP <-> Named Pipe relay for Cheat Engine remote control"
    )
    parser.add_argument("--port", type=int, default=TCP_PORT,
                        help=f"TCP port to listen on (default: {TCP_PORT})")
    parser.add_argument("--pipe", type=str, default=PIPE_DEFAULT,
                        help=f"Named pipe path (default: {PIPE_DEFAULT})")
    parser.add_argument("--bind", type=str, default="127.0.0.1",
                        help="Bind address (default: 127.0.0.1)")
    args = parser.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.bind, args.port))
    srv.listen(5)
    print(f"Relay listening on {args.bind}:{args.port} -> {args.pipe}", flush=True)

    while True:
        conn, addr = srv.accept()
        print(f"Connection from {addr}", flush=True)
        threading.Thread(target=relay, args=(conn, args.pipe), daemon=True).start()


if __name__ == "__main__":
    main()
