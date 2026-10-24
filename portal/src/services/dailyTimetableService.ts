// portal/src/services/dailyTimetableService.ts
// Phase 10C: Daily Timetable Service for Student and Teacher Apps (Asia/Kolkata IST)

import { supabase } from '../lib/supabase';

export interface DailyTimetableEntryItem {
  id: number;
  date: string;
  courseName: string;
  year: string;
  teacherName: string;
  subjectName: string;
  classRoom: string;
  startTime: string;
  endTime: string;
  sortOrder: number;
}

export interface DailyTimetableResult {
  isPublished: boolean;
  status: 'published' | 'draft' | 'not_created';
  date: string;
  heading: string;
  entries: DailyTimetableEntryItem[];
}

export const dailyTimetableService = {
  /**
   * Computes the date in Indian Standard Time (Asia/Kolkata, UTC+05:30)
   * offsetDays: 1 for Tomorrow, 0 for Today
   */
  getKolkataDate(offsetDays: number = 1): {
    dateStr: string;
    heading: string;
    weekday: string;
    ddMon: string;
  } {
    const now = new Date();
    // UTC milliseconds
    const utcMs = now.getTime() + now.getTimezoneOffset() * 60000;
    // Asia/Kolkata is UTC + 5.5 hours
    const kolkataMs = utcMs + 5.5 * 3600000;
    const kDate = new Date(kolkataMs);

    kDate.setDate(kDate.getDate() + offsetDays);

    const yyyy = kDate.getFullYear();
    const mm = String(kDate.getMonth() + 1).padStart(2, '0');
    const dd = String(kDate.getDate()).padStart(2, '0');
    const dateStr = `${yyyy}-${mm}-${dd}`;

    const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    const weekday = weekdays[kDate.getDay()];
    const ddMon = `${kDate.getDate()} ${months[kDate.getMonth()]}`;
    const prefix = offsetDays === 1 ? 'Tomorrow' : offsetDays === 0 ? 'Today' : weekday;
    const heading = `${prefix}, ${weekday} ${ddMon}`;

    return { dateStr, heading, weekday, ddMon };
  },

  /**
   * Fetches published daily timetable for the given date.
   * Resilient with Supabase query, localStorage cache, and default seed fallback.
   */
  async getDailyTimetable(dateStr: string, heading: string): Promise<DailyTimetableResult> {
    try {
      // O3 Optimization: Consolidated RPC fetches status + entries in 1 query
      const { data: rpcData, error: rpcErr } = await supabase.rpc('get_timetable_day_payload', {
        p_date: dateStr,
      });

      if (!rpcErr && rpcData) {
        if (rpcData.status === 'published') {
          const rawEntries = rpcData.entries || [];
          return {
            isPublished: true,
            status: 'published',
            date: dateStr,
            heading: rpcData.heading || heading,
            entries: rawEntries.map((e: any) => ({
              id: e.id,
              date: e.date,
              courseName: e.course_name,
              year: e.year || '1st Year',
              teacherName: e.teacher_name,
              subjectName: e.subject_name,
              classRoom: e.class_room,
              startTime: e.start_time,
              endTime: e.end_time,
              sortOrder: e.sort_order || 0,
            })),
          };
        } else if (rpcData.status && rpcData.status !== 'not_created') {
          return {
            isPublished: false,
            status: rpcData.status,
            date: dateStr,
            heading: rpcData.heading || heading,
            entries: [],
          };
        }
      }

      // Fallback: Check Supabase publication status only if RPC errored
      if (rpcErr) {
        const { data: ttStatus, error: statusErr } = await supabase
          .from('daily_timetables')
          .select('*')
          .eq('date', dateStr)
          .maybeSingle();

        if (!statusErr && ttStatus) {
          if (ttStatus.status !== 'published') {
            return {
              isPublished: false,
              status: ttStatus.status as any,
              date: dateStr,
              heading,
              entries: [],
            };
          }

          // Fetch entries
          const { data: entriesData, error: entriesErr } = await supabase
            .from('daily_timetable_entries')
            .select('*')
            .eq('date', dateStr)
            .order('sort_order', { ascending: true });

          if (!entriesErr && entriesData && entriesData.length > 0) {
            return {
              isPublished: true,
              status: 'published',
              date: dateStr,
              heading,
              entries: entriesData.map((e: any) => ({
                id: e.id,
                date: e.date,
                courseName: e.course_name,
                year: e.year || '1st Year',
                teacherName: e.teacher_name,
                subjectName: e.subject_name,
                classRoom: e.class_room,
                startTime: e.start_time,
                endTime: e.end_time,
                sortOrder: e.sort_order || 0,
              })),
            };
          }
        }
      }
    } catch (e) {
      console.warn('dailyTimetableService Supabase fetch fallback:', e);
    }

    // 2. Local storage fallback (synchronized with admin browser or mock state)
    try {
      const cached = localStorage.getItem(`mips_daily_timetable_${dateStr}`);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (parsed.status === 'published') {
          return {
            isPublished: true,
            status: 'published',
            date: dateStr,
            heading,
            entries: (parsed.entries || []).map((e: any) => ({
              id: e.id,
              date: dateStr,
              courseName: e.course_name || e.courseName,
              year: e.year || '1st Year',
              teacherName: e.teacher_name || e.teacherName,
              subjectName: e.subject_name || e.subjectName,
              classRoom: e.class_room || e.classRoom,
              startTime: e.start_time || e.startTime,
              endTime: e.end_time || e.endTime,
              sortOrder: e.sort_order || e.sortOrder || 0,
            })),
          };
        } else {
          return {
            isPublished: false,
            status: parsed.status || 'draft',
            date: dateStr,
            heading,
            entries: [],
          };
        }
      }
    } catch (_) {}

    // 3. Clean fallback when no timetable has been created or published
    return {
      isPublished: false,
      status: 'not_created',
      date: dateStr,
      heading,
      entries: [],
    };
  },
};
