#!/bin/bash
# 真机验收。**不需要参数**——报告按设备自报的硬件字符串自动命名。
#
#   ./Tools/accept.sh                只读：识别 + 遥测 + 读参数
#   ./Tools/accept.sh --write        额外做一次写入-回读-还原
#   ./Tools/accept.sh --label ak60-6 手工指定名字（设备认不出来时才需要）
#
# 一次只接一台。报告存到 Reports/，用于横向对比不同型号读到了什么。
# 手打标签容易在换电机时忘记改，于是把上一台的报告覆盖掉——自动命名就没这问题。
set -e
cd "$(dirname "$0")/.."

LABEL=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --label) LABEL="${2:-}"; shift 2 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

cat <<'SAFETY'

  ================================================================
   Bolt the motor to the bench before continuing.
   Remove the load, clear the range of rotation, keep the power
   cut-off within reach.  This command never commands torque, but
   a wrongly wired bench is dangerous regardless.
  ================================================================

SAFETY

swift build --product RotorApp >/dev/null

mkdir -p Reports
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="Reports/.pending-$STAMP.log"
set +e
./.build/debug/RotorApp --acceptance "${ARGS[@]}" 2>&1 | tee "$TMP"
STATUS=${PIPESTATUS[0]}
set -e

# 名字优先取设备自报的硬件串；连不上时退到 no-response，不要静默叫 unknown。
if [ -z "$LABEL" ]; then
    LABEL="$(sed -n 's/^Hardware  *//p' "$TMP" | head -1 \
             | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/-*$//')"
fi
[ -n "$LABEL" ] || LABEL="no-response"

OUT="Reports/${LABEL}-${STAMP}.log"
mv "$TMP" "$OUT"

echo
echo "report: $(cd Reports && pwd)/$(basename "$OUT")"
exit "$STATUS"
