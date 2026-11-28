#!/system/bin/sh
# Shadow Nexus Kernel - post-flash health check.
# Run as root:   su -c "sh /path/to/snk-check.sh"
# Read-only: it changes nothing. Prints PASS / WARN / FAIL lines and a summary.
# Exit code: 0 = no FAIL, 1 = at least one FAIL.

PASS=0; WARN=0; FAIL=0
ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
warn() { echo "[WARN] $1"; WARN=$((WARN+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }
info() { echo "       $1"; }
sect() { echo; echo "== $1 =="; }

cfg() { zcat /proc/config.gz 2>/dev/null | grep -q "^$1=y"; }
sym() { grep -q " $1\$" /proc/kallsyms 2>/dev/null; }

echo "Shadow Nexus Kernel health check"
[ "$(id -u 2>/dev/null)" = "0" ] && ok "running as root" || bad "not root: run with  su -c \"sh $0\""

sect "Kernel"
KR=$(uname -r); KV=$(uname -v)
info "release : $KR"
info "build   : $KV"
case "$KR" in 5.4.302*) ok "kernel is 5.4.302";; *) warn "unexpected kernel release: $KR";; esac
[ -r /proc/config.gz ] && ok "/proc/config.gz readable" || bad "/proc/config.gz missing (cannot verify config)"

sect "KernelSU-Next (manual hooks)"
cfg CONFIG_KSU && ok "CONFIG_KSU=y" || bad "CONFIG_KSU not enabled"
cfg CONFIG_KSU_MANUAL_HOOK && ok "CONFIG_KSU_MANUAL_HOOK=y" || bad "manual hooks not enabled"
for s in ksu_handle_execveat ksu_handle_faccessat ksu_handle_stat ksu_handle_vfs_read \
         ksu_handle_sys_reboot ksu_handle_input_handle_event ksu_handle_setresuid path_umount; do
  sym "$s" && ok "symbol $s" || bad "missing symbol $s"
done
if [ -x /data/adb/ksud ]; then info "ksud: $(/data/adb/ksud --version 2>&1 | head -1)"; ok "ksud present"; else bad "/data/adb/ksud missing"; fi

sect "Zygisk Next / Vector"
if ps -A 2>/dev/null | grep -q "[z]n-daemon"; then ok "zn-daemon running"; else warn "zn-daemon not running (ignore if you do not use Zygisk Next)"; fi
if ps -A 2>/dev/null | grep -q "[v]ectord"; then ok "vectord running"; else warn "vectord not running (ignore if you do not use Vector)"; fi
if [ -d /data/adb/modules ]; then info "modules: $(ls /data/adb/modules 2>/dev/null | tr '\n' ' ')"; fi

sect "Kernel log (vendor module ABI / crashes)"
N=$(dmesg 2>/dev/null | grep -ciE "disagrees about version|Unknown symbol|module verification failed|version magic")
[ "${N:-0}" = "0" ] && ok "no module version/symbol errors" || bad "$N module ABI error line(s) in dmesg (possible bootloop risk)"
N=$(dmesg 2>/dev/null | grep -cE "Kernel panic|Unable to handle kernel|BUG: |Oops[: ]")
[ "${N:-0}" = "0" ] && ok "no kernel panic/oops" || warn "$N panic/oops line(s) in dmesg: inspect with dmesg"

sect "Network"
CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
info "tcp congestion control: ${CC:-?}   available: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
[ "$CC" = "bbr" ] && ok "TCP BBR active" || warn "TCP is not BBR (built with tweaks=false, or changed by an app/ROM)"
info "default qdisc: $(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
cfg CONFIG_NET_SCH_CAKE && ok "CAKE compiled in" || warn "CAKE not compiled in"
cfg CONFIG_IP_NF_TARGET_TTL && ok "iptables TTL target compiled in" || warn "TTL target not compiled in"
if [ -d /sys/class/net/wlan0 ]; then
  ok "wlan0 present (state: $(cat /sys/class/net/wlan0/operstate 2>/dev/null))"
else
  bad "wlan0 missing (Wi-Fi driver did not load)"
fi

sect "Memory / storage / CPU"
info "zram algorithm : $(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
info "swap           : $(awk 'NR>1{t+=$3;u+=$4}END{printf "%d MB total, %d MB used", t/1024, u/1024}' /proc/swaps 2>/dev/null)"
RA=$(cat /sys/block/sda/queue/read_ahead_kb 2>/dev/null)
info "read_ahead_kb  : ${RA:-?} (sda)"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$p" ] && info "$(basename "$p"): governor=$(cat "$p/scaling_governor" 2>/dev/null) cur=$(cat "$p/scaling_cur_freq" 2>/dev/null) kHz"
done
TL=""
for f in /data/local/tmp/shadownexus_tuning.log /data/local/tmp/bossmido_tuning.log; do [ -f "$f" ] && TL=$f && break; done
if [ -n "$TL" ]; then
  if tail -3 "$TL" | grep -q "done"; then ok "tuning module ran ($(basename "$TL"))"; else warn "tuning log exists but has no 'done' line"; fi
else
  info "tuning module not installed (optional)"
fi

sect "Battery / thermal (snapshot)"
B=${SNK_BATT:-/sys/class/power_supply/battery}
info "level $(cat $B/capacity 2>/dev/null)%  status $(cat $B/status 2>/dev/null)  temp $(( $(cat $B/temp 2>/dev/null || echo 0) / 10 )) C"

echo
echo "Manual checks (not automatable): camera opens, audio plays, mobile data works, Wi-Fi connects, fingerprint, reboot twice."
echo
echo "SUMMARY: $PASS pass, $WARN warn, $FAIL fail"
[ "$FAIL" = "0" ] && exit 0 || exit 1
