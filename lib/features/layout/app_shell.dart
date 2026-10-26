import '../auth/auth_provider.dart';
import '../auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/responsive.dart';
import '../dashboard/dashboard_screen.dart';
import '../students/students_screen.dart';
import '../courses/courses_screen.dart';
import '../fees/fees_screen.dart';
import '../exams/exams_screen.dart';
import '../documents/documents_screen.dart';
import '../settings/settings_screen.dart';
import '../reports/reports_screen.dart';
import '../attendance/attendance_screen.dart';
import '../announcements/announcements_screen.dart';
import '../timetable/timetable_screen.dart';
import '../teachers/teachers_screen.dart';
import '../accounts/accounts_screen.dart';
import '../batches/batches_screen.dart';

final navigationProvider = StateProvider<int>((ref) => 0);
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(
          children: const [
            Icon(LucideIcons.alertTriangle, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 10),
            Text('Confirm Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out of MIPS ERP Admin? Your session will be terminated and all cached administrative data will be cleared.',
          style: TextStyle(fontSize: 13, color: AppColors.textStrong),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC93A3A),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.logOut, size: 16),
            label: const Text('Log Out'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(authProvider.notifier).logout();
      ref.read(navigationProvider.notifier).state = 0;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  final List<Widget> _screens = const [
    DashboardScreen(),
    StudentsScreen(),
    CoursesScreen(),
    FeesScreen(),
    DocumentsScreen(),
    ExamsScreen(),
    ReportsScreen(),
    SettingsScreen(),
    AttendanceScreen(),
    AnnouncementsScreen(),
    TimetableScreen(),
    TeachersScreen(),
    AccountsScreen(),
    BatchesScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationProvider);
    final isMobile = Responsive.isPhone(context);
    final isDesktop = Responsive.isDesktop(context);
    final isCollapsed = !isDesktop || ref.watch(sidebarCollapsedProvider);
    // Mobile Phone Admin Shell
    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        drawer: _buildDrawer(context, ref, currentIndex),
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          shadowColor: AppColors.border,
          leading: Builder(
            builder: (btnCtx) => IconButton(
              icon: const Icon(LucideIcons.menu, color: AppColors.brandDark, size: 22),
              onPressed: () => Scaffold.of(btnCtx).openDrawer(),
            ),
          ),
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  'assets/images/mips_logo.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(LucideIcons.graduationCap, color: AppColors.brand, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getBreadcrumb(currentIndex),
                  style: const TextStyle(
                    color: AppColors.textStrong,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.logOut, color: Colors.redAccent, size: 20),
              tooltip: 'Log out',
              onPressed: () => _confirmAndLogout(context, ref),
            ),
            _buildProfileMenu(context, ref),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: Builder(
          builder: (navCtx) => NavigationBar(
            height: 60,
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.brandTint,
            selectedIndex: _getBottomNavIndex(currentIndex),
            onDestinationSelected: (navIdx) {
              switch (navIdx) {
                case 0: ref.read(navigationProvider.notifier).state = 0; break;
                case 1: ref.read(navigationProvider.notifier).state = 1; break;
                case 2: ref.read(navigationProvider.notifier).state = 3; break;
                case 3: ref.read(navigationProvider.notifier).state = 5; break;
                case 4: Scaffold.of(navCtx).openDrawer(); break;
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(LucideIcons.layoutDashboard, size: 20),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(LucideIcons.users, size: 20),
                label: 'Students',
              ),
              NavigationDestination(
                icon: Icon(LucideIcons.indianRupee, size: 20),
                label: 'Fees',
              ),
              NavigationDestination(
                icon: Icon(LucideIcons.checkSquare, size: 20),
                label: 'Exams',
              ),
              NavigationDestination(
                icon: Icon(LucideIcons.menu, size: 20),
                label: 'More',
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _screens[currentIndex],
          ),
        ),
      );
    }

    // Desktop Admin Shell
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: AppDurations.normal,
            curve: Curves.easeOut,
            width: isCollapsed ? 72.0 : 232.0,
            color: AppColors.brandDark,
            child: Column(
              children: [
                // Logo Area
                Container(
                  height: 60,
                  alignment: isCollapsed ? Alignment.center : Alignment.centerLeft,
                  padding: isCollapsed ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/images/mips_logo.png',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(LucideIcons.graduationCap, color: Colors.white, size: 28),
                        ),
                      ),
                      if (!isCollapsed) ...[
                        const SizedBox(width: 12),
                        const Text('MIPS', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Nav Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _SidebarItem(index: 0, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.layoutDashboard, label: 'Dashboard', moduleBase: AppColors.textMuted, moduleTint: AppColors.surface.withOpacity(0.1)),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 1, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.users, label: 'Students', moduleBase: AppColors.students.base, moduleTint: AppColors.students.tint),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 2, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.bookOpen, label: 'Courses', moduleBase: AppColors.courses.base, moduleTint: AppColors.courses.tint),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 13, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.layers, label: 'Batches', moduleBase: Colors.amberAccent, moduleTint: Colors.amber.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      if ((ref.watch(authProvider).profile?['role'] as String? ?? 'admin') == 'admin') _SidebarItem(index: 3, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.indianRupee, label: 'Fees', moduleBase: AppColors.fees.base, moduleTint: AppColors.fees.tint),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 4, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.fileText, label: 'Documents', moduleBase: AppColors.documents.base, moduleTint: AppColors.documents.tint),
                      const SizedBox(height: 4),
                      if ((ref.watch(authProvider).profile?['role'] as String? ?? 'admin') == 'admin') _SidebarItem(index: 5, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.checkSquare, label: 'Exams & Results', moduleBase: AppColors.exams.base, moduleTint: AppColors.exams.tint),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 8, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.calendarCheck, label: 'Attendance', moduleBase: Colors.tealAccent, moduleTint: Colors.teal.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 9, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.megaphone, label: 'Announcements', moduleBase: Colors.orangeAccent, moduleTint: Colors.orange.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      _SidebarItem(index: 10, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.calendar, label: 'Timetable', moduleBase: Colors.indigoAccent, moduleTint: Colors.indigo.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      if ((ref.watch(authProvider).profile?['role'] as String? ?? 'admin') == 'admin') _SidebarItem(index: 11, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.graduationCap, label: 'Teachers', moduleBase: Colors.purpleAccent, moduleTint: Colors.purple.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      if ((ref.watch(authProvider).profile?['role'] as String? ?? 'admin') == 'admin') _SidebarItem(index: 12, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.shieldCheck, label: 'Accounts', moduleBase: Colors.cyanAccent, moduleTint: Colors.cyan.withOpacity(0.2)),
                      const SizedBox(height: 4),
                      if ((ref.watch(authProvider).profile?['role'] as String? ?? 'admin') == 'admin') _SidebarItem(index: 6, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.barChart2, label: 'Reports', moduleBase: AppColors.reports.base, moduleTint: AppColors.reports.tint),
                      const SizedBox(height: 4),
                      if ((ref.watch(authProvider).profile?['role'] as String? ?? 'admin') == 'admin') _SidebarItem(index: 7, current: currentIndex, collapsed: isCollapsed, icon: LucideIcons.settings, label: 'Settings', moduleBase: AppColors.settings.base, moduleTint: AppColors.settings.tint),
                    ],
                  ),
                ),
                // Bottom of Sidebar Logout Button
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCollapsed ? 8 : 12,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: InkWell(
                    onTap: () => _confirmAndLogout(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.logOut, color: Colors.redAccent, size: 18),
                          if (!isCollapsed) ...[
                            const SizedBox(width: 10),
                            const Text(
                              'Log out',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Toggle Sidebar (only if > 1280)
                      if (isDesktop)
                        IconButton(
                          icon: Icon(LucideIcons.menu, color: AppColors.textMuted, size: 20),
                          onPressed: () => ref.read(sidebarCollapsedProvider.notifier).state = !isCollapsed,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      if (isDesktop) const SizedBox(width: 16),
                      
                      // Breadcrumb
                      Text(_getBreadcrumb(currentIndex), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
                      
                      const Spacer(),
                      
                      // Search
                      Container(
                        width: 280,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(LucideIcons.search, size: 16, color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search (Ctrl+K)...',
                                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  fillColor: Colors.transparent,
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      // Notifications
                      IconButton(
                        icon: Icon(LucideIcons.bell, size: 20, color: AppColors.textMuted),
                        onPressed: () {},
                      ),
                      const SizedBox(width: 12),
                      // Visible Log out button in top bar (tablet & desktop)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                        ),
                        icon: const Icon(LucideIcons.logOut, size: 15),
                        label: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        onPressed: () => _confirmAndLogout(context, ref),
                      ),
                      const SizedBox(width: 12),
                      // Profile Menu with Sign Out
                      _buildProfileMenu(context, ref),
                    ],
                  ),
                ),
                
                // Content Area
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: SizedBox.expand(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Builder(
                            builder: (context) {
                              return _screens[currentIndex];
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _getBottomNavIndex(int current) {
    switch (current) {
      case 0: return 0;
      case 1: return 1;
      case 3: return 2;
      case 5: return 3;
      default: return 4;
    }
  }

  Widget _buildProfileMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Account Menu',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (value) async {
        if (value == 'logout') {
          await _confirmAndLogout(context, ref);
        }
      },
      itemBuilder: (context) {
        final auth = ref.read(authProvider);
        return [
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Text(
                  auth.email,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Divider(),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(LucideIcons.logOut, size: 16, color: Colors.red),
                SizedBox(width: 8),
                Text('Sign Out', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ];
      },
      child: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.brandTint,
        child: Text(
          ref.watch(authProvider).displayName.isNotEmpty
              ? ref.watch(authProvider).displayName.substring(0, 1).toUpperCase()
              : 'A',
          style: TextStyle(color: AppColors.brandDark, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, WidgetRef ref, int currentIndex) {
    final auth = ref.watch(authProvider);
    final nav = ref.read(navigationProvider.notifier);

    return Drawer(
      backgroundColor: AppColors.brandDark,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/mips_logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(LucideIcons.graduationCap, color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MIPS ERP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.displayName.isNotEmpty ? auth.displayName : 'Administrator',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _DrawerItem(
                    index: 0,
                    currentIndex: currentIndex,
                    icon: LucideIcons.layoutDashboard,
                    label: 'Dashboard',
                    onTap: () {
                      nav.state = 0;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 1,
                    currentIndex: currentIndex,
                    icon: LucideIcons.users,
                    label: 'Students',
                    onTap: () {
                      nav.state = 1;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 2,
                    currentIndex: currentIndex,
                    icon: LucideIcons.bookOpen,
                    label: 'Courses',
                    onTap: () {
                      nav.state = 2;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 13,
                    currentIndex: currentIndex,
                    icon: LucideIcons.layers,
                    label: 'Batches',
                    onTap: () {
                      nav.state = 13;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 3,
                    currentIndex: currentIndex,
                    icon: LucideIcons.indianRupee,
                    label: 'Fees',
                    onTap: () {
                      nav.state = 3;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 4,
                    currentIndex: currentIndex,
                    icon: LucideIcons.fileText,
                    label: 'Documents',
                    onTap: () {
                      nav.state = 4;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 5,
                    currentIndex: currentIndex,
                    icon: LucideIcons.checkSquare,
                    label: 'Exams & Results',
                    onTap: () {
                      nav.state = 5;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 8,
                    currentIndex: currentIndex,
                    icon: LucideIcons.calendarCheck,
                    label: 'Attendance',
                    onTap: () {
                      nav.state = 8;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 9,
                    currentIndex: currentIndex,
                    icon: LucideIcons.megaphone,
                    label: 'Announcements',
                    onTap: () {
                      nav.state = 9;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 10,
                    currentIndex: currentIndex,
                    icon: LucideIcons.calendar,
                    label: 'Timetable',
                    onTap: () {
                      nav.state = 10;
                      Navigator.pop(context);
                    },
                  ),
                  if ((auth.profile?['role'] as String? ?? 'admin') == 'admin') ...[
                    _DrawerItem(
                      index: 11,
                      currentIndex: currentIndex,
                      icon: LucideIcons.graduationCap,
                      label: 'Teachers',
                      onTap: () {
                        nav.state = 11;
                        Navigator.pop(context);
                      },
                    ),
                    _DrawerItem(
                      index: 12,
                      currentIndex: currentIndex,
                      icon: LucideIcons.shieldCheck,
                      label: 'Accounts',
                      onTap: () {
                        nav.state = 12;
                        Navigator.pop(context);
                      },
                    ),
                  ],
                  _DrawerItem(
                    index: 6,
                    currentIndex: currentIndex,
                    icon: LucideIcons.barChart2,
                    label: 'Reports',
                    onTap: () {
                      nav.state = 6;
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    index: 7,
                    currentIndex: currentIndex,
                    icon: LucideIcons.settings,
                    label: 'Settings',
                    onTap: () {
                      nav.state = 7;
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: const Icon(LucideIcons.logOut, color: Colors.redAccent, size: 20),
                title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmAndLogout(context, ref);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getBreadcrumb(int index) {
    switch (index) {
      case 0: return 'Dashboard';
      case 1: return 'Students';
      case 2: return 'Courses';
      case 3: return 'Fees';
      case 4: return 'Documents';
      case 5: return 'Exams & Results';
      case 6: return 'Reports';
      case 7: return 'Settings';
      case 8: return 'Attendance (Morning / Evening)';
      case 9: return 'Announcements';
      case 10: return 'Timetable & Scheduling';
      case 11: return 'Teachers & Faculty';
      case 12: return 'Accounts & Authentication';
      case 13: return 'Batches & Completion';
      default: return '';
    }
  }
}

class _DrawerItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == currentIndex;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 20),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SidebarItem extends ConsumerWidget {
  final int index;
  final int current;
  final bool collapsed;
  final IconData icon;
  final String label;
  final Color moduleBase;
  final Color moduleTint;

  const _SidebarItem({
    required this.index,
    required this.current,
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.moduleBase,
    required this.moduleTint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = index == current;
    
    return InkWell(
      onTap: () => ref.read(navigationProvider.notifier).state = index,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Stack(
          children: [
            // Active Indicator
            AnimatedPositioned(
              duration: AppDurations.normal,
              curve: Curves.easeOut,
              left: 0,
              top: isActive ? 8 : 24,
              bottom: isActive ? 8 : 24,
              width: 4,
              child: AnimatedOpacity(
                duration: AppDurations.normal,
                opacity: isActive ? 1.0 : 0.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            
            // Content
            Row(
              children: [
                const SizedBox(width: 8),
                // Icon Tile
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive ? moduleTint : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 18,
                      color: isActive ? moduleBase : AppColors.textMuted.withOpacity(0.8),
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isActive ? Colors.white : AppColors.textMuted.withOpacity(0.8),
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}



