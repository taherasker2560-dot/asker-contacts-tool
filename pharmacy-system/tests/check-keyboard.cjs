// البرنامج كله بالكيبورد بس: مفيش ولا ضغطة ماوس في الاختبار ده (مفيش click ولا fill).
// دخول ← بيع بالباركود والاسم ← تعديل الفاتورة بالأسهم ← عميل وآجل ← تعليق ← آخر فاتورة ← بحث ← صنف ← عملاء ← طلبيات
// ← التقارير السبعة وتنزيل Excel ← وضع الحروف ← الإعدادات ← ملاحظة ← ليلي ← خروج. وكل حاجة بتتأكد من القاعدة.
// الاستخدام: BASE=… DBURL=… node pharmacy-system/tests/check-keyboard.cjs
'use strict';
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const BASE = process.env.BASE || 'http://127.0.0.1:8091';
const sql = (q) => execFileSync('psql', [process.env.DBURL, '-qXAt', '-c', q], { encoding: 'utf8' }).trim();
let failed = 0;
const ok = (c, m) => { if (c) console.log('OK  ', m); else { failed++; console.log('FAIL', m); } };

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage();
  const errors = [];
  p.on('pageerror', (e) => errors.push(e.message));
  const K = p.keyboard;
  const press = async (k, wait = 250) => { await K.press(k); await p.waitForTimeout(wait); };
  const type = async (t, wait = 200) => { await K.type(t, { delay: 15 }); await p.waitForTimeout(wait); };
  const hash = () => p.evaluate(() => location.hash);
  const n = (q) => Number(sql(q));

  // الدخول
  await p.goto(BASE + '/'); await p.evaluate(() => localStorage.clear()); await p.goto(BASE + '/');
  await p.waitForSelector('#u:focus');
  await type('taher'); await press('Tab'); await type('demo-pass-1'); await press('Enter', 100);
  await p.waitForSelector('.kpi .v');
  ok(true, 'الدخول بالكيبورد (اسم ← Tab ← كلمة السر ← Enter)');

  await press('F1'); ok(await p.locator('.kb-guide').count() === 1, 'F1 فتح دليل الاختصارات');
  ok(await p.locator('.kb-guide .kb-row').count() >= 20, 'الدليل فيه كل الاختصارات');
  await press('Escape'); ok(await p.locator('.modal').count() === 0, 'Esc قفل الدليل');

  // البيع
  await press('Alt+Digit2', 600); ok((await hash()) === '#/pos', 'Alt+2 = البيع');
  await p.waitForSelector('#q:focus');
  const code = sql(`select barcode from ph.item_barcodes where item_id = 1005 limit 1`);
  await type(code); await press('Enter', 500);
  await type('بنادول اكسترا', 700); await press('Enter', 500);
  await type('اوجمنتين', 700); await press('Enter', 500);
  ok(await p.locator('.cart-line').count() === 3, 'باركود + اسمين بالعربي ← 3 أصناف');
  await press('ArrowUp'); ok(await p.locator('.cart-line.kb-sel').count() === 1, '↑ اختار صنف في الفاتورة');
  await press('Equal'); ok((await p.inputValue('.cart-line.kb-sel input[data-q]')) === '2', '+ زوّد الكمية');
  await press('Delete'); ok(await p.locator('.cart-line').count() === 2, 'Del شال الصنف المختار');
  await press('Escape');
  await press('Alt+KeyC'); ok(await p.evaluate(() => document.activeElement && document.activeElement.id === 'cq'), 'Alt+C = خانة العميل');
  await type('الحاج سيد', 900); await press('Enter', 400);
  ok(/الحاج سيد/.test(await p.textContent('#reg')), 'العميل اتختار بـ Enter');
  await press('F9'); ok(await p.locator('.pay button.on[data-m="credit"]').count() === 1, 'F9 = آجل');
  const before = n(`select count(*) from ph.sales`);
  await press('Control+Enter', 1200);
  await p.waitForSelector('.receipt');
  ok(n(`select count(*) from ph.sales where on_credit > 0 and customer_id = (select id from ph.customers where name = 'الحاج سيد عبد الله') and id = (select max(id) from ph.sales)`) === 1, 'Ctrl+Enter: فاتورة آجل على العميل في القاعدة');
  await press('Enter'); ok(await p.locator('.receipt').count() === 0, 'Enter = فاتورة جديدة');
  await type(code); await press('Enter', 500);
  await press('Alt+KeyP'); ok(await p.locator('[data-park]').count() === 1 && await p.locator('.cart-line').count() === 0, 'Alt+P علّق الفاتورة');
  await press('Alt+Shift+KeyP'); ok(await p.locator('.cart-line').count() === 1, 'Alt+Shift+P رجّعها');
  await press('F8'); await press('Alt+KeyR'); await type('500'); await press('Enter', 1200);
  await p.waitForSelector('.receipt');
  ok(n(`select count(*) from ph.sales`) === before + 2, 'F8 كاش ← Alt+R المستلم ← Enter خلّص');
  await press('Enter');
  await press('Alt+KeyL', 600); ok(await p.locator('.receipt').count() === 1, 'Alt+L آخر فاتورة تاني'); await press('Escape');

  // البحث والصنف
  await press('F3'); await type('كتافلام', 900); await p.waitForSelector('.p-item b:has-text("كتافلام")'); await press('Enter', 300);
  await p.waitForSelector('#page [data-back]');
  ok(/^#\/items\/\d+$/.test(await hash()), 'F3 بحث ← Enter فتح الصنف');
  await press('Escape', 300); await p.waitForSelector('#s[data-search]'); ok((await hash()) === '#/items', 'Esc رجع للأصناف');
  await press('Slash'); await type('pana', 300); await p.waitForSelector('#rows tr[data-row] >> text=PANADOL'); await press('ArrowDown'); await press('Enter', 300); await p.waitForSelector('#page [data-back]');
  ok(/^#\/items\/\d+$/.test(await hash()), '/ بحث ← ↓ ← Enter فتح صنف');

  // العملاء
  await press('Alt+Digit7', 900); ok((await hash()).startsWith('#/customers'), 'Alt+7 = العملاء');
  await p.waitForSelector('#body [data-row], #body .empty');
  await press('BracketRight', 300); await p.waitForSelector('#body tr[data-row] [data-key="a"]'); ok((await hash()) === '#/customers/chronic', '] التاب اللي بعده');
  const meds = n(`select count(*) from ph.customer_meds`);
  await press('ArrowDown'); await press('KeyA', 900);
  ok(n(`select count(*) from ph.customer_meds`) === meds + 1, '↓ ← A سجّل العميل مزمن');
  await press('BracketRight', 300); await p.waitForSelector('#body tr[data-row] [data-key="p"]'); ok((await hash()) === '#/customers/dues', '] المديونيات');
  const pays = n(`select count(*) from ph.payments`);
  await press('ArrowDown'); await press('KeyP', 700); await press('Enter', 900);
  ok(n(`select count(*) from ph.payments`) === pays + 1, '↓ ← P حصّل ← Enter سجّل الدفعة');

  // الطلبيات
  await press('Alt+Digit6', 300); await p.waitForSelector('#groups tr[data-row] input'); ok((await hash()) === '#/orders', 'Alt+6 = الطلبيات');
  const pos = n(`select count(*) from ph.purchase_orders`);
  await press('ArrowDown'); const q0 = await p.inputValue('tr.kb-sel input'); await press('Equal');
  ok(Number(await p.inputValue('tr.kb-sel input')) === Number(q0) + 1, '+ زوّد كمية الطلبية');
  await press('KeyM', 1000); ok(n(`select count(*) from ph.purchase_orders`) === pos + 1, 'M = اتطلبت');

  // المشتريات: فاتورة شرا من أولها لترحيلها بالكيبورد
  await press('Alt+Digit4', 300); await p.waitForSelector('#rows tr[data-row]'); ok((await hash()) === '#/purchases', 'Alt+4 = المشتريات');
  await press('Alt+KeyA', 1300); ok((await hash()) === '#/purchases/new', 'Alt+A فاتورة شرا جديدة');
  await p.waitForSelector('#sup:focus');
  await press('ArrowDown', 400);
  if (await p.evaluate(() => document.activeElement.id === 'sup')) await press('Tab');
  await type('KB-1'); await press('Enter');
  const item = 1206, parts = n(`select pack_parts from ph.items where id = ${item}`), stock0 = n(`select coalesce(units, 0) from ph.v_onhand where item_id = ${item}`);
  const piName = sql(`select name_ar from ph.items where id = ${item}`);
  await type(piName, 300); await p.waitForSelector('#res .res'); await press('Enter', 300); await p.waitForSelector('#lb tr[data-i] input:focus');
  ok(await p.locator('#lb tr[data-i]').count() === 1, 'الصنف دخل الفاتورة والمؤشر على الكمية');
  await type('5'); await press('Enter'); await type('1'); await press('Enter'); await press('Enter'); await type('25'); await press('Enter'); await press('Enter');
  await type('12/28'); await press('Enter');
  const posted0 = n(`select count(*) from ph.purchase_invoices where status = 'posted'`);
  await press('Control+Enter', 2000);
  ok(n(`select count(*) from ph.purchase_invoices where status = 'posted'`) === posted0 + 1 && /^#\/purchases\/\d+$/.test(await hash()), 'Ctrl+Enter رحّل الفاتورة');
  ok(n(`select coalesce(units, 0) from ph.v_onhand where item_id = ${item}`) === stock0 + 6 * parts, 'المخزون زاد 5 + 1 بونص');
  ok(sql(`select l.expiry || '|' || round(l.cost_total) from ph.purchase_invoice_lines l join ph.purchase_invoices i on i.id = l.invoice_id where i.supplier_doc_no = 'KB-1'`).startsWith('2028-12-31|'), 'الصلاحية 12/28 ← 2028-12-31');

  // الخزن: تحويل ومصروف
  await press('Alt+Digit9', 300); await p.waitForSelector('#mv tr'); ok((await hash()) === '#/cash', 'Alt+9 = الخزن');
  const tr0 = n(`select count(*) from ph.cash_transfers`), ex0 = n(`select count(*) from ph.expenses`);
  await press('Alt+KeyR', 600); await type('100'); await press('Enter', 1200);
  ok(n(`select count(*) from ph.cash_transfers`) === tr0 + 1, 'Alt+R ← 100 ← Enter: توريد من الدرج للخزنة');
  await press('Alt+KeyE', 700); await type('50'); await press('Enter', 1200);
  ok(n(`select count(*) from ph.expenses`) === ex0 + 1, 'Alt+E ← 50 ← Enter: مصروف');
  ok(n(`select count(*) from ph.health_check() where not ok`) === 0, 'الفحص الذاتي سليم بعد الشرا والخزن');

  // التقارير
  await press('Alt+Digit0', 1500); ok((await hash()).startsWith('#/reports'), 'Alt+0 = التقارير');
  const seen = new Set();
  for (let i = 0; i < 7; i++) { await p.waitForSelector('#body .kpi .v'); seen.add(await hash()); await press('BracketRight', 1300); }
  ok(seen.size === 7, '] لفّ على التقارير السبعة');
  await press('Shift+BracketRight', 1300); ok(await p.locator('#per .chip.on').count() === 1, 'Shift+] غيّر الفترة');
  await p.evaluate(() => { location.hash = '#/reports/stock'; }); await p.waitForSelector('#body tr[data-row]');
  await press('ArrowDown');
  const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 5000 }), press('KeyX')]);
  ok(/\.csv$/.test(dl.suggestedFilename()), 'X نزّل الجدول المختار Excel');
  await press('Alt+KeyM', 900); ok(await p.locator('.modal pre').count() === 1, 'Alt+M ملخص الصبح'); await press('Escape');

  // وضع الحروف: من غير أي اختصار، روح الإعدادات بحرف
  await press('F4', 300);
  ok(await p.locator('.kb-hints span').count() > 10, 'F4 حط حرف على كل زرار');
  const codeFor = await p.evaluate(() => {
    const a = document.querySelector('.nav a[data-path="settings"]').getBoundingClientRect();
    let best = null, d = 1e9;
    document.querySelectorAll('.kb-hints span').forEach((s) => { const r = s.getBoundingClientRect(); const dd = Math.abs(r.left - a.left - 2) + Math.abs(r.top - a.top - 2); if (dd < d) { d = dd; best = s.textContent; } });
    return best;
  });
  await type(codeFor.toLowerCase(), 1500);
  ok((await hash()) === '#/settings', `F4 ← «${codeFor}» فتح الإعدادات`);

  // الإعدادات: قفل ملاحظة
  await p.waitForSelector('#notes [data-row]');
  const open = n(`select count(*) from ph.trial_notes where status = 'open'`);
  await press('ArrowDown'); await press('KeyF', 600); await type('اتصلحت من الكيبورد'); await press('Enter', 900);
  ok(n(`select count(*) from ph.trial_notes where status = 'open'`) === open - 1, '↓ ← F ← Enter قفل الملاحظة');
  await press('Alt+KeyN', 500); await type('ملاحظة من الكيبورد بس'); await press('Control+Enter', 900);
  ok(n(`select count(*) from ph.trial_notes where note like 'ملاحظة من الكيبورد بس%'`) === 1, 'Alt+N ← اكتب ← Ctrl+Enter سجّل ملاحظة');
  await press('Alt+KeyT'); ok((await p.evaluate(() => document.documentElement.dataset.theme)) === 'dark', 'Alt+T ليلي');
  await press('Alt+KeyT'); ok((await p.evaluate(() => document.documentElement.dataset.theme)) === 'light', 'Alt+T نهاري تاني');
  await press('Alt+KeyK', 500); await p.waitForSelector('.swatches');
  await press('ArrowLeft', 300); ok((await p.evaluate(() => document.documentElement.dataset.accent)) === 'crimson', 'Alt+K ← اللون اتغير لعنابي');
  await press('ArrowRight', 300); ok((await p.evaluate(() => document.documentElement.dataset.accent)) === 'asker', '→ رجع أزرق عسكر');
  await press('Escape', 500);
  await press('Alt+Digit1', 900); ok((await hash()) === '#/', 'Alt+1 اللوحة');
  await press('F3'); await type('خروج', 500); await press('Enter', 800);
  ok(await p.locator('#login').count() === 1, 'F3 ← «خروج» ← Enter');

  ok(errors.length === 0, 'مفيش أخطاء' + (errors.length ? ': ' + errors.join(' | ') : ''));
  await browser.close();
  console.log(failed ? `KEYBOARD FAILED (${failed})` : 'KEYBOARD OK');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
