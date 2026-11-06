import 'package:flutter/material.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';
import 'task_widgets.dart';

class TaskKanbanBoard extends StatefulWidget {
  const TaskKanbanBoard({
    super.key,
    required this.tasks,
    required this.canMove,
    required this.onMove,
    required this.onRefresh,
    this.showTeam = false,
    this.bottomPadding = 24,
  });

  final List<TeamTask> tasks;
  final bool Function(TeamTask task) canMove;
  final void Function(TeamTask task, TaskStatus status) onMove;
  final Future<void> Function() onRefresh;
  final bool showTeam;
  final double bottomPadding;

  @override
  State<TaskKanbanBoard> createState() => _TaskKanbanBoardState();
}

class _TaskKanbanBoardState extends State<TaskKanbanBoard> {
  late final PageController _pages = PageController(viewportFraction: 0.88);
  int _page = 0;
  bool _dragging = false;
  DateTime _lastEdgeSwitch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<TeamTask> _byStatus(TaskStatus status) {
    final list = widget.tasks.where((t) => t.status == status).toList();
    list.sort((a, b) {
      final due = (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999));
      if (due != 0) return due;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });
    return list;
  }

  void _goTo(int page) {
    if (page < 0 || page >= TaskStatus.values.length) return;
    _pages.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _edgeHover(int direction) {
    final now = DateTime.now();
    if (now.difference(_lastEdgeSwitch).inMilliseconds < 650) return;
    _lastEdgeSwitch = now;
    _goTo(_page + direction);
  }

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          for (var i = 0; i < TaskStatus.values.length; i++) ...[
            Expanded(child: _tab(TaskStatus.values[i], i)),
            if (i != TaskStatus.values.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _tab(TaskStatus status, int index) {
    final selected = _page == index;
    final color = taskStatusColor(status);
    final count = widget.tasks.where((t) => t.status == status).length;
    return GestureDetector(
      onTap: () => _goTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : orgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : orgBorder, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(taskStatusIcon(status), color: color, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${status.label} $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : orgMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draggableCard(TeamTask task, double width) {
    final card = TaskCard(
      task: task,
      showTeam: widget.showTeam,
      onStatusChange: widget.canMove(task) ? (next) => widget.onMove(task, next) : null,
    );
    if (!widget.canMove(task)) return card;
    return LongPressDraggable<TeamTask>(
      data: task,
      delay: const Duration(milliseconds: 220),
      hapticFeedbackOnStart: true,
      onDragStarted: () => setState(() => _dragging = true),
      onDragEnd: (_) => setState(() => _dragging = false),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          child: Transform.rotate(
            angle: 0.03,
            child: Opacity(
              opacity: 0.95,
              child: TaskCard(task: task, showTeam: widget.showTeam),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      child: card,
    );
  }

  Widget _column(TaskStatus status, double pageWidth) {
    final tasks = _byStatus(status);
    final color = taskStatusColor(status);
    return DragTarget<TeamTask>(
      onWillAcceptWithDetails: (d) => d.data.status != status,
      onAcceptWithDetails: (d) => widget.onMove(d.data, status),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: hovering ? color.withValues(alpha: 0.10) : orgCard.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hovering ? color : orgBorder, width: hovering ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(taskStatusIcon(status), color: color, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      status.label,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${tasks.length}',
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: orgTeal,
                  backgroundColor: orgCard,
                  onRefresh: widget.onRefresh,
                  child: tasks.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 60),
                            Icon(taskStatusIcon(status), color: color.withValues(alpha: 0.35), size: 38),
                            const SizedBox(height: 10),
                            Center(
                              child: Text(
                                hovering ? 'Drop here' : 'No ${status.label.toLowerCase()} tasks',
                                style: const TextStyle(color: orgMuted, fontSize: 13),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(12, 4, 12, widget.bottomPadding + 90),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _draggableCard(tasks[i], pageWidth - 48),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dockTarget(TaskStatus status) {
    final color = taskStatusColor(status);
    return Expanded(
      child: DragTarget<TeamTask>(
        onWillAcceptWithDetails: (d) => d.data.status != status,
        onAcceptWithDetails: (d) => widget.onMove(d.data, status),
        builder: (context, candidates, rejected) {
          final hovering = candidates.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: hovering ? 64 : 56,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: hovering ? color.withValues(alpha: 0.28) : orgField,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hovering ? color : orgBorder, width: hovering ? 2 : 1),
              boxShadow: hovering ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14)] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(taskStatusIcon(status), color: color, size: 20),
                const SizedBox(height: 3),
                Text(
                  status.label,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _edge(int direction) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: direction < 0 ? 0 : null,
      right: direction > 0 ? 0 : null,
      width: 36,
      child: DragTarget<TeamTask>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (_) {},
        onMove: (_) => _edgeHover(direction),
        builder: (context, candidates, rejected) => const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth * 0.88;
        return Stack(
          children: [
            Column(
              children: [
                _tabs(),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: TaskStatus.values.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => Padding(
                      padding: EdgeInsets.only(bottom: widget.bottomPadding),
                      child: _column(TaskStatus.values[i], pageWidth),
                    ),
                  ),
                ),
              ],
            ),
            if (_dragging) ...[_edge(-1), _edge(1)],
            Positioned(
              left: 12,
              right: 12,
              bottom: 14 + widget.bottomPadding,
              child: IgnorePointer(
                ignoring: !_dragging,
                child: AnimatedSlide(
                  offset: _dragging ? Offset.zero : const Offset(0, 1.6),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: _dragging ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Row(children: [for (final s in TaskStatus.values) _dockTarget(s)]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}