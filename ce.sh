#!/bin/bash
# Convenience wrapper for CE remote client.
#
# Usage:
#   ./ce.sh                     # interactive shell
#   ./ce.sh ping                # bare words → --cmd "…"
#   ./ce.sh "readBytes AA 16"
#   ./ce.sh --host 192.168.1.2 --cmd "tableStatus"
#   ./ce.sh -i
#   ./ce.sh --timeout 120 --cmd "AOBScan 90 90"

DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$DIR/client.py"

if [[ $# -eq 0 ]]; then
  exec python3 "$CLIENT" -i
fi

# Client flags / options: pass through unchanged
if [[ "$1" == -* ]]; then
  exec python3 "$CLIENT" "$@"
fi

# Convenience: ./ce.sh ping  →  --cmd "ping"
exec python3 "$CLIENT" --cmd "$*"
