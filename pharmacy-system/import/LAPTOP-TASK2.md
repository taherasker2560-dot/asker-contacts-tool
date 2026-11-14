# مهمة جلسة Claude على اللاب (2): رصيد الموردين، ثم النقل على البرنامج التجريبي

المالك (د. طاهر) **وافق على النقل على البرنامج التجريبي** (13 نوفمبر 2026). **مش عايز يتابع خطوة بخطوة.** اشتغل لوحدك لحد الآخر، وكلّمه مرة واحدة بالنتيجة، بالمصري وفي رسالة قصيرة. لو وقفت في حاجة محتاجاه فيها بس، اسأله سؤال واحد واضح.

## ممنوع
- أي كتابة في فارمافلاي أو الهَب (`D:\PharmaYaqez`) أو SQL Server بتاعه. قراية بس.
- رفع أي داتا من الصيدلية على GitHub أو أي مكان. ملف الربط (SQL) بس مسموح يتبعت للمالك.
- تشغيل أكتر من حاجة تقيلة في نفس الوقت: الجهاز بيتقل.
- مسح أي نسخة احتياطية.

## اقرا الأول
`pharmacy-system/docs/handoff.md` (قسم «نقل فارمافلاي»)، و`import/MAPPING.md` (آخر قسمين)، و`import/pharmafly-to-stage.sql`.
**مهم:** التجربة الأولى في `asker_import_test` اتعملت قبل تعديل `202611132000`: النقل وقتها كان بيصفّر رصيد كل الموردين. فرصيد الموردين هناك غلط.

## الخطوات
1. **آخر كود:** أمر التحديث (بيعمل نسخة احتياطية الأول، وبيطبّق `202611131800` و`202611132000`):
   ```powershell
   [Net.ServicePointManager]::SecurityProtocol='Tls12'; iwr -useb https://raw.githubusercontent.com/taherasker2560-dot/asker-contacts-tool/ccr-7fcc0f51-5mtsr9/pharmacy-system/install/laptop/get.ps1 -OutFile $env:TEMP\asker-get.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\asker-get.ps1
   ```
   اتأكد إنه خلص ("البرنامج اتسطّب واتفتح ✓")، وإن `import\pharmafly-to-stage.sql` اللي نزل هو نسخة التجربة الحقيقية. لو إنت عدّلت عليه بعد ما بعته، حط تعديلك تاني.

2. **رصيد الموردين النهارده في فارمافلاي** (قراية بس). جرّب المصادر دي، وقارن كل واحد بتاريخ المورد (فواتير الشرا − المرتجع − Operation 9 و 55):
   - `Cards.Credit` للمورد (بإشارته وعكسها).
   - `NewBalance` في آخر حركة للمورد في `CashFlow` (Operation 9 وغيره).
   - أي جدول تاني فيه رصيد مورد (`PurchaseInvoices.Settled`، `Paid`…).

   المصدر اللي بيطابق تاريخ أغلب الموردين هو الصح. زوّده على ملف الربط في `stage.current_balances` بـ `party_type = 'supplier'` (زي العملاء، بالقرش، ومن غير الصفر).
   **لو مالقيتش مصدر بيطابق أكتر من 80% من الموردين: ماتحطش رصيد للموردين.** النقل من `202611132000` بيسيبهم على تاريخهم. اكتب ده للمالك.

3. **اتأكد على قاعدة التجربة:** امسح `asker_import_test` واعملها من جديد بالكود الجديد (`db\00`..`13` + كل `db\migrations`)، وانقل `pf_raw` (من `copy.py` أو `pg_dump -n pf_raw` من النسخة القديمة)، وشغّل الربط و`ph.import_history`. لازم:
   - فرق حسابات العملاء زي المرة اللي فاتت (حوالي 30)، ومخزون حوالي 3.7%.
   - الموردين: يا مطابقين (لو حطيت رصيدهم)، يا **مفيش ولا مورد في `balance_reconciled`** (لو ماحطيتش).
   - `ph.health_check()`: كله سليم ما عدا التشغيلات بالسالب اللي هي نفس سالب `Work`.

4. **النقل على البرنامج التجريبي (`asker` على `D:\AskerTrial`):**
   1. اقفل البرنامج: `install\laptop\stop-trial.ps1`.
   2. نسخة احتياطية (لو فشلت **وقّف** وقول للمالك):
      `powershell -ExecutionPolicy Bypass -File install\backup.ps1 -Dir D:\AskerBackups -PgBin D:\AskerTrial\bin\pg\pgsql\bin -Port 5433 -PasswordFile D:\AskerTrial\secrets\postgres.txt`
   3. كلمة سر مؤقتة للمالك: اعمل 12 حرف عشوائي، واكتبها في `D:\AskerTrial\secrets\owner-first.txt` وفي ملف تاني `D:\AskerTrial\secrets\owner-first-copy.txt` عشان تقولهاله (التاني بيفضل، الأول السكريبت بيمسحه).
   4. القاعدة من جديد من غير البيانات الوهمية:
      `powershell -ExecutionPolicy Bypass -File install\laptop\setup-trial.ps1 -ResetDb -OwnerPasswordFile D:\AskerTrial\secrets\owner-first.txt`
      (سجل ملاحظات التجربة بيتحفظ CSV في `D:\AskerTrial\reports` قبل المسح.)
   5. `copy.py` على `asker` (`PGURL=postgresql://postgres:<secrets\postgres.txt>@127.0.0.1:5433/asker`)، ثم ملف الربط بـ `psql -f`، ثم `select ph.import_history('pharmafly <التاريخ>');`.
   6. نفس فحوص الخطوة 3 على `asker`، وبعدين `select count(*) from ph.health_run();` عشان الإعدادات واللوحة يعرضوا الفحص.
   7. شغّل البرنامج: `install\laptop\start-trial.ps1`، وافتحه، وادخل بـ `taher` وكلمة السر المؤقتة، واتأكد إن اللوحة والأصناف والتقارير بتفتح وفيها داتا.
   - لو أي خطوة من 4 وقعت: ارجع بـ `install\laptop\rollback-trial.ps1` (بيرجّع آخر نسخة في `D:\AskerBackups`، وبيسأل `yes` بـ Read-Host: لو مش قادر تكتبها، اطلب من المالك يشغّله ويكتب yes)، وقول للمالك وقف فين.

5. **رسالة للمالك (مرة واحدة):**
   - اتنقل كام فاتورة بيع وشرا وتحصيل، ومن سنة كام، وكام عميل ومورد وصنف.
   - فرق الحسابات والمخزون بالأرقام، ورصيد الموردين اتعمل فيه إيه.
   - أهم 3 حاجات لقيتها في تاريخ فارمافلاي (من `ph.import_issues`).
   - كلمة السر المؤقتة، وإنه **يغيّرها من الإعدادات أول ما يدخل**، وبعدها امسح `owner-first-copy.txt`.
   - إن فارمافلاي ماتلمسش، وإن الرجوع للبيانات الوهمية ممكن بـ `rollback-trial.ps1`.
   - ولو ملف الربط اتغير: يبعته لجلسة السحابة عشان يتحفظ في المستودع.
