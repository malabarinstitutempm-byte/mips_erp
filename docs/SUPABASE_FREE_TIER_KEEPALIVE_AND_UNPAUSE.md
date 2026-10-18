# Supabase Free Tier Keep-Alive & Project Unpause Guide

This document explains how to keep the MIPS ERP Supabase Free Tier project active during long vacations or semester breaks without incurring costs, and how to restore it if it ever gets paused.

---

## 1. Free Tier Inactivity Policy
- Supabase automatically pauses Free Tier projects that experience **7 consecutive days of inactivity** (zero API requests or database connections).
- In an academic institution, extended holidays (e.g., semester break, summer holidays, festival holidays) can exceed 7 days.
- When paused:
  - Data is NOT lost. The PostgreSQL database is safely frozen.
  - The API returns HTTP 503 / 410.
  - Client apps will report connection errors until unpaused.

---

## 2. Automated Keep-Alive Solution (Zero-Cost via GitHub Actions)

We have configured an automated GitHub Actions workflow:
`.github/workflows/supabase_keepalive.yml`

### How It Works:
- Runs automatically **twice a week** (Tuesday and Friday at 06:00 UTC / 11:30 AM IST).
- Sends a lightweight `GET` request to `/rest/v1/courses?select=id&limit=1` using the public `SUPABASE_ANON_KEY`.
- Registers valid API activity in Supabase, keeping the project active indefinitely throughout institutional holidays.

### Setup Instructions:
1. In your GitHub repository, navigate to **Settings** -> **Secrets and variables** -> **Actions**.
2. Add the following repository secrets:
   - `SUPABASE_URL`: e.g., `https://your-project.supabase.co`
   - `SUPABASE_ANON_KEY`: Your project's public anon key.
3. Test the workflow:
   - Go to the **Actions** tab in GitHub.
   - Click **"Supabase Free Tier Keep-Alive"** on the left menu.
   - Click **Run workflow** -> Select `main` branch -> Click green button.
   - Check the run logs to verify HTTP 200/206 status.

---

## 3. Checklist: Restoring a Paused Project from Dashboard

If GitHub Actions was not configured or the project was paused before setup:

### Steps:
1. Open browser and log in to [https://supabase.com/dashboard](https://supabase.com/dashboard).
2. Locate the **MIPS ERP** project card. It will show a yellow or grey badge labeled **"Paused"**.
3. Click on the project card.
4. Click the green button: **"Restore project"** (or **"Unpause project"**).
5. Wait **2 to 3 minutes** while Supabase spins up the compute instance and attaches the PostgreSQL volume.
6. Once the status shows **"Active"**:
   - Open the Flutter Admin App on the office PC.
   - Check the **System Health Card** to confirm database connectivity.
   - Click **"Backup Now"** to generate an immediate fresh backup to `Documents/MIPS_ERP_Database/Backups/`.
   - Verify that all students, fees, and results appear correctly.

---

## 4. Disaster Recovery from Encrypted Local Backup

If Supabase project cannot be restored or needs to be completely re-created on a fresh project:
1. Create a new Supabase project in the dashboard.
2. Apply migrations:
   ```bash
   supabase db push
   ```
3. Run the disaster recovery restore drill tool:
   ```bash
   dart run tools/restore_drill.dart "YOUR_BACKUP_PASSWORD"
   ```
4. Verify 100% reconciliation output (row counts, fee totals, payments, attendance records).
