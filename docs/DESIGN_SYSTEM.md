PART 1: DESIGN SYSTEM
1. Design principle

"Calm blue foundation, color used as a label." Surfaces stay light and quiet. Color appears only in small places (icon tiles, badges, chart series, progress bars), so the app feels colorful without feeling loud.

2. Color tokens

Neutrals (slate)

Token	Hex	Use
bg	#F4F6FB	App background (light blue-grey, not pure white)
surface	#FFFFFF	Cards, tables
border	#E3E8F0	Card and input borders
textStrong	#0F172A	Headings, numbers
textBody	#334155	Body text
textMuted	#64748B	Labels, captions

Brand

Token	Hex
brand	#1D4ED8 (replace with your exact MIPS blue)
brandDark	#1E3A8A (sidebar, headings)
brandTint	#EAF0FF

Module colors (icon tiles, section headers, charts only)

Module	Base	Tint	Dark (text on tint)
Students	#0EA5E9	#E0F2FE	#075985
Fees	#10B981	#D1FAE5	#065F46
Exams	#6366F1	#E0E7FF	#3730A3
Documents	#14B8A6	#CCFBF1	#115E59
Courses	#8B5CF6	#EDE9FE	#5B21B6
Reports	#F97316	#FFEDD5	#9A3412
Settings	#64748B	#F1F5F9	#334155

Status colors (badges, progress, validation only; never used for modules)

Status	Base	Tint	Dark text
Success / Paid / Active	#16A34A	#DCFCE7	#166534
Warning / Pending	#D97706	#FEF3C7	#92400E
Danger / Overdue / Failed	#DC2626	#FEE2E2	#991B1B
Info / Draft	#2563EB	#DBEAFE	#1E40AF

Always put the dark shade on the tint for badge text. This passes contrast, which amber on white does not.

3. Typography
Font: Plus Jakarta Sans (friendly, modern) for UI. Optionally use Inter for table numbers, with tabular figures on.
Scale: Page title 24/700 · Section title 16/600 · Card number 26/700 · Body 14/400 · Table 13/500 · Caption 12/500 muted
Money and marks use tabular figures so columns align.

4. Shape, spacing, depth
Spacing scale: 4, 8, 12, 16, 24, 32
Radius: cards 14, inputs and buttons 10, badges and chips full pill, icon tiles 10
Borders: 1px border on every card. Shadow is almost none at rest (0 1px 2px rgba(15,23,42,.04)).
Hover lift: 0 8px 24px rgba(15,23,42,.08) plus 2px upward translate, 150ms
Card padding: 16 (compact), 20 (normal)
Table row height: 52, header 40

5. Layout shell
Sidebar 232px, brandDark background, white text, active item has a lighter pill with a small animated left indicator. Each module's icon sits in its own module-colored tile. Collapsible to 72px icons-only below 1280px.
Top bar 60px: page title and breadcrumb on the left, global search (Ctrl+K), notifications, and profile menu on the right.
Content max width 1440, padding 24, 12-column grid, 16 gap.

6. Icons
Lucide or Phosphor (one family only). 20px in nav and buttons, 18px in tiles. Icon tile = 36×36, radius 10, tint background, base-color icon. No emojis in the UI.

7. Reusable components (build these before screens)
AppScaffold, SidebarItem, PageHeader, KpiCard, StatusBadge, CourseChip, IconTile, SectionCard, AppDataTable, SearchField, FilterBar, Avatar (initials with a color derived from the name), ProgressBar, EmptyState, SkeletonLoader, AppDialog, Toast, FormSection, Stepper.

8. Motion
150–200ms ease-out. Only: card hover lift, button press scale 0.98, sidebar indicator slide, dialog fade and scale from 0.96, toast slide-in, and a progress bar fill on load. Respect reduced-motion.

9. States everyone forgets
Loading skeletons (not spinners) for tables and cards. Empty states with one line of text and one action. Error states with Retry. Dark mode: not in this phase.

PART 2: CONSISTENT SAMPLE DATA

Use these everywhere so no screen contradicts another.

Students: 248 (12 new this month) · Courses: 8 · Active batches: 6
Total receivable: ₹24.8L · Collected: ₹18.4L (74%) · Pending: ₹6.4L · Students with dues: 61
Student sample: Rahul K., ADM-2026-0012, DMLT, total ₹60,000, paid ₹40,000 (₹20,000 Cash on 05 Sep + ₹20,000 UPI on 05 Oct), pending ₹20,000
Exam: 2026 Final Examination, DMLT, 2026 batch, 248 students, 8 subjects, 92% marks entered
Results: Passed 231, Failed 17, Pass rate 93.1%, Average 78.4%
