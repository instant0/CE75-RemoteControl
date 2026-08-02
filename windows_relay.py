"""
Windows TCP <-> Named Pipe relay for Cheat Engine remote control.

Run this on Windows (from cmd, PowerShell, or WSL via python.exe).
It listens on TCP and relays to Cheat Engine's named pipe.

Usage:
    python windows_relay.py [--port PORT] [--pipe PIPE_NAME] [--timeout SEC]

Requires: Python 3.6+ (no extra deps; ctypes for Win32 API)

Hardening (why cmd used to "fully hang"):
  Pipe ReadFile/WriteFile were synchronous with no timeout. If CE's server
  thread died or stuck mid-command without closing the pipe, ReadFile blocked
  forever; join() never returned; Ctrl+C often cannot interrupt kernel waits.
  Now: overlapped I/O + WaitForSingleObject timeouts, TCP timeouts, join caps,
  and clean KeyboardInterrupt shutdown.
"""
from __future__ import annotations

import argparse
import ctypes
import socket
import struct
import sys
import threading
import time
from ctypes import wintypes

PIPE_DEFAULT = r"\\.\pipe\UEScanRemote"
TCP_PORT = 8888
BUFFER_SIZE = 65536
# Default per-I/O wait (seconds). Long enough for AOB/GroupScan; not infinite.
DEFAULT_IO_TIMEOUT_SEC = 300
# Max length-prefixed payload (bytes). Guards runaway length fields.
MAX_PAYLOAD = 16 * 1024 * 1024
# How long to wait for worker threads after close before abandoning.
JOIN_TIMEOUT_SEC = 5.0

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_FLAG_OVERLAPPED = 0x40000000
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 0x00000102
WAIT_FAILED = 0xFFFFFFFF
ERROR_IO_PENDING = 997
ERROR_IO_INCOMPLETE = 996
ERROR_OPERATION_ABORTED = 995
ERROR_BROKEN_PIPE = 109
ERROR_PIPE_NOT_CONNECTED = 233
ERROR_NO_DATA = 232
INFINITE = 0xFFFFFFFF

kernel32.CreateFileW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
    ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE,
]
kernel32.CreateFileW.restype = wintypes.HANDLE

kernel32.ReadFile.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p,
]
kernel32.ReadFile.restype = wintypes.BOOL

kernel32.WriteFile.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p,
]
kernel32.WriteFile.restype = wintypes.BOOL

kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL

kernel32.CancelIoEx.argtypes = [wintypes.HANDLE, ctypes.c_void_p]
kernel32.CancelIoEx.restype = wintypes.BOOL

kernel32.CreateEventW.argtypes = [
    ctypes.c_void_p, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR,
]
kernel32.CreateEventW.restype = wintypes.HANDLE

kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD

kernel32.GetOverlappedResult.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p,
    ctypes.POINTER(wintypes.DWORD), wintypes.BOOL,
]
kernel32.GetOverlappedResult.restype = wintypes.BOOL

kernel32.ResetEvent.argtypes = [wintypes.HANDLE]
kernel32.ResetEvent.restype = wintypes.BOOL


class OVERLAPPED(ctypes.Structure):
    _fields_ = [
        ("Internal", ctypes.c_void_p),
        ("InternalHigh", ctypes.c_void_p),
        ("Offset", wintypes.DWORD),
        ("OffsetHigh", wintypes.DWORD),
        ("hEvent", wintypes.HANDLE),
    ]


