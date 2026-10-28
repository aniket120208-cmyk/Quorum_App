import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/whiteboard_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'whiteboard_list_screen.dart';
import 'whiteboard_sheets.dart';

enum _View { meeting, organizations, organizationBoards }

class MeetingWhiteboardSheet extends StatefulWidget {
  const MeetingWhiteboardSheet({super.key, required this.meetingCode});
  final String meetingCode;
  static Future<Whiteboard?> show(BuildContext context, String meetingCode) {
    return showModalBottomSheet<Whiteboard>(
      context: context,
      isScrollControlled: true,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      builder: (_) => MeetingWhiteboardSheet(meetingCode: meetingCode),
    );
  }

  @override
  State<MeetingWhiteboardSheet> createState() => _MeetingWhiteboardSheetState();
}

class _MeetingWhiteboardSheetState extends State<MeetingWhiteboardSheet> {
  final _boards = WhiteboardRepository.instance;
  final _orgs = OrganizationRepository.instance;
  _View _view = _View.meeting;
  List<Whiteboard> _meetingBoards = const [];
  List<Organization> _organizations = const [];
  List<Whiteboard> _orgBoards = const [];
  Organization? _org;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMeeting();
  }

  Future<void> _guarded(Future<void> Function() run) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await run();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadMeeting() => _guarded(() async {
        _meetingBoards = await _boards.meetingBoards(widget.meetingCode);
      });

  Future<void> _loadOrganizations() => _guarded(() async {
        _view = _View.organizations;
        _organizations = await _orgs.organizations();
      });

  Future<void> _loadOrgBoards(Organization org) => _guarded(() async {
        _view = _View.organizationBoards;
        _org = org;
        final page = await _boards.list(org.id, limit: 50);
        _orgBoards = page.items;
      });

  void _back() {
    if (_view == _View.organizationBoards) {
      _loadOrganizations();
    } else {
      setState(() {
        _view = _View.meeting;
        _error = null;
      });
      _loadMeeting();
    }
  }

  Future<void> _openBoard(Whiteboard board) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final opened = await _boards.openInMeeting(widget.meetingCode, board.id);
      if (!mounted) return;
      final result = opened.whiteboard.id.isEmpty ? board : opened.whiteboard;
      Navigator.pop(context, result.name.isEmpty ? board : result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    final name = await showOrgSheet<String>(
      context,
      const WhiteboardNameSheet(title: 'New whiteboard', action: 'Create'),
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final board = await _boards.createInMeeting(widget.meetingCode, name: name);
      if (!mounted) return;
      Navigator.pop(context, board.copyWith(name: name));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  String get _title {
    switch (_view) {
      case _View.meeting:
        return 'Whiteboards';
      case _View.organizations:
        return 'Choose organization';
      case _View.organizationBoards:
        return _org?.name ?? 'Boards';
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_view != _View.meeting)
                    IconButton(
                      onPressed: _busy ? null : _back,
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_view == _View.meeting) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New board', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orgAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _loadOrganizations,
                        icon: const Icon(Icons.business_rounded, size: 18, color: orgTeal),
                        label: const Text(
                          'From organization',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: orgBorder),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Flexible(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: orgTeal)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                switch (_view) {
                  case _View.meeting:
                    _loadMeeting();
                  case _View.organizations:
                    _loadOrganizations();
                  case _View.organizationBoards:
                    if (_org != null) _loadOrgBoards(_org!);
                }
              },
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    switch (_view) {
      case _View.meeting:
        return _list<Whiteboard>(
          _meetingBoards,
          'No whiteboards in this meeting yet',
          (b) => _row(Icons.draw_rounded, b.name, whiteboardAgo(b.updatedAt), () => _openBoard(b)),
        );
      case _View.organizations:
        return _list<Organization>(
          _organizations,
          'You are not part of any organization',
          (o) => _row(Icons.business_rounded, o.name, orgRoleLabel(o.role), () => _loadOrgBoards(o)),
        );
      case _View.organizationBoards:
        return _list<Whiteboard>(
          _orgBoards,
          'No whiteboards in this organization',
          (b) => _row(Icons.draw_rounded, b.name, whiteboardAgo(b.updatedAt), () => _openBoard(b)),
        );
    }
  }

  Widget _list<T>(List<T> items, String empty, Widget Function(T) builder) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(child: Text(empty, style: const TextStyle(color: orgMuted))),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => builder(items[index]),
    );
  }

  Widget _row(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: orgTeal, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: const TextStyle(color: orgMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: orgMuted),
          ],
        ),
      ),
    );
  }
}