import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/deep_link_router.dart';
import 'package:quorum_app/api/quorumbot_controller.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'package:quorum_app/models/quorumbot_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart' show AppColors;
import 'package:quorum_app/screens/video_call_screen/meeting_launcher.dart';
import 'package:quorum_app/widgets/quorumbot_mascot.dart';

const Color _bg = Color(0xFF090A10);
const Color _card = Color(0xFF14151F);
const Color _border = Color(0x1AFFFFFF);
const Color _muted = Color(0xFF9EA3AE);
const Color _red = Color(0xFF3DDCC4);
const Color _redDeep = Color(0xFF4C3AE3);
const Color _err = Color(0xFFFF5A5F);
const Color _ok = Color(0xFF3DDC84);

class UltronHost extends StatelessWidget {
  final Widget child;
  const UltronHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => const _UltronLayer())],
          ),
        ),
      ],
    );
  }
}

class _UltronLayer extends StatefulWidget {
  const _UltronLayer();

  @override
  State<_UltronLayer> createState() => _UltronLayerState();
}

class _UltronLayerState extends State<_UltronLayer> with SingleTickerProviderStateMixin {
  static const double _bubble = 58;
  final UltronController _c = UltronController.instance;
  Offset? _pos;
  Rect? _panel;
  bool _dragging = false;
  late final AnimationController _snap;
  Animation<Offset>? _snapAnim;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        final a = _snapAnim;
        if (a != null) setState(() => _pos = a.value);
      });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  static const double _minW = 280;
  static const double _minH = 300;

  Rect _defaultPanel(Size area, EdgeInsets pad) {
    final topLimit = pad.top + 6;
    final bottomLimit = area.height - pad.bottom - 8;
    final w = math.min(380.0, math.max(_minW, area.width - 16));
    final h = math.min(560.0, math.max(_minH, (bottomLimit - topLimit) * 0.9));
    return Rect.fromLTWH(area.width - w - 8, bottomLimit - h, w, h);
  }

  Rect _limit(Rect r, Size area, EdgeInsets pad, double kb) {
    final topLimit = pad.top + 6;
    final bottomLimit = area.height - math.max(kb, pad.bottom) - 8;
    final maxW = math.max(_minW, area.width - 16);
    final maxH = math.max(_minH, bottomLimit - topLimit);
    final w = r.width.clamp(_minW, maxW).toDouble();
    final h = r.height.clamp(_minH, maxH).toDouble();
    final left = r.left.clamp(8.0, math.max(8.0, area.width - w - 8)).toDouble();
    final top = r.top.clamp(topLimit, math.max(topLimit, bottomLimit - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  Rect _current(Size area, EdgeInsets pad, double kb) {
    return _limit(_panel ?? _defaultPanel(area, pad), area, pad, kb);
  }

  void _movePanel(Offset d, Size area, EdgeInsets pad, double kb) {
    final base = _current(area, pad, kb);
    setState(() => _panel = _limit(base.shift(d), area, pad, kb));
  }

  void _resizePanel(Offset d, Size area, EdgeInsets pad, double kb) {
    final base = _current(area, pad, kb);
    final topLimit = pad.top + 6;
    final maxW = math.max(_minW, base.right - 8);
    final maxH = math.max(_minH, base.bottom - topLimit);
    final w = (base.width - d.dx).clamp(_minW, maxW).toDouble();
    final h = (base.height - d.dy).clamp(_minH, maxH).toDouble();
    setState(() => _panel = Rect.fromLTRB(base.right - w, base.bottom - h, base.right, base.bottom));
  }

  Offset _clamp(Offset o, Size area, EdgeInsets pad) {
    final minX = 8.0;
    final maxX = area.width - _bubble - 8;
    final minY = pad.top + 8;
    final maxY = area.height - _bubble - pad.bottom - 8;
    return Offset(o.dx.clamp(minX, maxX), o.dy.clamp(minY, math.max(minY, maxY)));
  }

  void _release(Size area, EdgeInsets pad) {
    final p = _pos;
    if (p == null) return;
    final toRight = p.dx + _bubble / 2 > area.width / 2;
    final target = _clamp(Offset(toRight ? area.width - _bubble - 12 : 12, p.dy), area, pad);
    _snapAnim = Tween<Offset>(begin: p, end: target).animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    _snap
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (!_c.active) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final area = mq.size;
        final pad = mq.padding;
        final kb = mq.viewInsets.bottom;
        _pos ??= Offset(area.width - _bubble - 12, area.height - _bubble - pad.bottom - 96);
        final pos = _clamp(_pos!, area, pad);

        final rect = _current(area, pad, kb);

        return Stack(
          children: [
            if (_c.open)
              Positioned.fromRect(
                rect: rect,
                child: _UltronPanel(
                  controller: _c,
                  onMove: (d) => _movePanel(d, area, pad, kb),
                  onResize: (d) => _resizePanel(d, area, pad, kb),
                ),
              ),
            if (!_c.open)
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  onTap: _c.toggle,
                  onPanStart: (_) {
                    _snap.stop();
                    setState(() => _dragging = true);
                  },
                  onPanUpdate: (d) => setState(() => _pos = _clamp((_pos ?? pos) + d.delta, area, pad)),
                  onPanEnd: (_) {
                    setState(() => _dragging = false);
                    _release(area, pad);
                  },
                  child: _Bubble(thinking: _c.thinking, lifted: _dragging, hasPending: _c.messages.any((m) => m.kind == UltronMessageKind.plan && !m.settled)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool thinking;
  final bool lifted;
  final bool hasPending;
  const _Bubble({required this.thinking, required this.lifted, required this.hasPending});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: lifted ? 1.12 : 1,
      duration: const Duration(milliseconds: 120),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF1C2140), Color(0xFF0A0B14)],
              ),
              border: Border.all(color: _red.withOpacity(0.75), width: 1.6),
              boxShadow: [
                BoxShadow(color: _red.withOpacity(thinking ? 0.55 : 0.32), blurRadius: thinking ? 22 : 14, spreadRadius: 1),
                const BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.all(7),
            child: UltronMascot(size: 44, thinking: thinking),
          ),
          if (hasPending)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _ok,
                  shape: BoxShape.circle,
                  border: Border.all(color: _bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UltronPanel extends StatefulWidget {
  final UltronController controller;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  const _UltronPanel({required this.controller, required this.onMove, required this.onResize});

  @override
  State<_UltronPanel> createState() => _UltronPanelState();
}

class _UltronPanelState extends State<_UltronPanel> {
  final Map<UltronMode, TextEditingController> _inputs = {
    for (final m in UltronMode.values) m: TextEditingController(),
  };
  final Map<UltronMode, ScrollController> _scrolls = {
    for (final m in UltronMode.values) m: ScrollController(),
  };
  final Map<UltronMode, FocusNode> _focuses = {
    for (final m in UltronMode.values) m: FocusNode(),
  };
  late final PageController _pages = PageController(initialPage: c.mode == UltronMode.ask ? 1 : 0);
  int _lastCount = 0;
  bool _lastThinking = false;

  UltronController get c => widget.controller;

  @override
  void dispose() {
    for (final x in _inputs.values) {
      x.dispose();
    }
    for (final x in _scrolls.values) {
      x.dispose();
    }
    for (final x in _focuses.values) {
      x.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final sc in _scrolls.values) {
        if (!sc.hasClients) continue;
        sc.animateTo(
          sc.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(UltronMode m) {
    final input = _inputs[m]!;
    final t = input.text;
    if (t.trim().isEmpty || c.thinking) return;
    input.clear();
    c.send(t);
  }

  void _select(UltronMode m) {
    c.setMode(m);
    _pages.animateToPage(
      m == UltronMode.command ? 0 : 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Widget _page(UltronMode m) {
    return Column(
      children: [
        Expanded(child: c.messagesFor(m).isEmpty ? _empty(m) : _list(m)),
        _composer(m),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(child: _frame()),
          Positioned(
            left: 0,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => widget.onResize(d.delta),
              child: const SizedBox(width: 30, height: 30, child: CustomPaint(painter: _GripPainter())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _frame() {
    return Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _red.withOpacity(0.35)),
          boxShadow: [BoxShadow(color: _red.withOpacity(0.18), blurRadius: 28, spreadRadius: 1)],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            if (c.messages.length != _lastCount || c.thinking != _lastThinking) {
              _lastCount = c.messages.length;
              _lastThinking = c.thinking;
              _toBottom();
            }
            return Column(
              children: [
                _header(),
                _modeBar(),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const ClampingScrollPhysics(),
                    onPageChanged: (i) => c.setMode(i == 0 ? UltronMode.command : UltronMode.ask),
                    children: [_page(UltronMode.command), _page(UltronMode.ask)],
                  ),
                ),
              ],
            );
          },
        ),
    );
  }

  Widget _header() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => widget.onMove(d.delta),
      child: _headerBody(),
    );
  }

  Widget _headerBody() {
    return Container(
      padding: const EdgeInsets.fromLTRB(34, 12, 6, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF151A33), _bg]),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0E1122),
              border: Border.all(color: _red.withOpacity(0.7)),
            ),
            padding: const EdgeInsets.all(4),
            child: UltronMascot(size: 32, thinking: c.thinking),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUORUM BOT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.8),
                ),
                const SizedBox(height: 2),
                Text(
                  'One command. Full execution.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (c.messagesFor(c.mode).isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              visualDensity: VisualDensity.compact,
              onPressed: c.thinking ? null : c.clearChat,
              icon: const Icon(Icons.delete_sweep_outlined, color: _muted, size: 20),
            ),
          IconButton(
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: c.close,
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _modeBar() {
    Widget chip(UltronMode m, IconData icon, String label) {
      final on = c.mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => _select(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? AppColors.primary : Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: on ? Colors.white : _muted),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: on ? Colors.white : _muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
      child: Row(
        children: [
          chip(UltronMode.command, Icons.bolt_rounded, 'Command'),
          chip(UltronMode.ask, Icons.chat_bubble_outline_rounded, 'Ask'),
        ],
      ),
    );
  }

  static const List<String> _commandExamples = [
    'Create a Design team with Sarah, schedule a review for Friday 3 PM, and share Brand Guidelines.',
    'Schedule a standup with the Mobile team tomorrow at 10 AM and notify everyone.',
    'Create a Backend team with Alice and Bob and notify them.',
  ];

  static const List<String> _askExamples = [
    'What should I focus on today?',
    'Summarize my recent meetings.',
  ];

  Widget _empty(UltronMode m) {
    final examples = m == UltronMode.command ? _commandExamples : _askExamples;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0E1122),
              border: Border.all(color: _red.withOpacity(0.55)),
              boxShadow: [BoxShadow(color: _red.withOpacity(0.35), blurRadius: 26)],
            ),
            padding: const EdgeInsets.all(10),
            child: const UltronMascot(size: 64),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            m == UltronMode.command ? 'Tell me what to get done.' : 'Ask me anything about your work.',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            m == UltronMode.command
                ? (c.handsFree
                    ? 'Typed commands show a plan first. Voice commands run right away.'
                    : 'I plan every step first. Nothing runs until you confirm.')
                : 'Quick answers from your workspace knowledge.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 18),
        for (final e in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _inputs[m]!.text = e;
                _inputs[m]!.selection = TextSelection.collapsed(offset: e.length);
                _focuses[m]!.requestFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                child: Row(
                  children: [
                    const Icon(Icons.north_west_rounded, size: 14, color: _red),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _list(UltronMode m) {
    final msgs = c.messagesFor(m);
    return ListView.builder(
      controller: _scrolls[m],
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: msgs.length + (c.thinking && c.thinkingMode == m && !msgs.any((m) => m.busy) ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= msgs.length) return const _Typing();
        return _MessageView(message: msgs[i], controller: c);
      },
    );
  }

  Widget _composer(UltronMode m) {
    final cmd = m == UltronMode.command;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cmd) _handsFreeRow(),
          _composerRow(m),
        ],
      ),
    );
  }

  Widget _handsFreeRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => c.setHandsFree(!c.handsFree),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: c.handsFree ? _red : _muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                c.handsFree ? 'Hands-free voice: runs without asking' : 'Hands-free voice off: voice shows a plan first',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.handsFree ? Colors.white70 : _muted, fontSize: 11.5),
              ),
            ),
            SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: c.handsFree,
                  onChanged: c.setHandsFree,
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? _redDeep : _card,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _micButton(UltronMode mode) {
    final on = c.listening && c.mode == mode;
    return GestureDetector(
      onTap: c.thinking ? null : c.toggleListening,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? _err : _card,
          border: Border.all(color: on ? _err : _border),
          boxShadow: on ? [BoxShadow(color: _err.withOpacity(0.45), blurRadius: 14, spreadRadius: 2)] : null,
        ),
        child: Icon(on ? Icons.stop_rounded : Icons.mic_rounded, color: on ? Colors.white : _red, size: 22),
      ),
    );
  }

  Widget _composerRow(UltronMode m) {
    final cmd = m == UltronMode.command;
    final listening = c.listening && c.mode == m;
    return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20), border: Border.all(color: listening ? _err : _border)),
              child: listening
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          c.transcript.isEmpty ? 'Listening…' : c.transcript,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.transcript.isEmpty ? _muted : Colors.white, fontSize: 14),
                        ),
                      ),
                    )
                  : TextField(
                controller: _inputs[m],
                focusNode: _focuses[m],
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(m),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  hintText: cmd ? 'Give QUORUM BOT a command…' : 'Ask QUORUM BOT…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _micButton(m),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(m),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 10)],
              ),
              child: c.thinking && c.thinkingMode == m
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _red.withOpacity(0.25 + 0.75 * math.max(0, math.sin((_a.value * 2 * math.pi) - i * 0.9))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 14,
          color: _copied ? _ok : Colors.white60,
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  final UltronMessage message;
  final UltronController controller;
  const _MessageView({required this.message, required this.controller});

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case UltronMessageKind.user:
        return LayoutBuilder(builder: (context, box) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.85),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35)),
                const SizedBox(height: 4),
                _CopyButton(text: message.text),
              ],
            ),
          ),
        ));
      case UltronMessageKind.text:
        return _bot(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(message.text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 4),
              _CopyButton(text: message.text),
            ],
          ),
        );
      case UltronMessageKind.error:
        return _bot(
          context,
          tint: _err,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: _err, size: 17),
              const SizedBox(width: 8),
              Expanded(child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35))),
            ],
          ),
        );
      case UltronMessageKind.plan:
        return _bot(context, wide: true, child: _PlanCard(message: message, controller: controller));
      case UltronMessageKind.execution:
        return _bot(context, wide: true, child: _ExecutionCard(execution: message.execution!));
    }
  }

  Widget _bot(BuildContext context, {required Widget child, Color? tint, bool wide = false}) {
    return LayoutBuilder(builder: (context, box) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: box.maxWidth * (wide ? 0.96 : 0.88)),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint == null ? const Color(0xFF1E293B) : tint.withOpacity(0.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tint == null ? const Color(0xFF334155) : tint.withOpacity(0.35)),
        ),
        child: child,
      ),
    ));
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _when(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${months[d.month - 1]} ${d.day}, $h:${_two(d.minute)} $ap';
}

