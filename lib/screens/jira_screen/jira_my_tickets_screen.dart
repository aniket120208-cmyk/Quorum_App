import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/jira_repository.dart';
import 'package:quorum_app/models/jira_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'jira_widgets.dart';

class JiraMyTicketsScreen extends StatefulWidget {
  const JiraMyTicketsScreen({super.key});

  @override
  State<JiraMyTicketsScreen> createState() => _JiraMyTicketsScreenState();
}

class _JiraMyTicketsScreenState extends State<JiraMyTicketsScreen> {
  final _repo = JiraRepository.instance;
  List<JiraTicket> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tickets = await _repo.myTickets();
      tickets.sort((a, b) => a.column.index.compareTo(b.column.index));
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _tickets.isEmpty) _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('My Jira tickets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? JiraMessageView(
                  icon: Icons.error_outline_rounded,
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              : RefreshIndicator(
                  color: orgTeal,
                  backgroundColor: orgCard,
                  onRefresh: () => _load(silent: true),
                  child: _tickets.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            Center(child: Text('No Jira tickets assigned to you', style: TextStyle(color: orgMuted))),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          itemCount: _tickets.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => JiraTicketCard(ticket: _tickets[index], showAssignee: false),
                        ),
                ),
    );
  }
}