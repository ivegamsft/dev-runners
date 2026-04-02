#!/usr/bin/env bash
# CIS-inspired hardening checks for Ubuntu 22.04 runner images
# Returns JSON report; exits non-zero on required control failures
set -euo pipefail

REPORT_FILE="${1:-/tmp/cis-check-linux.json}"
PASS=0
FAIL=0
WARN=0
RESULTS=()

check() {
  local id="$1" desc="$2" severity="$3" result="$4"
  local status
  if [ "$result" = "true" ]; then status="PASS"; ((PASS++)); else
    if [ "$severity" = "required" ]; then status="FAIL"; ((FAIL++)); else status="WARN"; ((WARN++)); fi
  fi
  RESULTS+=("{\"id\":\"$id\",\"description\":\"$desc\",\"severity\":\"$severity\",\"status\":\"$status\"}")
}

# File system checks
check "CIS-1.1" "Ensure /tmp is a separate partition or noexec" "recommended" \
  "$(mount | grep -q 'on /tmp ' && echo true || echo false)"
check "CIS-1.2" "Ensure no world-writable files outside /tmp" "required" \
  "$([ $(find / -xdev -type f -perm -0002 ! -path '/tmp/*' ! -path '/proc/*' ! -path '/sys/*' 2>/dev/null | wc -l) -eq 0 ] && echo true || echo false)"

# Account/auth checks
check "CIS-5.1" "Ensure no empty password fields in /etc/shadow" "required" \
  "$(! grep -q '::' /etc/shadow 2>/dev/null && echo true || echo false)"
check "CIS-5.2" "Ensure root login is disabled via SSH" "required" \
  "$(grep -qi 'PermitRootLogin no' /etc/ssh/sshd_config 2>/dev/null && echo true || echo false)"
check "CIS-5.3" "Ensure password authentication disabled for SSH" "recommended" \
  "$(grep -qi 'PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null && echo true || echo false)"

# Service hardening
check "CIS-2.1" "Ensure unnecessary services are not running" "recommended" \
  "$(! systemctl is-active --quiet avahi-daemon 2>/dev/null && echo true || echo false)"
check "CIS-2.2" "Ensure automatic updates are enabled (unattended-upgrades)" "recommended" \
  "$(dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && echo true || echo false)"

# Network checks
check "CIS-3.1" "Ensure IP forwarding is disabled" "required" \
  "$([ $(sysctl -n net.ipv4.ip_forward 2>/dev/null) -eq 0 ] && echo true || echo false)"
check "CIS-3.2" "Ensure ICMP redirects are not accepted" "required" \
  "$([ $(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null) -eq 0 ] && echo true || echo false)"

# Logging
check "CIS-4.1" "Ensure auditd or equivalent is present" "recommended" \
  "$(dpkg -l auditd 2>/dev/null | grep -q '^ii' && echo true || echo false)"

# Build results JSON
ITEMS=$(IFS=,; echo "${RESULTS[*]}")
cat > "$REPORT_FILE" <<EOF
{"summary":{"pass":$PASS,"fail":$FAIL,"warn":$WARN,"total":$((PASS+FAIL+WARN))},"checks":[$ITEMS]}
EOF

echo "CIS Check Results: $PASS pass, $FAIL fail, $WARN warn"
cat "$REPORT_FILE"

if [ "$FAIL" -gt 0 ]; then
  echo "FAILED: $FAIL required controls did not pass"
  exit 1
fi
