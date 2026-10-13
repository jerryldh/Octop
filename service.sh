#!/usr/bin/env bash
# ============================================================
#  Atour DataAgent 服务管理 (Linux / macOS)
#
#  用法:
#    ./service.sh start      安装(如需要)并启动服务
#    ./service.sh stop       停止服务
#    ./service.sh restart    重启服务
#    ./service.sh status     查看状态 + HTTP 健康检查
#    ./service.sh logs       跟踪日志
#    ./service.sh install    仅安装依赖(可选，一般由 start 自动完成)
#    ./service.sh help       显示帮助
#
#  原理: 直接封装 Octop 内置的 `octop service` 命令
#        Linux -> systemd (user unit / system unit)
#        macOS -> launchd
#        无需手写 unit 文件，由 CLI 自动生成与管理。
#
#  环境变量(可选):
#    OCTOP_HOME   数据目录        默认 $HOME/.octop
#    OCTOP_BIN    octop 可执行文件  默认自动探测
#    SERVICE_SCOPE 安装范围        user | system | auto(默认)
#    BIND_HOST    监听地址        默认沿用 config.json
#    BIND_PORT    监听端口        默认沿用 config.json
# ============================================================
set -euo pipefail

OCTOP_HOME="${OCTOP_HOME:-$HOME/.octop}"
SERVICE_SCOPE="${SERVICE_SCOPE:-auto}"
BIND_HOST="${BIND_HOST:-}"
BIND_PORT="${BIND_PORT:-}"
LOG_FILE="$OCTOP_HOME/logs/octop.log"

C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'

info()  { printf "%s\n" "  $*"; }
ok()    { printf "  ${C_GREEN}%s${C_RESET}\n" "$*"; }
warn()  { printf "  ${C_YELLOW}%s${C_RESET}\n" "$*"; }
err()   { printf "  ${C_RED}%s${C_RESET}\n" "$*" >&2; }

# ── 定位 octop 可执行文件 ─────────────────────────────────────
resolve_octop() {
  if [[ -n "${OCTOP_BIN:-}" && -x "$OCTOP_BIN" ]]; then
    printf "%s" "$OCTOP_BIN"; return 0
  fi
  local c
  for c in "$OCTOP_HOME/bin/octop" "$OCTOP_HOME/venv/bin/octop" \
           "$OCTOP_HOME/bin/octop.cmd" "$OCTOP_HOME/venv/Scripts/octop.exe"; do
    [[ -x "$c" ]] && { printf "%s" "$c"; return 0; }
  done
  if command -v octop >/dev/null 2>&1; then
    command -v octop; return 0
  fi
  return 1
}

OCTOP=""
need_octop() {
  if ! OCTOP="$(resolve_octop)"; then
    err "未找到 octop 可执行文件"
    info "请先安装:  bash scripts/install.sh"
    info "或手动指定:  export OCTOP_BIN=/path/to/octop"
    exit 1
  fi
}

# ── 健康检查(HTTP) ────────────────────────────────────────────
probe_http() {
  local host port url code
  host="$(read_bind_host)"
  port="$(read_bind_port)"
  url="http://${host}:${port}/api/health"
  if command -v curl >/dev/null 2>&1; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
  else
    code=""
  fi
  if [[ -n "$code" && "$code" != "000" ]]; then
    ok "health: HTTP $code   $url"
  else
    warn "health: 未能探测到 HTTP 响应 ($url)"
  fi
}

# 从 config.json 读监听地址/端口(不依赖 python 也能降级)
read_bind_host() {
  [[ -n "$BIND_HOST" ]] && { printf "%s" "$BIND_HOST"; return; }
  local cfg="$OCTOP_HOME/config.json" v=""
  if [[ -f "$cfg" ]]; then
    v="$(sed -n 's/.*"bind_host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -n1)"
  fi
  # 0.0.0.0 不可直连探测, 换回环地址
  [[ -z "$v" || "$v" == "0.0.0.0" ]] && v="127.0.0.1"
  printf "%s" "$v"
}
read_bind_port() {
  [[ -n "$BIND_PORT" ]] && { printf "%s" "$BIND_PORT"; return; }
  local cfg="$OCTOP_HOME/config.json" v=""
  if [[ -f "$cfg" ]]; then
    v="$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]\{1,5\}\).*/\1/p' "$cfg" | head -n1)"
  fi
  [[ -z "$v" ]] && v="8088"
  printf "%s" "$v"
}

scope_args() {
  printf -- "--scope %s" "$SERVICE_SCOPE"
}