String? _detail(UltronStep s) {
  final p = s.params;
  switch (s.action) {
    case 'CREATE_TEAM':
      final n = p['memberIds'] is List ? (p['memberIds'] as List).length : 0;
      return '${p['name'] ?? 'Team'} · $n member${n == 1 ? '' : 's'}';
    case 'SCHEDULE_MEETING':
      final start = p['startTime'] == null ? '' : _when(p['startTime'].toString());
      final dur = p['durationMinutes'] == null ? '' : ' · ${p['durationMinutes']} min';
      return '${p['title'] ?? 'Meeting'}${start.isEmpty ? '' : ' · $start'}$dur';
    case 'NOTIFY_MEMBERS':
      final n = p['userIds'] is List ? (p['userIds'] as List).length : 0;
      return '$n recipient${n == 1 ? '' : 's'}';
    default:
      return null;
  }
}

IconData _icon(String action) {
  switch (action) {
    case 'CREATE_TEAM':
      return Icons.groups_rounded;
    case 'SCHEDULE_MEETING':
      return Icons.event_rounded;
    case 'SHARE_DOCUMENT':
      return Icons.description_rounded;
    case 'NOTIFY_MEMBERS':
      return Icons.notifications_active_rounded;
    default:
      return Icons.bolt_rounded;
  }
}

