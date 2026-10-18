# MIPS ERP — Administrator User Guide & Operations Manual

> **Document Type**: Institutional Administrator Operations Guide  
> **Audience**: College Principals, Administrative Officers, Accountants, Exam Officers  
> **System Scope**: Flutter Admin Desktop Native (Windows 64-bit) & Admin Web Management  

---

## 1. System Access, Login & Security

### 1.1 Launching the Application
- **Windows Desktop**: Double-click the **MIPS ERP** shortcut on the desktop (or launch `build\windows\x64\runner\Release\mips_erp.exe`).
- **Web Admin**: Open the institutional administrator URL in Google Chrome, Microsoft Edge, or Mozilla Firefox.

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Windows desktop login screen showing "MIPS ERP Administration Portal", username field, password field, and secure "Sign In" button]*

### 1.2 Administrative Login
1. Enter your designated **Username** (e.g., `admin`).
2. Enter your **Password**.
3. Click **Sign In**.

### 1.3 Security Protections & Lockout Policy
- **Sliding-Window Failure Protection**: If 5 consecutive failed login attempts occur within 15 minutes, the account is automatically locked for 15 minutes.
- **Anti-Enumeration Defense**: The system returns an identical error message (`"Username or password is incorrect"`) regardless of whether the username exists, preventing user harvesting.
- **Two-Factor Authentication (TOTP / MFA)**: Administrators can enroll a mobile authenticator app (Google Authenticator, Microsoft Authenticator) in **Settings** > **Security** for 6-digit TOTP verification on every login.
- **Inactivity Guard**: The session automatically terminates after 15 minutes of user inactivity to prevent unauthorized access on unattended office computers.

---

## 2. Institutional Dashboard & System Health

The dashboard serves as the daily command center for institutional operations.

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Main Administrator Dashboard displaying KPI metric cards at top, Today's Attendance Board in center, and System Health & Offline Backup card at right]*

### 2.1 Key Performance Indicators (KPIs)
- **Active Students**: Total students currently enrolled in active academic batches.
- **Total Fees Collected**: Real-time monetary collections for the current fiscal period.
- **Pending Balances**: Total outstanding tuition and lab fee dues across all batches.
- **Published Examinations**: Count of completed exams currently verified and accessible to students.

### 2.2 Today's Attendance Board
- Summarizes completion states for all active **Primary Course Batches** for today.
- Each batch displays side-by-side badges for the **Morning Slot** (09:00 AM – 12:30 PM) and **Evening Slot** (01:30 PM – 04:30 PM).
- **Badge Indicators**:
  - `Not Marked` (Amber): Slot has not yet been taken.
  - `Submitted` (Green): Session marked and locked by a teacher (displays teacher's name and submission timestamp).
  - `No Class` (Slate): Declared official holiday or class suspension with reason.
- Click **Review Session** on any submitted slot to jump directly to detailed attendance records.

### 2.3 System Health & Offline Backup Status Card
Monitors institutional database resilience and critical alerts:
- **Last Backup Date & Size**: Displays the exact timestamp and file size of the latest offline backup.
- **3-Day Stale Warning**: If the last backup is more than 3 days old, an amber banner warns:
  > *"Warning: Last offline backup was taken more than 3 days ago. Run an offline backup now to protect against data loss."*
- **Failed Logins (24 Hours)**: Count of rejected login attempts across the institution.
- **Locked Accounts**: Real-time count of accounts currently under temporary brute-force lockout.
- **Unmarked Sessions Today**: Count of primary batch slots remaining unmarked.
- **Action Buttons**:
  - **Backup Now**: Generates an immediate full cloud export.
  - **Copy backup to another folder or drive**: Opens a directory selector to clone the latest encrypted backup ZIP to a USB flash drive.

---

## 3. Student Admissions & Lifecycle Management

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: New Student Admission form showing Student Profile photo uploader, Personal Details fields, and Academic Enrolled Course dropdown]*

### 3.1 Admitting a New Student
1. Navigate to **Students** in the left sidebar and click **+ New Admission**.
2. **Personal Information**:
   - **Full Name**: Enter student's official name as registered on secondary school certificates.
   - **Date of Birth**: Select from the date picker (format: `YYYY-MM-DD`).
     > [!IMPORTANT]
     > The student's **Date of Birth** serves as their identity verification gate to activate their account on the student portal.
   - **Gender**: Select **Male**, **Female**, or **Other** (used automatically for certificate pronouns).
   - **Contact Details**: 10-digit mobile number, parent phone, and permanent residential address.
   - **Profile Photo**: Click upload area to attach passport portrait (system automatically optimizes display and thumbnail dimensions).
3. **Academic Enrollment**:
   - **Admission Number**: Auto-generated sequential identifier (e.g., `MIPS-2026-0042`).
   - **University / Board Reg No**: Optional university registration code.
   - **Enrolled Course**: Select primary course program (e.g., *Diploma in Medical Laboratory Technology*).
   - **Enrolled Batch**: Assign to the appropriate academic batch.
4. Click **Complete Admission**. The student's fee ledger is generated automatically based on the course fee structure.

