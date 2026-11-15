import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/models/office_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'office_widgets.dart';

const double _grid = 10;
const double _wallUnits = 1.5;
const double _deskHeight = 0.28;

const Rect _warRect = Rect.fromLTRB(0.3, 0.3, 4.7, 4.7);
const Rect _coffeeRect = Rect.fromLTRB(5.3, 0.3, 9.7, 4.7);
const Rect _focusRect = Rect.fromLTRB(0.3, 5.3, 4.7, 9.7);
const Rect _openRect = Rect.fromLTRB(5.3, 5.3, 9.7, 9.7);

const List<Offset> _warSlots = [
  Offset(1.0, 2.4),
  Offset(2.0, 1.2),
  Offset(3.4, 1.2),
  Offset(4.1, 2.4),
  Offset(3.5, 3.7),
  Offset(2.2, 3.8),
  Offset(1.0, 3.5),
];

const List<Offset> _coffeeSlots = [
  Offset(6.3, 1.7),
  Offset(8.5, 1.7),
  Offset(6.3, 3.5),
  Offset(8.5, 3.6),
  Offset(7.5, 4.2),
  Offset(7.5, 1.1),
];

const List<Offset> _podCenters = [
  Offset(1.5, 6.6),
  Offset(3.5, 6.6),
  Offset(1.5, 8.6),
  Offset(3.5, 8.6),
];

List<Rect> _deskRects(int n) {
  const cols = 4;
  final rows = math.max((n / cols).ceil(), 1);
  const x0 = 5.4;
  const x1 = 9.7;
  const y0 = 5.7;
  const y1 = 9.7;
  final cw = (x1 - x0) / cols;
  final rh = (y1 - y0) / rows;
  return [
    for (var i = 0; i < n; i++)
      Rect.fromLTWH(x0 + (i % cols) * cw + cw * 0.1, y0 + (i ~/ cols) * rh + rh * 0.1, cw * 0.8, rh * 0.5),
  ];
}

class _Iso {
  const _Iso({required this.ox, required this.oy, required this.tw, required this.th, required this.unit});
  final double ox;
  final double oy;
  final double tw;
  final double th;
  final double unit;

  Offset p(double x, double y, [double z = 0]) =>
      Offset(ox + (x - y) * tw / 2, oy + (x + y) * th / 2 - z * unit);
}

Color _shade(Color c, double f) => Color.lerp(c, Colors.black, 1 - f)!;

class _FloorPainter extends CustomPainter {
  _FloorPainter({
    required this.iso,
    required this.myZone,
    required this.warLive,
    required this.deskRects,
    required this.deskColors,
    required this.mineDesk,
    required this.focusCount,
    required this.pulse,
  }) : super(repaint: pulse);

  final _Iso iso;
  final OfficeZone? myZone;
  final bool warLive;
  final List<Rect> deskRects;
  final List<Color?> deskColors;
  final int mineDesk;
  final int focusCount;
  final Animation<double> pulse;

  Path _path(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path..close();
  }

  void _fill(Canvas c, List<Offset> pts, Color color) {
    c.drawPath(_path(pts), Paint()..color = color);
  }

  void _slab(Canvas c) {
    const t = 0.5;
    _fill(c, [iso.p(0, _grid), iso.p(_grid, _grid), iso.p(_grid, _grid, -t), iso.p(0, _grid, -t)], const Color(0xFF1B2440));
    _fill(c, [iso.p(_grid, 0), iso.p(_grid, _grid), iso.p(_grid, _grid, -t), iso.p(_grid, 0, -t)], const Color(0xFF111729));
  }

