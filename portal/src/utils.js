// Helper utilities for date formatting, validation and mock sample data

export function formatDobInput(value) {
  const clean = value.replace(/\D/g, '').slice(0, 8);
  if (clean.length <= 2) {
    return clean;
  }
  if (clean.length <= 4) {
    return `${clean.slice(0, 2)} / ${clean.slice(2)}`;
  }
  return `${clean.slice(0, 2)} / ${clean.slice(2, 4)} / ${clean.slice(4, 8)}`;
}

export function parseDobToIso(formattedValue) {
  if (!formattedValue) return null;
  const digits = formattedValue.replace(/\D/g, '');
  if (digits.length !== 8) return null;
  const day = digits.slice(0, 2);
  const month = digits.slice(2, 4);
  const year = digits.slice(4, 8);

  const d = parseInt(day, 10);
  const m = parseInt(month, 10);
  const y = parseInt(year, 10);

  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1920 || y > 2025) {
    return null;
  }
  return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
}

export function formatDate(dateString) {
  if (!dateString) return '—';
  try {
    const d = new Date(dateString);
    if (isNaN(d.getTime())) return dateString;
    return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
  } catch (_) {
    return dateString;
  }
}

export function formatDateTime(dateString = new Date()) {
  try {
    const d = new Date(dateString);
    if (isNaN(d.getTime())) return new Date().toLocaleString();
    return d.toLocaleString('en-IN', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: true,
    });
  } catch (_) {
    return new Date().toLocaleString();
  }
}

// Sample published results for demo & testing verification
export function getSampleResults() {
  return [
    {
      id: 101,
      exam_id: 1,
      exam_name: 'First Year B.Sc MLT Annual Examination',
      course: 'B.Sc Medical Laboratory Technology',
      batch: '2024 - 2027',
      register_no: 'MIPS24BDT001',
      student_name: 'Fathima Nihala K',
      total: 412,
      percentage: 82.4,
      grade: 'A',
      result_status: 'Pass',
      result_code: 'MIPS-EX2026-001',
      published_at: '2026-10-10T10:00:00Z',
      subjects_json: [
        { name: 'Human Anatomy & Physiology', max: 100, obtained: 88, status: 'Pass' },
        { name: 'Clinical Biochemistry I', max: 100, obtained: 78, status: 'Pass' },
        { name: 'General Microbiology & Immunology', max: 100, obtained: 82, status: 'Pass' },
        { name: 'Haematology & Blood Banking', max: 100, obtained: 84, status: 'Pass' },
        { name: 'Pathology & Cytology Techniques', max: 100, obtained: 80, status: 'Pass' },
      ],
    },
    {
      id: 102,
      exam_id: 2,
      exam_name: 'Semester I Mid-Term Assessment',
      course: 'B.Sc Medical Laboratory Technology',
      batch: '2024 - 2027',
      register_no: 'MIPS24BDT001',
      student_name: 'Fathima Nihala K',
      total: 89,
      percentage: 89.0,
      grade: 'A+',
      result_status: 'Pass',
      result_code: 'MIPS-EX2026-002',
      published_at: '2026-06-15T09:30:00Z',
      subjects_json: [
        { name: 'Basic Principles of Biochemistry', max: 50, obtained: 46, status: 'Pass' },
        { name: 'General Anatomy Basics', max: 50, obtained: 43, status: 'Pass' },
      ],
    },
  ];
}