class _PlanCard extends StatelessWidget {
  final UltronMessage message;
  final UltronController controller;
  const _PlanCard({required this.message, required this.controller});

  @override
  Widget build(BuildContext context) {
    final plan = message.plan!;
    final locked = message.settled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree_rounded, color: _red, size: 16),
            const SizedBox(width: 6),
            Text(
              locked ? 'PLAN · CLOSED' : 'PLAN · REVIEW',
              style: const TextStyle(color: _red, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
          ],
        ),
        if (plan.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(plan.summary, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
        ],
        const SizedBox(height: 10),
        for (final s in plan.steps)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _red.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
                  child: Icon(_icon(s.action), size: 15, color: _red),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.step}. ${s.label}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      if (s.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(s.description, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
                        ),
                      if (_detail(s) != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(_detail(s)!, style: const TextStyle(color: _muted, fontSize: 11.5)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (!locked) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: message.busy ? null : () => controller.dismissPlan(message.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: _border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: message.busy ? null : () => controller.confirm(message.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _redDeep,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF2E2680),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                  icon: message.busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(message.busy ? 'Executing…' : 'Confirm & Execute'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ExecutionCard extends StatelessWidget {
  final UltronExecution execution;
  const _ExecutionCard({required this.execution});

  void _snack(BuildContext context, String m) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final ok = execution.allOk;
    final color = ok ? _ok : (execution.okCount == 0 ? _err : const Color(0xFFF5A623));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: color, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                ok ? 'Done. ${execution.okCount} of ${execution.results.length} steps completed.' : '${execution.okCount} of ${execution.results.length} steps completed.',
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final r in execution.results)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (r.success ? _ok : _err).withOpacity(0.07),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: (r.success ? _ok : _err).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(r.success ? Icons.check_rounded : Icons.close_rounded, size: 16, color: r.success ? _ok : _err),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.description.isEmpty ? r.title : r.description,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3),
                      ),
                    ),
                  ],
                ),
                if (!r.success && r.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 24),
                    child: Text(r.error!, style: const TextStyle(color: _err, fontSize: 11.5)),
                  ),
                if (r.success && (r.meetingCode != null || r.meetingLink != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 24),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (r.meetingCode != null)
                          _pill(Icons.videocam_rounded, 'Join Video Call (${r.meetingCode})', () {
                            UltronController.instance.close();
                            MeetingLauncher.joinCode(r.meetingCode!, title: r.title, isHost: true);
                          })
                        else
                          _pill(Icons.videocam_rounded, 'Join', () {
                            UltronController.instance.close();
                            DeepLinkRouter.tryOpen(Uri.parse(r.meetingLink!));
                          }),
                        if (r.meetingLink != null)
                          _pill(Icons.copy_rounded, 'Copy link', () {
                            Clipboard.setData(ClipboardData(text: r.meetingLink!));
                            _snack(context, 'Meeting link copied');
                          }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pill(IconData i, String t, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _red.withOpacity(0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _red.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(t, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}


class _GripPainter extends CustomPainter {
  const _GripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _red.withOpacity(0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(9, 20), const Offset(20, 9), p);
    canvas.drawLine(const Offset(9, 14), const Offset(14, 9), p);
    canvas.drawLine(const Offset(9, 26), const Offset(26, 9), p);
  }

  @override
  bool shouldRepaint(covariant _GripPainter old) => false;
}