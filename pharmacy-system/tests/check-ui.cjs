// البرنامج نفسه في Chromium زي ما الصيدلي هيستخدمه: الدخول، الكاشير بالكيبورد، البيع والنت قاطع، اللوحة، التقارير السبعة،
// البحث (Ctrl+K)، ملاحظات التجربة، والموبايل. كل بيع بيتأكد من القاعدة نفسها مش من الشاشة بس.
// الاستخدام: BASE=http://127.0.0.1:8091 DBURL=postgresql:///db node pharmacy-system/tests/check-ui.cjs [فولدر للصور]
'use strict';
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');

const BASE = process.env.BASE || 'http://127.0.0.1:8091';
const DBURL = process.env.DBURL;
const shots = process.argv[2];
const sql = (q) => execFileSync('psql', [DBURL, '-qXAt', '-c', q], { encoding: 'utf8' }).trim();
let failed = 0;
const ok = (c, m) => { if (c) console.log('OK  ', m); else { failed++; console.log('FAIL', m); } };

async function login(page, u, p) {
  await page.goto(BASE + '/');
  await page.evaluate(() => { localStorage.clear(); });
  await page.goto(BASE + '/');
  await page.fill('#u', u); await page.fill('#p', p); await page.click('#login button[type=submit]');
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_INTERNET_DISCONNECTED/.test(m.text())) errors.push(m.text()); });

  // ---------------------------------------------------------------- الدخول
  await login(page, 'taher', 'غلط-خالص');
  await page.waitForSelector('.login .err');
  ok(/غلط|مش صح|كلمة السر/.test(await page.textContent('.login .err')), 'كلمة سر غلط: رسالة واضحة ومفيش دخول');

  // ---------------------------------------------------------------- الكاشير
  await login(page, 'cashier', 'demo-pass-1');
  await page.waitForSelector('#q');
  ok(page.url().endsWith('#/pos'), 'الكاشير بيدخل على البيع على طول');
  ok(await page.locator('.nav a[data-path="reports"]').count() === 0, 'الكاشير مابيشوفش التقارير في القايمة');
  ok(await page.locator('.nav a[data-path=""]').count() === 0, 'الكاشير مابيشوفش لوحة الأرباح');
  await page.waitForSelector('#shift b');
  ok(/وردية رقم/.test(await page.textContent('#shift')), 'ورديته المفتوحة ظاهرة');

  const item = 1005, code = sql(`select barcode from ph.item_barcodes where item_id = ${item} limit 1`);
  const before = Number(sql(`select units from ph.v_onhand where item_id = ${item}`));
  const salesBefore = Number(sql(`select count(*) from ph.sales`));
  await page.fill('#q', '2*' + code); await page.keyboard.press('Enter');
  await page.waitForSelector('.cart-line');
  ok(await page.locator('.cart-line').count() === 1, 'الباركود دخل الصنف في الفاتورة (2* = علبتين)');
  ok((await page.inputValue('.cart-line input[data-q]')) === '2', 'الكمية 2');
  await page.fill('#q', 'بنادول'); await page.waitForSelector('.res'); await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelectorAll('.cart-line').length === 2);
  ok(true, 'البحث بالعربي + Enter ضاف صنف تاني');
  await page.keyboard.press('Delete');
  ok(await page.locator('.cart-line').count() === 1, 'Del شال آخر صنف');
  await page.click('#tend'); await page.fill('#tend', '500');
  ok(/الباقي/.test(await page.textContent('#reg')), 'حساب الباقي للعميل');
  await page.keyboard.press('Control+Enter');
  await page.waitForSelector('.receipt');
  const no = [await page.getAttribute('.receipt', 'data-no')].filter((x) => /^S-\d{4}-\d+$/.test(x || ''));
  ok(!!no, 'الإيصال طلع برقم الفاتورة ' + (no ? no[0] : ''));
  const after = Number(sql(`select units from ph.v_onhand where item_id = ${item}`));
  const parts = Number(sql(`select pack_parts from ph.items where id = ${item}`));
  ok(before - after === 2 * parts, `المخزون نقص علبتين بالظبط (${before} ← ${after})`);
  ok(no && sql(`select status from ph.sales where no = '${no[0]}'`) === 'posted', 'الفاتورة مترحّلة في القاعدة');
  if (shots) await page.screenshot({ path: path.join(shots, 'ui-receipt.png') });
  await page.keyboard.press('Enter');
  await page.waitForSelector('.receipt', { state: 'detached' });

  // آجل من غير عميل: القاعدة بترفض والشاشة بتقول ليه
  await page.fill('#q', code); await page.keyboard.press('Enter'); await page.waitForSelector('.cart-line');
  await page.keyboard.press('F9');
  ok(/محتاج تختار العميل/.test(await page.textContent('#reg')), 'F9 = آجل، وبيقول محتاج عميل');
  await page.keyboard.press('Control+Enter');
  await page.waitForSelector('.toast.bad');
  ok(Number(sql(`select count(*) from ph.sales`)) === salesBefore + 1, 'الآجل من غير عميل مااتسجلش');

  // النت قطع: الفاتورة بتستنى على الجهاز وبتتبعت مرة واحدة بس
  await page.keyboard.press('F8');
  await ctx.setOffline(true);
  await page.keyboard.press('Control+Enter');
  await page.waitForSelector('.outbox');
  ok(/مستنية الشبكة/.test(await page.textContent('#outbox')), 'النت قاطع: الفاتورة اتحفظت على الجهاز');
  ok(Number(sql(`select count(*) from ph.sales`)) === salesBefore + 1, 'ولسه مااتسجلتش في القاعدة');
  await ctx.setOffline(false);
  await page.click('#flush');
  await page.waitForFunction(() => !document.querySelector('#outbox .outbox'));
  ok(Number(sql(`select count(*) from ph.sales`)) === salesBefore + 2, 'النت رجع: اتسجلت مرة واحدة');
  // النت قطع بعد ما الفاتورة اتسجلت وقبل الرد: الجهاز بيبعتها تاني بنفس client_uuid ← نفس الفاتورة، مش واحدة جديدة
  const lastUuid = sql(`select client_uuid from ph.sales order by id desc limit 1`);
  const again = await page.evaluate(async (uuid) => {
    const s = JSON.parse(localStorage.getItem('asker.session'));
    const r = await fetch('/rest/v1/rpc/post_sale', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + s.token },
      body: JSON.stringify({ p: { client_uuid: uuid, lines: [{ item_id: 1005, packs: 1 }], payments: [] } }) });
    return r.json();
  }, lastUuid);
  ok(again.repeat === true && Number(sql(`select count(*) from ph.sales`)) === salesBefore + 2, 'نفس الفاتورة اتبعتت تاني: مااتسجلتش مرتين');

  // تعليق الفاتورة
  await page.fill('#q', code); await page.keyboard.press('Enter'); await page.waitForSelector('.cart-line');
  await page.keyboard.press('F6');
  ok(await page.locator('[data-park]').count() === 1 && await page.locator('.cart-line').count() === 0, 'F6 علّق الفاتورة');
  await page.click('[data-park]');
  ok(await page.locator('.cart-line').count() === 1, 'رجعت للفاتورة المعلقة');

  // ---------------------------------------------------------------- المالك
  await login(page, 'taher', 'demo-pass-1');
  await page.waitForSelector('.kpi .v');
  ok(await page.evaluate(() => document.documentElement.dataset.accent === 'asker' && getComputedStyle(document.documentElement).getPropertyValue('--c-main').trim() === '#0a4aa6'), 'اللون الأساسي أزرق عسكر (زي البوت والموقع)');
  await page.waitForSelector('#health .pill');
  ok(/سليمة 10\/10/.test(await page.textContent('#health')), 'اللوحة: القاعدة سليمة 10/10');
  ok(await page.locator('#todo a').count() >= 4, 'اللوحة: «محتاج منك النهارده»');
  ok(await page.locator('#hourly svg path.s1').count() > 0, 'اللوحة: رسم البيع بالساعة');
  if (shots) await page.screenshot({ path: path.join(shots, 'ui-dashboard.png'), fullPage: true });

  await page.keyboard.press('Control+k');
  await page.fill('#pq', 'بنادول');
  await page.waitForSelector('.p-item b:has-text("بنادول")');
  await page.keyboard.press('Enter');
  await page.waitForURL(/#\/items\/\d+/);
  ok(true, 'Ctrl+K: بحث بالعربي فتح صفحة الصنف');
  await page.waitForSelector('#wk svg');
  ok(await page.locator('.kpi').count() === 4, 'صفحة الصنف: الرصيد والبيع والتغطية والسعر');

  const tabs = ['sales', 'stock', 'buy', 'cust', 'short', 'money', 'store'];
  for (const t of tabs) {
    await page.goto(BASE + '/#/reports/' + t);
    await page.waitForSelector('#body .kpi .v');
    await page.waitForTimeout(300);
    const bad = await page.locator('#body .empty b:has-text("مقدرتش")').count();
    ok(bad === 0 && await page.locator('#body .card').count() >= 3, `التقارير: ${t}`);
  }
  await page.goto(BASE + '/#/reports/stock'); await page.waitForSelector('[data-csv="dead"]');
  const [dl] = await Promise.all([page.waitForEvent('download'), page.click('[data-csv="dead"]')]);
  ok(/\.csv$/.test(dl.suggestedFilename()), 'تنزيل Excel: ' + dl.suggestedFilename());
  await page.click('#brief'); await page.waitForSelector('.modal pre');
  ok(/صباح الخير/.test(await page.textContent('.modal pre')), 'ملخص الصبح');
  await page.keyboard.press('Escape');

  await page.goto(BASE + '/#/orders'); await page.waitForSelector('[data-mark]');
  const pos = Number(sql(`select count(*) from ph.purchase_orders`));
  await page.click('[data-mark]'); await page.waitForSelector('.toast.good');
  ok(Number(sql(`select count(*) from ph.purchase_orders`)) === pos + 1, 'الطلبيات: «اتطلبت» سجّلت طلبية');

  await page.goto(BASE + '/#/customers/chronic'); await page.waitForSelector('[data-add]');
  const meds = Number(sql(`select count(*) from ph.customer_meds`));
  await page.click('[data-add]'); await page.waitForSelector('.toast.good');
  ok(Number(sql(`select count(*) from ph.customer_meds`)) === meds + 1, 'العملاء: «سجّله مزمن»');

  await page.click('#fab'); await page.fill('#nt', 'اختبار: ملاحظة من الشاشة'); await page.click('#ns');
  await page.waitForSelector('.toast.good');
  ok(sql(`select count(*) from ph.trial_notes where note like 'اختبار: ملاحظة من الشاشة%'`) === '1', 'سجّل ملاحظة: اتسجلت في القاعدة');

  await page.goto(BASE + '/#/settings'); await page.waitForSelector('#staff table'); await page.waitForSelector('#health .pill');
  ok(await page.locator('#staff [data-token="bot"]').count() === 1, 'الإعدادات: يوزر البوت وزرار مفتاحه');
  ok(await page.locator('#health .pill.p-good').count() === 10, 'الإعدادات: الفحوص العشرة سليمة');

  // ---------------------------------------------------------------- الموبايل والليلي
  for (const scheme of ['light', 'dark']) {
    const m = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const mp = await m.newPage();
    // الليلي بيتختار من البرنامج (زي البوت)، مش من إعداد الجهاز
    await mp.addInitScript((sc) => { if (sc === 'dark') try { localStorage.setItem('asker.theme', 'dark'); } catch (e) {} }, scheme);
    await login(mp, 'taher', 'demo-pass-1');
    await mp.waitForSelector('.kpi .v');
    for (const hsh of ['#/', '#/pos', '#/reports/sales', '#/customers', '#/items']) {
      await mp.goto(BASE + '/' + hsh); await mp.waitForTimeout(900);
      ok(await mp.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `موبايل ${scheme} ${hsh}: من غير سكرول جانبي`);
    }
    if (scheme === 'dark') ok(await mp.evaluate(() => document.documentElement.dataset.theme === 'dark'), 'الليلي اتطبق من اختيار البرنامج');
    await mp.click('#more'); await mp.waitForSelector('.modal a[href="#/reports"]');
    ok(true, `موبايل ${scheme}: «المزيد» فيه التقارير`);
    if (shots) await mp.screenshot({ path: path.join(shots, `ui-phone-${scheme}.png`) });
    await m.close();
  }

  ok(errors.length === 0, 'مفيش أخطاء JavaScript' + (errors.length ? ': ' + errors.slice(0, 3).join(' | ') : ''));
  await browser.close();
  console.log(failed ? `UI FAILED (${failed})` : 'UI OK');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
