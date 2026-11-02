#!/usr/bin/env bash
# Sourceable logging library for mise tasks and scripts.
#
# Provides consistent, colorized, level-aware logging functions using printf.
# Respects NO_COLOR, TERM=dumb, and non-interactive terminal streams.
#
# Usage:
#   source "${REPO_ROOT}/.mise/lib/log.sh"
#   log_step "Building dependencies..."
#   log_info "Target cluster: ${CLUSTER}"
#   log_success "Build completed successfully!"
#   log_warn "Outdated dependencies detected"
#   log_error "Chart validation failed"
#   log_fatal "Directory not found" [exit_code]
#   log_badge "OK" "green"
#   log_badge "FAIL" "red"

# Prevent double-sourcing
if [[ -n "${_MISE_LIB_LOG_LOADED:-}" ]]; then
  return 0
fi
_MISE_LIB_LOG_LOADED=1

# Color support detection (respects NO_COLOR, dumb terminals, and non-TTY)
_setup_colors() {
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_DIM="\033[2m"
    COLOR_RED="\033[31m"
    COLOR_BOLD_RED="\033[1;31m"
    COLOR_GREEN="\033[32m"
    COLOR_BOLD_GREEN="\033[1;32m"
    COLOR_YELLOW="\033[33m"
    COLOR_BOLD_YELLOW="\033[1;33m"
    COLOR_CYAN="\033[36m"
    COLOR_BOLD_CYAN="\033[1;36m"
  else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_RED=""
    COLOR_BOLD_RED=""
    COLOR_GREEN=""
    COLOR_BOLD_GREEN=""
    COLOR_YELLOW=""
    COLOR_BOLD_YELLOW=""
    COLOR_CYAN=""
    COLOR_BOLD_CYAN=""
  fi
}
_setup_colors

# Major step / phase header: ">> Building dependencies..."
log_step() {
  printf "\n"
  printf "%b%b>> %s%b\n" "${COLOR_BOLD}" "${COLOR_CYAN}" "$*" "${COLOR_RESET} ..."
}

# Sub-step or detail under a step: "   Added repo..."
log_info() {
  printf "   %s\n" "$*"
}

# Success indicator: "✓ All charts built successfully"
log_success() {
  printf "\n"
  printf "%b%b✓ %s%b\n" "${COLOR_BOLD}" "${COLOR_GREEN}" "$*" "${COLOR_RESET}"
}

# Warning message to stderr: "! Warning: ..."
log_warn() {
  printf "%b%b! Warning: %s%b\n" "${COLOR_BOLD}" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}" >&2
}

# Error message to stderr: "✗ Error: ..."
log_error() {
  printf "%b%b✗ Error: %s%b\n" "${COLOR_BOLD}" "${COLOR_RED}" "$*" "${COLOR_RESET}" >&2
}

# Fatal error: logs error to stderr and exits with given or default code
log_fatal() {
  local code=1
  if [[ $# -ge 2 ]] && [[ "${!#}" =~ ^[0-9]+$ ]]; then
    code="${!#}"
    set -- "${@:1:$#-1}"
  fi
  printf "\n"
  printf "%b%b✗ Fatal: %s%b\n" "${COLOR_BOLD}" "${COLOR_RED}" "$*" "${COLOR_RESET}" >&2
  exit "${code}"
}

# Debug message: printed only when DEBUG=1 or LOG_LEVEL=debug
log_debug() {
  if [[ "${DEBUG:-0}" = "1" ]] || [[ "${LOG_LEVEL:-}" = "debug" ]]; then
    printf "%b[DEBUG] %s%b\n" "${COLOR_DIM}" "$*" "${COLOR_RESET}"
  fi
}

# Status badge generator, e.g. [OK] (green), [FAIL] (red)
log_badge() {
  local text="$1"
  local color="${2:-green}"
  case "$color" in
    red|fail) printf "%b[%s]%b" "${COLOR_BOLD_RED}" "$text" "${COLOR_RESET}" ;;
    green|ok) printf "%b[%s]%b" "${COLOR_BOLD_GREEN}" "$text" "${COLOR_RESET}" ;;
    yellow|warn) printf "%b[%s]%b" "${COLOR_BOLD_YELLOW}" "$text" "${COLOR_RESET}" ;;
    cyan|info) printf "%b[%s]%b" "${COLOR_BOLD_CYAN}" "$text" "${COLOR_RESET}" ;;
    *) printf "[%s]" "$text" ;;
  esac
}

# Section divider: "----"
log_divider() {
  printf "\n----\n"
}
