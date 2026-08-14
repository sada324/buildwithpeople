const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await b.newPage({ viewport: { width: 375, height: 812 } });
  page.on('console', m => console.log('PAGE:', m.text()));
  page.on('pageerror', e => console.log('PAGEERROR:', e.message));
  await page.goto('http://localhost:8098/index.html');
  await page.waitForTimeout(1000);
  await page.evaluate(() => {
    document.querySelectorAll('.view-hidden').forEach(el => el.classList.remove('view-hidden'));
    document.getElementById('dashboardView').classList.remove('view-hidden');
    document.querySelector('header')?.remove();
    document.querySelectorAll('body > section').forEach(s => s.remove());
    window.isSignedIn = true;
    try {
      enterDashboard({ name:'Jordan Rivera', headline:'Growth-focused sales partner', skills:'', idea:'', roles:['Sales'], comp:['Commission'], commit:'Part-time', avatarUrl:null });
    } catch(e) { document.title = 'ERR:' + e.message; }
  });
  await page.waitForTimeout(1200);
  console.log('TITLE:', await page.title());
  await page.screenshot({ path: '/tmp/mobile_dashboard.png', fullPage: true });
  await b.close();
})();
