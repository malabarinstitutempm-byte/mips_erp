# Synthetic Email Domain Architecture & Authentication Configuration

## Overview & Institutional Requirements

MIPS ERP uses Supabase Auth as the identity provider for three distinct roles:
1. **Administrators**: System owners with administrative authority across all modules.
2. **Teachers**: Institutional staff who record classroom attendance and manage assigned academic periods.
3. **Students**: Learners who view academic results, fee ledgers, receipts, and personal attendance statistics.

To satisfy the system architecture requirements while operating within Supabase Auth's user entity model, **synthetic email addresses** are used for non-admin accounts.

---

## 1. Synthetic Email Domain Specification

| Role | User Identifier | Synthetic Auth Email Format | Email Delivery Status |
|---|---|---|---|
| **Student** | Registration Number (e.g., `REG2024001`) | `{registration_number lowercase}@students.mips.invalid` | **Never Sent / No Mailbox** |
| **Teacher** | Login Username (e.g., `prof_kumar`) | `{username lowercase}@teachers.mips.invalid` | **Never Sent / No Mailbox** |
| **Admin** | Real Email (e.g., `principal@mips.edu`) | Direct Real Email Address | Active Institutional Mailbox |

### Why RFC 2606 `.invalid` is Enforced
Under **IETF RFC 2606 ("Reserved Top Level DNS Names")**, the `.invalid` top-level domain is permanently reserved:
> *".invalid is intended for use in online construction of domain names that are generally invalid and cannot be resolved by the Domain Name System (DNS)."*

**Benefits:**
- **Zero Accidental Mail Leakage**: Even if a mail server misconfiguration occurs, public mail transfer agents (MTAs) immediately drop `.invalid` domains without DNS lookups.
- **No Domain Squatting**: No third party can ever register `.invalid` or intercept credentials.
- **No Mailbox Costs**: Eliminates the overhead of provisioning thousands of student mailboxes.
- **Deterministic Mapping**: Any student or teacher identifier maps 1:1 to an immutable internal auth identity.

---

## 2. Supabase Auth Configuration (`supabase/config.toml`)

The identity engine is configured with strict security boundaries:

```toml
[auth]
# STRICT: Disable public self-registration.
# No student, teacher, or external party can sign up directly.
enable_signup = false
enable_manual_linking = false

# Token Lifespans
jwt_expiry = 3600          # 1 hour access token (session freshness)
[auth.sessions]
timebox = "30d"            # 30-day refresh token lifespan
inactivity_timeout = "30d"

# Email Delivery Hardening: Turn off all email dispatches to prevent 
# SMTP attempts against synthetic @*.mips.invalid domains
[auth.email]
enable_signup = false
enable_confirmations = false
double_confirm_changes = false

[auth.email.template.confirmation]
enabled = false

[auth.email.template.recovery]
enabled = false

[auth.email.template.invite]
enabled = false

[auth.email.template.magic_link]
enabled = false

[auth.email.template.email_change]
enabled = false
```

---

## 3. Account Provisioning & Password Governance

### 1. Students
- **First Login**: Students navigate to the portal and enter their **Registration Number + Date of Birth + New Password**.
- The `student_first_login` Edge Function verifies their DOB against `students.dob` (without disclosing which field was wrong).
- The account is activated, credentials set, and the profile marked `first_login_required = false`.
- **Subsequent Logins**: Handled by the `login` Edge Function using `registration_number + password`.

### 2. Teachers
- **Provisioning**: Administrators create teacher accounts via `create_teacher`.
- A strong temporary password is generated and returned **once** to the administrator.
- Teacher logs in with `username + temporary_password`.
- Because `must_change_password = true`, the teacher must immediately set a permanent password before proceeding.

### 3. Password Resets (No Email Reset)
- Self-service email password recovery is explicitly disabled.
- **Student Reset**: An administrator calls `reset_password(user_id)`. The function invalidates the existing password with high-entropy random data, revokes all sessions, and sets `first_login_required = true`. The student then verifies their identity via Date of Birth on their next portal visit.
- **Teacher Reset**: An administrator calls `reset_password(user_id)`. A new temporary password is generated and returned once to the admin; `must_change_password` is set to `true`.

---

## 4. Bootstrapping Administrators (`create_admin.ts`)

Administrator accounts are bootstrapped using the offline CLI utility:

```bash
npx tsx scripts/create_admin.ts --email=admin@example.com --name="Principal"
```

**Security Rules:**
1. Administrators **must use real email addresses** (the script explicitly rejects `.invalid` domains for admins).
2. The `SUPABASE_SERVICE_ROLE_KEY` is loaded from local environment variables or `.env` and is **never** committed or exposed to client apps.
3. The script generates a 16-character temporary password printed once to `stdout`.
4. The profile is initialized with `role = 'admin'` and `must_change_password = true`.