  void _floor(Canvas c) {
    final pts = [iso.p(0, 0), iso.p(_grid, 0), iso.p(_grid, _grid), iso.p(0, _grid)];
    final path = _path(pts);
    c.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF414E75), Color(0xFF2C3659)],
        ).createShader(path.getBounds()),
    );
    final line = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < _grid.toInt(); i++) {
      c.drawLine(iso.p(i.toDouble(), 0), iso.p(i.toDouble(), _grid), line);
      c.drawLine(iso.p(0, i.toDouble()), iso.p(_grid, i.toDouble()), line);
    }
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x33FFFFFF),
    );
  }

  void _pad(Canvas c, Rect r, Color color, {bool mine = false, bool live = false}) {
    final pts = [iso.p(r.left, r.top), iso.p(r.right, r.top), iso.p(r.right, r.bottom), iso.p(r.left, r.bottom)];
    c.drawPath(_path(pts), Paint()..color = color);
    if (live) {
      c.drawPath(
        _path(pts),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = officeGreen.withValues(alpha: 0.35 + 0.55 * pulse.value)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    } else if (mine) {
      c.drawPath(
        _path(pts),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFA78BFA).withValues(alpha: 0.9),
      );
    } else {
      c.drawPath(
        _path(pts),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x22FFFFFF),
      );
    }
  }

  void _pads(Canvas c) {
    _pad(c, _warRect, warLive ? const Color(0x4022C55E) : const Color(0x404F7BD9),
        mine: myZone == OfficeZone.warRoom, live: warLive);
    _pad(c, _coffeeRect, const Color(0x38FBBF24), mine: myZone == OfficeZone.coffeeLounge);
    _pad(c, _focusRect, const Color(0x388B5CF6), mine: myZone == OfficeZone.focusPod);
    _pad(c, _openRect, const Color(0x3214B8A6), mine: myZone == OfficeZone.openWorkspace);
    _ellipse(c, 7.5, 2.5, 1.35, 0.01, const Color(0x1FFFFFFF));
  }

  Path _ring(double cx, double cy, double r, double z) {
    final path = Path();
    for (var i = 0; i <= 36; i++) {
      final a = i / 36 * 2 * math.pi;
      final o = iso.p(cx + r * math.cos(a), cy + r * math.sin(a), z);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    return path..close();
  }

  void _ellipse(Canvas c, double cx, double cy, double r, double z, Color color) {
    c.drawPath(_ring(cx, cy, r, z), Paint()..color = color);
  }

  void _wall(Canvas c, double x1, double y1, double x2, double y2, double h, Color a, Color b, {bool edge = true}) {
    final pts = [iso.p(x1, y1), iso.p(x2, y2), iso.p(x2, y2, h), iso.p(x1, y1, h)];
    final path = _path(pts);
    c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [b, a],
        ).createShader(path.getBounds()),
    );
    if (edge) {
      c.drawLine(
        iso.p(x1, y1, h),
        iso.p(x2, y2, h),
        Paint()
          ..color = const Color(0x66FFFFFF)
          ..strokeWidth = 1.4,
      );
    }
  }

  void _windows(Canvas c, bool alongX) {
    for (var k = 0; k < 4; k++) {
      final s = 0.9 + k * 2.4;
      final e = s + 1.4;
      final pts = alongX
          ? [iso.p(s, 0, 0.8), iso.p(e, 0, 0.8), iso.p(e, 0, 1.35), iso.p(s, 0, 1.35)]
          : [iso.p(0, s, 0.8), iso.p(0, e, 0.8), iso.p(0, e, 1.35), iso.p(0, s, 1.35)];
      _fill(c, pts, const Color(0x3360A5FA));
    }
  }

  void _walls(Canvas c) {
    _wall(c, 0, _grid, 0, 0, _wallUnits, const Color(0x80232C4D), const Color(0x4D6B7FB5));
    _wall(c, 0, 0, _grid, 0, _wallUnits, const Color(0x80232C4D), const Color(0x4D6B7FB5));
    _windows(c, true);
    _windows(c, false);
  }

  void _box(Canvas c, double x, double y, double w, double d, double h, Color top, {double z0 = 0, double alpha = 1}) {
    Color a(Color col) => alpha == 1 ? col : col.withValues(alpha: col.a * alpha);
    final z1 = z0 + h;
    _fill(c, [iso.p(x, y + d, z0), iso.p(x + w, y + d, z0), iso.p(x + w, y + d, z1), iso.p(x, y + d, z1)], a(_shade(top, 0.72)));
    _fill(c, [iso.p(x + w, y, z0), iso.p(x + w, y + d, z0), iso.p(x + w, y + d, z1), iso.p(x + w, y, z1)], a(_shade(top, 0.52)));
    _fill(c, [iso.p(x, y, z1), iso.p(x + w, y, z1), iso.p(x + w, y + d, z1), iso.p(x, y + d, z1)], a(top));
  }

  void _cyl(Canvas c, double cx, double cy, double r, double h, Color top, {double z0 = 0}) {
    final side = Paint()..color = _shade(top, 0.6);
    for (var i = 0; i <= 6; i++) {
      c.drawPath(_ring(cx, cy, r, z0 + h * i / 6), side);
    }
    c.drawPath(_ring(cx, cy, r, z0 + h), Paint()..color = top);
  }

  void _plant(Canvas c, double x, double y) {
    _cyl(c, x, y, 0.22, 0.3, const Color(0xFF8A6A45));
    final top = iso.p(x, y, 0.78);
    c.drawCircle(top, iso.tw * 0.2, Paint()..color = const Color(0xFF1F9D68));
    c.drawCircle(top.translate(-iso.tw * 0.07, -iso.tw * 0.07), iso.tw * 0.12, Paint()..color = const Color(0xFF34D399));
  }

  void _wallScreen(Canvas c) {
    _box(c, 1.4, 0.05, 2.0, 0.08, 0.7, const Color(0xFF0F172A), z0: 0.55);
    _fill(
      c,
      [iso.p(1.5, 0.13, 0.62), iso.p(3.3, 0.13, 0.62), iso.p(3.3, 0.13, 1.18), iso.p(1.5, 0.13, 1.18)],
      warLive ? officeGreen.withValues(alpha: 0.35 + 0.3 * pulse.value) : const Color(0x5560A5FA),
    );
  }

  void _pod(Canvas c, int i) {
    final cx = _podCenters[i].dx;
    final cy = _podCenters[i].dy;
    final active = i < focusCount;
    _box(c, cx - 0.75, cy - 0.75, 1.5, 1.5, 0.06, active ? const Color(0xFF8B5CF6) : const Color(0xFF3B4268));
    _wall(c, cx - 0.75, cy + 0.75, cx - 0.75, cy - 0.75, 1.0, const Color(0x558B5CF6), const Color(0x22C4B5FD));
    _wall(c, cx - 0.75, cy - 0.75, cx + 0.75, cy - 0.75, 1.0, const Color(0x558B5CF6), const Color(0x22C4B5FD));
    _box(c, cx - 0.5, cy - 0.6, 1.0, 0.35, 0.34, const Color(0xFF6B7280), z0: 0.06);
  }

  void _desk(Canvas c, int i) {
    final r = deskRects[i];
    final color = deskColors[i];
    if (i == mineDesk) {
      _ellipse(c, r.center.dx, r.center.dy + 0.2, 0.95, 0.02, const Color(0x55A78BFA));
    }
    _box(c, r.left + r.width * 0.3, r.bottom + 0.05, r.width * 0.4, 0.32, 0.3, const Color(0xFF334155));
    _box(c, r.left, r.top, r.width, r.height, _deskHeight, const Color(0xFFC8B08A));
    final my = r.top + r.height * 0.2;
    _box(c, r.left + r.width * 0.25, my, r.width * 0.5, 0.07, 0.4, const Color(0xFF0F172A), z0: _deskHeight);
    _fill(
      c,
      [
        iso.p(r.left + r.width * 0.28, my + 0.07, _deskHeight + 0.05),
        iso.p(r.left + r.width * 0.72, my + 0.07, _deskHeight + 0.05),
        iso.p(r.left + r.width * 0.72, my + 0.07, _deskHeight + 0.36),
        iso.p(r.left + r.width * 0.28, my + 0.07, _deskHeight + 0.36),
      ],
      color == null ? const Color(0xFF1E293B) : color.withValues(alpha: 0.85),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _slab(canvas);
    _floor(canvas);
    _pads(canvas);
    _walls(canvas);

    final items = <(double, VoidCallback)>[];
    items.add((0.5, () => _wallScreen(canvas)));
    items.add((4.8, () => _box(canvas, 1.4, 1.8, 2.0, 1.2, 0.35, const Color(0xFF9DB0D6))));
    items.add((7.35, () => _wall(canvas, 5.0, 0.0, 5.0, 4.7, 0.55, const Color(0x2EFFFFFF), const Color(0x14FFFFFF))));
    items.add((7.35, () => _wall(canvas, 0.0, 5.0, 4.7, 5.0, 0.55, const Color(0x2EFFFFFF), const Color(0x14FFFFFF))));
    items.add((6.9, () {
      _box(canvas, 5.5, 0.35, 1.6, 0.6, 0.55, const Color(0xFFB08968));
      _box(canvas, 5.8, 0.45, 0.35, 0.35, 0.35, const Color(0xFF1F2937), z0: 0.55);
    }));
    items.add((10.0, () => _cyl(canvas, 7.5, 2.5, 0.55, 0.4, const Color(0xFFE8CFA6))));
    items.add((11.0, () {
      _box(canvas, 9.1, 1.2, 0.55, 2.6, 0.35, const Color(0xFFC2704B));
      _box(canvas, 9.45, 1.2, 0.2, 2.6, 0.75, const Color(0xFFA85A3A));
    }));
    items.add((9.0, () => _plant(canvas, 5.6, 4.3)));
    items.add((9.4, () => _plant(canvas, 4.3, 4.3)));
    items.add((19.0, () => _plant(canvas, 9.4, 9.4)));
    for (var i = 0; i < _podCenters.length; i++) {
      items.add((_podCenters[i].dx + _podCenters[i].dy, () => _pod(canvas, i)));
    }
    for (var i = 0; i < deskRects.length; i++) {
      final r = deskRects[i];
      items.add((r.center.dx + r.center.dy, () => _desk(canvas, i)));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final item in items) {
      item.$2();
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPainter old) => true;
}

class OfficeIsoFloor extends StatefulWidget {
  const OfficeIsoFloor({super.key, required this.state, required this.onMemberTap, required this.onDeskTap});
  final OfficeState state;
  final ValueChanged<OfficeMember> onMemberTap;
  final ValueChanged<OfficeDesk> onDeskTap;

  @override
  State<OfficeIsoFloor> createState() => _OfficeIsoFloorState();
}

class _OfficeIsoFloorState extends State<OfficeIsoFloor> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _label(String text, Offset at) {
    return Positioned(
      left: at.dx - 55,
      top: at.dy - 7,
      width: 110,
      child: IgnorePointer(
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xDDFFFFFF),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            shadows: [Shadow(color: Color(0x99000000), blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  Widget _camera(Offset at) {
    return Positioned(
      left: at.dx - 12,
      top: at.dy - 12,
      child: IgnorePointer(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: officeGreen,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: officeGreen.withValues(alpha: 0.6), blurRadius: 10)],
          ),
          child: const Icon(Icons.videocam_rounded, size: 15, color: Colors.white),
        ),
      ),
    );
  }

  Widget _more(int n, Offset at) {
    return Positioned(
      left: at.dx - 14,
      top: at.dy - 10,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xCC0F172A), borderRadius: BorderRadius.circular(10)),
          child: Text('+$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final mine = state.members[CurrentUser.id];
    final warM = state.inZone(OfficeZone.warRoom);
    final coffeeM = state.inZone(OfficeZone.coffeeLounge);
    final focusM = state.inZone(OfficeZone.focusPod);
    final warLive = state.activeMeetingCode != null;
    final deskRects = _deskRects(state.desks.length);
    final deskColors = <Color?>[];
    var mineDesk = -1;
    for (var i = 0; i < state.desks.length; i++) {
      final id = state.desks[i].occupiedByUserId;
      final m = id == null ? null : state.members[id];
      deskColors.add(m == null ? null : officePresenceColor(m.presence));
      if (id != null && id == CurrentUser.id) mineDesk = i;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF222E50), Color(0xFF151C33)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('Virtual Office', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                Text('Quorum Office', style: TextStyle(color: orgMuted, fontSize: 12)),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final tw = w / (_grid + 0.4);
              final th = tw * 0.56;
              final unit = th * 1.7;
              final top = _wallUnits * unit + 18;
              final h = top + _grid * th + 0.5 * unit + 16;
              final iso = _Iso(ox: w / 2, oy: top, tw: tw, th: th, unit: unit);
              final s = (tw * 0.68).clamp(20.0, 30.0);

              final spots = <String, Offset>{};
              final labelFor = <String, String>{};
              final extras = <Widget>[];

              void assign(List<OfficeMember> list, List<Offset> slots, double z) {
                for (var i = 0; i < list.length && i < slots.length; i++) {
                  spots[list[i].userId] = iso.p(slots[i].dx, slots[i].dy, z);
                  labelFor[list[i].userId] = list[i].userId == CurrentUser.id ? 'You' : list[i].name.split(' ').first;
                }
                if (list.length > slots.length && slots.isNotEmpty) {
                  extras.add(_more(list.length - slots.length, iso.p(slots.last.dx + 0.6, slots.last.dy, z)));
                }
              }

              assign(warM, _warSlots, 0);
              assign(coffeeM, _coffeeSlots, 0);
              assign(
                focusM,
                [for (final p in _podCenters) Offset(p.dx, p.dy + 0.2)],
                0.06,
              );

              final seated = <String>{};
              final desks = <Widget>[];
              for (var i = 0; i < state.desks.length; i++) {
                final desk = state.desks[i];
                final r = deskRects[i];
                final at = iso.p(r.center.dx, r.center.dy, 0.3);
                desks.add(
                  Positioned(
                    left: at.dx - s * 0.75,
                    top: at.dy - s * 0.55,
                    width: s * 1.5,
                    height: s * 1.1,
                    child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => widget.onDeskTap(desk)),
                  ),
                );
                final id = desk.occupiedByUserId;
                final m = id == null ? null : state.members[id];
                if (m != null && m.zone == OfficeZone.openWorkspace) {
                  spots[m.userId] = iso.p(r.center.dx, r.bottom + 0.2, 0.15);
                  if (m.userId == CurrentUser.id) labelFor[m.userId] = 'You';
                  seated.add(m.userId);
                }
              }
              final standing = state.inZone(OfficeZone.openWorkspace).where((m) => !seated.contains(m.userId)).toList();
              for (var i = 0; i < standing.length && i < 5; i++) {
                spots[standing[i].userId] = iso.p(5.8 + i * 0.9, 5.1);
                labelFor[standing[i].userId] = standing[i].userId == CurrentUser.id ? 'You' : standing[i].name.split(' ').first;
              }

              final entries = spots.entries.where((e) => state.members.containsKey(e.key)).toList()
                ..sort((a, b) => a.value.dy.compareTo(b.value.dy));

              final warTitle = warLive ? 'Meeting Room · LIVE' : (warM.isEmpty ? 'Meeting Room' : 'Meeting Room · ${warM.length}');
              final avatars = [
                for (final e in entries)
                  AnimatedPositioned(
                    key: ValueKey(e.key),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutCubic,
                    left: e.value.dx - 30,
                    top: e.value.dy - s - 6,
                    width: 60,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => widget.onMemberTap(state.members[e.key]!),
                      child: _IsoAvatar(member: state.members[e.key]!, size: s, label: labelFor[e.key]),
                    ),
                  ),
              ];

              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FloorPainter(
                          iso: iso,
                          myZone: mine?.zone,
                          warLive: warLive,
                          deskRects: deskRects,
                          deskColors: deskColors,
                          mineDesk: mineDesk,
                          focusCount: focusM.length,
                          pulse: _pulse,
                        ),
                      ),
                    ),
                    _label(warTitle, iso.p(2.5, 0, 0.3)),
                    _label(
                      coffeeM.isEmpty ? 'Coffee Lounge' : 'Coffee Lounge · ${coffeeM.length}',
                      iso.p(7.5, 0, 0.3),
                    ),
                    _label(
                      focusM.isEmpty ? 'Focus Pod' : 'Focus Pod · ${focusM.length}',
                      iso.p(0, 7.5, 0.3),
                    ),
                    _label('Open Workspace', iso.p(7.5, 5.1)),
                    if (warLive) ...[
                      _camera(iso.p(1.9, 2.1, 1.3)),
                      _camera(iso.p(3.0, 2.1, 1.3)),
                    ],
                    ...desks,
                    ...avatars,
                    ...extras,
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IsoAvatar extends StatelessWidget {
  const _IsoAvatar({required this.member, required this.size, this.label});
  final OfficeMember member;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ring = officePresenceColor(member.presence);
    return Opacity(
      opacity: member.presence == OfficePresence.away ? 0.6 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F172A),
                    border: Border.all(color: ring, width: 1.6),
                    boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.55), blurRadius: 8)],
                  ),
                  child: OrgAvatar(name: member.name, logo: member.avatarUrl, size: size - 7, circular: true),
                ),
                if (member.isInMeeting)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: officeGreen, borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.videocam_rounded, size: 9, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          if (label != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xB30F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ring.withValues(alpha: 0.8), width: 0.8),
              ),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}