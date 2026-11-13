#!/usr/bin/env bash
# (1) فك الملف المضغوط (أو كذا ملف) ولاقي نسخة فارمافلاي جواه (.bak).
# الاستخدام: bash unpack.sh <الشغل> <ملف1.zip> [ملف2.rar …]
#   <الشغل> فولدر برا المستودع (فيه داتا العملاء: ممنوع يترفع على GitHub).
set -euo pipefail
WORK="${1:?اكتب فولدر الشغل}"; shift
[ $# -ge 1 ] || { echo "اكتب الملف المضغوط"; exit 1; }
case "$(cd "$(dirname "$WORK")" 2>/dev/null && pwd)/" in
  "$(cd "$(dirname "$0")/../.." && pwd)/"*) echo "فولدر الشغل جوه المستودع: اختار مكان برّاه"; exit 1 ;;
esac
mkdir -p "$WORK/unpacked"
for f in "$@"; do
  [ -f "$f" ] || { echo "مش لاقي: $f"; exit 1; }
  dest="$WORK/unpacked/$(basename "${f%.*}")"
  mkdir -p "$dest"
  case "${f,,}" in
    *.zip) unzip -o -q "$f" -d "$dest" ;;
    *.7z|*.rar) command -v 7z >/dev/null || { echo "محتاج 7z (apt install p7zip-full) لـ $f"; exit 1; }; 7z x -y -o"$dest" "$f" >/dev/null ;;
    *.bak) cp "$f" "$dest/" ;;
    *.gz) gunzip -c "$f" > "$dest/$(basename "${f%.gz}")" ;;
    *) echo "نوع ملف مش معروف: $f"; exit 1 ;;
  esac
  echo "اتفك: $f"
done
echo "النسخ اللي لقيتها:"
find "$WORK/unpacked" -type f \( -iname '*.bak' -o -iname '*.mdf' \) -printf '%s\t%p\n' | sort -n |
  while IFS=$'\t' read -r size path; do
    printf '  %s  %s MB  sha256 %s\n' "$path" "$((size / 1048576))" "$(sha256sum "$path" | cut -c1-16)"
  done
