# MIPS ERP — Office PC Daily Operations Runbook (1-Page Desk Reference)

> **Location**: Print and tape next to the primary Administrative Office PC  
> **Applicability**: MIPS Administrative Office PC (Windows 64-bit Desktop)  

---

## 1. Morning Startup Sequence

```mermaid
flowchart LR
    A["1. Power On PC & Connect Receipt Printer"] --> B["2. Launch MIPS ERP Desktop App"]
    B --> C["3. Auto-Backup Runs (~2 sec)"]
    C --> D["4. Check System Health Card (Green)"]
```

1. **Power On**: Turn on the office computer and ensure thermal receipt printer (or A4 office printer) is connected via USB and turned on.
2. **Launch Application**: Double-click the **MIPS ERP** desktop shortcut.
3. **Automatic Cloud Export**: On launch, the system automatically checks if a backup has occurred today. If not, it exports all database tables to an encrypted ZIP file in:
   ```
   C:\Users\hp\Documents\MIPS_ERP_Database\Backups\
   ```
4. **Log In**: Enter your administrative username and password.

---

## 2. Daily Offline Backup & USB Archiving (Evening Routine)

> [!IMPORTANT]
> **Daily Rule**: Before leaving the office, always export an archival copy to the institutional USB drive.

1. **Check Dashboard Health**:
   - Look at the **System Health & Offline Backup** card on the main dashboard.
   - **Date**: Must reflect today's date.
   - **Status**: Must be green. If an amber warning is visible (*"Last backup taken more than 3 days ago"*), click **Backup Now**.
2. **Copy to External USB Drive**:
   - Insert the designated college backup USB flash drive into the computer.
   - On the System Health card, click **Copy backup to another folder or drive**.
   - In the directory browser, select your USB flash drive (e.g., `E:\MIPS_Vault_Backups\`) and click **Select Folder**.
   - Wait for the green confirmation toast:
     > *"Backup copied successfully to USB: E:\MIPS_Vault_Backups\MIPS_Backup_YYYY-MM-DD.zip"*
   - Safely eject the USB drive and store it in the college administrative safe.

---

## 3. How to Know if Internet is Down & What Works Offline

### Visual Indicators:
- A prominent yellow/orange banner at the top of the application:
  > *"Offline Mode: Working from local database. Online cloud sync paused."*

### What Operates 100% Offline (Work NEVER Stops):
- ✅ New student admissions and editing student profiles.
- ✅ Collecting fee payments and printing receipts on the local thermal printer.
- ✅ Generating certificates (Bonafide, TC, Study, Fee Certificates).
- ✅ Scanning, cropping, and attaching student certificates and photographs.
- ✅ Local automated backups to the PC hard disk.

### What Requires Active Internet:
- 🌐 Publishing finalized exam results to the online student portal.
- 🌐 Receiving live attendance markings from teachers' smartphones.

> [!TIP]
> **When Internet Restores**: Simply resume normal operations. Click **Refresh** on Today's Attendance Board to pull any sessions marked by faculty.

---

## 4. Emergency Contacts & Escalation Matrix

If the system displays a connection blocker, database warning, or hardware failure:

| Role / Function | Contact Person | Phone / WhatsApp | Email |
|---|---|---|---|
| **College Principal** | Dr. Institutional Head | +91 98460 00001 | principal@mipsedu.in |
| **Administrative Officer** | Chief Accountant | +91 98460 00002 | office@mipsedu.in |
| **Lead Systems Engineer** | Antigravity DevOps / IT Support | +91 98460 00003 | support@mipsedu.in |
| **Cloud Hosting Provider** | Supabase Enterprise Status | [status.supabase.com](https://status.supabase.com) | Dashboard Unpause |

### Emergency Recovery Checklist (PC Replacement):
1. In the event of hard disk failure or PC replacement:
2. Retrieve the latest backup ZIP file from the USB flash drive.
3. On the new computer, open terminal in `mips_erp`:
   ```bash
   dart run tools/restore_drill.dart "MIPS@CollegeOffice#2026"
   ```
4. All student ledgers, fees, and results restore in under 1 second.
