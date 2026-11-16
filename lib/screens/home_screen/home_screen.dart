import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/quorumbot_controller.dart';
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
import 'package:quorum_app/api/deep_link_service.dart';
import 'package:quorum_app/api/presence_service.dart';
import 'package:quorum_app/api/push_service.dart';
import 'package:quorum_app/screens/profile_screen/set_status_sheet.dart';
import 'package:quorum_app/widgets/presence_widgets.dart';
import 'package:quorum_app/screens/organization_screen/all_organizations_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_detail_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/profile_screen/profile_screen.dart';
import 'package:quorum_app/screens/project_screen/accept_project_invite_screen.dart';
import 'package:quorum_app/screens/project_screen/projects_list_screen.dart';
import 'bottom_nav_bar.dart';
import 'calendar_screen.dart';
import 'home_stories.dart';
import 'package:quorum_app/screens/organization_screen/task_widgets.dart';
import 'package:quorum_app/screens/chat_screen/chat_screen.dart';
import 'package:quorum_app/screens/ai_assistant_screen/ai_assistant_screen.dart';
import 'package:quorum_app/screens/community_screen/community_screen.dart';
import 'package:quorum_app/screens/video_call_screen/video_call_screen.dart';
import 'package:quorum_app/screens/home_screen/my_teams_screen.dart';
import 'package:quorum_app/screens/organization_screen/team_tasks_screen.dart';
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
    PresenceService.instance.start();
    PushService.instance.start();
    UltronController.instance.activate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.markReady();
      PushService.instance.markReady();
    });
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
      extendBody: true,
      resizeToAvoidBottomInset: false,
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

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  String _userName = CurrentUser.isLoaded ? CurrentUser.name : '';
  StreamSubscription<NotificationItem>? _notificationSub;

  List<Organization>? _orgs;
  bool _orgsLoading = true;
  String? _orgsError;

  List<CalendarEvent> _events = [];
  List<TeamTask> _myTasks = [];
  final Map<String, Organization> _taskOrgs = {};
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

  Widget _profileAvatar() {
    return GestureDetector(
      onTap: _openProfile,
      child: OrgAvatar(
        name: _userName,
        logo: CurrentUser.avatar,
        size: 40,
        circular: true,
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              _greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<int>(
            valueListenable: NotificationService.instance.unreadCount,
            builder: (_, count, __) => _headerButton(
              icon: Icons.notifications_none_rounded,
              onTap: _showNotifications,
              badge: count,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onLongPress: () => showSetStatusSheet(context),
            child: PresenceWrap(
              userId: CurrentUser.id,
              avatarSize: 40,
              ringColor: const Color(0xFF090A10),
              child: _profileAvatar(),
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
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: RefreshIndicator(
                color: _teal,
                onRefresh: () => Future.wait([
                  _loadOrgs(),
                  _loadStories(),
                ]),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    4 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      _buildWorkspaceSection(),
                      const SizedBox(height: 12),
                      const SizedBox(height: 16),
                      CalendarCard(),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
    final taskOrgs = <String, Organization>{};
    try {
      final orgs =
          _orgs ?? await OrganizationRepository.instance.organizations();
      final lists = await Future.wait(
        orgs.take(6).map(
              (o) => OrganizationRepository.instance
                  .myTasks(o.id)
                  .catchError((_) => <TeamTask>[]),
            ),
      );
      final scoped = orgs.take(6).toList();
      for (var i = 0; i < lists.length; i++) {
        tasks.addAll(lists[i]);
        for (final t in lists[i]) {
          taskOrgs[t.id] = scoped[i];
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _events = events;
      _myTasks = tasks;
      _taskOrgs
        ..clear()
        ..addAll(taskOrgs);
      _storiesLoaded = true;
    });
  }

  List<StorySlide> _storySlides() {
    final now = DateTime.now();
    final events = _events
        .where((e) => e.startDate.isAfter(now.subtract(const Duration(hours: 1))))
        .take(4)
        .toList();
    final open = _myTasks
        .where((t) => t.status != TaskStatus.completed)
        .toList()
      ..sort(
        (a, b) => (a.dueDate ?? DateTime(9999))
            .compareTo(b.dueDate ?? DateTime(9999)),
      );
    final overdue = open.where((t) => t.isOverdue).length;
    final unread = NotificationService.instance.unreadCount.value;
    final orgs = _orgs ?? const <Organization>[];

    return [
      StorySlide(
        id: 'schedule',
        label: 'Schedule',
        icon: Icons.event_rounded,
        colors: const [Color(0xFF7C5CFC), Color(0xFF4C3AE3)],
        headline: events.isEmpty
            ? 'Nothing coming up'
            : (events.length == 1
                ? '1 thing coming up'
                : '${events.length} things coming up'),
        subtitle: events.isEmpty
            ? 'Your calendar is clear for now.'
            : 'Your next events and meetings.',
        lines: [
          for (final e in events)
            StoryLine(
              icon: e.meetingLink != null
                  ? Icons.videocam_rounded
                  : Icons.event_note_rounded,
              text: e.title,
              trailing: storyTimeLabel(e.startDate, allDay: e.isAllDay),
            ),
        ],
        actionLabel: 'Open calendar',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CalendarScreen(),
          ),
        ),
      ),
      StorySlide(
        id: 'tasks',
        label: 'Tasks',
        icon: Icons.task_alt_rounded,
        colors: const [Color(0xFF22A58A), Color(0xFF14806B)],
        headline: open.isEmpty
            ? 'All tasks done'
            : (open.length == 1
                ? '1 open task'
                : '${open.length} open tasks'),
        subtitle: open.isEmpty
            ? 'Nothing is waiting on you.'
            : (overdue > 0
                ? '$overdue overdue, tackle those first.'
                : 'Nothing overdue, nice work.'),
        lines: [
          for (final t in open.take(4))
            StoryLine(
              icon: taskStatusIcon(t.status),
              iconColor: t.isOverdue ? const Color(0xFFFFB4B4) : null,
              text: t.title,
              trailing:
                  t.dueDate != null ? taskDueLabel(t.dueDate!) : t.status.label,
              onTap: () => _openTask(t),
            ),
        ],
      ),
      StorySlide(
        id: 'alerts',
        label: 'Alerts',
        icon: Icons.notifications_active_rounded,
        colors: const [Color(0xFFF59E0B), Color(0xFFEA580C)],
        headline: unread == 0
            ? 'All caught up'
            : (unread == 1 ? '1 unread alert' : '$unread unread alerts'),
        subtitle: unread == 0
            ? 'No new notifications.'
            : 'Mentions, invites and updates waiting for you.',
        actionLabel: unread == 0 ? null : 'Open notifications',
        onAction: unread == 0 ? null : _showNotifications,
      ),
      StorySlide(
        id: 'workspaces',
        label: 'Teams',
        icon: Icons.apartment_rounded,
        colors: const [Color(0xFFEC4899), Color(0xFFBE185D)],
        headline: orgs.isEmpty
            ? 'No workspaces yet'
            : (orgs.length == 1
                ? '1 workspace'
                : '${orgs.length} workspaces'),
        subtitle: orgs.isEmpty
            ? 'Create or join one to get started.'
            : 'Where your teams get things done.',
        lines: [
          for (final o in orgs.take(4))
            StoryLine(
              icon: Icons.groups_rounded,
              text: o.name,
              trailing: o.membersCount == 1
                  ? '1 member'
                  : '${o.membersCount} members',
            ),
        ],
        actionLabel: orgs.isEmpty ? null : 'View all my teams',
        onAction: orgs.isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MyTeamsScreen(organizations: orgs)),
                ),
      ),
    ];
  }

  void _openTask(TeamTask task) {
    final org = _taskOrgs[task.id];
    if (org == null) return;
    final team = OrgTeam(
      id: task.teamId,
      name: (task.teamName ?? '').isEmpty ? 'Team' : task.teamName!,
      membersCount: 0,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamTasksScreen(organization: org, team: team)),
    );
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

  Future<void> _openJoinProject() async {
    final joined = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AcceptProjectInviteScreen()),
    );
    if (joined != true || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
    );
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
                leading: _iconBox(Icons.handshake_outlined),
                title: const Text(
                  'Join a Project',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openJoinProject();
                },
              ),
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
    final visible = orgs.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                orgs.length == 1 ? 'Your Organization' : 'Your Organizations',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _openAllOrgs(orgs),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  'View all',
                  style: TextStyle(
                    color: _teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
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
        for (final org in visible) ...[
          OrgListTile(
            organization: org,
            onTap: () => _openOrg(org),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _openAllOrgs(List<Organization> orgs) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AllOrganizationsScreen(organizations: orgs),
      ),
    );

    if (!mounted) return;
    await _loadOrgs();
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _actionCard(
            icon: Icons.handshake_outlined,
            title: 'Freelance & Company to Company Collaboration',
            subtitle:
                'Join a project with an invitation token or link, no organization needed',
            cta: 'Join a project',
            onTap: _openJoinProject,
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