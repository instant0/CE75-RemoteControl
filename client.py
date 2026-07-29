"""
WSL/Linux client for Cheat Engine remote control via TCP relay.

Usage:
    # Send a single command
    python client.py --cmd "readBytes 7FF12345678 64"

    # Interactive mode
    python client.py --interactive

    # Use as module
    from client import CERemote
    ce = CERemote("localhost", 8888)
    result = ce.cmd("readQword 7FF12345678")
"""
import argparse
import socket
import struct
import sys


class CERemote:
    def __init__(self, host="localhost", port=8888, timeout=30):
        self.host = host
        self.port = port
        self.timeout = timeout

    def cmd(self, command):
        with socket.create_connection((self.host, self.port), self.timeout) as s:
            s.settimeout(self.timeout)
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


def main():
    parser = argparse.ArgumentParser(
        description="Cheat Engine remote control client"
    )
    parser.add_argument("--host", default="localhost",
                        help="Relay host (default: localhost)")
    parser.add_argument("--port", type=int, default=8888,
                        help="Relay TCP port (default: 8888)")
    parser.add_argument("--timeout", type=int, default=30,
                        help="Connection timeout in seconds (default: 30)")
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
        print(f"Connected to CE relay at {args.host}:{args.port}")
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
    else:
        print(f"WARNING: ping response unexpected: {result}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
