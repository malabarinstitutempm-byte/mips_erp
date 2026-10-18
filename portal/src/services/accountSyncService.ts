// src/services/accountSyncService.ts
// Cross-App Credential Synchronization and First-Time Verification Store

export interface AccountSyncData {
  identifier: string; // lowercase, e.g. '2023mlt042', 'prof_kumar'
  role?: 'student' | 'teacher' | 'admin';
  name?: string;
  status?: 'active' | 'not_activated' | 'locked' | 'inactive';
  firstLoginRequired?: boolean;
  password?: string | null;
  tempPassword?: string | null;
  mustChangePassword?: boolean;
  phone?: string;
  dob?: string;
  updatedAt?: string;
}

const STORAGE_KEY = 'mips_portal_synced_accounts';

// Institutional defaults for local/dev fallback when Supabase tables are offline
const INITIAL_DEFAULTS: Record<string, AccountSyncData> = {
  '2023mlt042': {
    identifier: '2023mlt042',
    role: 'student',
    name: 'Muhammed Nihal C',
    status: 'active',
    firstLoginRequired: false,
    dob: '2004-08-15',
  },
  'adm-2026-0001': {
    identifier: 'adm-2026-0001',
    role: 'student',
    name: 'Aisha K',
    status: 'active',
    firstLoginRequired: false,
    dob: '2005-05-15',
  },
  'prof_kumar': {
    identifier: 'prof_kumar',
    role: 'teacher',
    name: 'Prof. Suresh Kumar',
    status: 'active',
    firstLoginRequired: false,
    phone: '9845001122',
  },
  'fatima_noor': {
    identifier: 'fatima_noor',
    role: 'teacher',
    name: 'Dr. Fatima Noor',
    status: 'active',
    firstLoginRequired: false,
    phone: '9845123456',
  },
  'ahmed_raza': {
    identifier: 'ahmed_raza',
    role: 'teacher',
    name: 'Prof. Ahmed Raza',
    status: 'active',
    firstLoginRequired: false,
    phone: '9876543210',
  },
  'zaid_t': {
    identifier: 'zaid_t',
    role: 'teacher',
    name: 'Sheikh Zaid Tariq',
    status: 'active',
    firstLoginRequired: false,
    phone: '9966332211',
  },
  'bilal_h': {
    identifier: 'bilal_h',
    role: 'teacher',
    name: 'Usthad Bilal Hussain',
    status: 'inactive',
    firstLoginRequired: false,
    phone: '9744112233',
  },
};

class AccountSyncService {
  private accounts: Record<string, AccountSyncData> = {};
  private isLoaded = false;

  constructor() {
    this.loadFromStorage();
    this.syncFromBackend();
  }

  private loadFromStorage() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        this.accounts = { ...INITIAL_DEFAULTS, ...JSON.parse(stored) };
      } else {
        this.accounts = { ...INITIAL_DEFAULTS };
      }
    } catch (_) {
      this.accounts = { ...INITIAL_DEFAULTS };
    }
    this.isLoaded = true;
  }

  private saveToStorage() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.accounts));
    } catch (_) {}
  }

  public async syncFromBackend(): Promise<void> {
    try {
      if (typeof window === 'undefined' || !window.fetch) return;
      const res = await fetch('/api/account-sync', { method: 'GET' });
      if (res.ok) {
        const remoteData = await res.json();
        if (remoteData && typeof remoteData === 'object') {
          Object.keys(remoteData).forEach((key) => {
            const cleanKey = key.trim().toLowerCase();
            this.accounts[cleanKey] = {
              ...(this.accounts[cleanKey] || {}),
              ...remoteData[key],
              identifier: cleanKey,
            };
          });
          this.saveToStorage();
        }
      }
    } catch (_) {
      // Backend sync endpoint may be unreachable in some test environments
    }
  }

  public getAccount(identifier: string): AccountSyncData | null {
    if (!this.isLoaded) this.loadFromStorage();
    const cleanId = identifier.trim().toLowerCase();
    return this.accounts[cleanId] || null;
  }

  public async updateAccount(identifier: string, data: Partial<AccountSyncData>): Promise<AccountSyncData> {
    const cleanId = identifier.trim().toLowerCase();
    const existing = this.accounts[cleanId] || { identifier: cleanId };
    const updated: AccountSyncData = {
      ...existing,
      ...data,
      identifier: cleanId,
      updatedAt: new Date().toISOString(),
    };

    this.accounts[cleanId] = updated;
    this.saveToStorage();

    // Push to Vite dev middleware endpoint
    try {
      if (typeof window !== 'undefined' && window.fetch) {
        await fetch('/api/account-sync', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(updated),
        });
      }
    } catch (_) {}

    return updated;
  }

  /// Invalidate password and require first-time login
  public async resetToFirstLogin(identifier: string, role: 'student' | 'teacher' = 'student'): Promise<void> {
    await this.updateAccount(identifier, {
      role,
      status: 'not_activated',
      firstLoginRequired: true,
      password: null,
      tempPassword: null,
      mustChangePassword: false,
    });
  }

  /// Invalidate old password and set a temporary password requiring change on login
  public async setTemporaryPassword(identifier: string, tempPassword: string, role?: 'student' | 'teacher'): Promise<void> {
    await this.updateAccount(identifier, {
      ...(role ? { role } : {}),
      status: 'active',
      firstLoginRequired: false,
      password: null,
      tempPassword,
      mustChangePassword: true,
    });
  }

  /// Establish permanent password upon first login or password change
  public async setPermanentPassword(identifier: string, newPassword: string): Promise<void> {
    await this.updateAccount(identifier, {
      status: 'active',
      firstLoginRequired: false,
      password: newPassword,
      tempPassword: null,
      mustChangePassword: false,
    });
  }

  /// Normalize phone string to compare 10-digit indian numbers
  public cleanPhone(phone: string): string {
    const digits = phone.replace(/\D/g, '');
    return digits.length > 10 ? digits.slice(-10) : digits;
  }

  /// Teacher record lookup for first-time verification
  public findTeacher(username: string): AccountSyncData | null {
    const clean = username.trim().toLowerCase();
    const direct = this.getAccount(clean);
    if (direct && direct.role === 'teacher') return direct;

    // Search by username
    for (const key of Object.keys(this.accounts)) {
      const acc = this.accounts[key];
      if (acc.role === 'teacher' && (key === clean || acc.identifier === clean)) {
        return acc;
      }
    }
    return null;
  }
}

export const accountSyncService = new AccountSyncService();
