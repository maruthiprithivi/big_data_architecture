#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
trap 'printf "Lab command failed. Check: docker compose logs --tail 30\n" >&2' ERR

case "${1:-}" in preflight|setup|postflight) ;; *) fail "Use: bash lab.sh preflight|setup|postflight" ;; esac
command -v docker >/dev/null || fail "Install and start Docker Desktop, then reopen Terminal."
docker compose version >/dev/null || fail "Docker Compose v2 is required; update Docker Desktop."
engine=$(docker info --format '{{.OSType}} {{.Architecture}} {{.MemTotal}}') || fail "Start Docker Desktop and wait for the engine."
read -r engine_os engine_arch engine_memory <<< "$engine"
[[ "$engine_os" == linux ]] || fail "Switch Docker Desktop to Linux containers."
case "$engine_arch" in aarch64|arm64|x86_64|amd64) ;; *) fail "Supported CPU architectures: ARM64 and AMD64." ;; esac
[[ "$engine_memory" =~ ^[0-9]+$ ]] || fail "Could not read Docker memory allocation."
(( engine_memory >= 3896508416 )) || fail "Allocate at least 4 GiB to Docker Desktop; reported memory must cover the 3716 MiB workload."
docker compose config --quiet
printf 'PASS preflight: Linux/%s, Compose, configuration, memory covers 3716 MiB workload.\n' "$engine_arch"

case "$1" in
  setup)
    printf 'Starting the lab. First run downloads images and a 1.1 GB model.\n'
    docker compose up --build -d
    docker compose exec -T app python verify.py --ready
    printf 'READY: http://localhost:8090\n'
    ;;
  postflight)
    docker compose exec -T app python verify.py
    mkdir -p results
    docker compose cp app:/tmp/campusstream-e2e.json results/postflight.json
    docker compose cp app:/tmp/campusstream-dashboard.html results/dashboard.html
    printf 'PASS postflight. Saved results/postflight.json and results/dashboard.html\n'
    ;;
esac
