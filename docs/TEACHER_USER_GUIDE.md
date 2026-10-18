# MIPS ERP — Teacher User Guide & Operations Manual

> **Document Type**: Faculty Attendance & Academic Portal Guide  
> **Audience**: Faculty Members, Clinical Instructors, Department HODs  
> **Platform**: Web Browser (Mobile, Tablet, and Desktop responsive)  

---

## 1. Accessing the Faculty Portal

### 1.1 Web Portal URL
Open your preferred web browser (Google Chrome, Safari, Microsoft Edge, or Firefox) on your mobile phone, tablet, or laptop and navigate to:
```
https://portal.mipsedu.in   (or institution-provided portal URL)
```

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Clean Navy-themed Portal Login screen displaying username input, password input, and "Sign In to Faculty Portal" button]*

### 1.2 First-Time Login
1. Enter your **Username** provided by the administrative office (e.g., `prof_kumar`).
2. Enter the **Temporary Password** issued to you.
3. Click **Log In**.
4. **Mandatory Password Change**: On your first login, the system will prompt you to establish a permanent private password.
   - **Password Rules**: Minimum 8 characters; must not contain your username or common dictionary sequences.
5. Once saved, your active faculty dashboard will open immediately.

---

## 2. Universal Faculty Permissions Model

Under the institutional policy:
- Teachers are **not assigned** to specific courses, batches, or subjects.
- Any active faculty member can mark attendance for **any active Primary Course batch** across campus.
- **Attendance Exclusivity**: Attendance tracking is conducted strictly for Primary Programs (e.g., *DMLT*, *DOTAT*). Short-term skill courses do not take attendance.
- **Student Privacy Protection**: Faculty rosters display strictly safe academic identifiers (**Name**, **Registration Number**, **Admission Number**, and **Batch**). Faculty cannot view student Date of Birth, Phone Numbers, Residential Addresses, Fee Balances, or Examination Marks.

---

## 3. Step-by-Step Attendance Marking Workflow

Navigate to the **Attendance** tab in the top navigation bar.

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Attendance Tab guided flow showing Step 1 Primary Course selection buttons, Step 2 Batch cards with live slot status badges, and Step 3 Date & Slot segmented control]*

### Step 1: Select Primary Course
- Click on the relevant primary academic program from the course selector (e.g., `Diploma in Medical Laboratory Technology [DMLT]`).

### Step 2: Select Batch & Review Slot Status
- Each active batch row displays today's live completion state for both slots:
  - **Morning**: `Not Marked` (Amber), `Marked by {Teacher}` (Green), or `No Class` (Slate).
  - **Evening**: `Not Marked` (Amber), `Marked by {Teacher}` (Green), or `No Class` (Slate).
- Click on the batch card you wish to mark (e.g., `Batch 2024-26`).

### Step 3: Select Date & Slot
- **Session Date**: Automatically defaults to today (`YYYY-MM-DD`). Future dates are disabled.
- **Slot Control**: Select either:
  - **Morning Slot** (09:00 AM – 12:30 PM)
  - **Evening Slot** (01:30 PM – 04:30 PM)

---

## 4. Marking Student Records

Once the batch and slot are selected, the student roster renders:

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Student attendance marking table showing student rows, Present/Late/Absent/Leave segmented toggle buttons, "Mark All Present" shortcut button, and live stats breakdown bar]*

### 4.1 Attendance Status Options
For each student in the list, toggle their attendance status:
- **Present** (Green button): Student attended the session on time.
- **Late** (Amber button): Student arrived late (calculated as 0.5 weight toward attendance percentage).
- **Absent** (Rose button): Unexcused absence.
- **Leave** (Slate button): Approved medical or institutional leave (excluded from denominator calculations).

### 4.2 Quick Actions & Search
- **Mark All Present**: Click the green **Mark All Present** button at top-right to immediately set all students to *Present*. You can then quickly switch individual absent students.
- **Student Search**: Type a student's name or registration number into the search box to filter long batch lists instantly.

### 4.3 Real-Time Breakdown Bar
As you toggle statuses, the summary bar updates in real time:
- **Total Students** enrolled in batch.
- Live counts of **Present**, **Late**, **Absent**, and **Leave**.
- **Effective Session Percentage (%)**.

---

