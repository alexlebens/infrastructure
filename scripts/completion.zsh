# ==============================================================================
# Kubernetes Scripts Tab Completion (Zsh)
#
# Provides namespace and option tab completion for:
#   - examine-namespace
#   - resource-capacity
#   - get-images
#   - cleanup-pgsql-local
#   - cnpg-remediator
#
# Features:
#   - 30-second cache in $TMPDIR for instant response without kubectl API lag
#   - Supports command invocation from PATH, ./<script>, or relative paths
#
# Usage:
#   Add to ~/.zshrc:
#     source /Users/alexlebens/projects/infrastructure/scripts/completion.zsh
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

# Scripts where 1st argument is a namespace (examine-namespace, resource-capacity, get-images)
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

# Register completions for commands, relative paths, and script dir paths
compdef _k8s_script_ns_arg examine-namespace ./examine-namespace scripts/examine-namespace ./scripts/examine-namespace
compdef _k8s_script_ns_arg resource-capacity ./resource-capacity scripts/resource-capacity ./scripts/resource-capacity
compdef _k8s_script_ns_arg get-images ./get-images scripts/get-images ./scripts/get-images
compdef _cleanup_pgsql_local cleanup-pgsql-local ./cleanup-pgsql-local scripts/cleanup-pgsql-local ./scripts/cleanup-pgsql-local
compdef _cnpg_remediator cnpg-remediator ./cnpg-remediator scripts/cnpg-remediator ./scripts/cnpg-remediator
