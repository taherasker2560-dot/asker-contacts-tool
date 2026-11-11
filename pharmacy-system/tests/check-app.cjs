// بيفتح هيكل الواجهة (app/index.html) في Chromium على مقاس موبايل ويدوس على كل حاجة.
// الاستخدام: node pharmacy-system/tests/check-app.cjs [مكان حفظ الصور]
'use strict';
const path = require('path');
const { chromium } = require('playwright');

const FILE = 'file://' + path.resolve(__dirname, '../app/index.html');
const shotsDir = process.argv[2];
let failed = 0;
const ok = (cond, msg) => { if (cond) console.log('OK  ', msg); else { failed++; console.log('FAIL', msg); } };

(async () => {
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)|ERR_|Failed to load resource/.test(m.text())) errors.push(m.text()); });
    await page.goto(FILE);
    const noSideScroll = () => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);

    // الخريطة
    ok(await page.locator('#mapView .section').count() === 6, `${scheme}: الخريطة فيها 5 أقسام + المراحل`);
    ok(await page.locator('#mapView .row').count() === 27, `${scheme}: الخريطة فيها 27 شاشة`);
    ok(await noSideScroll(), `${scheme}: الخريطة من غير سكرول جانبي`);
    if (shotsDir && scheme === 'light') await page.screenshot({ path: path.join(shotsDir, 'map.png'), fullPage: true });

    // جرّب الشاشات: كل قسم وكل تبويب
    await page.click('#modeTry');
    ok(await page.locator('#bottomNav').isVisible(), `${scheme}: الشريط اللي تحت ظاهر`);
    const sections = ['purchases', 'accounts', 'sales'];
    let tabsSeen = 0;
    for (const sec of sections) {
      await page.click(`#navIn button[data-sec="${sec}"]`);
      const chips = await page.locator('#chips .chip').all();
      for (const chip of chips) {
        const label = (await chip.textContent()).trim();
        await chip.click();
        const title = (await page.locator('#panel h2').first().textContent()).trim();
        if (title !== label) ok(false, `${scheme}: ${sec} / ${label} فتح «${title}»`);
        if (!(await noSideScroll())) ok(false, `${scheme}: سكرول جانبي في ${label}`);
        tabsSeen++;
      }
    }
    ok(tabsSeen === 19, `${scheme}: اتفتحت ${tabsSeen} شاشة في الأقسام التلاتة (المتوقع 19)`);
    await page.click('#gearBtn');
    ok(await page.locator('#chips .chip').count() === 4, `${scheme}: الترس بيفتح الإعدادات (4 تبويبات)`);

    // شريط النهارده
    await page.click('#todayStrip button[data-go="purchases:expiry"]');
    ok((await page.locator('#panel h2').first().textContent()).trim() === 'الصلاحية', `${scheme}: «صلاحية قربت» بتفتح الصلاحية`);

    // البحث + البديل
    await page.fill('#q', 'بنادول');
    ok(await page.locator('#searchOut .item').count() === 2, `${scheme}: البحث عن «بنادول» = صنفين`);
    ok(await page.locator('#searchOut').getByText('البديل').count() === 1, `${scheme}: الصنف اللي مفيش منه بيطلع معاه البديل`);
    ok(await page.locator('#sectionArea').isHidden(), `${scheme}: البحث بيخفي القسم لحد ما يتمسح`);
    await page.fill('#q', 'xyz');
    ok(await page.locator('#searchOut').getByText('مفيش صنف').count() === 1, `${scheme}: بحث من غير نتيجة بيقول كده`);
    await page.fill('#q', '');
    ok(await page.locator('#sectionArea').isVisible(), `${scheme}: مسح البحث بيرجّع القسم`);

    // الألوان: الخلفية مش شفافة والنص مقروء في الوضعين
    const colors = await page.evaluate(() => {
      const cs = getComputedStyle(document.body);
      return { bg: cs.backgroundColor, fg: cs.color };
    });
    ok(colors.bg !== 'rgba(0, 0, 0, 0)' && colors.bg !== colors.fg, `${scheme}: خلفية ${colors.bg} ونص ${colors.fg}`);

    if (shotsDir) {
      await page.click('#navIn button[data-sec="accounts"]');
      await page.screenshot({ path: path.join(shotsDir, `try-accounts-${scheme}.png`) });
      await page.click('#navIn button[data-sec="sales"]');
      await page.click('#chips .chip[data-tab="salesmove"]');
      await page.screenshot({ path: path.join(shotsDir, `try-sales-${scheme}.png`) });
    }
    ok(errors.length === 0, `${scheme}: مفيش أخطاء في الصفحة ${errors.join(' | ')}`);
    await page.close();
  }
  await browser.close();
  console.log(failed ? `${failed} FAILED` : 'APP OK');
  process.exit(failed ? 1 : 0);
})();