class PipeConn:
    """Named-pipe client with timed overlapped read/write (never blocks forever)."""

    def __init__(self, pipename: str, io_timeout_sec: float = DEFAULT_IO_TIMEOUT_SEC):
        self.pipename = pipename
        self.io_timeout_ms = max(1000, int(io_timeout_sec * 1000))
        self.handle = INVALID_HANDLE_VALUE
        self.last_error = None
        self._close_lock = threading.Lock()
        self._closed = False

    def connect(self) -> bool:
        """Single-shot open with OVERLAPPED flag for timed I/O."""
        self.handle = kernel32.CreateFileW(
            self.pipename,
            GENERIC_READ | GENERIC_WRITE,
            0,
            None,
            OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED,
            None,
        )
        if self.handle != INVALID_HANDLE_VALUE:
            self._closed = False
            return True
        self.last_error = ctypes.get_last_error()
        return False

    def _xfer(self, write: bool, buf: ctypes.Array, nbytes: int) -> int | None:
        """Overlapped ReadFile/WriteFile; return bytes transferred or None on fail/timeout."""
        if self._closed or self.handle == INVALID_HANDLE_VALUE:
            return None

        event = kernel32.CreateEventW(None, True, False, None)
        if not event:
            self.last_error = ctypes.get_last_error()
            return None

        ov = OVERLAPPED()
        ov.Internal = None
        ov.InternalHigh = None
        ov.Offset = 0
        ov.OffsetHigh = 0
        ov.hEvent = event

        transferred = wintypes.DWORD(0)
        try:
            if write:
                ok = kernel32.WriteFile(
                    self.handle, buf, nbytes, None, ctypes.byref(ov)
                )
            else:
                ok = kernel32.ReadFile(
                    self.handle, buf, nbytes, None, ctypes.byref(ov)
                )

            if ok:
                # Completed synchronously
                if not kernel32.GetOverlappedResult(
                    self.handle, ctypes.byref(ov), ctypes.byref(transferred), False
                ):
                    self.last_error = ctypes.get_last_error()
                    return None
                return int(transferred.value)

            err = ctypes.get_last_error()
            if err != ERROR_IO_PENDING:
                self.last_error = err
                return None

            wait = kernel32.WaitForSingleObject(event, self.io_timeout_ms)
            if wait == WAIT_OBJECT_0:
                if not kernel32.GetOverlappedResult(
                    self.handle, ctypes.byref(ov), ctypes.byref(transferred), False
                ):
                    self.last_error = ctypes.get_last_error()
                    return None
                return int(transferred.value)

            # Timeout or wait failure: cancel and fail the session
            self.last_error = (
                WAIT_TIMEOUT if wait == WAIT_TIMEOUT else ctypes.get_last_error()
            )
            kernel32.CancelIoEx(self.handle, ctypes.byref(ov))
            # Drain cancel completion (short wait)
            kernel32.WaitForSingleObject(event, 1000)
            kernel32.GetOverlappedResult(
                self.handle, ctypes.byref(ov), ctypes.byref(transferred), False
            )
            if wait == WAIT_TIMEOUT:
                print(
                    f"[relay] pipe I/O timeout after {self.io_timeout_ms}ms "
                    f"({'write' if write else 'read'}) — closing session "
                    f"(CE hung or dead without closing pipe)",
                    flush=True,
                )
            return None
        finally:
            kernel32.CloseHandle(event)

    def read_exact(self, size: int) -> bytes | None:
        if size < 0 or size > MAX_PAYLOAD:
            self.last_error = -1
            return None
        result = bytearray()
        while len(result) < size:
            need = size - len(result)
            buf = ctypes.create_string_buffer(need)
            n = self._xfer(False, buf, need)
            if n is None or n == 0:
                return None
            result.extend(buf.raw[:n])
        return bytes(result)

    def write_all(self, data: bytes) -> bool:
        if not data:
            return True
        if len(data) > MAX_PAYLOAD + 4:
            return False
        total = 0
        while total < len(data):
            chunk = data[total:]
            # WriteFile needs a buffer that lives for the call
            buf = ctypes.create_string_buffer(chunk)
            n = self._xfer(True, buf, len(chunk))
            if n is None or n == 0:
                return False
            total += n
        return True

    def close(self) -> None:
        with self._close_lock:
            if self.handle == INVALID_HANDLE_VALUE:
                self._closed = True
                return
            self._closed = True
            # Cancel pending overlapped ops so blocked workers wake up
            kernel32.CancelIoEx(self.handle, None)
            kernel32.CloseHandle(self.handle)
            self.handle = INVALID_HANDLE_VALUE


def _recv_exact(sock: socket.socket, size: int) -> bytes | None:
    if size < 0 or size > MAX_PAYLOAD:
        return None
    data = b""
    while len(data) < size:
        try:
            chunk = sock.recv(size - len(data))
        except (OSError, socket.timeout):
            return None
        if not chunk:
            return None
        data += chunk
    return data


