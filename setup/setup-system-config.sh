#!/usr/bin/env bash
# =============================================================================
# es-sysconfig.sh
# System configuration for Elasticsearch on Ubuntu (production)
#
# Covers:
#   - Virtual memory (vm.max_map_count)
#   - Swap (disable)
#   - File descriptors (nofile)
#   - Max threads (nproc)
#   - JNA temp directory
#   - TCP retransmission timeout
#   - Elasticsearch service user & directory permissions
#
# Usage:
#   sudo bash es-sysconfig.sh [--user <es-user>] [--dry-run]
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
ES_USER="elasticsearch"
ES_GROUP="elasticsearch"
ES_HOME="/usr/share/elasticsearch"
ES_DATA="/var/lib/elasticsearch"
ES_LOG="/var/log/elasticsearch"
ES_CONF="/etc/elasticsearch"
DRY_RUN=false

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${CYAN}==> $*${NC}"; }

run() {
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@"
  fi
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)    ES_USER="$2";  shift 2 ;;
    --dry-run) DRY_RUN=true;  shift   ;;
    *)
      log_error "Unknown argument: $1"
      echo "Usage: sudo bash $0 [--user <es-user>] [--dry-run]"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root (sudo)."
  exit 1
fi

OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
if [[ "$OS_ID" != "ubuntu" ]]; then
  log_warn "This script is designed for Ubuntu. Detected: $OS_ID — proceed with caution."
fi

UBUNTU_VERSION=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
log_info "Ubuntu version : $UBUNTU_VERSION"
log_info "Elasticsearch user : $ES_USER"
$DRY_RUN && log_warn "DRY-RUN mode — no changes will be applied."

# =============================================================================
# 1. Create Elasticsearch service user (if not exists)
# =============================================================================
log_section "1. Service user: $ES_USER"

if id "$ES_USER" &>/dev/null; then
  log_info "User '$ES_USER' already exists — skipping."
else
  run "groupadd --system $ES_GROUP"
  run "useradd \
    --system \
    --no-create-home \
    --shell /sbin/nologin \
    --gid $ES_GROUP \
    --comment 'Elasticsearch service user' \
    $ES_USER"
  log_info "User '$ES_USER' created."
fi

# =============================================================================
# 2. Directory structure & permissions
# =============================================================================
log_section "2. Directories & permissions"

for DIR in "$ES_DATA" "$ES_LOG" "$ES_CONF"; do
  if [[ ! -d "$DIR" ]]; then
    run "mkdir -p $DIR"
    log_info "Created: $DIR"
  fi
  run "chown -R $ES_USER:$ES_GROUP $DIR"
  run "chmod 750 $DIR"
  log_info "Permissions set: $DIR → $ES_USER:$ES_GROUP (750)"
done

# =============================================================================
# 3. Disable swap
# =============================================================================
log_section "3. Disable swap"

# Disable immediately
run "swapoff -a"
log_info "Swap disabled (runtime)."

# Persist across reboots — comment out swap entries in /etc/fstab
if grep -qE '^\s*[^#].+\bswap\b' /etc/fstab; then
  run "sed -i.bak -E 's|^(\s*[^#].+\bswap\b)|# \1  # disabled by es-sysconfig|' /etc/fstab"
  log_info "Swap entries commented out in /etc/fstab (backup: /etc/fstab.bak)."
else
  log_info "No active swap entries found in /etc/fstab."
fi

# =============================================================================
# 4. Virtual memory — vm.max_map_count
# =============================================================================
log_section "4. Virtual memory (vm.max_map_count)"

SYSCTL_CONF="/etc/sysctl.d/99-elasticsearch.conf"

apply_sysctl() {
  local KEY="$1"
  local VALUE="$2"

  if grep -qE "^${KEY}\s*=" "$SYSCTL_CONF" 2>/dev/null; then
    run "sed -i -E 's|^${KEY}\s*=.*|${KEY} = ${VALUE}|' $SYSCTL_CONF"
  else
    run "echo '${KEY} = ${VALUE}' >> $SYSCTL_CONF"
  fi
  run "sysctl -w ${KEY}=${VALUE}"
  log_info "Set: ${KEY} = ${VALUE}"
}

[[ -f "$SYSCTL_CONF" ]] || run "touch $SYSCTL_CONF"

# Elasticsearch requires at least 262144
apply_sysctl "vm.max_map_count"       "262144"

# Reduce swappiness to near-zero (complement to swapoff)
apply_sysctl "vm.swappiness"          "1"

# TCP retransmission timeout (reduce from default 15 → 5 retries)
# Helps Elasticsearch detect failed nodes faster
apply_sysctl "net.ipv4.tcp_retries2"  "5"

