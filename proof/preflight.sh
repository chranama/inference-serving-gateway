#!/usr/bin/env bash

require_ports_free() {
  local label="$1"
  shift

  local busy=()
  local port
  for port in "$@"; do
    if python3 - "${port}" <<'PY' >/dev/null 2>&1
import socket
import sys

port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.settimeout(0.2)
    sys.exit(0 if sock.connect_ex(("127.0.0.1", port)) == 0 else 1)
PY
    then
      busy+=("${port}")
    fi
  done

  if ((${#busy[@]})); then
    echo "${label} cannot start because localhost port(s) are already in use: ${busy[*]}" >&2
    echo "Stop the conflicting process or rerun with alternate port environment variables when supported." >&2
    exit 1
  fi
}
