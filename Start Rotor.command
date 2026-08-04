#!/bin/bash
# 双击启动 Rotor.app。
#
# 单独放一个 .command 是因为：从 Finder 双击 .app 时，崩溃信息和 stderr
# 会进系统日志，用户看不见。这个脚本让应用在终端里启动，出问题时
# 报错就直接摆在眼前，不用去 Console.app 里翻。
#
# 面向用户的输出一律英文——本工具按英文发布，终端里的安全提示是其中
# 最不该出现语言差异的一段。
set -e
cd "$(dirname "$0")"

APP="Rotor.app"

if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found."
    echo "       Build it first:  cd RotorKit && ./make_app.sh"
    exit 1
fi

cat <<'SAFETY'

  ================================================================
   SAFETY — READ BEFORE CONNECTING
  ================================================================

   The motor MUST be bolted to a test bench before you connect.
   Remove any load, clear the full range of rotation, and keep a
   physical way to cut power within reach.

   Parameter detection and firmware-mode switching WILL rotate the
   rotor under power, without warning and without further prompts.

   Using this software means you accept all risks and the full
   liability waiver in DISCLAIMER.md.

  ================================================================

SAFETY

echo "Starting $APP ..."
LOG_DIR="${TMPDIR:-/tmp}/rotor-logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/rotor-$(date +%Y%m%d-%H%M%S).log"
echo "Log: $LOG"
echo

# 同时写终端与日志文件：崩溃时终端会被关掉，日志留得住。
exec "./$APP/Contents/MacOS/Rotor" 2>&1 | tee "$LOG"