## 5. Finalizing & Submitting Attendance

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Confirm Attendance Submission modal showing batch title, date, slot, breakdown summary (Present: 28, Late: 1, Absent: 1), and Confirm & Finalize button]*

1. Click **Submit Attendance** at the bottom of the table.
2. Review the **Confirm Attendance Submission** modal summary:
   - Verifies the total student count, date, slot, and breakdown.
3. Click **Confirm & Finalize**.
4. The session is committed to the cloud database and **permanently locked**.
5. The slot status immediately changes to green:
   > *"Marked by Prof. {Your Name} at {Timestamp}"*

---

## 6. Declaring "No Class Conducted"

If classes are suspended due to an official holiday, sports meet, symposium, or faculty absence:

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Mark No Class modal showing official reason dropdown (College Holiday, Faculty Symposium, Emergency Suspension) and Confirm No Class button]*

1. On the attendance screen, click **Mark No Class**.
2. Select or enter the official reason:
   - *Public / State Holiday*
   - *College Annual Day / Sports Day*
   - *Campus Examination Conduction*
   - *Special Administrative Suspension*
3. Click **Confirm No Class**.
4. The slot is recorded as `No Class`. Sessions marked as *No Class* are automatically excluded from student attendance percentages so student records are not penalized.

---

## 7. Shared Slot States & Race Condition Protection

To prevent conflicting submissions across faculty members:

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Amber Session Locked Alert Banner showing "Already marked by Prof. Fatima Zehra at 10:15 AM. Only the administrator can correct it. Editing disabled."]*

### 7.1 Already Marked Sessions
- If another teacher has already submitted the chosen slot, the screen opens in **Read-Only Mode**.
- An amber alert banner displays:
  > *"Session Locked • Read-Only View: Already marked by Prof. Fatima Zehra at 10:15 AM. Only the administrator can correct it."*
- All attendance toggles and submit buttons are disabled.

### 7.2 Parallel Submission Race Handling
- If you and another teacher have the same slot open at the same time, the system uses an atomic database lock during submission.
- The first submission commits successfully.
- If you submit second, the system will **not overwrite** the existing session. It returns an `ALREADY_MARKED` notification:
  > *"This slot was already submitted by {Other Teacher}. Your entries remain on screen for review but were not committed."*
- **Administrative Corrections Only**: If an error occurred in marking, contact the college administrative office. Only administrators can issue corrections.

---

## 8. "Today's Board" & "My Marked Sessions"

Toggle sections at the top of the Attendance screen:

### 8.1 Today's Board
- Provides a bird's-eye view of all primary batches across campus for today.
- Displays Morning and Evening states, who marked each session, and exact timestamps.
- Features a 1-click **Mark Slot** button on any unmarked slot to jump straight into marking.

### 8.2 My Marked Sessions
- Lists all historical attendance sessions marked under your faculty login.
- Review past dates, batch names, slot types, student counts, and submission times.

---

## 9. Troubleshooting & What To Do If Something Goes Wrong

### Q1: An amber "You're offline" banner appears.
- **Cause**: Network connection temporarily interrupted.
- **Action**: Do **not** refresh or close the browser tab. Your entered marks remain safely in your browser memory. When connectivity restores, click **Retry** or **Submit Attendance**.

### Q2: I accidentally marked the wrong student absent.
- **Cause**: Human error during live roll call.
- **Action**: Once finalized, teachers cannot edit submitted sessions. Send a brief note or message to the college administrative office with the **Date**, **Batch**, **Slot**, **Student Name**, and **Correct Status**. The administrator will make the correction in the Session Review tab, which is permanently logged in the audit trail.

### Q3: My session timed out with an inactivity warning.
- **Cause**: Browser left open with no touches or mouse activity for 15 minutes.
- **Action**: Log back in. The system preserves recently viewed state.

---

## 10. Signing Out Safely

> [!NOTE]
> **SCREENSHOT PLACEHOLDER**: *[Screenshot: Top header showing red Log Out button (44x44 touch target) and Confirm Sign Out dialog]*

1. Click the **Log Out** button located on the top right of the navigation header.
2. On the **Confirm Sign Out** modal, click **Sign Out**.
3. **Security Actions Performed**:
   - Clears active session tokens.
   - Unsubscribes Web Push Notifications on this device.
   - Clears cached student data from the browser memory.
   - Redirects to the login screen, preventing back-button access on shared devices.