### 3.2 Dual Enrollments (Primary + Skill Course)
If a student enrolls in a secondary Skill Course (e.g., *Phlebotomy Technician Certification*):
1. Open the student's profile and click **Add Enrollment**.
2. Select the Skill Course from the catalog.
3. The student ledger reflects both fee schedules independently.
4. **Attendance Policy**: Attendance applies exclusively to the primary course; skill course enrollments do not generate attendance sessions.

### 3.3 Bulk Excel Import & 1-Click Undo
1. Navigate to **Students** > **Bulk Import**.
2. Click **Download Sample Template** to retrieve `mips_student_import_template.xlsx`.
3. Populate rows with student records and upload the spreadsheet.
4. The system validates all columns (detecting duplicate admission numbers or invalid courses).
5. Click **Import Validated Rows**.
6. **Emergency Undo**: If a spreadsheet was uploaded in error, click **Undo Last Import** to safely revert the batch without modifying pre-existing records.

---

## 4. Fee Management, Collections & Receipts

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Fee Collection dialog showing student outstanding installments, payment mode selector, amount in Rupees, and thermal receipt print preview]*

### 4.1 Collecting Fee Payments
1. Navigate to **Fee Management** (or open the **Fees** tab on a student's profile).
2. Click **Collect Payment**.
3. Select or search for the student by Admission Number or Name.
4. Enter the **Amount Paid (₹)** (e.g., `15,000`).
5. Select **Payment Mode**: *Cash*, *UPI / GooglePay*, *Bank Transfer / NEFT*, or *Cheque*.
6. Enter optional transaction reference or remarks.
7. Click **Confirm & Process Payment**.

### 4.2 FIFO Installment Allocation
The payment engine automatically distributes collections using First-In, First-Out (FIFO) allocation against the student's oldest unpaid fee items based on due date. Any excess payment allocates forward to subsequent term installments.

### 4.3 Thermal & A4 Receipt Printing
Immediately upon payment confirmation:
- Click **Print Receipt**.
- Choose between:
  - **Thermal Slip (80mm)**: Compact slip with institution header, student details, amount paid, remaining balance, and verification QR code.
  - **A4 College Official Receipt**: Formal letterhead receipt with signature and stamp blocks.

### 4.4 Voiding / Cancelling a Receipt
1. Open **Fee Management** > **Payment Transactions**.
2. Locate the transaction receipt and click **Void / Cancel**.
3. **Mandatory Reason**: You must enter a clear explanation (e.g., `"Bounced cheque #40291"` or `"Erroneous double collection"`).
4. Click **Confirm Cancellation**.
5. The receipt is marked cancelled, the student's outstanding balance increases back automatically, and an immutable entry is logged in `audit_log`. Rows are never permanently deleted.

---

## 5. Examinations & Cloud Results Publishing

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Examination Marks Spreadsheet showing student rows, subject columns with Max/Pass headers, Pass/Fail color tags, and Publish Online button]*

### 5.1 Creating an Examination
1. Navigate to **Examinations** > Click **Create Exam**.
2. Enter **Exam Title** (e.g., *Second Year Semester Final - November 2026*).
3. Select **Course** and **Batch**.
4. The system automatically loads all curriculum subjects defined for the course, including their default Maximum Marks and Minimum Pass Marks.
5. Click **Save Examination**.

### 5.2 Entering Marks Spreadsheet
1. Click **Enter Marks** on the exam card.
2. Enter scores directly into the subject cells:
   - Type numeric score (e.g., `45` out of `50`).
   - Check **Absent** checkbox if student missed the paper.
3. The table dynamically computes:
   - Total Marks obtained.
   - Aggregate Percentage (%).
   - Pass / Fail status (turns green **PASS** or red **FAIL** if any individual subject falls below pass mark).
4. **Editing Max/Pass Marks on the Fly**:
   - Click any subject header (e.g., `Pathology [Max: 50 | Pass: 20]`) to update thresholds.
   - Click **Save & Recalculate** to instantly adjust all results.
5. Click **Save All Marks**.

### 5.3 Publishing Results Online to Cloud Portal
1. When all marks are finalized, click **Publish Online**.
2. The desktop software calls the secure cloud sync RPC `publish_results(jsonb)`.
3. The exam badge changes to **Published** (Green).
4. Students and parents can now instantly check and download their verified marksheets on the student web portal.

---

## 6. Attendance Monitoring & Administrative Corrections

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Session Review & Corrections screen showing date filter, submitted sessions list, Marked By teacher column, and Edit Correction modal with mandatory reason input]*

### 6.1 Reviewing Campus Attendance
1. Navigate to **Attendance Management** > **Session Review & Corrections**.
2. Select the target **Date** (defaults to today).
3. Review all submitted sessions, showing:
   - Course Name & Batch Name.
   - Slot (*Morning* or *Evening*).
   - Marked By (Teacher Name & Role).
   - Submission Timestamp.
   - Total Students Recorded.

