#!/bin/sh
# Shadow Nexus Kernel - network benchmark (run in Termux, no root needed).
# Usage: sh snk-net.sh <label>        e.g.  sh snk-net.sh before   /   sh snk-net.sh after
# Needs: pkg install curl iputils (or any ping that supports -i)
# Measures: idle latency/jitter/loss, download speed, and latency UNDER LOAD
# (the difference is bufferbloat; this is what fq_codel/CAKE are meant to improve).
# Uses Cloudflare's public speed endpoint. Run each label 3 times and compare the medians.

LABEL=${1:-run}
HOST=${HOST:-1.1.1.1}
URL=${URL:-https://speed.cloudflare.com/__down?bytes=50000000}
OUT=${OUT:-$HOME/snk-net-results.txt}

command -v curl >/dev/null 2>&1 || { echo "curl missing: pkg install curl"; exit 2; }
command -v ping >/dev/null 2>&1 || { echo "ping missing: pkg install iputils"; exit 2; }

pingstat() {  # $1 = count ; prints "avg_ms mdev_ms loss_pct"
  ping -c "$1" -i 0.3 "$HOST" 2>/dev/null | awk '
    /packet loss/ { for(i=1;i<=NF;i++) if($i ~ /%/) loss=$i }
    /min\/avg\/max/ { split($4,a,"/"); avg=a[2]; mdev=a[4] }
    END { gsub("%","",loss); printf "%s %s %s\n", (avg==""?"NA":avg), (mdev==""?"NA":mdev), (loss==""?"NA":loss) }'
}

echo "[$LABEL] idle latency to $HOST ..."
IDLE=$(pingstat 20)

echo "[$LABEL] download + latency under load (about 10-20 s) ..."
curl -s -o /dev/null -w "%{speed_download}" --max-time 15 "$URL" > ${TMPDIR:-$HOME}/.snk-speed.$$ 2>/dev/null &
CPID=$!
sleep 2
LOADED=$(pingstat 20)
wait "$CPID" 2>/dev/null
SPD=$(cat ${TMPDIR:-$HOME}/.snk-speed.$$ 2>/dev/null); rm -f ${TMPDIR:-$HOME}/.snk-speed.$$
MBIT=$(awk -v s="${SPD:-0}" 'BEGIN{printf "%.1f", s*8/1000000}')

CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "?")
LINE="$(date '+%Y-%m-%d %H:%M:%S') label=$LABEL kernel=$(uname -r) cc=$CC idle(avg/mdev/loss%)=$(echo $IDLE | tr ' ' '/') loaded(avg/mdev/loss%)=$(echo $LOADED | tr ' ' '/') download=${MBIT}Mbit/s"
echo "$LINE"
echo "$LINE" >> "$OUT"
echo "saved to $OUT"
