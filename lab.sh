#!/usr/bin/env bash
# lab.sh -- the only command a workshop participant needs.
#
#   ./lab.sh up            build + start the container lab (one-time)
#   ./lab.sh levels        list the escape levels
#   ./lab.sh start <n>     (re)create the vulnerable container for level <n>
#   ./lab.sh enter <n>     drop into a shell inside level <n>'s container
#   ./lab.sh submit <n> <flag>   check a flag you captured
#   ./lab.sh reset <n>     rebuild level <n> from scratch
#   ./lab.sh status        show what's running
#   ./lab.sh down          stop and wipe the whole lab

set -euo pipefail

# Disable MSYS path conversion on Windows, so that absolute paths like
# /c/Users/... are passed through to docker.exe as-is. Otherwise, MSYS
# would convert them to C:\Users\... which docker.exe doesn't understand.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD="$ROOT/.build"
FLAGS_SRC="$ROOT/lab/flags"
ANSWERS="$BUILD/answers"
LEVELS="1 2 3 4 5 6 7"
COMPOSE="docker compose"

c_grn=$'\033[32m'; c_red=$'\033[31m'; c_ylw=$'\033[33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s!%s %s\n' "$c_ylw" "$c_off" "$*"; }
die()  { printf '%s✗ %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

need_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed / not on PATH."
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Is Docker running?"
}

title() {
  case "$1" in
    1) echo "Bind-mounted host path      (-v /:/mnt/host)";;
    2) echo "Mounted Docker socket       (-v /var/run/docker.sock)";;
    3) echo "Exposed Docker API over TCP (dockerd on :2375)";;
    4) echo "Privileged + host PID ns    (--privileged --pid=host)";;
    5) echo "No --privileged, just caps  (--cap-add=SYS_ADMIN,SYS_PTRACE --pid=host)";;
    6) echo "Unauth Engine API, stock container (CVE-2025-9074)";;
    7) echo "One capability only         (CAP_DAC_READ_SEARCH / open_by_handle_at)";;
  esac
}

gen_flags() {
  mkdir -p "$FLAGS_SRC" "$BUILD"
  : > "$ANSWERS"
  local names=( [1]=bind_mount [2]=docker_socket [3]=tcp_api [4]=privileged_pidhost [5]=cap_sys_admin [6]=unauth_engine_api [7]=dac_read_search )
  for n in $LEVELS; do
    local rnd; rnd="$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    local flag="ESD26{${names[$n]}_${rnd}}"
    printf '%s\n' "$flag" > "$FLAGS_SRC/level${n}.txt"
    chmod 600 "$FLAGS_SRC/level${n}.txt"
    printf '%s %s\n' "$n" "$flag" >> "$ANSWERS"
  done
}

host_exec()  { $COMPOSE exec -T host "$@"; }
host_ready() { host_exec docker info >/dev/null 2>&1; }

wait_for_engine() {
  printf 'Waiting for the inner Docker engine'
  for _ in $(seq 1 60); do
    if host_ready; then printf '\n'; ok "inner engine is up"; return 0; fi
    printf '.'; sleep 1
  done
  printf '\n'; die "inner Docker engine did not come up in time (check: $COMPOSE logs host)"
}

cmd_up() {
  need_docker
  say "${c_dim}Generating fresh, unique flags for this run...${c_off}"
  gen_flags
  say "${c_dim}Building the vulnerable image on your machine...${c_off}"
  docker build -q -t vuln:latest lab/vulnerable >/dev/null
  say "${c_dim}Saving it for offline load into the lab...${c_off}"
  docker save vuln:latest -o .build/vuln.tar
  say "${c_dim}Building + starting the DinD host...${c_off}"
  $COMPOSE up -d --build
  wait_for_engine
  say "${c_dim}Loading the vulnerable image into the lab engine...${c_off}"
  # .build is bind-mounted read-only at /mnt/build inside the host (see
  # docker-compose.yml), so the saved image tar loads directly. This works the
  # same on Linux/macOS/Windows -- no stdin piping (which PowerShell corrupts)
  # and no `docker cp` (which dind's private mount namespace hides).
  host_exec docker load -i /mnt/build/vuln.tar >/dev/null
  ok "lab is ready"
  echo
  cmd_levels
  echo
  say "Next:  ${c_grn}./lab.sh enter 1${c_off}   then try to escape and read the flag."
}

cmd_levels() {
  say "Escape levels:"
  for n in $LEVELS; do printf '  %s  %s\n' "$n" "$(title "$n")"; done
}

cmd_start() {
  need_docker
  local n="${1:?usage: lab.sh start <level>}"
  host_ready || die "lab is not running -- run './lab.sh up' first."
  host_exec /opt/lab/launch.sh "$n"
}

cmd_enter() {
  need_docker
  local n="${1:?usage: lab.sh enter <level>}"
  host_ready || die "lab is not running -- run './lab.sh up' first."
  # (re)create the level if it isn't already running, then attach.
  if ! host_exec docker inspect -f '{{.State.Running}}' "level${n}" 2>/dev/null | grep -q true; then
    host_exec /opt/lab/launch.sh "$n"
  fi
  say "${c_dim}Entering level ${n}. Goal: escape this container and read the host's /flags/level${n}.txt${c_off}"
  say "${c_dim}(from in here it may be under /mnt/host/... or need a breakout first -- see the guide). Type 'exit' to leave.${c_off}"
  # Pick the shell up front. Do NOT use 'bash || sh': that fallback also fires
  # when bash simply exits non-zero (e.g. your last command failed), dropping
  # you into a second shell in the SAME container instead of back on your laptop.
  local shell=/bin/bash
  host_exec docker exec "level${n}" test -x /bin/bash >/dev/null 2>&1 || shell=/bin/sh
  $COMPOSE exec host docker exec -it "level${n}" "$shell"
}

cmd_reset() {
  need_docker
  local n="${1:?usage: lab.sh reset <level>}"
  host_exec docker rm -f "level${n}" >/dev/null 2>&1 || true
  cmd_start "$n"
  ok "level ${n} reset"
}

cmd_submit() {
  local n="${1:?usage: lab.sh submit <level> <flag>}"; shift
  local got="${*:?usage: lab.sh submit <level> <flag>}"
  [ -f "$ANSWERS" ] || die "no answers file -- run './lab.sh up' first."
  local want; want="$(awk -v n="$n" '$1==n{print $2}' "$ANSWERS")"
  [ -n "$want" ] || die "unknown level: $n"
  if [ "$got" = "$want" ]; then
    ok "Correct! Level ${n} captured: ${want}"
  else
    die "Not quite. That flag doesn't match level ${n}. Keep going!"
  fi
}

cmd_status() {
  need_docker
  if host_ready; then
    ok "lab host is up"
    host_exec docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' || true
  else
    warn "lab host is not running"
  fi
}

cmd_down() {
  need_docker
  $COMPOSE down -v
  ok "lab stopped and wiped"
}

case "${1:-}" in
  up)     shift; cmd_up "$@";;
  levels) shift; cmd_levels "$@";;
  start)  shift; cmd_start "$@";;
  enter)  shift; cmd_enter "$@";;
  reset)  shift; cmd_reset "$@";;
  submit) shift; cmd_submit "$@";;
  status) shift; cmd_status "$@";;
  down)   shift; cmd_down "$@";;
  ""|help|-h|--help)
    grep -E '^#( |$)' "$0" | sed -E 's/^# ?//' | sed -n '1,20p';;
  *) die "unknown command: $1  (try: ./lab.sh help)";;
esac
