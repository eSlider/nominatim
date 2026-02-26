#!/usr/bin/env bash
set -euo pipefail

# Low-latency host tuning helper for Nominatim.
# By default it only reports current values.
# Use --apply to apply runtime tuning via sysfs/sysctl (requires root/sudo).

MODE="status"
if [[ "${1:-}" == "--apply" ]]; then
    MODE="apply"
elif [[ "${1:-}" == "--status" || -z "${1:-}" ]]; then
    MODE="status"
else
    echo "Usage: $0 [--status|--apply]" >&2
    exit 1
fi

require_root_for_apply() {
    if [[ "$MODE" == "apply" && "${EUID:-$(id -u)}" -ne 0 ]]; then
        echo "Apply mode needs root. Re-run with sudo:" >&2
        echo "  sudo $0 --apply" >&2
        exit 1
    fi
}

thp_file() {
    local name="$1"
    local path="/sys/kernel/mm/transparent_hugepage/$name"
    [[ -f "$path" ]] && echo "$path"
}

show_thp() {
    local enabled defrag
    enabled="$(thp_file enabled || true)"
    defrag="$(thp_file defrag || true)"
    [[ -n "$enabled" ]] && echo "THP enabled: $(<"$enabled")"
    [[ -n "$defrag" ]] && echo "THP defrag : $(<"$defrag")"
}

apply_thp() {
    local enabled defrag
    enabled="$(thp_file enabled || true)"
    defrag="$(thp_file defrag || true)"
    [[ -n "$enabled" ]] && echo never >"$enabled"
    [[ -n "$defrag" ]] && echo never >"$defrag"
}

show_cpu_governor() {
    local f first=""
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [[ -f "$f" ]] || continue
        if [[ -z "$first" ]]; then
            first="$(<"$f")"
        fi
    done
    if [[ -n "$first" ]]; then
        echo "CPU governor sample: $first"
    else
        echo "CPU governor sample: unavailable (cpufreq not exposed)"
    fi
}

apply_cpu_governor() {
    local f
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [[ -f "$f" ]] || continue
        echo performance >"$f" || true
    done
}

show_sysctl_values() {
    echo "vm.swappiness: $(sysctl -n vm.swappiness 2>/dev/null || echo unavailable)"
    echo "vm.dirty_background_bytes: $(sysctl -n vm.dirty_background_bytes 2>/dev/null || echo unavailable)"
    echo "vm.dirty_bytes: $(sysctl -n vm.dirty_bytes 2>/dev/null || echo unavailable)"
}

apply_sysctl_values() {
    sysctl -w vm.swappiness=1 >/dev/null
    sysctl -w vm.dirty_background_bytes=268435456 >/dev/null
    sysctl -w vm.dirty_bytes=1073741824 >/dev/null
}

print_recommended() {
    cat <<'EOF'
Recommended runtime targets:
  - THP: never
  - CPU governor: performance
  - vm.swappiness: 1
  - vm.dirty_background_bytes: 268435456 (256 MiB)
  - vm.dirty_bytes: 1073741824 (1 GiB)
EOF
}

main() {
    require_root_for_apply

    echo "=== Nominatim low-latency tuning ($MODE) ==="
    print_recommended
    echo ""

    if [[ "$MODE" == "apply" ]]; then
        apply_thp
        apply_cpu_governor
        apply_sysctl_values
        echo "Applied runtime tuning."
        echo ""
    fi

    echo "Current values:"
    show_thp
    show_cpu_governor
    show_sysctl_values
}

main "$@"
