import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/api/calendar_repository.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/notification_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/notification_screen/notification_screen.dart';
import 'package:quorum_app/screens/organization_screen/create_organization_screen.dart';
import 'package:quorum_app/screens/organization_screen/join_organization_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_detail_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/profile_screen/profile_screen.dart';
import 'bottom_nav_bar.dart';
import 'calendar_screen.dart';
import 'home_stories.dart';
import 'package:quorum_app/screens/organization_screen/task_widgets.dart';
import 'package:quorum_app/screens/chat_screen/chat_screen.dart';
import 'package:quorum_app/screens/ai_assistant_screen/ai_assistant_screen.dart';
import 'package:quorum_app/screens/community_screen/community_screen.dart';
import 'package:quorum_app/screens/video_call_screen/video_call_screen.dart';
import 'calender_card.dart';

const _card = Color(0xFF14151F);
const _cardBorder = Color(0x1AFFFFFF);
const _teal = Color(0xFF3DDCC4);
const _muted = Color(0xFF9EA3AE);

String _getTimeGreeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.start();
  }

  final List<Widget> _pages = const [
    HomeScreen(),
    ChatScreen(),
    VideoCallScreen(),
    CommunityScreen(),
    AIAssistantScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F101A),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _userName = CurrentUser.isLoaded ? CurrentUser.name : '';
  StreamSubscription<NotificationItem>? _notificationSub;

  List<Organization>? _orgs;
  bool _orgsLoading = true;
  String? _orgsError;

  List<CalendarEvent> _events = [];
  List<TeamTask> _myTasks = [];
  bool _storiesLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationSub =
        NotificationService.instance.incoming.listen(_onNotification);
    _loadUser();
    _loadOrgs();
    _loadStories();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadOrgs();
      _loadStories();
    }
  }

  void _onNotification(NotificationItem n) {
    if (n.type != NotificationType.teamInvite) return;
    _loadOrgs(ensureOrgId: n.data['organizationId']?.toString());
  }

  Future<void> _loadUser() async {
    try {
      if (!CurrentUser.isLoaded) {
        CurrentUser.setFromProfile(
          await AuthService.instance.getUserProfile(),
        );
      }
      if (!mounted) return;
      setState(() => _userName = CurrentUser.name);
    } on ApiException {
      return;
    }
  }

  String get _greeting {
    final name = _userName.trim();
    return name.isEmpty ? _getTimeGreeting() : '${_getTimeGreeting()}, $name';
  }

  void _showNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotificationScreen(),
      ),
    );
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
      ),
    );
    if (mounted && CurrentUser.isLoaded) {
      setState(() => _userName = CurrentUser.name);
    }
  }

  Widget _headerButton({
    required IconData icon,
    required VoidCallback? onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _card,
              shape: BoxShape.circle,
              border: Border.all(color: _cardBorder),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: const Color(0xFF090A10),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          color: _teal,
          onRefresh: () => Future.wait([_loadOrgs(), _loadStories()]),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        'QUORUM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ValueListenableBuilder<int>(
                      valueListenable:
                          NotificationService.instance.unreadCount,
                      builder: (_, count, __) => _headerButton(
                        icon: Icons.notifications_none_rounded,
                        onTap: _showNotifications,
                        badge: count,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _headerButton(
                      icon: Icons.person_outline_rounded,
                      onTap: _openProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  _greeting,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Here is what is happening across your teams today.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                if (_storiesLoaded) ...[
                  _buildStories(),
                  const SizedBox(height: 18),
                ],
                _buildHero(),
                const SizedBox(height: 22),
                _buildWorkspaceSection(),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
                CalendarCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadStories() async {
    var events = _events;
    try {
      events = await CalendarRepository.instance.getUpcoming(limit: 6);
    } catch (_) {}
    final tasks = <TeamTask>[];
    try {
      final orgs = _orgs ?? await OrganizationRepository.instance.organizations();
      final lists = await Future.wait(
        orgs.take(6).map((o) => OrganizationRepository.instance.myTasks(o.id).catchError((_) => <TeamTask>[])),
      );
      for (final list in lists) {
        tasks.addAll(list);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _events = events;
      _myTasks = tasks;
      _storiesLoaded = true;
    });
  }

  List<StorySlide> _storySlides() {
    final now = DateTime.now();
    final events = _events.where((e) => e.startDate.isAfter(now.subtract(const Duration(hours: 1)))).take(4).toList();
    final open = _myTasks.where((t) => t.status != TaskStatus.completed).toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
    final overdue = open.where((t) => t.isOverdue).length;
    final unread = NotificationService.instance.unreadCount.value;
    final orgs = _orgs ?? const <Organization>[];

    return [
      StorySlide(
        id: 'schedule',
        label: 'Schedule',
        icon: Icons.event_rounded,
        colors: const [Color(0xFF7C5CFC), Color(0xFF4C3AE3)],
        headline: events.isEmpty ? 'Nothing coming up' : (events.length == 1 ? '1 thing coming up' : '${events.length} things coming up'),
        subtitle: events.isEmpty ? 'Your calendar is clear for now.' : 'Your next events and meetings.',
        lines: [
          for (final e in events)
            StoryLine(
              icon: e.meetingLink != null ? Icons.videocam_rounded : Icons.event_note_rounded,
              text: e.title,
              trailing: storyTimeLabel(e.startDate, allDay: e.isAllDay),
            ),
        ],
        actionLabel: 'Open calendar',
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalendarScreen())),
      ),
      StorySlide(
        id: 'tasks',
        label: 'Tasks',
        icon: Icons.task_alt_rounded,
        colors: const [Color(0xFF22A58A), Color(0xFF14806B)],
        headline: open.isEmpty ? 'All tasks done' : (open.length == 1 ? '1 open task' : '${open.length} open tasks'),
        subtitle: open.isEmpty
            ? 'Nothing is waiting on you.'
            : (overdue > 0 ? '$overdue overdue, tackle those first.' : 'Nothing overdue, nice work.'),
        lines: [
          for (final t in open.take(4))
            StoryLine(
              icon: taskStatusIcon(t.status),
              iconColor: t.isOverdue ? const Color(0xFFFFB4B4) : null,
              text: t.title,
              trailing: t.dueDate != null ? taskDueLabel(t.dueDate!) : t.status.label,
            ),
        ],
      ),
      StorySlide(
        id: 'alerts',
        label: 'Alerts',
        icon: Icons.notifications_active_rounded,
        colors: const [Color(0xFFF59E0B), Color(0xFFEA580C)],
        headline: unread == 0 ? 'All caught up' : (unread == 1 ? '1 unread alert' : '$unread unread alerts'),
        subtitle: unread == 0 ? 'No new notifications.' : 'Mentions, invites and updates waiting for you.',
        actionLabel: unread == 0 ? null : 'Open notifications',
        onAction: unread == 0 ? null : _showNotifications,
      ),
      StorySlide(
        id: 'workspaces',
        label: 'Teams',
        icon: Icons.apartment_rounded,
        colors: const [Color(0xFFEC4899), Color(0xFFBE185D)],
        headline: orgs.isEmpty ? 'No workspaces yet' : (orgs.length == 1 ? '1 workspace' : '${orgs.length} workspaces'),
        subtitle: orgs.isEmpty ? 'Create or join one to get started.' : 'Where your teams get things done.',
        lines: [
          for (final o in orgs.take(4))
            StoryLine(
              icon: Icons.groups_rounded,
              text: o.name,
              trailing: o.membersCount == 1 ? '1 member' : '${o.membersCount} members',
            ),
        ],
      ),
    ];
  }

  Widget _buildStories() {
    final slides = _storySlides();
    return StoriesRow(
      slides: slides,
      onOpen: (i) async {
        await openStories(context, slides, i);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildHero() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        height: 150,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3A2D6B), Color(0xFF1E2A4A),],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -10,
              child: Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C4BE0), Color(0xFF3B2A93),],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 70,
              top: 28,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5B83D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: -30,
              bottom: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFF1F7F86),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: 18,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFF3DB6A8),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Build, collaborate, make\nit happen.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Plan, create, collaborate and turn\nyour vision into reality.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadOrgs({String? ensureOrgId}) async {
    try {
      var orgs = await OrganizationRepository.instance.organizations();

      if (ensureOrgId != null &&
          ensureOrgId.isNotEmpty &&
          !orgs.any((o) => o.id == ensureOrgId)) {
        try {
          final extra = await OrganizationRepository.instance.detail(
            ensureOrgId,
            role: 'MEMBER',
          );
          orgs = [...orgs, extra];
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _orgs = orgs;
        _orgsLoading = false;
        _orgsError = null;
      });

      final withCounts = await Future.wait(orgs.map(_withCounts));
      if (!mounted) return;
      setState(() => _orgs = withCounts);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _orgsLoading = false;
        if (_orgs == null) {
          _orgsError = errorText(e);
        }
      });
    }
  }

  Future<Organization> _withCounts(Organization org) async {
    final repo = OrganizationRepository.instance;
    var members = org.membersCount;
    var teams = org.teamsCount;
    try {
      members = (await repo.members(org.id)).length;
    } catch (_) {}
    try {
      teams = (await repo.teams(org.id)).length;
    } catch (_) {}
    return org.copyWith(membersCount: members, teamsCount: teams);
  }

  void _retryOrgs() {
    setState(() {
      _orgsLoading = true;
      _orgsError = null;
    });
    _loadOrgs();
  }

  Future<void> _openCreateOrg() async {
    final org = await Navigator.push<Organization>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateOrganizationScreen(),
      ),
    );

    if (org == null || !mounted) return;
    await _loadOrgs();
  }

  Future<void> _openJoinOrg() async {
    final joined = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const JoinOrganizationScreen(),
      ),
    );

    if (joined != true || !mounted) return;
    await _loadOrgs();
  }

  Future<void> _openOrg(Organization org) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizationDetailScreen(
          organization: org,
        ),
      ),
    );

    if (!mounted) return;
    await _loadOrgs();
  }

  void _showAddOrgSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: _iconBox(Icons.add_business_outlined),
                title: const Text(
                  'Create Organization',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openCreateOrg();
                },
              ),
              ListTile(
                leading: _iconBox(Icons.group_add_outlined),
                title: const Text(
                  'Join Organization',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openJoinOrg();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceSection() {
    if (_orgsLoading) {
      return Container(
        width: double.infinity,
        height: 120,
        decoration: _cardDecoration(),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _teal,
          ),
        ),
      );
    }

    if (_orgsError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Text(
              _orgsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _retryOrgs,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: _teal,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final orgs = _orgs ?? const <Organization>[];

    if (orgs.isEmpty) {
      return _buildWorkspaceActions();
    }

    return _buildOrganizations(orgs);
  }

  Widget _buildOrganizations(List<Organization> orgs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              orgs.length == 1 ? 'Your Organization' : 'Your Organizations',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              onTap: _showAddOrgSheet,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _card,
                  shape: BoxShape.circle,
                  border: Border.all(color: _cardBorder),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final org in orgs) ...[
          _orgTile(org),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _orgTile(Organization org) {
    return GestureDetector(
      onTap: () => _openOrg(org),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            OrgAvatar(
              name: org.name,
              logo: org.logo,
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    org.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${org.membersCount} ${org.membersCount == 1 ? 'member' : 'members'} · ${org.teamsCount} ${org.teamsCount == 1 ? 'team' : 'teams'}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OrgRoleBadge(role: org.role),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: _muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Workspace Actions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _actionCard(
                  icon: Icons.add_business_outlined,
                  title: 'Create\nOrganization',
                  subtitle: 'Start your company or department hub',
                  cta: 'Build now',
                  onTap: _openCreateOrg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionCard(
                  icon: Icons.group_add_outlined,
                  title: 'Join\nOrganization',
                  subtitle: 'Connect via direct invite links or id/QR code',
                  cta: 'Enter code',
                  onTap: _openJoinOrg,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String cta,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBox(icon),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cta,
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    decorationColor: _teal,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward,
                  color: _teal,
                  size: 14,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreelanceCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.work_outline_rounded),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Freelance & Contractor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Join client workspaces with guest permissions',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(color: _cardBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'No organisation account needed',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Join Workspace',
                      style: TextStyle(
                        color: _teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decorationColor: _teal,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      color: _teal,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      );

  Widget _iconBox(IconData icon, {double size = 40}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF16302F),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: _teal,
          size: size * 0.5,
        ),
      );
}