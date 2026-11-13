// بيفتح هيكل الواجهة (app/index.html) في Chromium على مقاس موبايل ويدوس على كل حاجة، نهاري وليلي.
// الاستخدام: node pharmacy-system/tests/check-app.cjs [فولدر للصور]
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

    // الخريطة: 7 أقسام + المراحل، و34 شاشة
    ok(await page.locator('#mapView .section').count() === 9, `${scheme}: الخريطة فيها العيوب + 7 أقسام + المراحل`);
    ok(await page.locator('#mapView .row').count() === 40, `${scheme}: الخريطة فيها 6 عيوب + 34 شاشة`);
    ok(await noSideScroll(), `${scheme}: الخريطة من غير سكرول جانبي`);
    if (shotsDir && scheme === 'light') await page.screenshot({ path: path.join(shotsDir, 'map.png'), fullPage: true });

    // القاعدة
    await page.click('#modeDb');
    ok(await page.locator('#dbView .rules li').count() === 8, `${scheme}: قواعد القاعدة الـ 8`);
    ok(await page.locator('#dbView .row').count() === 11, `${scheme}: ملفات القاعدة الـ 11`);
    ok(await noSideScroll(), `${scheme}: القاعدة من غير سكرول جانبي`);
    if (shotsDir) await page.screenshot({ path: path.join(shotsDir, `db-${scheme}.png`), fullPage: true });

    // جرّب الشاشات: كل قسم وكل شاشة
    await page.click('#modeTry');
    ok(await page.locator('#navIn button').count() === 5, `${scheme}: الشريط اللي تحت فيه 5 أقسام`);
    let seen = 0;
    for (const btn of await page.locator('#navIn button').all()) {
      await btn.click();
      for (const chip of await page.locator('#chips .chip').all()) {
        const label = (await chip.textContent()).trim();
        await chip.click();
        const title = (await page.locator('#panel h2').first().textContent()).trim();
        if (title !== label) ok(false, `${scheme}: «${label}» فتح «${title}»`);
        if (!(await noSideScroll())) ok(false, `${scheme}: سكرول جانبي في ${label}`);
        seen++;
      }
    }
    ok(seen === 25, `${scheme}: اتفتحت ${seen} شاشة في الأقسام الخمسة (المتوقع 25)`);
    await page.click('#gearBtn');
    ok(await page.locator('#chips .chip').count() === 4, `${scheme}: الترس بيفتح الإعدادات (4 شاشات)`);
    await page.click('#chips .chip[data-tab="import"]');
    ok(await page.locator('#panel .stat').count() === 3, `${scheme}: شاشة النقل من فارمافلاي فيها الملخص`);
    if (shotsDir) await page.screenshot({ path: path.join(shotsDir, `import-${scheme}.png`) });
    await page.click('#navIn button[data-sec="sales"]');
    await page.click('#chips .chip[data-tab="pos"]');
    ok(await page.locator('#panel .offline').count() === 1, `${scheme}: الكاشير بيوضح شغله والنت واقف`);
    if (shotsDir) await page.screenshot({ path: path.join(shotsDir, `pos-${scheme}.png`) });

    const colors = await page.evaluate(() => { const cs = getComputedStyle(document.body); return { bg: cs.backgroundColor, fg: cs.color }; });
    ok(colors.bg !== 'rgba(0, 0, 0, 0)' && colors.bg !== colors.fg, `${scheme}: خلفية ${colors.bg} ونص ${colors.fg}`);
    ok(errors.length === 0, `${scheme}: مفيش أخطاء في الصفحة ${errors.join(' | ')}`);
    await page.close();
  }
  await browser.close();
  console.log(failed ? `${failed} FAILED` : 'APP OK');
  process.exit(failed ? 1 : 0);
})();
