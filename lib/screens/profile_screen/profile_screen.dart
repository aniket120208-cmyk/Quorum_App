import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/api/calendar_repository.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/meeting_history_store.dart';
import 'package:quorum_app/api/notification_service.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/calendar_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/screens/home_screen/calendar_helpers.dart';
import 'package:quorum_app/screens/home_screen/calendar_screen.dart';
import 'package:quorum_app/screens/jira_screen/jira_settings_screen.dart';
import 'package:quorum_app/screens/notification_screen/notification_preferences_screen.dart';
import 'package:quorum_app/screens/notification_screen/notification_screen.dart';
import 'package:quorum_app/screens/organization_screen/create_organization_screen.dart';
import 'package:quorum_app/screens/organization_screen/join_organization_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_detail_screen.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/saved_items_screen/saved_items_screen.dart';
import 'package:quorum_app/screens/sign_in_screen/sign_in_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> _profile = {};
  List<Organization> _orgs = [];
  List<CalendarEvent> _upcoming = [];
  int _meetingCount = 0;
  int? _openTasks;
  bool _profileLoading = true;
  bool _orgsLoading = true;
  bool _upcomingLoading = true;
  String? _profileError;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadProfile(),
      _loadOrgs(),
      _loadUpcoming(),
      _loadMeetings(),
    ]);
  }

  Future<void> _loadProfile() async {
    try {
      final data = await AuthService.instance.getUserProfile();
      CurrentUser.setFromProfile(data);
      if (!mounted) return;
      setState(() {
        _profile = AuthService.userFrom(data);
        _profileLoading = false;
        _profileError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileError = errorText(e);
      });
    }
  }

  Future<void> _loadOrgs() async {
    try {
      final orgs = await OrganizationRepository.instance.organizations();
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _orgsLoading = false;
      });
      _loadOpenTasks(orgs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _orgsLoading = false);
    }
  }

  Future<void> _loadOpenTasks(List<Organization> orgs) async {
    var total = 0;
    var reached = false;
    for (final org in orgs) {
      try {
        final tasks = await OrganizationRepository.instance.myTasks(org.id);
        total += tasks.where((t) => t.status != TaskStatus.completed).length;
        reached = true;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _openTasks = reached || orgs.isEmpty ? total : null);
  }

  Future<void> _loadUpcoming() async {
    try {
      final events = await CalendarRepository.instance.getUpcoming(limit: 3);
      if (!mounted) return;
      setState(() {
        _upcoming = events;
        _upcomingLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _upcomingLoading = false);
    }
  }

  Future<void> _loadMeetings() async {
    if (!CurrentUser.isLoaded) return;
    try {
      final items = await MeetingHistoryStore.instance.load(CurrentUser.id);
      if (!mounted) return;
      setState(() => _meetingCount = items.length);
    } catch (_) {}
  }

  String get _name {
    final fromProfile = (_profile['name'] ?? _profile['username'] ?? '').toString().trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    return CurrentUser.isLoaded ? CurrentUser.name : 'Your profile';
  }

  String? get _email {
    final value = (_profile['email'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  String? get _avatar {
    final value = (_profile['avatar'] ?? _profile['image'] ?? _profile['picture'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  DateTime? get _memberSince {
    final raw = _profile['createdAt'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  bool get _verified =>
      _profile['isEmailVerified'] == true ||
      _profile['isVerified'] == true ||
      _profile['emailVerified'] == true;

  List<String> get _useCases {
    final raw = _profile['useCases'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().replaceAll('_', ' ').replaceAll('-', ' ').trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e[0].toUpperCase() + e.substring(1))
        .toList();
  }

  String _memberSinceLabel(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.year}';
  }

  Future<void> _confirmLogout() async {
    final confirmed = await orgConfirm(
      context,
      title: 'Log out',
      body: 'Are you sure you want to log out?',
      action: 'Log out',
    );
    if (!confirmed || _loggingOut) return;

    setState(() => _loggingOut = true);
    try {
      await AuthService.instance.logout();
    } catch (_) {
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

  Future<void> _copyEmail() async {
    final email = _email;
    if (email == null) return;
    await Clipboard.setData(ClipboardData(text: email));
    if (mounted) orgToast(context, 'Email copied');
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: orgTeal,
        backgroundColor: orgCard,
        onRefresh: _loadAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _headerCard(),
            const SizedBox(height: 14),
            _statsRow(),
            if (_useCases.isNotEmpty) ...[
              const SizedBox(height: 22),
              _sectionTitle('Interests'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final label in _useCases) _tag(label)],
              ),
            ],
            const SizedBox(height: 22),
            _sectionTitle('Upcoming events', action: 'View calendar', onAction: () => _push(const CalendarScreen())),
            _upcomingSection(),
            const SizedBox(height: 22),
            _sectionTitle('Organizations'),
            _orgsSection(),
            const SizedBox(height: 22),
            _sectionTitle('Account'),
            _menuTile(
              icon: Icons.bookmark_border_rounded,
              label: 'Saved items',
              onTap: () => _push(const SavedItemsScreen()),
            ),
            _menuTile(
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
              trailing: ValueListenableBuilder<int>(
                valueListenable: NotificationService.instance.unreadCount,
                builder: (_, count, __) => count > 0 ? _badge(count) : const SizedBox.shrink(),
              ),
              onTap: () => _push(const NotificationScreen()),
            ),
            _menuTile(
              icon: Icons.tune_rounded,
              label: 'Notification preferences',
              onTap: () => _push(const NotificationPreferencesScreen()),
            ),
            _menuTile(
              icon: Icons.event_rounded,
              label: 'Calendar',
              onTap: () => _push(const CalendarScreen()),
            ),
            _menuTile(
              icon: Icons.view_kanban_outlined,
              label: 'Jira integration',
              onTap: () => _push(const JiraSettingsScreen()),
            ),
            const SizedBox(height: 22),
            _logoutButton(),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    final since = _memberSince;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2D6B), Color(0xFF1E2A4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        children: [
          OrgAvatar(name: _name, logo: _avatar, size: 84, circular: true),
          const SizedBox(height: 14),
          if (_profileLoading && _profile.isEmpty)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal),
            )
          else
            Text(
              _name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
            ),
          if (_email != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _copyEmail,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, color: Colors.white54, size: 14),
                ],
              ),
            ),
          ],
          if (_verified || since != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_verified) _pill(Icons.verified_rounded, 'Verified', orgTeal),
                if (since != null) _pill(Icons.calendar_today_rounded, 'Member since ${_memberSinceLabel(since)}', Colors.white70),
              ],
            ),
          ],
          if (_profileError != null && _profile.isEmpty) ...[
            const SizedBox(height: 12),
            Text(_profileError!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
            TextButton(
              onPressed: _loadProfile,
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        Expanded(child: _statTile(Icons.apartment_rounded, _orgsLoading ? '-' : '${_orgs.length}', 'Organizations')),
        const SizedBox(width: 10),
        Expanded(child: _statTile(Icons.task_alt_rounded, _openTasks == null ? '-' : '$_openTasks', 'Open tasks')),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orgBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: orgTeal, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: orgMuted, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {String? action, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action, style: const TextStyle(color: orgTeal, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF16302F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: orgTeal.withAlpha(90)),
      ),
      child: Text(label, style: const TextStyle(color: orgTeal, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _upcomingSection() {
    if (_upcomingLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal)),
      );
    }
    if (_upcoming.isEmpty) {
      return _emptyCard('No upcoming events');
    }
    return Column(
      children: [
        for (final event in _upcoming)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: orgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: orgBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: calendarEventColor(event.eventType),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${event.startDate.day}/${event.startDate.month}/${event.startDate.year} · ${calendarTimeLabel(context, event)}',
                        style: const TextStyle(color: orgMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(event.eventType.label, style: const TextStyle(color: orgMuted, fontSize: 11.5)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _orgsSection() {
    return Column(
      children: [
        if (_orgsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: orgTeal)),
          )
        else if (_orgs.isEmpty)
          _emptyCard('You are not part of any organization yet')
        else
          for (final org in _orgs)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _push(OrganizationDetailScreen(organization: org)),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: orgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: orgBorder),
                ),
                child: Row(
                  children: [
                    OrgAvatar(name: org.name, logo: org.logo, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        org.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OrgRoleBadge(role: org.role),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _push(const JoinOrganizationScreen()),
                icon: const Icon(Icons.login_rounded, size: 18, color: orgTeal),
                label: const Text('Join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: orgBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _push(const CreateOrganizationScreen()),
                icon: const Icon(Icons.add_rounded, size: 18, color: orgTeal),
                label: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: orgBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: orgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: orgBorder),
      ),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted, fontSize: 13)),
    );
  }

  Widget _badge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(10)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: orgTeal, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) ...[trailing, const SizedBox(width: 8)],
            const Icon(Icons.chevron_right_rounded, color: orgMuted),
          ],
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _loggingOut ? null : _confirmLogout,
        icon: _loggingOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
              )
            : const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
        label: const Text(
          'Log out',
          style: TextStyle(color: Color(0xFFEF4444), fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: const Color(0xFFEF4444).withAlpha(140)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}