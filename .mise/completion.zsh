# ==============================================================================
# Mise & Kubernetes Scripts Tab Completion (Zsh)
#
# Provides tab completion for:
#   - mise run kube:status <namespace>
#   - mise run kube:resource-capacity <namespace>
#   - mise run kube:get-images [namespace]
#   - mise run app:cnpg-reset [namespace]
#   - mise run app:cnpg-remediator
#   - mise run app:tofu-adopt-garage-bucket [app-name]
#   - mise run check-chart <chart>
#   - mise run helm:* [chart...]
#
# Features:
#   - 30-second cache in $TMPDIR for instant response without kubectl API lag
#   - Dynamic Helm chart discovery from clusters/<cluster>/helm/
#   - Supports command invocation from PATH, ./<script>, or mise run <task>
#
# Usage:
#   Add to ~/.zshrc:
#     source /Users/alexlebens/projects/infrastructure/.mise/completion.zsh
# ==============================================================================

# Ensure zsh completion engine is initialized
if ! whence compdef >/dev/null 2>&1; then
  autoload -Uz compinit && compinit
fi

# Fetch and cache namespaces with a 30-second TTL
_k8s_get_namespaces() {
  local cache_dir="${TMPDIR:-/tmp}"
  local cache_file="${cache_dir%/}/k8s_ns_cache_${USER:-default}"
  local refresh=0

  if [[ ! -f "$cache_file" ]]; then
    refresh=1
  else
    local mtime=0
    if [[ "$OSTYPE" == darwin* ]]; then
      mtime=$(stat -f %m "$cache_file" 2>/dev/null || echo 0)
    else
      mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    fi
    local now
    now=$(date +%s)
    if (( now - mtime > 30 )); then
      refresh=1
    fi
  fi

  if (( refresh )); then
    local ns_output
    ns_output=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    if [[ -n "$ns_output" ]]; then
      printf "%s\n" "$ns_output" > "$cache_file"
    fi
  fi

  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
  fi
}

_k8s_namespaces_tag() {
  local -a namespaces
  namespaces=(${(f)"$(_k8s_get_namespaces)"})
  if (( ${#namespaces[@]} > 0 )); then
    _describe 'kubernetes namespace' namespaces
  fi
}

# Fetch Helm charts in the repository
_k8s_get_charts() {
  local cluster="${CLUSTER:-cl01tl}"
  local repo_root="${MISE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  if [[ -n "$repo_root" && -d "$repo_root/clusters/$cluster/helm" ]]; then
    find "$repo_root/clusters/$cluster/helm" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/Chart.yaml' ';' -exec basename '{}' ';' 2>/dev/null | sort
  fi
}

_helm_charts_tag() {
  local -a charts
  charts=(${(f)"$(_k8s_get_charts)"})
  if (( ${#charts[@]} > 0 )); then
    _describe 'helm chart' charts
  fi
}

# Scripts where 1st argument is a namespace
_k8s_script_ns_arg() {
  _arguments '1:namespace:_k8s_namespaces_tag'
}

# cleanup-pgsql-local [OPTIONS] [NAMESPACE]
_cleanup_pgsql_local() {
  _arguments -s -S \
    '(-n --namespace)'{-n,--namespace}'[Target namespace]:namespace:_k8s_namespaces_tag' \
    '(-d --dry-run)'{-d,--dry-run}'[Preview actions without deleting any resources]' \
    '(-h --help)'{-h,--help}'[Show help message]' \
    '1:namespace:_k8s_namespaces_tag'
}

# cnpg-remediator [OPTIONS]
_cnpg_remediator() {
  _arguments -s -S \
    '(-n --namespace)'{-n,--namespace}'[Scan only a specific namespace]:namespace:_k8s_namespaces_tag' \
    '(-r --min-restarts)'{-r,--min-restarts}'[Minimum restart count required]:min restarts:' \
    '(-c --cooldown)'{-c,--cooldown}'[Cooldown window in seconds]:seconds:' \
    '(-m --max-clusters)'{-m,--max-clusters}'[Max clusters to remediate per run]:max clusters:' \
    '(-d --dry-run)'{-d,--dry-run}'[Report actions without deleting any resources]' \
    '(-h --help)'{-h,--help}'[Show help message]'
}

# Direct task completions
compdef _k8s_script_ns_arg .mise/tasks/kube/status
compdef _k8s_script_ns_arg .mise/tasks/kube/resource-capacity
compdef _k8s_script_ns_arg .mise/tasks/kube/get-images
compdef _cleanup_pgsql_local .mise/tasks/app/cnpg-reset
compdef _helm_charts_tag .mise/tasks/app/tofu-adopt-garage-bucket

# ── Mise Task Arguments Completion ──────────────────────────────────────────
# Wraps _mise completion to complete task arguments (namespaces, charts)
if whence _mise >/dev/null 2>&1; then
  _mise_with_task_args() {
    # Check if we are completing arguments after 'mise r' or 'mise run'
    local words=("${(@s/ /)BUFFER}")
    if [[ "${words[1]}" == "mise" && ("${words[2]}" == "run" || "${words[2]}" == "r") ]]; then
      local task="${words[3]}"
      case "$task" in
        kube:status|kube:resource-capacity|kube:get-images|app:cnpg-reset)
          _k8s_namespaces_tag && return 0
          ;;
        check-chart|render|helm:*|app:tofu-adopt-garage-bucket)
          _helm_charts_tag && return 0
          ;;
      esac
    fi
    # Fall back to default mise completion
    _mise "$@"
  }
  compdef _mise_with_task_args mise
fi