### 6.2 Administrative Attendance Corrections
Because submitted sessions are locked and read-only for teachers, only administrators can modify attendance records:
1. Click **Review & Correct** on the submitted session row.
2. In the student table, locate the student whose status requires adjustment.
3. Select the corrected status (*Present*, *Absent*, *Late*, *Leave*).
4. **Mandatory Explanation Reason**: Enter an audit justification (minimum 5 characters, e.g., `"Medical leave certificate submitted for roll 14"`).
5. Click **Save Correction**.
6. The update immediately recalculates the student's attendance percentage and records a permanent, unalterable entry in `attendance_changes`.

---

## 7. Teacher Management & Open Faculty Model

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Faculty Management screen showing active teachers roster, Add Faculty button, and Deactivate button]*

### 7.1 Open Faculty Model
Under the institutional policy:
- Teachers are **not assigned** to specific batches or subjects.
- Any active teacher can mark attendance for **any active primary course batch**.
- Teachers have zero access to student sensitive details (DOB, phone, address, fee balances, examination marks).

### 7.2 Provisioning a New Teacher
1. Navigate to **Teachers** > Click **+ Add Faculty**.
2. Enter **Full Name**, **Username** (e.g., `prof_kumar`), and optional **Phone Number**.
3. Click **Create Teacher Account**.
4. The system provisions the account via the `create-teacher` Edge Function and displays a one-time temporary password.
5. Provide the credentials to the faculty member. They will be forced to choose a permanent password on first login.

### 7.3 Deactivating a Teacher
If a teacher departs the institution:
1. Click **Deactivate** on the teacher's card.
2. Confirm deactivation.
3. The system bans the teacher's auth user and revokes all active sessions immediately.
4. Historical attendance sessions previously marked by the teacher permanently retain their attribution.

---

## 8. Password Resets & Account Unlock

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Password Reset dialog showing temporary password generated for teacher, and student DOB reset trigger]*

### 8.1 Resetting a Teacher's Password
1. In **Teachers**, locate the faculty member and click **Reset Password**.
2. The system executes `reset-password` Edge Function and returns a one-time secure temporary password (e.g., `Mips#Temp9021`).
3. Communicate the temporary password securely to the teacher.

### 8.2 Resetting a Student's Password
1. In **Students**, search for the student and click **Reset Password**.
2. The system resets their auth account and sets `first_login_required = true`.
3. The student can now re-activate their account on the portal using their **Registration Number** and **Date of Birth**.

### 8.3 Unlocking Accounts
If a user is locked out due to 5 failed attempts:
1. Navigate to **Settings** > **Account Security**.
2. Locate the locked account under **Locked Accounts List**.
3. Click **Unlock Account**. The failure counter resets to 0.

---

## 9. Campus Announcements & Web Push Notifications

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Create Announcement composer showing Category selector, Title, Body, Send Web Push Notification toggle, and Publish button]*

1. Navigate to **Announcements** > Click **Create Announcement**.
2. Select **Audience**: *All Campus*, *Students Only*, or *Faculty Only*.
3. Select **Category**: *Academic*, *Exams*, *Fee Notice*, *Holiday*, or *Urgent*.
4. Enter **Title** and **Message Body**.
5. Check **Send Web Push Notification** to instantly alert subscribed mobile and desktop devices.
6. Click **Publish Announcement**.

---

## 10. Timetables & Clash Prevention

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Weekly Timetable grid showing Monday through Saturday periods and clash prevention warning badge]*

1. Navigate to **Timetable**.
2. Select the target **Primary Batch**.
3. Click on any period slot (e.g., *Wednesday Period 2, 10:00 - 11:00 AM*).
4. Assign the Subject and Classroom.
5. **Clash Detection**: If the assigned classroom is already booked by another batch at that exact time, the system flags a red clash warning and prevents saving until resolved.

---

## 11. Offline Backups & External Vault Copies

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Offline Backup modal showing progress bar, password envelope indicator, and completed backup archive saved to Documents]*

### 11.1 Performing a Manual Offline Backup
1. In the **System Health Card** on the Dashboard, click **Backup Now** (or navigate to **Settings** > **Master Database & Backups**).
2. The software queries the cloud database dump RPC `export_database_dump()`.
3. The data is packaged into an encrypted ZIP with SHA-256 checksums and saved to:
   ```
   C:\Users\hp\Documents\MIPS_ERP_Database\Backups\MIPS_Backup_YYYY-MM-DD_HHmmss.zip
   ```
4. The dashboard backup status updates to green.

### 11.2 Creating an External USB Archive Copy
1. Plug a USB flash drive into the office PC.
2. In the **System Health Card**, click **Copy backup to another folder or drive**.
3. In the folder browser, select your USB flash drive (e.g., `E:\MIPS_Vault_Backups\`).
4. Click **Select Folder**.
5. The software copies the latest encrypted archive to the USB drive and displays a confirmation notification.

### 11.3 Restoring from an Offline Backup
In the event of hardware failure or computer replacement:
1. Ensure the new PC has Flutter/Dart installed.
2. Open terminal in the application directory:
   ```bash
   dart run tools/restore_drill.dart "MIPS@CollegeOffice#2026"
   ```
3. The restore drill verifies all SHA-256 table checksums, unpacks the data, and reconciles all student and financial metrics in under 1 second.
