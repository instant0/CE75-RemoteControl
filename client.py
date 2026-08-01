"""
WSL/Linux client for Cheat Engine remote control via TCP relay.

Usage:
    # Single command
    python client.py --cmd "ping"
    python client.py --host 192.168.176.1 --port 8000 --timeout 120 --cmd "tableStatus"

    # Interactive
    python client.py -i

    # As module (table migration helpers)
    from client import CERemote
    ce = CERemote("192.168.176.1", 8000, timeout=120)
    print(ce.cmd("ping"))
    print(ce.table_status())
    print(ce.al_dump(limit=50)[:500])
    text = ce.al_get_script(78)          # full AA script as str
    ce.al_set_script(78, text)           # chunked upload
    ce.st_ensure_seed()
    ce.st_clone("Src", "Src_v2")

See docs/TABLE-MIGRATE.md and skills/ce-table-migrate/SKILL.md.
"""
from __future__ import annotations

import argparse
import re
import socket
import struct
import sys
from typing import List, Optional, Sequence, Union

# Script chunk size in raw bytes (before hex). ~16k hex chars — under 48 KiB wire.
SCRIPT_CHUNK = 8192
SCRIPT_GET_CHUNK = 16384


def _parse_kv(line: str) -> dict:
    """Parse KEY=value tokens from an OK/ERROR response line."""
    out = {}
    for m in re.finditer(r"(\w+)=(\S+)", line or ""):
        out[m.group(1)] = m.group(2)
    return out


def _hex_encode(data: bytes) -> str:
    return data.hex().upper()


def _hex_decode(h: str) -> bytes:
    h = re.sub(r"\s+", "", h or "")
    if len(h) % 2:
        raise ValueError("odd hex length")
    return bytes.fromhex(h)


