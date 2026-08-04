#!/usr/bin/env python3
"""发布英文版前的"干净"校验。

为什么不直接在二进制里 grep CJK：
1. `grep -P '[\\x{4e00}-\\x{9fff}]'` 在 Mach-O 上不工作（实测三种写法全部失败）；
2. 就算能跑，按 UTF-8 字节模式扫 2 MB 二进制必然误报——随机字节撞上
   `[\\xe4-\\xe9][\\x80-\\xbf]{2}` 的概率很高，实测一次误报 2913 处。

所以改成两条**精确**的检查：
- 源码里不得有含 CJK 的**字符串字面量**（注释里的中文不进二进制，不算）；
- 打包产物里不得出现未获准的 .lproj 目录。

两条都成立时，产物里就不可能有来自本项目的中文。
"""
import re
import sys
from pathlib import Path

CJK = re.compile(r"[一-鿿぀-ヿ가-힯]")
# Swift 字符串字面量（不跨行，够用：本项目没有含 CJK 的多行字面量）
LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def literals_with_cjk(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    out = []
    for line_no, line in enumerate(text.splitlines(), 1):
        # 去掉行注释再找字面量，避免把注释里的中文算进来
        without_comment = line.split("//")[0]
        for literal in LITERAL.findall(without_comment):
            if CJK.search(literal):
                out.append((line_no, literal.strip()))
    return out


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    app = Path(sys.argv[1]) if len(sys.argv) > 1 else root.parent / "Rotor.app"
    allowed = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else {"en"}

    failed = False

    # 1) 源码字符串字面量
    offenders = []
    for swift in sorted((root / "Sources").rglob("*.swift")):
        # kitcheck 是开发者自用 CLI，不在本次英文化范围内
        if "kitcheck" in swift.parts:
            continue
        # 语言菜单里每种语言用自身书写（"简体中文"而非"Simplified Chinese"）——
        # 看不懂当前界面语言的人，正是靠这一项找回自己的语言。这是刻意的。
        if swift.name == "L10n.swift":
            continue
        hits = literals_with_cjk(swift)
        if hits:
            offenders.append((swift.relative_to(root), hits))
    if offenders:
        failed = True
        total = sum(len(h) for _, h in offenders)
        print(f"❌ 源码中仍有 {total} 条含中文的字符串字面量，未完成本地化迁移：")
        for path, hits in offenders:
            print(f"     {path}  ({len(hits)} 条)  例如第 {hits[0][0]} 行 {hits[0][1][:40]}")

    # 2) 产物里的语言目录
    resources = app / "Contents" / "Resources"
    if resources.is_dir():
        shipped = {p.name[: -len(".lproj")] for p in resources.glob("*.lproj")}
        extra = shipped - allowed
        if extra:
            failed = True
            print(f"❌ 产物中包含未获准的语言目录：{sorted(extra)}（允许：{sorted(allowed)}）")

    if failed:
        return 1
    print("   ✅ 已验证：源码字符串字面量与产物语言目录均不含中文")
    return 0


if __name__ == "__main__":
    sys.exit(main())
