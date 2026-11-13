#!/usr/bin/env bash
# بيطبّق ملفات db/migrations اللي لسه ماتطبقتش على قاعدة موجودة، كل ملف في عملية واحدة، ويسجّله في ph.schema_migrations.
# بيوقف لو ملف اتطبق قبل كده واتعدّل بعدها. وفي الآخر بيقول لـ PostgREST يقرا القاعدة من جديد.
# الاستخدام: bash pharmacy-system/tools/migrate.sh <PGURL> [فولدر الملفات]
set -euo pipefail
URL="${1:?اكتب عنوان القاعدة}"; DIR="${2:-$(dirname "$0")/../db/migrations}"
q() { psql "$URL" -qXAt -v ON_ERROR_STOP=1 "$@"; }
applied=0
for f in $(ls "$DIR"/*.sql 2>/dev/null | sort); do
  v=$(basename "$f" .sql); sum=$(sha256sum "$f" | cut -c1-64)
  old=$(q -c "select coalesce(checksum, '') from ph.schema_migrations where version = '$v'")
  if [ -n "$old" ]; then
    [ "$old" = "$sum" ] || { echo "وقفت: $v اتطبق قبل كده والملف اتعدّل بعدها. اعمل ملف جديد بدل ما تعدّله."; exit 2; }
    continue
  fi
  if psql "$URL" -qX -v ON_ERROR_STOP=1 -1 -f "$f" -c "insert into ph.schema_migrations (version, checksum) values ('$v', '$sum')" >/dev/null; then
    echo "اتطبق: $v"; applied=$((applied + 1))
  else
    echo "فشل: $v (مااتطبقش منه حاجة)"; exit 1
  fi
done
q -c "notify pgrst, 'reload schema'" >/dev/null
echo "تعديلات جديدة: $applied"
