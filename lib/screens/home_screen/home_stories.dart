import 'package:flutter/material.dart';

class StoryLine {
  final IconData icon;
  final Color? iconColor;
  final String text;
  final String? trailing;
  const StoryLine({required this.icon, required this.text, this.iconColor, this.trailing});
}

class StorySlide {
  final String id;
  final String label;
  final IconData icon;
  final List<Color> colors;
  final String headline;
  final String subtitle;
  final List<StoryLine> lines;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StorySlide({
    required this.id,
    required this.label,
    required this.icon,
    required this.colors,
    required this.headline,
    required this.subtitle,
    this.lines = const [],
    this.actionLabel,
    this.onAction,
  });
}

final Set<String> _viewedStories = {};

String storyTimeLabel(DateTime date, {bool allDay = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(today).inDays;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour >= 12 ? 'PM' : 'AM';
  final time = allDay ? 'All day' : '$hour:$minute $suffix';
  if (diff == 0) return allDay ? 'Today' : 'Today $time';
  if (diff == 1) return allDay ? 'Tomorrow' : 'Tomorrow $time';
  return allDay ? days[date.weekday - 1] : '${days[date.weekday - 1]} $time';
}

class StoriesRow extends StatelessWidget {
  const StoriesRow({super.key, required this.slides, required this.onOpen});

  final List<StorySlide> slides;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slides.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          final slide = slides[i];
          final viewed = _viewedStories.contains(slide.id);
          return GestureDetector(
            onTap: () => onOpen(i),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: viewed
                          ? null
                          : LinearGradient(
                              colors: slide.colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: viewed ? const Color(0xFF2C3246) : null,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF090A10)),
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: slide.colors.map((c) => c.withValues(alpha: viewed ? 0.45 : 1)).toList(),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(slide.icon, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    slide.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: viewed ? const Color(0xFF9EA3AE) : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> openStories(BuildContext context, List<StorySlide> slides, int initialIndex) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => StoryViewer(slides: slides, initialIndex: initialIndex),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    ),
  );
}

class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.slides, this.initialIndex = 0});

  final List<StorySlide> slides;
  final int initialIndex;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(seconds: 6);

  late final AnimationController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctrl = AnimationController(vsync: this, duration: _slideDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _start();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    _viewedStories.add(widget.slides[_index].id);
    _ctrl.forward(from: 0);
  }

  void _next() {
    if (!mounted) return;
    if (_index >= widget.slides.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _start();
  }

  void _previous() {
    if (_index == 0) {
      _ctrl.forward(from: 0);
      return;
    }
    setState(() => _index--);
    _start();
  }

  void _onTap(TapUpDetails d) {
    final width = MediaQuery.of(context).size.width;
    if (d.globalPosition.dx < width * 0.3) {
      _previous();
    } else {
      _next();
    }
  }

  Widget _progressBars() {
    return Row(
      children: [
        for (var i = 0; i < widget.slides.length; i++) ...[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 3.5,
                child: i == _index
                    ? AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, _) => LinearProgressIndicator(
                          value: _ctrl.value,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : LinearProgressIndicator(
                        value: i < _index ? 1 : 0,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
              ),
            ),
          ),
          if (i != widget.slides.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }

  Widget _lineTile(StoryLine line, int order) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('${widget.slides[_index].id}-$order'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + order * 110),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, 22 * (1 - value)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(line.icon, color: line.iconColor ?? Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                line.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (line.trailing != null) ...[
              const SizedBox(width: 10),
              Text(
                line.trailing!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slides[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [slide.colors.first, slide.colors.last.withValues(alpha: 0.85), const Color(0xFF090A10)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTap,
                onLongPressStart: (_) => _ctrl.stop(),
                onLongPressEnd: (_) => _ctrl.forward(),
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IgnorePointer(child: _progressBars()),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
                          child: Icon(slide.icon, color: Colors.white, size: 19),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            slide.label,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                        ),
                      ],
                    ),
                    Expanded(
                      child: IgnorePointer(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          child: Column(
                            key: ValueKey(slide.id),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                slide.headline,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                slide.subtitle,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 15, height: 1.35),
                              ),
                              const SizedBox(height: 24),
                              for (var i = 0; i < slide.lines.length; i++) _lineTile(slide.lines[i], i),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (slide.actionLabel != null && slide.onAction != null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            slide.onAction!();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(slide.actionLabel!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}