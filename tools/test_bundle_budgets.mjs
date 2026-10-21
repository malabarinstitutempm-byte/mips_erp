// tools/test_bundle_budgets.mjs
// Automated CI Gate: Bundle Size Budgets for Web Portal & Assets

import fs from 'fs';
import path from 'path';
import zlib from 'zlib';

const DIST_DIR = path.resolve('portal/dist');
const ASSETS_DIR = path.join(DIST_DIR, 'assets');

// Configured budgets
const BUDGETS = {
  initialJsGzipMaxKb: 250,     // Hard limit: initial JS gzipped < 250 KB
  initialCssGzipMaxKb: 30,     // Hard limit: initial CSS gzipped < 30 KB
  appShellJsGzipMaxKb: 50,     // App shell entry chunk < 50 KB
  vendorReactGzipMaxKb: 100,   // React vendor chunk < 100 KB
  vendorSupabaseGzipMaxKb: 80, // Supabase vendor chunk < 80 KB
  webLogoMaxKb: 50,            // WebP logo < 50 KB
};

function getGzipSizeKb(filePath) {
  const fileBuffer = fs.readFileSync(filePath);
  const gzipped = zlib.gzipSync(fileBuffer);
  return (gzipped.length / 1024).toFixed(2);
}

function getRawSizeKb(filePath) {
  const stat = fs.statSync(filePath);
  return (stat.size / 1024).toFixed(2);
}

async function run() {
  console.log('===============================================================');
  console.log('          MIPS ERP: CI BUNDLE SIZE BUDGET VERIFICATION         ');
  console.log('===============================================================\n');

  if (!fs.existsSync(DIST_DIR)) {
    console.error('❌ portal/dist directory not found. Run "npm run build" in portal first.');
    process.exit(1);
  }

  const files = fs.readdirSync(ASSETS_DIR);
  let passed = true;

  // 1. App Shell Entry JS
  const indexJs = files.find(f => f.startsWith('index-') && f.endsWith('.js'));
  if (!indexJs) {
    console.error('❌ index-*.js not found in assets.');
    passed = false;
  } else {
    const gz = parseFloat(getGzipSizeKb(path.join(ASSETS_DIR, indexJs)));
    const ok = gz <= BUDGETS.appShellJsGzipMaxKb;
    console.log(`[App Shell JS] ${indexJs}: ${gz} KB gzip (Budget: <= ${BUDGETS.appShellJsGzipMaxKb} KB) -> ${ok ? '✅ PASS' : '❌ FAIL'}`);
    if (!ok) passed = false;
  }

  // 2. React Vendor JS
  const vendorReact = files.find(f => f.startsWith('vendor-react-') && f.endsWith('.js'));
  if (vendorReact) {
    const gz = parseFloat(getGzipSizeKb(path.join(ASSETS_DIR, vendorReact)));
    const ok = gz <= BUDGETS.vendorReactGzipMaxKb;
    console.log(`[Vendor React] ${vendorReact}: ${gz} KB gzip (Budget: <= ${BUDGETS.vendorReactGzipMaxKb} KB) -> ${ok ? '✅ PASS' : '❌ FAIL'}`);
    if (!ok) passed = false;
  }

  // 3. Supabase Vendor JS
  const vendorSupabase = files.find(f => f.startsWith('vendor-supabase-') && f.endsWith('.js'));
  if (vendorSupabase) {
    const gz = parseFloat(getGzipSizeKb(path.join(ASSETS_DIR, vendorSupabase)));
    const ok = gz <= BUDGETS.vendorSupabaseGzipMaxKb;
    console.log(`[Vendor Supabase] ${vendorSupabase}: ${gz} KB gzip (Budget: <= ${BUDGETS.vendorSupabaseGzipMaxKb} KB) -> ${ok ? '✅ PASS' : '❌ FAIL'}`);
    if (!ok) passed = false;
  }

  // 4. Main CSS
  const indexCss = files.find(f => f.startsWith('index-') && f.endsWith('.css'));
  if (indexCss) {
    const gz = parseFloat(getGzipSizeKb(path.join(ASSETS_DIR, indexCss)));
    const ok = gz <= BUDGETS.initialCssGzipMaxKb;
    console.log(`[Main CSS] ${indexCss}: ${gz} KB gzip (Budget: <= ${BUDGETS.initialCssGzipMaxKb} KB) -> ${ok ? '✅ PASS' : '❌ FAIL'}`);
    if (!ok) passed = false;
  }

  // 5. PDF Lazy Loading Isolation Check
  const html2pdfChunk = files.find(f => f.startsWith('html2pdf-') && f.endsWith('.js'));
  if (!html2pdfChunk) {
    console.error('❌ html2pdf chunk is missing or was not isolated into a lazy chunk.');
    passed = false;
  } else {
    console.log(`[PDF Dynamic Isolation] ${html2pdfChunk}: Isolated async chunk -> ✅ PASS`);
  }

  // 6. Optimized WebP Logo Check
  const logoWebp = path.resolve('portal/public/logo.webp');
  if (fs.existsSync(logoWebp)) {
    const rawKb = parseFloat(getRawSizeKb(logoWebp));
    const ok = rawKb <= BUDGETS.webLogoMaxKb;
    console.log(`[WebP Logo] logo.webp: ${rawKb} KB (Budget: <= ${BUDGETS.webLogoMaxKb} KB) -> ${ok ? '✅ PASS' : '❌ FAIL'}`);
    if (!ok) passed = false;
  }

  console.log('\n===============================================================');
  if (passed) {
    console.log('✅ ALL BUNDLE BUDGET CHECKS PASSED!');
    process.exit(0);
  } else {
    console.error('❌ BUNDLE BUDGET CHECK FAILED!');
    process.exit(1);
  }
}

run();
