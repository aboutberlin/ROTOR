#!/bin/bash
# 把 RotorApp 可执行文件打包成可双击运行的 Rotor.app（本机自用，ad-hoc）。
#
# 用法：
#   ./make_app.sh                     打包全部语言
#   ./make_app.sh --lang en           只打包英文（并断言产物不含 CJK 字符）
#   ./make_app.sh --lang en,zh-Hans   打包指定语言
set -e
cd "$(dirname "$0")"

LANGS="all"
if [ "${1:-}" = "--lang" ]; then
  LANGS="${2:-all}"
  [ -n "${2:-}" ] || { echo "❌ --lang 需要一个参数，例如 --lang en"; exit 2; }
fi
echo "== release 构建 =="
swift build -c release --product RotorApp
BIN="$(swift build -c release --show-bin-path)"
# 产物放在 src/ 顶层，与 “Start Rotor.command” 同级：那个脚本按同级目录找
# Rotor.app，RELEASE_STATUS.md 记的也是 src/Rotor.app。建在本目录会两头对不上。
OUT_DIR="$(cd .. && pwd)"
APP="$OUT_DIR/Rotor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/RotorApp" "$APP/Contents/MacOS/Rotor"
# SwiftPM 资源包（内含 mcconf.xml / appconf.xml）
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

# 翻译文件。它们刻意不是 SPM 资源，所以"发布时砍掉某语言"就是这里少拷一个目录，
# 而不必去动编译产物——不拷贝就是不存在。
if [ "$LANGS" = "all" ]; then
  for d in Localization/*.lproj; do
    [ -d "$d" ] && cp -R "$d" "$APP/Contents/Resources/"
  done
  echo "   语言：全部（$(ls -d Localization/*.lproj 2>/dev/null | wc -l | tr -d ' ') 种）"
else
  IFS=',' read -ra SEL <<< "$LANGS"
  for l in "${SEL[@]}"; do
    if [ -d "Localization/$l.lproj" ]; then
      cp -R "Localization/$l.lproj" "$APP/Contents/Resources/"
    elif [ "$l" != "en" ]; then
      # en 没有 .lproj 是正常的：英文原文内嵌在 key 里，不需要翻译文件。
      echo "❌ 找不到 Localization/$l.lproj"; exit 2
    fi
  done
  echo "   语言：$LANGS"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rotor</string>
  <key>CFBundleDisplayName</key><string>Rotor</string>
  <key>CFBundleExecutable</key><string>Rotor</string>
  <key>CFBundleIdentifier</key><string>com.junchengzhou.rotor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
# 只发英文时校验"干净"。用 Python 而不是 grep：grep -P 在 Mach-O 上不工作，
# 而按字节模式扫二进制必然误报（实测一次误报 2913 处）。改为精确检查源码里的
# 字符串字面量与产物的语言目录——两条都成立，产物里就不可能有本项目的中文。
if [ "$LANGS" = "en" ]; then
  python3 Tools/check_english_only.py "$APP" "en" || exit 1
fi

# ad-hoc 签名（本机运行足够；分发需正式签名/公证）
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign 跳过)"
echo "== 完成：$APP =="
echo "双击 ../\"Start Rotor.command\"，或： open \"$APP\""
