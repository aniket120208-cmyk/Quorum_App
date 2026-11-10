import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/document_repository.dart';
import 'package:quorum_app/models/document_models.dart';
import 'package:quorum_app/screens/document_screen/document_editor_screen.dart';
import 'package:quorum_app/screens/document_screen/document_widgets.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({
    super.key,
    required this.title,
    required this.scope,
    this.organizationId,
    this.teamId,
    this.projectId,
    this.meetingId,
  });

  final String title;
  final DocumentScope scope;
  final String? organizationId;
  final String? teamId;
  final String? projectId;
  final String? meetingId;

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final DocumentRepository _repo = DocumentRepository.instance;
  List<DocumentSummary> _docs = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final docs = await _repo.list(
        organizationId: widget.organizationId,
        teamId: widget.teamId,
        projectId: widget.projectId,
        meetingId: widget.meetingId,
      );
      docs.sort((a, b) {
        final at = a.updatedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.updatedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        _docs = docs.where((d) => !d.isArchived).toList();
        _error = null;
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

  Future<void> _open(String id, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocumentEditorScreen(documentId: id, initialTitle: title)),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _create() async {
    if (_creating) return;
    final title = await showOrgSheet<String>(
      context,
      const DocumentTextSheet(title: 'New document', hint: 'Document title', action: 'Create'),
    );
    if (title == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final doc = await _repo.create(
        title: title,
        scope: widget.scope,
        organizationId: widget.organizationId,
        teamId: widget.teamId,
        projectId: widget.projectId,
        meetingId: widget.meetingId,
      );
      if (!mounted) return;
      setState(() => _creating = false);
      await _open(doc.id, doc.title);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  List<DocumentSummary> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _docs;
    return _docs.where((d) => d.title.toLowerCase().contains(q)).toList();
  }

  Widget _tile(DocumentSummary doc) {
    final meta = [
      doc.scopeType.label,
      if (doc.updatedAt != null) documentAgo(doc.updatedAt),
      if (doc.collaboratorsCount > 0) '${doc.collaboratorsCount} collaborator${doc.collaboratorsCount == 1 ? '' : 's'}',
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(doc.id, doc.title),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: orgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: orgBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.description_outlined, color: orgTeal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: orgMuted, fontSize: 12.5),
                    ),
                    if (doc.createdBy.name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'by ${doc.createdBy.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: orgMuted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: orgMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text, {String? action, VoidCallback? onAction}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, color: orgMuted, size: 44),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted, fontSize: 14)),
        ),
        if (action != null)
          Center(
            child: TextButton(
              onPressed: onAction,
              child: Text(action, style: const TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: orgTeal));
    if (_error != null) {
      return _message(Icons.error_outline_rounded, _error!, action: 'Try again', onAction: _load);
    }
    final docs = _visible;
    if (docs.isEmpty) {
      return _message(
        Icons.description_outlined,
        _query.isEmpty ? 'No documents yet. Create the first one.' : 'No documents match your search.',
        action: _query.isEmpty ? 'New document' : null,
        onAction: _create,
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: docs.length,
      itemBuilder: (context, i) => _tile(docs[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _create,
        backgroundColor: orgAccent,
        foregroundColor: Colors.white,
        icon: _creating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_rounded),
        label: const Text('New document', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search documents',
                hintStyle: const TextStyle(color: orgMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: orgMuted),
                filled: true,
                fillColor: orgField,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: orgTeal,
              backgroundColor: orgCard,
              onRefresh: () => _load(silent: true),
              child: _content(),
            ),
          ),
        ],
      ),
    );
  }
}