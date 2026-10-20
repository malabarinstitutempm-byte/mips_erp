import { test, expect } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';

const VIEWPORTS = [
  { width: 360, height: 640, name: 'mobile_360' },
  { width: 390, height: 844, name: 'mobile_390' },
  { width: 412, height: 915, name: 'mobile_412' },
];

import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SCREENSHOT_DIR = path.resolve(__dirname, '../../docs/mobile-audit/screenshots/react');

test.beforeAll(() => {
  if (!fs.existsSync(SCREENSHOT_DIR)) {
    fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
  }
});

for (const vp of VIEWPORTS) {
  test.describe(`Viewport: ${vp.name} (${vp.width}x${vp.height})`, () => {
    test.use({ viewport: { width: vp.width, height: vp.height } });

    test(`Login Screen - No horizontal overflow at ${vp.width}px`, async ({ page }) => {
      await page.goto('/login');
      await page.waitForLoadState('networkidle');

      // Assert no horizontal scroll on the page
      const overflow = await page.evaluate(() => {
        return {
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        };
      });

      await page.screenshot({
        path: path.join(SCREENSHOT_DIR, `${vp.name}_login.png`),
        fullPage: true,
      });

      expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
    });

    test(`Admin Notice Screen - No horizontal overflow at ${vp.width}px`, async ({ page }) => {
      await page.goto('/admin');
      await page.waitForLoadState('networkidle');

      const overflow = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        innerWidth: window.innerWidth,
      }));

      await page.screenshot({
        path: path.join(SCREENSHOT_DIR, `${vp.name}_admin_notice.png`),
        fullPage: true,
      });

      expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
    });

    test(`Student Portal - All Tabs - No horizontal overflow at ${vp.width}px`, async ({ page }) => {
      // Seed student auth state in localStorage
      await page.addInitScript(() => {
        const studentUser = {
          id: 1,
          name: 'Mohammed Hamiz',
          role: 'student',
          registration_number: '2023MLT042',
          admission_number: '2023MLT042',
          must_change_password: false,
          first_login_required: false,
        };
        const studentProfile = {
          id: 1,
          name: 'Mohammed Hamiz',
          role: 'student',
          status: 'active',
          current_semester: 3,
          current_year: 2,
          course_structure: 'semester',
        };
        localStorage.setItem('mips_portal_user', JSON.stringify(studentUser));
        localStorage.setItem('mips_portal_role', 'student');
        localStorage.setItem('mips_portal_profile', JSON.stringify(studentProfile));
        localStorage.setItem('mips_portal_last_active', Date.now().toString());
      });

      await page.goto('/student');
      await page.waitForTimeout(1000);

      // Check default tab (Attendance)
      let overflow = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        innerWidth: window.innerWidth,
      }));
      await page.screenshot({
        path: path.join(SCREENSHOT_DIR, `${vp.name}_student_attendance.png`),
        fullPage: true,
      });
      expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);

      // Test Results tab
      const resultsBtn = page.getByRole('tab', { name: /Results|Marks/i });
      if (await resultsBtn.isVisible()) {
        await resultsBtn.click();
        await page.waitForTimeout(500);
        overflow = await page.evaluate(() => ({
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        }));
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, `${vp.name}_student_results.png`),
          fullPage: true,
        });
        expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
      }

      // Test Fees tab
      const feesBtn = page.getByRole('tab', { name: /Fees/i });
      if (await feesBtn.isVisible()) {
        await feesBtn.click();
        await page.waitForTimeout(500);
        overflow = await page.evaluate(() => ({
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        }));
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, `${vp.name}_student_fees.png`),
          fullPage: true,
        });
        expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
      }

      // Test Timetable tab
      const timetableBtn = page.getByRole('tab', { name: /Timetable/i });
      if (await timetableBtn.isVisible()) {
        await timetableBtn.click();
        await page.waitForTimeout(500);
        overflow = await page.evaluate(() => ({
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        }));
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, `${vp.name}_student_timetable.png`),
          fullPage: true,
        });
        expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
      }

      // Test Profile tab
      const profileBtn = page.getByRole('tab', { name: /Profile/i });
      if (await profileBtn.isVisible()) {
        await profileBtn.click();
        await page.waitForTimeout(500);
        overflow = await page.evaluate(() => ({
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        }));
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, `${vp.name}_student_profile.png`),
          fullPage: true,
        });
        expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
      }
    });

    test(`Teacher Portal - All Tabs - No horizontal overflow at ${vp.width}px`, async ({ page }) => {
      // Seed teacher auth state in localStorage
      await page.addInitScript(() => {
        const teacherUser = {
          id: 10,
          name: 'Prof. Anitha Nair',
          role: 'teacher',
          username: 'anitha',
          must_change_password: false,
          first_login_required: false,
        };
        const teacherProfile = {
          id: 10,
          name: 'Prof. Anitha Nair',
          role: 'teacher',
          department: 'Medical Laboratory Technology',
        };
        localStorage.setItem('mips_portal_user', JSON.stringify(teacherUser));
        localStorage.setItem('mips_portal_role', 'teacher');
        localStorage.setItem('mips_portal_profile', JSON.stringify(teacherProfile));
        localStorage.setItem('mips_portal_last_active', Date.now().toString());
      });

      await page.goto('/teacher');
      await page.waitForTimeout(1000);

      // Check default tab (Attendance)
      let overflow = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        innerWidth: window.innerWidth,
      }));
      await page.screenshot({
        path: path.join(SCREENSHOT_DIR, `${vp.name}_teacher_attendance.png`),
        fullPage: true,
      });
      expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);

      // Test Timetable tab
      const timetableBtn = page.getByRole('tab', { name: /Timetable/i });
      if (await timetableBtn.isVisible()) {
        await timetableBtn.click();
        await page.waitForTimeout(500);
        overflow = await page.evaluate(() => ({
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        }));
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, `${vp.name}_teacher_timetable.png`),
          fullPage: true,
        });
        expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
      }

      // Test Profile tab
      const profileBtn = page.getByRole('tab', { name: /Profile/i });
      if (await profileBtn.isVisible()) {
        await profileBtn.click();
        await page.waitForTimeout(500);
        overflow = await page.evaluate(() => ({
          scrollWidth: document.documentElement.scrollWidth,
          innerWidth: window.innerWidth,
        }));
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, `${vp.name}_teacher_profile.png`),
          fullPage: true,
        });
        expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.innerWidth);
      }
    });
  });
}