def relay(tcp_conn: socket.socket, pipename: str, io_timeout_sec: float) -> None:
    peer = "?"
    try:
        peer = str(tcp_conn.getpeername())
    except OSError:
        pass
    print(f"[relay] New connection from {peer}", flush=True)

    # TCP side also has a bound (slightly above pipe timeout for race)
    try:
        tcp_conn.settimeout(io_timeout_sec + 5.0)
    except OSError:
        pass

    pipe = PipeConn(pipename, io_timeout_sec=io_timeout_sec)
    if not pipe.connect():
        err = getattr(pipe, "last_error", None)
        print(
            f"[relay] Failed to connect to pipe '{pipename}' (GetLastError={err})",
            flush=True,
        )
        try:
            # Not length-prefixed; client may treat as garbage — prefer close only
            tcp_conn.sendall(b"\x00\x00\x00\x00")  # empty framed reply attempt
        except OSError:
            pass
        try:
            tcp_conn.close()
        except OSError:
            pass
        return

    print(f"[relay] Connected to pipe '{pipename}'", flush=True)
    done = threading.Event()

    def tcp_to_pipe() -> None:
        try:
            while not done.is_set():
                header = _recv_exact(tcp_conn, 4)
                if not header:
                    break
                length = struct.unpack("<I", header)[0]
                if length > MAX_PAYLOAD:
                    print(f"[relay] TCP payload too large: {length}", flush=True)
                    break
                data = _recv_exact(tcp_conn, length) if length else b""
                if data is None:
                    break
                if not pipe.write_all(header + data):
                    break
        except (OSError, ConnectionError, socket.timeout) as e:
            print(f"[relay] tcp_to_pipe end: {type(e).__name__}", flush=True)
        finally:
            done.set()
            pipe.close()
            try:
                tcp_conn.shutdown(socket.SHUT_RD)
            except OSError:
                pass

    def pipe_to_tcp() -> None:
        try:
            while not done.is_set():
                header = pipe.read_exact(4)
                if not header:
                    break
                length = struct.unpack("<I", header)[0]
                if length > MAX_PAYLOAD:
                    print(f"[relay] pipe payload too large: {length}", flush=True)
                    break
                data = pipe.read_exact(length) if length > 0 else b""
                if data is None:
                    break
                try:
                    tcp_conn.sendall(header + data)
                except (OSError, socket.timeout):
                    break
        finally:
            done.set()
            pipe.close()
            try:
                tcp_conn.shutdown(socket.SHUT_WR)
            except OSError:
                pass

    t1 = threading.Thread(target=tcp_to_pipe, name="tcp_to_pipe", daemon=True)
    t2 = threading.Thread(target=pipe_to_tcp, name="pipe_to_tcp", daemon=True)
    t1.start()
    t2.start()
    t1.join(timeout=io_timeout_sec + JOIN_TIMEOUT_SEC + 10)
    t2.join(timeout=JOIN_TIMEOUT_SEC)
    if t1.is_alive() or t2.is_alive():
        print(
            "[relay] worker still alive after join timeout — forcing pipe/tcp close",
            flush=True,
        )
        done.set()
        pipe.close()
        try:
            tcp_conn.close()
        except OSError:
            pass
        t1.join(timeout=JOIN_TIMEOUT_SEC)
        t2.join(timeout=JOIN_TIMEOUT_SEC)
        if t1.is_alive() or t2.is_alive():
            print(
                "[relay] WARNING: worker thread(s) still stuck in kernel I/O; "
                "session abandoned (main accept loop continues)",
                flush=True,
            )

    try:
        tcp_conn.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    try:
        tcp_conn.close()
    except OSError:
        pass
    print(f"[relay] Session ended ({peer})", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="TCP <-> Named Pipe relay for Cheat Engine remote control"
    )
    parser.add_argument(
        "--port", type=int, default=TCP_PORT,
        help=f"TCP port to listen on (default: {TCP_PORT})",
    )
    parser.add_argument(
        "--pipe", type=str, default=PIPE_DEFAULT,
        help=f"Named pipe path (default: {PIPE_DEFAULT})",
    )
    parser.add_argument(
        "--bind", type=str, default="127.0.0.1",
        help="Bind address (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--timeout", type=float, default=DEFAULT_IO_TIMEOUT_SEC,
        help=(
            f"Pipe/TCP I/O timeout seconds (default: {DEFAULT_IO_TIMEOUT_SEC}). "
            "Prevents infinite hang when CE dies mid-command."
        ),
    )
    args = parser.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # Accept can be interrupted more reliably with a timeout on some Windows builds
    srv.settimeout(1.0)
    srv.bind((args.bind, args.port))
    srv.listen(5)
    print(
        f"Relay listening on {args.bind}:{args.port} -> {args.pipe} "
        f"(I/O timeout {args.timeout:g}s)",
        flush=True,
    )
    print("Ctrl+C to stop. Sessions auto-abort on pipe/TCP timeout.", flush=True)

    try:
        while True:
            try:
                conn, addr = srv.accept()
            except socket.timeout:
                continue
            except OSError as e:
                print(f"[relay] accept error: {e}", flush=True)
                time.sleep(0.2)
                continue
            print(f"Connection from {addr}", flush=True)
            threading.Thread(
                target=relay,
                args=(conn, args.pipe, args.timeout),
                name=f"relay-{addr[0]}-{addr[1]}",
                daemon=True,
            ).start()
    except KeyboardInterrupt:
        print("\n[relay] KeyboardInterrupt — shutting down accept loop", flush=True)
    finally:
        try:
            srv.close()
        except OSError:
            pass
        print("[relay] socket closed; daemon sessions die with process", flush=True)


if __name__ == "__main__":
    main()
