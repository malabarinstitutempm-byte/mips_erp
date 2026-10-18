# MIPS Teacher & Student Web Portal

Official PWA web portal for **Malabar Institute of Paramedical Science (MIPS)** students and faculty. Built with **Vite + React + TypeScript + Tailwind CSS + TanStack Query + Supabase Auth + vite-plugin-pwa**.

---

## 1. Overview & Key Capabilities

- **Role-Based Authentication**:
  - **Students**: Secure login using Register Number / Username and Password, with first-time activation via Register Number + Date of Birth.
  - **Teachers**: Faculty login to view assigned batches, mark Morning/Evening attendance within a 7-day correction window, enter examination marks with live statistics, and view faculty timetables.
  - **Administrators**: Protected redirection to the administrative Flutter ERP.
- **Inactivity Protection**: Automatically signs out and wipes the client query cache after **15 minutes** of inactivity.
- **Offline First PWA**: Installed to homescreen on iOS and Android. Cached shell, offline banner, and mutative submission lockouts when network is disconnected.
- **Real-Time Notifications & Push Alerts**: Instant Web Audio chime + device vibration and browser push notification support.
- **Document Generation**: Formatted A4 print stylesheet and on-demand lazy-loaded PDF statement exports (results, payment receipts, timetables).

---

## 2. Environment Variables

Create a `.env` file in the `portal/` root directory.

| Variable | Required | Description | Example |
| :--- | :---: | :--- | :--- |
| `VITE_SUPABASE_URL` | **Yes** | Supabase project API URL | `https://xyzproject.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | **Yes** | Supabase anonymous public key | `eyJhbGciOi...` |
| `VITE_TURNSTILE_SITE_KEY` | No | Cloudflare Turnstile public site key (for brute-force captcha) | `0x4AAAAAA...` |
| `VITE_VAPID_PUBLIC_KEY` | No | Web Push VAPID public key | `BEl62iUYg...` |

> [!CAUTION]
> **NEVER** expose the `SUPABASE_SERVICE_ROLE_KEY` in `.env`. All privileged operations are secured via Supabase Edge Functions and PostgreSQL Row Level Security (RLS).

---

## 3. Local Development & Automated Testing

```bash
# Install dependencies
npm install

# Run development server (http://localhost:5173)
npm run dev

# Run automated Vitest test suite (10/10 scenarios)
npm test

# Production build
npm run build

# Preview production build locally
npm run preview
```

---

## 4. Production Deployment

### Method A: Cloudflare Pages (Recommended)
1. Push the repository to GitHub.
2. In the [Cloudflare Dashboard](https://dash.cloudflare.com/), navigate to **Workers & Pages** > **Create application** > **Pages** > **Connect to Git**.
3. Select the repository and configure:
   - **Framework preset**: `Vite`
   - **Root directory**: `portal`
   - **Build command**: `npm run build`
   - **Build output directory**: `dist`
4. Add environment variables under **Settings** > **Environment variables**:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
   - `VITE_TURNSTILE_SITE_KEY`
   - `VITE_VAPID_PUBLIC_KEY`
5. Connect your custom domain (e.g. `portal.mips.edu.in`).
6. The included `public/_headers` and `public/_redirects` files automatically configure CSP, framing protection, and SPA routing.

### Method B: Netlify
1. Click **Add new site** > **Import an existing project**.
2. Set base directory to `portal`, build command to `npm run build`, and publish directory to `dist`.
3. Add the environment variables in **Site configuration** > **Environment variables**.
4. Configure your custom domain with SSL in **Domain management**.

---

## 5. Rollback Procedures

If an emergency rollback is required:
1. **Cloudflare Pages / Netlify Instant Rollback**:
   - Open your hosting dashboard (Cloudflare Pages or Netlify).
   - Go to **Deployments**.
   - Find the previous known-good deployment and click **Rollback to this deployment**. Rollback takes $< 10$ seconds.
2. **Git Rollback**:
   ```bash
   git revert HEAD
   git push origin main
   ```

---

## 6. Manual Testing Checklist (Android Chrome & iPhone Safari)

Before releasing to staff and students, test on real physical mobile devices:

### Android Chrome
- [ ] **PWA Installation**: Open `https://portal.<your-domain>`, tap the Chrome menu (three dots) > **Add to Home screen** (or tap install prompt). Confirm the app launches full-screen without URL bar chrome and shows the MIPS logo.
- [ ] **Push Notification Opt-In**: Log in for the 2nd time, verify the opt-in modal appears, click "Enable Notifications", and grant Chrome permission.
- [ ] **Student Results**: Navigate to **Results**, verify PASS/FAIL badge, and tap **Download PDF**. Confirm `MIPS_Result_<regNo>.pdf` downloads cleanly to the device Downloads folder.
- [ ] **Fees & Receipt Download**: Navigate to **Fees**, verify integer paise display in Indian Rupee format (`₹`), and tap **Receipt PDF**. Confirm receipt generates.
- [ ] **Teacher Attendance**: Log in as faculty, open **Attendance**, choose a batch and Morning slot, mark a student Absent, tap **Submit Attendance**, and verify the confirmation modal.
- [ ] **Offline Banner**: Toggle Airplane Mode on device. Verify the orange banner *"You're offline. Showing saved data"* appears, and mutative submit buttons are disabled with *"Connect to the internet to submit."*

### iPhone Safari (iOS)
- [ ] **PWA Installation**: In Safari, tap the **Share** button > **Add to Home Screen** > **Add**. Open the app icon from iOS home screen and verify standalone display.
- [ ] **Touch Targets**: Confirm all tab buttons, attendance buttons (P, L, A, LV), and inputs are easily tappable ($\ge 44$px) without awkward zooming.
- [ ] **Print Action**: Open **Results**, tap **Print**, and verify iOS AirPrint preview opens formatted cleanly in A4 with header logo and no UI chrome.
- [ ] **Faculty Timetable**: Open faculty timetable and tap **Download Timetable PDF**. Confirm the PDF opens in iOS preview.
- [ ] **15-Minute Inactivity**: Leave the device idle for 15 minutes and confirm the session is cleanly signed out and redirected to the login screen with a warning notice.
