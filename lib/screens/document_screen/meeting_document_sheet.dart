import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/document_repository.dart';
import 'package:quorum_app/models/document_models.dart';
import 'package:quorum_app/screens/document_screen/document_widgets.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

typedef MeetingDocumentChoice = ({String id, String title});

class MeetingDocumentSheet extends StatefulWidget {
  const MeetingDocumentSheet({
    super.key,
    required this.meetingCode,
    required this.meetingTitle,
    required this.organizationId,
    this.meetingId = '',
    this.activeDocumentId,
  });

  final String meetingCode;
  final String meetingTitle;
  final String organizationId;
  final String meetingId;
  final String? activeDocumentId;

  static Future<MeetingDocumentChoice?> show(
    BuildContext context, {
    required String meetingCode,
    required String meetingTitle,
    required String organizationId,
    String meetingId = '',
    String? activeDocumentId,
  }) {
    return showModalBottomSheet<MeetingDocumentChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: orgCard,
      shape: orgSheetShape,
      builder: (_) => MeetingDocumentSheet(
        meetingCode: meetingCode,
        meetingTitle: meetingTitle,
        organizationId: organizationId,
        meetingId: meetingId,
        activeDocumentId: activeDocumentId,
      ),
    );
  }

  @override
  State<MeetingDocumentSheet> createState() => _MeetingDocumentSheetState();
}

class _MeetingDocumentSheetState extends State<MeetingDocumentSheet> {
  final DocumentRepository _repo = DocumentRepository.instance;
  List<DocumentSummary> _meetingDocs = const [];
  List<DocumentSummary> _otherDocs = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _byRecent(DocumentSummary a, DocumentSummary b) {
    final at = a.updatedAt?.millisecondsSinceEpoch ?? 0;
    final bt = b.updatedAt?.millisecondsSinceEpoch ?? 0;
    return bt.compareTo(at);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var meetingDocs = <DocumentSummary>[];
      if (widget.meetingId.isNotEmpty) {
        try {
          meetingDocs = await _repo.list(meetingId: widget.meetingId);
        } catch (_) {}
      }
      final all = await _repo.list(organizationId: widget.organizationId);
      final meetingIds = meetingDocs.map((d) => d.id).toSet();
      final others = all
          .where((d) =>
              !d.isArchived &&
              !meetingIds.contains(d.id) &&
              d.scopeType != DocumentScope.personal &&
              (d.organizationId == null || d.organizationId == widget.organizationId))
          .toList()
        ..sort(_byRecent);
      meetingDocs = meetingDocs.where((d) => !d.isArchived).toList()..sort(_byRecent);
      if (!mounted) return;
      setState(() {
        _meetingDocs = meetingDocs;
        _otherDocs = others;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _choose(String id, String title) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.openInMeeting(id, widget.meetingCode);
      if (!mounted) return;
      Navigator.pop(context, (id: id, title: title));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    final title = await showOrgSheet<String>(
      context,
      DocumentTextSheet(
        title: 'New meeting notes',
        hint: 'Document title',
        action: 'Create & open',
        initial: '${widget.meetingTitle} notes',
      ),
    );
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final hasMeeting = widget.meetingId.isNotEmpty;
      final doc = await _repo.create(
        title: title,
        scope: hasMeeting ? DocumentScope.meeting : DocumentScope.personal,
        meetingId: hasMeeting ? widget.meetingId : null,
      );
      await _repo.openInMeeting(doc.id, widget.meetingCode);
      if (!mounted) return;
      Navigator.pop(context, (id: doc.id, title: doc.title));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  List<DocumentSummary> _filter(List<DocumentSummary> docs) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return docs;
    return docs.where((d) => d.title.toLowerCase().contains(q)).toList();
  }

  Widget _section(String label, List<DocumentSummary> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(label, style: const TextStyle(color: orgMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        for (final d in docs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: !_busy,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.description_outlined, color: orgTeal, size: 20),
            ),
            title: Text(
              d.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
            subtitle: Text(
              [d.scopeType.label, if (d.updatedAt != null) documentAgo(d.updatedAt)].join(' • '),
              style: const TextStyle(color: orgMuted, fontSize: 12),
            ),
            trailing: d.id == widget.activeDocumentId
                ? const Icon(Icons.check_circle_rounded, color: orgTeal, size: 20)
                : const Icon(Icons.chevron_right_rounded, color: orgMuted),
            onTap: () => _choose(d.id, d.title),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final meetingDocs = _filter(_meetingDocs);
    final otherDocs = _filter(_otherDocs);
    final empty = meetingDocs.isEmpty && otherDocs.isEmpty;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Co-author a document', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Everyone in the call will see it open next to the video.', style: TextStyle(color: orgMuted, fontSize: 12.5)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.note_add_outlined, size: 18, color: Color.fromARGB(221, 255, 255, 255),),
                  label: const Text('New meeting notes', style: TextStyle(fontWeight: FontWeight.w700, color: Color.fromARGB(221, 255, 255, 255))),
                  style: FilledButton.styleFrom(
                    backgroundColor: orgAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search documents',
                  hintStyle: const TextStyle(color: orgMuted),
                  prefixIcon: const Icon(Icons.search_rounded, color: orgMuted),
                  isDense: true,
                  filled: true,
                  fillColor: orgField,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: orgTeal)),
                      )
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Try again', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          )
                        : empty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Center(child: Text('No documents yet.', style: TextStyle(color: orgMuted))),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: [
                                  _section('THIS MEETING', meetingDocs),
                                  _section(meetingDocs.isEmpty ? 'ORGANIZATION DOCUMENTS' : 'OTHER ORGANIZATION DOCUMENTS', otherDocs),
                                ],
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}