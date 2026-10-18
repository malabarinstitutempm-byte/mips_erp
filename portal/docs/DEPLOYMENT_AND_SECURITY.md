# MIPS ERP Portal — Deployment, Security & Production Guide

This document details the production build, security architecture, environment configuration, automated testing, and deployment options for the **MIPS Student & Teacher Web Portal** (`/portal`).

---

## 1. Environment Configuration

The frontend portal strictly adheres to zero-trust principles. Only public identifiers are bundled or exposed:

| Variable | Required | Description | Sample Value |
| :--- | :---: | :--- | :--- |
| `VITE_SUPABASE_URL` | **Yes** | Supabase Project API URL | `https://xyzproject.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | **Yes** | Supabase Anonymous Client Key | `eyJhbGciOi...` |
| `VITE_TURNSTILE_SITE_KEY` | Optional | Cloudflare Turnstile CAPTCHA public site key | `0x4AAAAAA...` |
| `VITE_VAPID_PUBLIC_KEY` | Optional | Web Push VAPID Public Key | `BEl62iUYg...` |

> [!CAUTION]
> **NEVER** expose `SUPABASE_SERVICE_ROLE_KEY` or any database connection strings in the frontend `.env`. All privileged mutations (first-login DOB verification, password resets, attendance corrections outside window) are strictly handled server-side via Supabase Edge Functions with Row Level Security (RLS) enforcement.

---

## 2. Security Architecture & Audit

1. **Session & Credential Safety**:
   - Session tokens are stored and refreshed strictly by the official Supabase Auth client in browser session/IndexedDB memory.
   - **No passwords, PINs, or DOBs** are ever stored in `localStorage`, `sessionStorage`, or cookies.
   - Date of Birth (DOB) is strictly prohibited from rendering on public or profile screens; it is exclusively used server-side during the initial first-login verification.
2. **Inactivity Guard**:
   - Automatically signs users out and wipes TanStack Query cache after **15 minutes** of continuous user inactivity.
   - Resets active timers upon mouse, keyboard, touch, or scroll events.
3. **Role Guards**:
   - Navigation to cross-role endpoints (`/teacher` by a student, or `/student` by a faculty member) is intercepted before component mounting and redirects users to their appropriate dashboard.
   - Administrative users attempting portal access are greeted with the dedicated `AdminNotice` modal and directed to the Flutter Admin ERP.
4. **HTTP Security Headers (`_headers`)**:
   - **Content-Security-Policy (CSP)**: Locks script and connect sources to origin, Supabase endpoints, and Cloudflare Turnstile.
   - `X-Frame-Options: DENY` (prevents clickjacking).
   - `X-Content-Type-Options: nosniff`.
   - `Referrer-Policy: strict-origin-when-cross-origin`.
   - `Permissions-Policy: camera=(), microphone=(), geolocation=()`.
5. **Mutation Safeguards**:
   - All critical mutative actions (attendance submission, marks finalization) are guarded against offline states. When offline, buttons are disabled with *"Connect to the internet to submit."*

---

## 3. Automated Test Verification (Phase 6E)

A dedicated, comprehensive test suite runs via Vitest (`vitest run`) covering all 10 essential scenarios:

```bash
cd portal
npm test
```

### Verified Test Scenarios:
1. **Student Login Failure**: Verifies that wrong passwords trigger clear error messages and increment server attempt counters.
2. **First Login Activation**: Verifies register number + DOB verification, password policy evaluation (length, non-DOB, non-regNo), and Edge Function activation invocation.
3. **Student Examination Results**: Verifies rendering of official PASS/FAIL badges, marks table, totals, grades, and lazy PDF statement download.
4. **Student Fees Ledger**: Verifies integer paise currency conversion (₹ en-IN grouping), primary vs. skill course fee breakdown, payment history without internal remarks, and receipt PDF generation.
5. **Student Attendance & Bands**: Verifies calculation from `student_attendance_summary`, warning banner when attendance $< 75\%$, recovery session counter, and session slot breakdown.
6. **Teacher Attendance Marking**: Verifies batch selection, slot selection (Morning/Evening), tap-friendly buttons ($\ge 44$px for P/L/A/LV), live counter updates, and two-step absentee submission modal.
7. **Teacher Marks Entry**: Verifies exam and subject selection, auto-advance keyboard navigation, absent toggle, real-time average/high/low/pass statistics, and submission modal.
8. **Role Guard Navigation**: Verifies cross-role redirection (student accessing faculty area redirected to student dashboard).
9. **Inactivity Auto-Logout**: Verifies 15-minute timer triggers automatic logout and query cache wipe.
10. **Offline PWA Banner**: Verifies dynamic online/offline network detection and alert banners.

---

## 4. Production Build & Bundle Size Optimization

The portal is optimized with dynamic code splitting (`React.lazy()`) for route bundles (`StudentArea`, `TeacherArea`), lazy import of heavy client libraries (`html2pdf.js`), and SVG stroke icons without bloated icon packs.

```bash
cd portal
npm run build
```

### Build Characteristics:
- **Total Initial Gzipped JS Bundle**: **~165 kB** (well below the strict 250 kB ceiling).
- **Service Worker & PWA Caching**: Precached assets for fast offline shell loading.
- **Font Optimization**: Google Fonts Sora and Plus Jakarta Sans loaded with `display=swap`.

---

## 5. Deployment Options

### Option A: Cloudflare Pages (Recommended)
1. Link your GitHub repository to Cloudflare Pages.
2. Set build configuration:
   - **Framework preset**: Vite
   - **Build command**: `npm run build`
   - **Build output directory**: `dist`
   - **Root directory**: `portal`
3. Add environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
   - `VITE_TURNSTILE_SITE_KEY`
   - `VITE_VAPID_PUBLIC_KEY`
4. The included `public/_headers` file will automatically configure CSP and HTTP security headers on Cloudflare's edge.

### Option B: Vercel
1. Import the repository in Vercel.
2. Set Root Directory to `portal`.
3. Set build command `npm run build` and output directory `dist`.
4. Configure environment variables in the Project Settings dashboard.

### Option C: Docker / Nginx
For self-hosting on your private college VPS or intranet:

```dockerfile
# Build Stage
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production Stage
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

Sample Nginx Single Page App configuration:
```nginx
server {
    listen 80;
    server_name portal.mips.edu.in;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```
