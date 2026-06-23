#!/usr/bin/env bash
# 生成 assets/fonts/NotoSansSCSubset.ttf —— 打包的中文子集字体。
#
# 为什么需要它：
#  - app 不再运行时从 Google Fonts 下载 Noto Sans SC（按 unicode-range 分 100+ 分片，
#    滚动时按需拉取造成全局卡顿）。改为打包一个完整子集，单文件一次性加载。
#  - flutter_svg 渲染 <text> 不读 ThemeData 字体；图解 SVG 的中文要靠这个字体族
#    （渲染前会把 SVG 的 font-family 改写为 AppSans，见 diagram_cards.dart）。
#
# 子集字符集 = GB2312 常用字 ∪ content 仓库实际字符 ∪ app 源码/ARB 中文，
# 覆盖现有全部内容与 UI，并对新增常用字有冗余。
#
# 依赖：python3 + fonttools（pip install fonttools 或 brew install fonttools）
# 用法：在 apps/client/ 下执行  bash tool/gen_cjk_subset.sh  [可选: content 仓库路径]
set -euo pipefail

CLIENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTENT_DIR="${1:-$CLIENT_DIR/../../mianshi-zhilian-content}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▶ 下载 Noto Sans SC 可变字体 (variable wght)…"
curl -sL -o "$WORK/notosanssc.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"

echo "▶ 收集字符集 (GB2312 ∪ content ∪ app)…"
python3 - "$CONTENT_DIR" "$CLIENT_DIR" "$WORK/chars.txt" <<'PY'
import sys, glob, string, os
content_dir, client_dir, out = sys.argv[1], sys.argv[2], sys.argv[3]
chars = set()
# GB2312 常用 6763 字（覆盖绝大多数常用中文，对未来内容有冗余）
for hi in range(0xA1, 0xFE):
    for lo in range(0xA1, 0xFE):
        try: chars.add(bytes([hi, lo]).decode('gb2312'))
        except Exception: pass
# content 仓库实际用到的字符（含图解 SVG 内的中文 <text>）
if os.path.isdir(content_dir):
    for pat in ('topics/**/*.json', 'domains/*.json', 'manifest.json', 'assets/diagrams/*.svg'):
        for f in glob.glob(os.path.join(content_dir, pat), recursive=True):
            try: chars |= set(open(f, encoding='utf-8').read())
            except Exception: pass
# app 源码 / ARB 里的中文（UI 文案）
for pat in ('lib/**/*.dart', 'lib/l10n/*.arb'):
    for f in glob.glob(os.path.join(client_dir, pat), recursive=True):
        try: chars |= set(open(f, encoding='utf-8').read())
        except Exception: pass
chars |= set(string.printable)
chars |= set('，。、；：？！“”‘’（）【】《》—…·　×÷±°％‰→←↑↓⇒∈≤≥≠∞√')
open(out, 'w', encoding='utf-8').write(''.join(sorted(chars)))
print(f'  字符数: {len(chars)}')
PY

echo "▶ 子集化 (保留 wght 可变轴)…"
pyftsubset "$WORK/notosanssc.ttf" \
  --text-file="$WORK/chars.txt" \
  --output-file="$CLIENT_DIR/assets/fonts/NotoSansSCSubset.ttf" \
  --no-hinting --desubroutinize

ls -la "$CLIENT_DIR/assets/fonts/NotoSansSCSubset.ttf"
echo "✓ 完成。改动后请 flutter pub get 并重新构建。"
