// portal/src/test/phase10_daily_timetable.test.tsx
// Phase 10C Automated Verification Test Suite

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { dailyTimetableService } from '../services/dailyTimetableService';
import { TimetableTab } from '../components/student/TimetableTab';
import { TeacherTimetableTab } from '../components/teacher/TeacherTimetableTab';
import { StudentEnrollmentInfo } from '../services/studentService';

describe('Phase 10C - Daily Timetable Architecture', () => {
  let queryClient: QueryClient;

  beforeEach(() => {
    queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false, cacheTime: 0 },
      },
    });
    localStorage.clear();

    vi.spyOn(dailyTimetableService, 'getDailyTimetable').mockImplementation(async (dateStr, heading) => ({
      isPublished: true,
      status: 'published',
      date: dateStr,
      heading,
      entries: [
        {
          id: 1,
          date: dateStr,
          courseName: 'DMLT',
          year: '1st Year',
          teacherName: 'Prof. Suresh Kumar',
          subjectName: 'Clinical Biochemistry',
          classRoom: 'LH-1',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
          sortOrder: 1,
        },
        {
          id: 2,
          date: dateStr,
          courseName: 'DRT',
          year: '1st Year',
          teacherName: 'Dr. Aysha Mariyam',
          subjectName: 'Radiographic Anatomy',
          classRoom: 'LH-2',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
          sortOrder: 2,
        },
        {
          id: 7,
          date: dateStr,
          courseName: 'DRT',
          year: '2nd Year',
          teacherName: 'Dr. Aysha Mariyam',
          subjectName: 'Special Radiographic Procedures',
          classRoom: 'X-Ray Room 1',
          startTime: '02:00 PM',
          endTime: '03:00 PM',
          sortOrder: 7,
        },
      ],
    }));
  });

  const renderWithClient = (ui: React.ReactElement) => {
    return render(<QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>);
  };

  it('1. getKolkataDate generates correct Tomorrow and Today headings in IST', () => {
    const tomorrowInfo = dailyTimetableService.getKolkataDate(1);
    expect(tomorrowInfo.heading).toMatch(/^Tomorrow, (Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) \d{1,2} [A-Z][a-z]{2}$/);
    expect(tomorrowInfo.dateStr).toMatch(/^\d{4}-\d{2}-\d{2}$/);

    const todayInfo = dailyTimetableService.getKolkataDate(0);
    expect(todayInfo.heading).toMatch(/^Today, (Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) \d{1,2} [A-Z][a-z]{2}$/);
    expect(todayInfo.dateStr).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('2. Student TimetableTab opens directly on Tomorrow without calendar or month view', async () => {
    const mockEnrollments: StudentEnrollmentInfo[] = [
      {
        enrollmentId: 101,
        courseId: 1,
        courseName: 'Diploma in Medical Laboratory Technology (DMLT)',
        courseType: 'primary',
        batchId: 1,
        batchName: 'Batch 2025-27 (1st Year)',
        status: 'active',
        completedOn: null,
      },
    ];

    renderWithClient(<TimetableTab enrollments={mockEnrollments} />);

    // Should display tomorrow heading immediately
    const tomorrowInfo = dailyTimetableService.getKolkataDate(1);
    await waitFor(() => {
      expect(screen.getByText(tomorrowInfo.heading)).toBeInTheDocument();
    }, { timeout: 4000 });

    // Should display small text link to toggle Today
    const todayLink = screen.getByRole('button', { name: /today's timetable/i });
    expect(todayLink).toBeInTheDocument();

    // No calendar grid or month picker
    expect(screen.queryByText('Select Month')).not.toBeInTheDocument();
    expect(screen.queryByText('Select Week')).not.toBeInTheDocument();

    // Clicking Today link switches to today's timetable
    fireEvent.click(todayLink);

    const todayInfo = dailyTimetableService.getKolkataDate(0);
    await waitFor(() => {
      expect(screen.getByText(todayInfo.heading)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /tomorrow's timetable/i })).toBeInTheDocument();
    }, { timeout: 4000 });
  });

  it('3. Student TimetableTab filters rows to active student course and year only', async () => {
    const mockEnrollments: StudentEnrollmentInfo[] = [
      {
        enrollmentId: 101,
        courseId: 1,
        courseName: 'DMLT',
        courseType: 'primary',
        batchId: 1,
        batchName: 'Batch 2025-27 (1st Year)',
        status: 'active',
        completedOn: null,
      },
    ];

    renderWithClient(<TimetableTab enrollments={mockEnrollments} />);

    await waitFor(() => {
      // DMLT 1st Year class should be visible
      expect(screen.getAllByText('Clinical Biochemistry').length).toBeGreaterThan(0);
    }, { timeout: 4000 });

    // DRT or 2nd year classes should NOT be shown in the student's personal view
    expect(screen.queryByText('Radiographic Anatomy')).not.toBeInTheDocument();
    expect(screen.queryByText('Special Radiographic Procedures')).not.toBeInTheDocument();
  });

  it('4. TeacherTimetableTab shows all rows with teacher classes highlighted and filters on My Classes Only', async () => {
    renderWithClient(
      <TeacherTimetableTab teacherId={10} teacherName="Prof. Suresh Kumar" />
    );

    const tomorrowInfo = dailyTimetableService.getKolkataDate(1);
    await waitFor(() => {
      expect(screen.getByText(tomorrowInfo.heading)).toBeInTheDocument();
      expect(screen.getAllByText('Clinical Biochemistry').length).toBeGreaterThan(0);
    }, { timeout: 4000 });

    // "Your Class" badge should appear for Prof. Suresh Kumar's class
    expect(screen.getAllByText(/your class/i).length).toBeGreaterThan(0);

    // Click "My classes only"
    const myClassesBtn = screen.getByRole('button', { name: /my classes only/i });
    fireEvent.click(myClassesBtn);

    await waitFor(() => {
      // Suresh Kumar's subjects stay visible
      expect(screen.getAllByText('Clinical Biochemistry').length).toBeGreaterThan(0);
      // Other teachers' classes (e.g. Dr. Aysha Mariyam's Radiographic Anatomy) are hidden
      expect(screen.queryByText('Radiographic Anatomy')).not.toBeInTheDocument();
    }, { timeout: 4000 });
  });

  it('5. Empty state is rendered cleanly if timetable is not published', async () => {
    // Override service to return unpublished
    vi.spyOn(dailyTimetableService, 'getDailyTimetable').mockResolvedValueOnce({
      isPublished: false,
      status: 'draft',
      date: '2026-10-18',
      heading: 'Tomorrow, Sunday 18 Oct',
      entries: [],
    });

    renderWithClient(<TimetableTab enrollments={[]} />);

    await waitFor(() => {
      expect(screen.getByText("Tomorrow's timetable hasn't been published yet.")).toBeInTheDocument();
    });
  });
});