class CERemote:
    def __init__(self, host: str = "localhost", port: int = 8888, timeout: float = 30):
        self.host = host
        self.port = port
        self.timeout = timeout

    def cmd(self, command: str, timeout: Optional[float] = None) -> Optional[str]:
        """Send one length-prefixed command; optional per-call timeout (seconds)."""
        t = self.timeout if timeout is None else timeout
        with socket.create_connection((self.host, self.port), t) as s:
            s.settimeout(t)
            data = command.encode("utf-8")
            s.sendall(struct.pack("<I", len(data)) + data)
            header = s.recv(4)
            if len(header) < 4:
                return None
            length = struct.unpack("<I", header)[0]
            response = b""
            while len(response) < length:
                chunk = s.recv(length - len(response))
                if not chunk:
                    break
                response += chunk
            return response.decode("utf-8", errors="replace")

    # --- foundation ---

    def ping(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("ping", timeout=timeout)

    def get_version(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("getVersion", timeout=timeout)

    def help(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("help", timeout=timeout)

    def table_status(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("tableStatus", timeout=timeout)

    def debug_sync(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("debugSync", timeout=timeout)

    # --- address list inventory ---

    def al_dump(self, offset: int = 0, limit: int = 500, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alDump {int(offset)} {int(limit)}", timeout=timeout)

    def al_get(self, memrec_id: int, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alGet {int(memrec_id)}", timeout=timeout)

    def al_resolve(self, memrec_id: int, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alResolve {int(memrec_id)}", timeout=timeout)

    def al_dump_parsed(
        self, offset: int = 0, limit: int = 500, timeout: Optional[float] = None
    ) -> List[dict]:
        """Parse alDump TSV into list of dicts (best-effort)."""
        raw = self.al_dump(offset=offset, limit=limit, timeout=timeout) or ""
        rows: List[dict] = []
        header = None
        for line in raw.splitlines():
            if line.startswith("COUNT=") or not line.strip():
                continue
            if line.startswith("ID\t") or line.startswith("ID "):
                header = re.split(r"\t+", line.strip())
                continue
            if header is None:
                continue
            cols = re.split(r"\t+", line.rstrip("\n"))
            if len(cols) < 2:
                continue
            row = {}
            for i, key in enumerate(header):
                row[key] = cols[i] if i < len(cols) else ""
            rows.append(row)
        return rows

    # --- address list mutate ---

    def al_set_desc(self, memrec_id: int, text: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alSetDesc {int(memrec_id)} {text}", timeout=timeout)

    def al_set_address(self, memrec_id: int, expr: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alSetAddress {int(memrec_id)} {expr}", timeout=timeout)

    def al_set_offsets(
        self,
        memrec_id: int,
        offsets: Sequence[int],
        timeout: Optional[float] = None,
    ) -> Optional[str]:
        if not offsets:
            return self.cmd(f"alSetOffsets {int(memrec_id)}", timeout=timeout)
        parts = [f"{int(o):X}" for o in offsets]
        return self.cmd(f"alSetOffsets {int(memrec_id)} {','.join(parts)}", timeout=timeout)

    def al_set_type(self, memrec_id: int, type_int: int, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alSetType {int(memrec_id)} {int(type_int)}", timeout=timeout)

    # --- AA scripts / active ---

    def al_get_script(
        self,
        memrec_id: int,
        chunk: int = SCRIPT_GET_CHUNK,
        timeout: Optional[float] = 60,
    ) -> str:
        """Download full AA script text (hex-decoded). Raises on ERROR."""
        mid = int(memrec_id)
        off = 0
        total = None
        parts: List[bytes] = []
        while True:
            resp = self.cmd(f"alGetScript {mid} {off} {int(chunk)}", timeout=timeout)
            if resp is None:
                raise RuntimeError("no response from alGetScript")
            if resp.startswith("ERROR:"):
                raise RuntimeError(resp)
            kv = _parse_kv(resp.splitlines()[0] if resp else "")
            if total is None:
                total = int(kv.get("TOTAL", "0"))
            data_hex = ""
            m = re.search(r"DATA=([0-9A-Fa-f]*)", resp)
            if m:
                data_hex = m.group(1)
            length = int(kv.get("LENGTH", str(len(data_hex) // 2)))
            if data_hex:
                parts.append(_hex_decode(data_hex))
            off += length
            if total is not None and off >= total:
                break
            if length == 0:
                break
        return b"".join(parts).decode("utf-8", errors="replace")

    def al_set_script(
        self,
        memrec_id: int,
        text: str,
        chunk: int = SCRIPT_CHUNK,
        timeout: Optional[float] = 60,
    ) -> Optional[str]:
        """Upload AA script via Begin/Chunk/Commit; abort on failure."""
        mid = int(memrec_id)
        data = text.encode("utf-8", errors="replace")
        try:
            r = self.cmd(f"alSetScriptBegin {mid} {len(data)}", timeout=timeout)
            if r is None or str(r).startswith("ERROR:"):
                return r
            off = 0
            while off < len(data):
                part = data[off : off + int(chunk)]
                hx = _hex_encode(part)
                r = self.cmd(f"alSetScriptChunk {mid} {off} {hx}", timeout=timeout)
                if r is None or str(r).startswith("ERROR:"):
                    self.cmd(f"alSetScriptAbort {mid}", timeout=timeout)
                    return r
                off += len(part)
            return self.cmd(f"alSetScriptCommit {mid}", timeout=timeout)
        except Exception:
            try:
                self.cmd(f"alSetScriptAbort {mid}", timeout=timeout)
            except Exception:
                pass
            raise

    def al_set_script_abort(self, memrec_id: int, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alSetScriptAbort {int(memrec_id)}", timeout=timeout)

    def aa_check(self, memrec_id: int, timeout: Optional[float] = 60) -> Optional[str]:
        return self.cmd(f"aaCheck {int(memrec_id)}", timeout=timeout)

    def al_set_active(
        self,
        memrec_id: int,
        active: bool,
        timeout: Optional[float] = 120,
        nocheck: bool = False,
    ) -> Optional[str]:
        """Enable/disable memrec. Default timeout 120s.
        Enable on AA rows runs aaCheck first unless nocheck=True.
        """
        extra = " nocheck" if nocheck else ""
        return self.cmd(
            f"alSetActive {int(memrec_id)} {1 if active else 0}{extra}",
            timeout=timeout,
        )

    def al_disable_soft(self, memrec_id: int, timeout: Optional[float] = 60) -> Optional[str]:
        return self.cmd(f"alDisableSoft {int(memrec_id)}", timeout=timeout)

    def al_apply(
        self,
        ops: Sequence[str],
        stop_on_error: bool = True,
        timeout: Optional[float] = 60,
    ) -> Optional[str]:
        """Batch setDesc/setAddress/setOffsets/setType in one server sync.
        Each op is e.g. 'setAddress 90 playerStat + 2e38' or 'setOffsets 91 10,2A0'.
        """
        body = "\n".join(op.strip() for op in ops if op and str(op).strip())
        hx = _hex_encode(body.encode("utf-8", errors="replace"))
        stop = 1 if stop_on_error else 0
        return self.cmd(f"alApply stop={stop} hex={hx}", timeout=timeout)

    def al_audit(self, n: int = 20, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"alAudit {int(n)}", timeout=timeout)

    def sym_get(self, name: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"symGet {name}", timeout=timeout)

    def sym_set(
        self,
        name: str,
        addr: Union[str, int],
        donotsave: bool = False,
        timeout: Optional[float] = None,
    ) -> Optional[str]:
        if isinstance(addr, int):
            addr = f"{addr:X}"
        ds = 1 if donotsave else 0
        return self.cmd(f"symSet {name} {addr} {ds}", timeout=timeout)

    # --- structures ---

    def st_dump(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("stDump", timeout=timeout)

    def st_find(self, name: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"stFind {name}", timeout=timeout)

    def st_get(
        self,
        name: str,
        elem_off: int = 0,
        elem_limit: int = 500,
        timeout: Optional[float] = None,
    ) -> Optional[str]:
        return self.cmd(
            f"stGet {name} {int(elem_off)} {int(elem_limit)}",
            timeout=timeout,
        )

    def st_ensure_seed(self, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd("stEnsureSeed", timeout=timeout)

    def st_clone(self, src: str, dst: str, timeout: Optional[float] = 120) -> Optional[str]:
        """Clone structure; uses 'src -> dst' form (spaces in names OK)."""
        return self.cmd(f"stClone {src} -> {dst}", timeout=timeout)

    def st_begin(self, name: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"stBegin {name}", timeout=timeout)

    def st_end(self, name: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"stEnd {name}", timeout=timeout)

    def st_upsert_elem(
        self,
        name: str,
        offset: int,
        elem_name: str,
        vtype: int,
        byte_size: Optional[int] = None,
        child_name: Optional[str] = None,
        child_start: Optional[int] = None,
        timeout: Optional[float] = None,
    ) -> Optional[str]:
        """Upsert element using pipe form (safe for spaces in names)."""
        off_hex = f"{int(offset):X}"
        fields = [name, off_hex, elem_name, str(int(vtype))]
        if byte_size is not None or child_name is not None or child_start is not None:
            fields.append("" if byte_size is None else str(int(byte_size)))
        if child_name is not None or child_start is not None:
            fields.append("" if child_name is None else child_name)
        if child_start is not None:
            fields.append(str(int(child_start)))
        return self.cmd("stUpsertElem " + "|".join(fields), timeout=timeout)

    def st_clear_elements(self, name: str, timeout: Optional[float] = 120) -> Optional[str]:
        return self.cmd(f"stClearElements {name}", timeout=timeout)

    def st_set_name(self, old: str, new: str, timeout: Optional[float] = None) -> Optional[str]:
        """Rename structure. Call st_end first if you used st_begin."""
        return self.cmd(f"stSetName {old} -> {new}", timeout=timeout)

    # --- memory / scan (thin wrappers; use raw cmd for anything else) ---

    def aob_scan(self, pattern: str, timeout: Optional[float] = 120) -> Optional[str]:
        return self.cmd(f"AOBScan {pattern}", timeout=timeout)

    def enum_modules(self, timeout: Optional[float] = 60) -> Optional[str]:
        return self.cmd("enumModules", timeout=timeout)

    def get_address(self, symbol: str, timeout: Optional[float] = None) -> Optional[str]:
        return self.cmd(f"getAddress {symbol}", timeout=timeout)

    def read_qword(self, addr_hex: Union[str, int], timeout: Optional[float] = None) -> Optional[str]:
        if isinstance(addr_hex, int):
            addr_hex = f"{addr_hex:X}"
        return self.cmd(f"readQword {addr_hex}", timeout=timeout)

    def run_script(self, code: str, timeout: Optional[float] = 60) -> Optional[str]:
        return self.cmd(f"runScript {code}", timeout=timeout)

    def run_script_safe(self, code: str, timeout: Optional[float] = 60) -> Optional[str]:
        """Like run_script but server rejects known-dangerous API strings."""
        return self.cmd(f"runScriptSafe {code}", timeout=timeout)


def main():
    parser = argparse.ArgumentParser(
        description="Cheat Engine remote control client"
    )
    parser.add_argument("--host", default="localhost",
                        help="Relay host (default: localhost)")
    parser.add_argument("--port", type=int, default=8888,
                        help="Relay TCP port (default: 8888)")
    parser.add_argument("--timeout", type=float, default=30,
                        help="Default socket timeout seconds (default: 30; use 120 for Active/AOB)")
    parser.add_argument("--cmd", help="Single command to execute")
    parser.add_argument("-i", "--interactive", action="store_true",
                        help="Interactive shell mode")
    args = parser.parse_args()

    ce = CERemote(args.host, args.port, args.timeout)

    if args.cmd:
        result = ce.cmd(args.cmd)
        if result is None:
            print("ERROR: No response from CE server", file=sys.stderr)
            sys.exit(1)
        print(result)
        sys.exit(0)

    if args.interactive:
        print(f"Connected to CE relay at {args.host}:{args.port} (timeout={args.timeout}s)")
        print("Type 'help' for available commands, 'quit' to exit.")
        while True:
            try:
                line = input("ce> ").strip()
            except EOFError:
                break
            if not line:
                continue
            if line == "quit" or line == "exit":
                break
            result = ce.cmd(line)
            if result is None:
                print("! ERROR: No response (is CE + relay running?)")
                continue
            print(result)
        return

    result = ce.cmd("ping")
    if result == "pong":
        print("CE relay is alive. Use --cmd to send commands or --interactive for shell.")
        print("Table helpers: from client import CERemote; see docs/TABLE-MIGRATE.md")
    else:
        print(f"WARNING: ping response unexpected: {result}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
