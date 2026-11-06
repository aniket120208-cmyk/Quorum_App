import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';
import 'task_kanban_board.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key, required this.organization});
  final Organization organization;

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  final _repo = OrganizationRepository.instance;
  List<TeamTask> _tasks = [];
  bool _loading = true;
  String? _error;
  Timer? _poller;
  int _inFlight = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_loading && _inFlight == 0) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  String _signature(List<TeamTask> tasks) => tasks
      .map((t) => '${t.id}|${t.status.name}|${t.title}|${t.assigneeId}|${t.dueDate?.millisecondsSinceEpoch}')
      .join(';');

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tasks = await _repo.myTasks(widget.organization.id);
      if (!mounted) return;
      if (silent && _inFlight > 0) return;
      if (silent && !_loading && _error == null && _signature(tasks) == _signature(_tasks)) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _tasks.isEmpty) _error = errorText(e);
      });
    }
  }

  Future<void> _changeStatus(TeamTask task, TaskStatus status) async {
    final previous = task.status;
    _inFlight++;
    setState(() {
      _tasks = [for (final t in _tasks) t.id == task.id ? t.copyWith(status: status) : t];
    });
    try {
      final confirmed = await _repo.updateTaskStatus(
        widget.organization.id,
        task.teamId,
        task.id,
        status,
      );
      _inFlight--;
      if (!mounted) return;
      setState(() {
        _tasks = [for (final t in _tasks) t.id == task.id ? t.copyWith(status: confirmed) : t];
      });
    } catch (e) {
      _inFlight--;
      if (!mounted) return;
      setState(() {
        _tasks = [for (final t in _tasks) t.id == task.id ? t.copyWith(status: previous) : t];
      });
      orgToast(context, errorText(e), error: true);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(widget.organization.name, style: const TextStyle(fontSize: 12, color: orgMuted)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: orgTeal))
          : _error != null
              ? _errorView()
              : _tasks.isEmpty
                  ? RefreshIndicator(
                      color: orgTeal,
                      backgroundColor: orgCard,
                      onRefresh: () => _load(silent: true),
                      child: _empty(),
                    )
                  : TaskKanbanBoard(
                      tasks: _tasks,
                      showTeam: true,
                      canMove: (_) => true,
                      onMove: _changeStatus,
                      onRefresh: () => _load(silent: true),
                    ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: orgMuted, size: 42),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _load(),
              child: const Text('Retry', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: Text('No tasks assigned to you', style: TextStyle(color: orgMuted))),
      ],
    );
  }
}