# التجربة على اللاب

البرنامج بيتسطب على اللاب للتجربة والتحسين، وفارمافلاي يفضل هو الشغال في الصيدلية.

- **كله في فولدر واحد:** `D:\AskerTrial`. مسحه = البرنامج اتشال.
- **مابيلمسش** فارمافلاي ولا الهَب (`D:\PharmaYaqez`) ولا SQL Server. ليه بورتات لوحده: القاعدة 5433، والمحرك 3010، والشاشات 8080.
- **على اللاب بس** افتراضيًا. `-Lan` لو عايز تفتحه من جهاز تاني.
- **لم يُختبر على ويندوز لسه.** نفس المكونات اتجربت على Linux (`tests/check-api.sh`).

## الخطوات
| | | |
|---|---|---|
| 1 | هات آخر نسخة من الفرع `ccr-7fcc0f51-5mtsr9` | `git pull` |
| 2 | التسطيب (مرة واحدة). بينزّل البرامج ويطبع بصمة كل ملف، وبيسألك على كلمة سر المالك | `powershell -ExecutionPolicy Bypass -File pharmacy-system\install\laptop\setup-trial.ps1` |
| 3 | التشغيل | `…\start-trial.ps1` ← `http://127.0.0.1:8080` |
| 4 | خريطة جداول فارمافلاي من القاعدة اللي الهَب مرجّعها | `pharmacy-system\import\discover.py` بـ `MSSQL_HOST` و`MSSQL_USER` و`MSSQL_PASSWORD` و`MSSQL_DB` |
| 5 | ملف الربط (`import\pharmafly-to-stage.sql`) حسب `import\MAPPING.md` والخريطة | بيتكتب مرة واحدة |
| 6 | النقل: نسخ الجداول ← الربط ← النقل بالتاريخ | `copy.py` بـ `PGURL=postgresql://postgres:<secrets\postgres.txt>@127.0.0.1:5433/asker` ثم `psql -f pharmafly-to-stage.sql` ثم `select ph.import_history('…');` |
| 7 | نقل من نسخة أحدث بعدين | `setup-trial.ps1 -ResetDb` ثم 6 تاني |
| 8 | الإيقاف | `…\stop-trial.ps1` |

## الثبات والأخطاء والمشاكل
الخطة والشروط في [`docs/trial.md`](../../docs/trial.md).

| | | |
|---|---|---|
| التقرير اليومي | البرامج، الفحص الذاتي، أخطاء السجلات، النسخة الاحتياطية، المساحة، المشاكل المفتوحة | `…\check-trial.ps1` |
| اختبار الضغط | كذا كاشير في نفس الوقت على قاعدة لوحدها | `…\soak-trial.ps1 -Clients 4 -Seconds 600` |
| النسخة الاحتياطية | كل ليلة | `pharmacy-system\install\backup.ps1 -PgBin D:\AskerTrial\bin\pg\pgsql\bin -Port 5433 -PasswordFile D:\AskerTrial\secrets\postgres.txt` |
| النسخة بترجع؟ | آخر نسخة ← قاعدة تانية ← الفحص | `…\restore-test.ps1` |
| مشكلة جديدة | تتسجل في `ph.trial_notes` | Claude على اللاب يسجلها |

## اللي بيتعمل في `D:\AskerTrial`
```
bin\        PostgreSQL 16 و PostgREST 12.2.3 و Caddy 2.8.4 (zip من غير تسطيب)
pgdata\     القاعدة
secrets\    كلمة سر القاعدة وسر المفاتيح (لصاحب الحساب بس، مابتترفعش)
conf\       إعدادات PostgREST
logs\       لو حاجة ماقامتش
downloads\  الملفات اللي اتنزلت
```

## لو حاجة وقعت
- PostgreSQL ماقامش: `logs\postgres.log` (غالبًا البورت 5433 مشغول ← `-PgPort` غيره في التلات سكريبتات).
- رابط تنزيل PostgreSQL مابقاش شغال: `-PgZipUrl` بنسخة 16 تانية من موقع EnterpriseDB (Windows x86-64 binaries).
- الشاشات مابتفتحش: `logs\caddy.err` و`logs\postgrest.err`.
