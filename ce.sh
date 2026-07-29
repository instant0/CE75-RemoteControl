#!/bin/bash
# Convenience wrapper for CE remote client
# Usage: ./ce.sh <command>
#   ./ce.sh ping
#   ./ce.sh "readBytes 7FF12345678 64"
#   ./ce.sh --interactive

DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/client.py" --cmd "$*"