export function generatePdfMarkup(result) {
  const subjects = Array.isArray(result.subjects_json) ? result.subjects_json : [];
  const totalMax = subjects.reduce((sum, s) => sum + (Number(s.max) || 100), 0) || 500;
  const isPass = result.result_status === 'Pass';

  return `
    <div style="font-family: 'Plus Jakarta Sans', Arial, sans-serif; padding: 24px 30px; background: #ffffff; color: #0B2A4A; box-sizing: border-box; width: 100%;">
      
      <!-- 1. Header with Logo, College Name & Examination Title -->
      <div style="display: flex; align-items: center; justify-content: space-between; border-bottom: 2px solid #0B2A4A; padding-bottom: 14px; margin-bottom: 18px;">
        <div style="display: flex; align-items: center; gap: 14px;">
          <img src="/logo.png" alt="MIPS" style="height: 48px; width: 48px; object-fit: contain;" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';" />
          <div style="width: 48px; height: 48px; border-radius: 8px; background: #0B2A4A; color: #ffffff; font-weight: bold; font-size: 24px; display: none; align-items: center; justify-content: center;">M</div>
          <div>
            <div style="font-size: 18px; font-weight: 800; color: #0B2A4A; letter-spacing: -0.02em; line-height: 1.2;">MALABAR INSTITUTE OF PARAMEDICAL SCIENCE</div>
            <div style="font-size: 11px; color: #5B6B7F; margin-top: 2px;">CH Centre, Malappuram, Kerala - 676519</div>
          </div>
        </div>
        <div style="text-align: right;">
          <div style="display: inline-block; background: #0B2A4A; color: #ffffff; padding: 4px 10px; border-radius: 4px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em;">Examination Result</div>
          <div style="font-size: 12px; font-weight: 700; color: #0B2A4A; margin-top: 4px;">${result.exam_name}</div>
        </div>
      </div>

      <!-- 2. Student Details Box -->
      <div style="border: 1px solid #C9D4E3; border-radius: 12px; padding: 12px 18px; margin-bottom: 16px; background: #F7F9FC;">
        <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
          <tr>
            <td style="width: 26%; padding: 4px 0;">
              <span style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase; display: block;">Student Name</span>
              <strong style="font-size: 13px; color: #0B2A4A;">${result.student_name}</strong>
            </td>
            <td style="width: 24%; padding: 4px 0;">
              <span style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase; display: block;">Register Number</span>
              <strong style="font-size: 13px; color: #0B2A4A; letter-spacing: 0.05em;">${result.register_no}</strong>
            </td>
            <td style="width: 30%; padding: 4px 0;">
              <span style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase; display: block;">Course</span>
              <span style="font-weight: 600; color: #0B2A4A;">${result.course}</span>
            </td>
            <td style="width: 20%; padding: 4px 0;">
              <span style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase; display: block;">Batch</span>
              <span style="font-weight: 600; color: #0B2A4A;">${result.batch || '—'}</span>
            </td>
          </tr>
        </table>
      </div>

      <!-- 3. Summary Stat Tiles -->
      <div style="display: flex; gap: 12px; margin-bottom: 18px;">
        <div style="flex: 1; border: 1px solid #C9D4E3; border-radius: 10px; padding: 10px 14px; background: #ffffff;">
          <div style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase;">Total Marks</div>
          <div style="font-size: 18px; font-weight: 800; color: #0B2A4A; margin-top: 2px;">${result.total} <span style="font-size: 12px; font-weight: 600; color: #5B6B7F;">/ ${totalMax}</span></div>
        </div>
        <div style="flex: 1; border: 1px solid #C9D4E3; border-radius: 10px; padding: 10px 14px; background: #ffffff;">
          <div style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase;">Percentage</div>
          <div style="font-size: 18px; font-weight: 800; color: #0B2A4A; margin-top: 2px;">${Number(result.percentage).toFixed(1)}%</div>
        </div>
        <div style="flex: 1; border: 1px solid #C9D4E3; border-radius: 10px; padding: 10px 14px; background: #ffffff;">
          <div style="font-size: 10px; font-weight: 700; color: #5B6B7F; text-transform: uppercase;">Grade</div>
          <div style="font-size: 18px; font-weight: 800; color: #0B2A4A; margin-top: 2px;">${result.grade}</div>
        </div>
        <div style="flex: 1; border: 1px solid ${isPass ? '#BFE6D1' : '#F3BDBD'}; border-radius: 10px; padding: 10px 14px; background: ${isPass ? '#E3F6EC' : '#FDECEC'}; color: ${isPass ? '#0B5D3B' : '#8A1F1F'};">
          <div style="font-size: 10px; font-weight: 700; text-transform: uppercase;">Result</div>
          <div style="font-size: 18px; font-weight: 800; margin-top: 2px; text-transform: uppercase;">${result.result_status}</div>
        </div>
      </div>

      <!-- 4. Subject-wise Marks Table (12pt text, borders) -->
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 24px; font-size: 12pt; border: 1px solid #C9D4E3;">
        <thead>
          <tr style="background-color: #F7F9FC; border-bottom: 1.5px solid #0B2A4A;">
            <th style="padding: 9px 12px; text-align: left; font-size: 11pt; font-weight: 700; color: #0B2A4A; text-transform: uppercase;">Subject</th>
            <th style="padding: 9px 12px; text-align: center; font-size: 11pt; font-weight: 700; color: #0B2A4A; text-transform: uppercase; width: 110px;">Max Marks</th>
            <th style="padding: 9px 12px; text-align: center; font-size: 11pt; font-weight: 700; color: #0B2A4A; text-transform: uppercase; width: 140px;">Marks Obtained</th>
            <th style="padding: 9px 12px; text-align: center; font-size: 11pt; font-weight: 700; color: #0B2A4A; text-transform: uppercase; width: 100px;">Status</th>
          </tr>
        </thead>
        <tbody>
          ${subjects.map((sub, idx) => {
            const passSub = sub.status === 'Pass';
            const bg = idx % 2 === 1 ? '#FAFBFD' : '#FFFFFF';
            return `
              <tr style="background-color: ${bg}; border-bottom: 1px solid #E1E8F2;">
                <td style="padding: 8px 12px; font-weight: 600; color: #0B2A4A;">${sub.name || sub.subject}</td>
                <td style="padding: 8px 12px; text-align: center; color: #5B6B7F;">${sub.max || 100}</td>
                <td style="padding: 8px 12px; text-align: center; font-weight: 700; color: #0B2A4A;">${sub.obtained ?? '—'}</td>
                <td style="padding: 8px 12px; text-align: center; font-weight: 700; color: ${passSub ? '#0B5D3B' : '#8A1F1F'};">
                  ${sub.status || 'Pass'}
                </td>
              </tr>
            `;
          }).join('')}
          <tr style="background-color: #F3F6FB; border-top: 2px solid #0B2A4A; font-weight: bold;">
            <td style="padding: 10px 12px; color: #0B2A4A;">Total</td>
            <td style="padding: 10px 12px; text-align: center; color: #0B2A4A;">${totalMax}</td>
            <td style="padding: 10px 12px; text-align: center; color: #0B2A4A; font-size: 13pt;">${result.total}</td>
            <td style="padding: 10px 12px; text-align: center; color: ${isPass ? '#0B5D3B' : '#8A1F1F'}; text-transform: uppercase;">
              ${result.result_status}
            </td>
          </tr>
        </tbody>
      </table>

      <!-- 5. Signatures -->
      <div style="display: flex; justify-content: space-between; margin-top: 36px; margin-bottom: 22px; padding: 0 10px;">
        <div style="text-align: center;">
          <div style="width: 130px; border-bottom: 1px solid #0B2A4A; margin-bottom: 6px;"></div>
          <span style="font-size: 10px; font-weight: 600; color: #5B6B7F; text-transform: uppercase;">Prepared By</span>
        </div>
        <div style="text-align: center;">
          <div style="width: 130px; border-bottom: 1px solid #0B2A4A; margin-bottom: 6px;"></div>
          <span style="font-size: 10px; font-weight: 600; color: #5B6B7F; text-transform: uppercase;">Verified By</span>
        </div>
        <div style="text-align: center;">
          <div style="width: 170px; border-bottom: 1px solid #0B2A4A; margin-bottom: 6px;"></div>
          <span style="font-size: 10px; font-weight: 600; color: #5B6B7F; text-transform: uppercase;">Controller of Examinations</span>
        </div>
      </div>

      <!-- 6. Disclaimer & Result Code -->
      <div style="border-top: 1px solid #C9D4E3; padding-top: 10px; text-align: center; font-size: 10px; color: #5B6B7F;">
        <p style="margin: 0;">This is a computer-generated result for information purposes only.</p>
        <p style="margin: 3px 0 0 0; font-family: monospace;">
          Result code: <strong style="color: #0B2A4A;">${result.result_code}</strong> · Generated on ${formatDateTime()}
        </p>
      </div>

    </div>
  `;
}

