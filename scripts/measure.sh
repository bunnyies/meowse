#!/bin/zsh
# Efficiency check for the running Meowse app (rule 2 in CONTRIBUTING.md).
#
#   scripts/measure.sh [seconds]     # default 10; leave the Mac idle while it runs
#
# Pass criteria while idle: CPU 0.0%, idle wakeups 0.
set -euo pipefail
SECS=${1:-10}
PID=$(pgrep -x Meowse | head -1 || true)
[[ -z "$PID" ]] && { echo "Meowse is not running."; exit 1; }

# Two samples SECS apart. CPU is averaged over the interval; IDLEW is cumulative.
out=$(top -l 2 -s "$SECS" -pid "$PID" -stats pid,idlew,cpu,threads,ports | awk -v p="$PID" '$1 == p')
first=$(echo "$out" | head -1); last=$(echo "$out" | tail -1)
w1=$(echo "$first" | awk '{print $2}' | tr -d '+'); w2=$(echo "$last" | awk '{print $2}' | tr -d '+')
read -r _ _ cpu threads ports <<< "$last"
threads=${threads//[+-]/} ports=${ports//[+-]/}
wake=$(( w2 - w1 ))
# Activity Monitor's Memory column, to 0.1 MB.
footprint=$(vmmap --summary "$PID" 2>/dev/null | awk -F': *' '/^Physical footprint:/ {now = $2} /^Physical footprint \(peak\):/ {peak = $2} END {print now " (peak " peak ")"}')

printf "Meowse (pid %s), %ss window\n" "$PID" "$SECS"
printf "  CPU            %s%%\n" "$cpu"
printf "  Idle wakeups   %d  (%.2f/s)\n" "$wake" "$(( wake * 1.0 / SECS ))"
printf "  Memory         %s   Threads %s   Ports %s\n" "$footprint" "$threads" "$ports"
if [[ "$cpu" == "0.0" && "$wake" -eq 0 ]]; then
  echo "  PASS: idle is zero"
else
  echo "  NOTE: non-zero idle activity. Expected only while a glide, Keep Awake expiry or Wiggle is active."
fi