# ── 命令实现 ──────────────────────────────────────────────────
cmd_start() {
  need_octop
  printf "%s\n" "============================================================"
  printf "%s\n" "  Atour DataAgent - start"
  printf "%s\n" "============================================================"
  info "octop      : $OCTOP"
  info "数据目录   : $OCTOP_HOME"
  info "安装范围   : $SERVICE_SCOPE"
  info "日志文件   : $LOG_FILE"
  printf "%s\n" "------------------------------------------------------------"

  local args=()
  [[ -n "$BIND_HOST" ]] && args+=(--host "$BIND_HOST")
  [[ -n "$BIND_PORT" ]] && args+=(--port "$BIND_PORT")
  # shellcheck disable=SC2086
  "$OCTOP" service start ${args[@]+"${args[@]}"} $(scope_args)
}

cmd_stop() {
  need_octop
  printf "%s\n" "============================================================"
  printf "%s\n" "  Atour DataAgent - stop"
  printf "%s\n" "============================================================"
  # shellcheck disable=SC2086
  "$OCTOP" service stop $(scope_args)
}

cmd_restart() {
  need_octop
  printf "%s\n" "============================================================"
  printf "%s\n" "  Atour DataAgent - restart"
  printf "%s\n" "============================================================"
  # shellcheck disable=SC2086
  "$OCTOP" service restart $(scope_args)
}

cmd_status() {
  need_octop
  printf "%s\n" "============================================================"
  printf "%s\n" "  Atour DataAgent - status"
  printf "%s\n" "============================================================"
  info "octop      : $OCTOP"
  info "数据目录   : $OCTOP_HOME"
  info "安装范围   : $SERVICE_SCOPE"
  printf "%s\n" "------------------------------------------------------------"
  # shellcheck disable=SC2086
  "$OCTOP" service status $(scope_args) || true
  printf "%s\n" "------------------------------------------------------------"
  probe_http
}

cmd_logs() {
  local journal
  if command -v journalctl >/dev/null 2>&1; then
    if [[ "$SERVICE_SCOPE" == "user" ]]; then
      journal="journalctl --user -u octop -f -n 60"
    else
      journal="journalctl -u octop -f -n 60"
    fi
    if [[ -f "$LOG_FILE" ]]; then
      info "同时可直接查看: tail -f $LOG_FILE"
    fi
    info "执行: $journal"
    printf "%s\n" "------------------------------------------------------------"
    # shellcheck disable=SC2086
    eval "$journal"
  elif [[ -f "$LOG_FILE" ]]; then
    info "跟踪日志: $LOG_FILE   (Ctrl+C 退出)"
    printf "%s\n" "------------------------------------------------------------"
    tail -n 60 -f "$LOG_FILE"
  else
    warn "日志文件尚未生成: $LOG_FILE"
    warn "若为 systemd 安装, 可尝试: journalctl -u octop -n 80 --no-pager"
  fi
}

cmd_install() {
  printf "%s\n" "============================================================"
  printf "%s\n" "  Atour DataAgent - install (dependencies)"
  printf "%s\n" "============================================================"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$script_dir/scripts/install.sh" ]]; then
    info "使用仓库自带安装脚本: $script_dir/scripts/install.sh"
    bash "$script_dir/scripts/install.sh" "$@"
  else
    warn "未找到 scripts/install.sh"
    info "请手动安装:  bash scripts/install.sh"
  fi
}

cmd_help() {
  cat <<EOF
============================================================
  Atour DataAgent 服务管理  Linux / macOS
============================================================
  用法:
    ./service.sh start      安装(如需要)并启动服务(后台, systemd/launchd)
    ./service.sh stop       停止服务
    ./service.sh restart    重启服务
    ./service.sh status     查看状态 + HTTP 健康检查
    ./service.sh logs       跟踪日志(journalctl / 日志文件)
    ./service.sh install    仅安装依赖
    ./service.sh help       显示本帮助

  说明:
    Linux 使用 systemd, macOS 使用 launchd, 由 \`octop service\` 自动管理。
    root 用户 -> 系统级 unit (/etc/systemd/system)
    普通用户  -> 用户级 unit (~/.config/systemd/user)

  环境变量:
    OCTOP_HOME=$OCTOP_HOME
    OCTOP_BIN=${OCTOP_BIN:-<自动探测>}
    SERVICE_SCOPE=$SERVICE_SCOPE   (user | system | auto)
    BIND_HOST=${BIND_HOST:-<沿用 config.json>}
    BIND_PORT=${BIND_PORT:-<沿用 config.json>}
============================================================
EOF
}

# ── 分发 ──────────────────────────────────────────────────────
CMD="${1:-help}"
case "$CMD" in
  start)         shift; cmd_start "$@" ;;
  stop)          shift; cmd_stop "$@" ;;
  restart)       shift; cmd_restart "$@" ;;
  status)        shift; cmd_status "$@" ;;
  logs|log)      shift; cmd_logs "$@" ;;
  install)       shift; cmd_install "$@" ;;
  help|-h|--help) cmd_help ;;
  *)             err "未知命令: $CMD"; echo; cmd_help; exit 1 ;;
esac