run "sysctl -p $SYSCTL_CONF"
log_info "sysctl settings applied from $SYSCTL_CONF"

# =============================================================================
# 5. File descriptors & threads — /etc/security/limits.d
# =============================================================================
log_section "5. File descriptors & max threads (limits.d)"

LIMITS_CONF="/etc/security/limits.d/99-elasticsearch.conf"

cat_limits() {
cat <<EOF
# Elasticsearch production limits
# Generated by es-sysconfig.sh

# File descriptors
$ES_USER  soft  nofile  65535
$ES_USER  hard  nofile  65535

# Threads (nproc) — Elasticsearch needs many threads
$ES_USER  soft  nproc   4096
$ES_USER  hard  nproc   4096

# Memory lock (required when bootstrap.memory_lock=true)
$ES_USER  soft  memlock unlimited
$ES_USER  hard  memlock unlimited
EOF
}

if $DRY_RUN; then
  log_warn "[DRY-RUN] Would write to $LIMITS_CONF:"
  cat_limits
else
  cat_limits > "$LIMITS_CONF"
  log_info "Limits written to $LIMITS_CONF"
fi

# PAM — ensure pam_limits is loaded (needed for limits.d to take effect)
PAM_COMMON="/etc/pam.d/common-session"
if ! grep -q "pam_limits" "$PAM_COMMON"; then
  run "echo 'session required pam_limits.so' >> $PAM_COMMON"
  log_info "pam_limits added to $PAM_COMMON"
else
  log_info "pam_limits already present in $PAM_COMMON"
fi

# =============================================================================
# 6. JNA temporary directory (Linux only)
# =============================================================================
log_section "6. JNA temporary directory"

JNA_TMPDIR="/tmp/elasticsearch-jna"
run "mkdir -p $JNA_TMPDIR"
run "chown $ES_USER:$ES_GROUP $JNA_TMPDIR"
run "chmod 700 $JNA_TMPDIR"

# Ensure /tmp is mounted with exec (remount if noexec)
if findmnt /tmp | grep -q "noexec"; then
  log_warn "/tmp is mounted with noexec. Remounting with exec..."
  run "mount -o remount,exec /tmp"
  log_warn "Add 'exec' to /tmp mount options in /etc/fstab for persistence."
else
  log_info "/tmp is executable — JNA should work correctly."
fi

log_info "JNA tmpdir: $JNA_TMPDIR"

# =============================================================================
# 7. Systemd service overrides (if running via systemd, not Docker)
# =============================================================================
log_section "7. systemd override (non-Docker only)"

SYSTEMD_OVERRIDE_DIR="/etc/systemd/system/elasticsearch.service.d"

if systemctl list-unit-files elasticsearch.service &>/dev/null; then
  run "mkdir -p $SYSTEMD_OVERRIDE_DIR"

  if $DRY_RUN; then
    log_warn "[DRY-RUN] Would write to $SYSTEMD_OVERRIDE_DIR/override.conf"
  else
    cat > "$SYSTEMD_OVERRIDE_DIR/override.conf" <<'SYSTEMD'
[Service]
# Memory lock
LimitMEMLOCK=infinity

# File descriptors
LimitNOFILE=65535

# Threads
LimitNPROC=4096

# Disable OOM kill
OOMScoreAdjust=-1000
SYSTEMD

    log_info "systemd override written: $SYSTEMD_OVERRIDE_DIR/override.conf"
    run "systemctl daemon-reload"
    log_info "systemd daemon reloaded."
  fi
else
  log_info "elasticsearch.service not found — skipping (likely running in Docker)."
fi

# =============================================================================
# Summary
# =============================================================================
log_section "Summary"

echo ""
printf "%-40s %s\n" "Setting"                          "Value"
printf "%-40s %s\n" "-------"                          "-----"
printf "%-40s %s\n" "vm.max_map_count"                 "262144"
printf "%-40s %s\n" "vm.swappiness"                    "1"
printf "%-40s %s\n" "net.ipv4.tcp_retries2"            "5"
printf "%-40s %s\n" "nofile (soft/hard)"               "65535"
printf "%-40s %s\n" "nproc  (soft/hard)"               "4096"
printf "%-40s %s\n" "memlock (soft/hard)"              "unlimited"
printf "%-40s %s\n" "swap"                             "disabled"
printf "%-40s %s\n" "JNA tmpdir"                       "$JNA_TMPDIR"
printf "%-40s %s\n" "ES user"                          "$ES_USER:$ES_GROUP"
echo ""

if $DRY_RUN; then
  log_warn "DRY-RUN complete — no changes were made."
else
  log_info "All settings applied. A reboot is recommended to ensure limits.d take full effect."
fi