#!/bin/bash
# Port Conflict Detection Script
# Attempts to find an available ClickHouse HTTP port from the list: 8123, 8125, 8126

set -e

check_port() {
  local port=$1
  # Check if port is in use using ss (or netstat as fallback)
  if command -v ss &> /dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
      return 1  # Port in use
    else
      return 0  # Port available
    fi
  elif command -v netstat &> /dev/null; then
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
      return 1  # Port in use
    else
      return 0  # Port available
    fi
  else
    # If neither ss nor netstat is available, try using lsof
    if command -v lsof &> /dev/null; then
      if lsof -i ":$port" &> /dev/null; then
        return 1  # Port in use
      else
        return 0  # Port available
      fi
    else
      echo "ERROR: No port checking tool available (ss, netstat, or lsof)" >&2
      exit 1
    fi
  fi
}

# Try ports in order: 8123 (default), 8125, 8126
for port in 8123 8125 8126; do
  if check_port $port; then
    echo "$port"
    exit 0
  fi
done

# If we get here, all ports are in use
echo "ERROR: No available ports (tried 8123, 8125, 8126)" >&2
exit 1
