import 'dart:math';
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/screens/home_screen/home_screen.dart';
import 'package:quorum_app/screens/on_boarding_screen/on_boarding_screen.dart';
import 'package:quorum_app/screens/sign_in_screen/sign_in_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF090A10);
  static const String _word = 'QUORUM';

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  late final AnimationController _outro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  late final Animation<double> _streak = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.2, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _arcs = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.12, 0.45, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _dots = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.25, 0.55, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _spin = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.12, 0.65, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.12, 0.5, curve: Curves.easeOutBack),
  ));

  late final Animation<double> _bars = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.3, 0.9, curve: Curves.linear),
  );

  late final Animation<double> _letters = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.42, 0.82, curve: Curves.linear),
  );

  late final Animation<double> _shine = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.72, 1.0, curve: Curves.easeInOut),
  );

  late final Animation<double> _zoom = CurvedAnimation(
    parent: _outro,
    curve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _intro.dispose();
    _outro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<Widget> _resolveNext() async {
    if (await AuthService.instance.hasStoredSession()) {
      try {
        await AuthService.instance.getUserProfile();
        return const MainNavigationScreen();
      } on ApiException catch (e) {
        return e.statusCode == null ? const MainNavigationScreen() : SignInScreen();
      }
    }
    return const OnboardingScreen();
  }

  Future<void> _run() async {
    final nextFuture = _resolveNext().catchError((Object _) => SignInScreen());

    try {
      await _intro.forward().orCancel;
      final next = await nextFuture;
      if (!mounted) return;
      await _outro.forward().orCancel;
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => next,
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    } on TickerCanceled {
      return;
    }
  }

  Widget _wordmark() {
    final lt = _letters.value;
    final s = -0.25 + 1.5 * _shine.value;

    final letters = <Widget>[];
    for (var i = 0; i < _word.length; i++) {
      final p = ((lt - i * 0.1) / 0.5).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(p);
      letters.add(
        Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - eased)),
            child: Transform.scale(
              scale: 0.7 + 0.3 * eased,
              child: Text(
                _word[i],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        colors: const [Color(0xFFA5B4FC), Colors.white, Color(0xFFA5B4FC)],
        stops: [
          (s - 0.25).clamp(0.0, 1.0),
          s.clamp(0.0, 1.0),
          (s + 0.25).clamp(0.0, 1.0),
        ],
      ).createShader(rect),
      child: Row(mainAxisSize: MainAxisSize.min, children: letters),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: _bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _outro, _pulse]),
        builder: (context, _) {
          final outro = _outro.value;
          final t = _intro.value;
          final groupScale = 1 + 13 * _zoom.value;
          final groupOpacity = 1 - ((outro - 0.35) / 0.65).clamp(0.0, 1.0);
          final flash = max(0.0, 1 - ((t - 0.45).abs() / 0.07));
          final glow = (0.18 + 0.14 * _pulse.value + 0.5 * flash) * (1 - outro);

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _LightBarsPainter(
                  progress: _bars.value,
                  visibility: 1 - outro,
                ),
              ),
              Center(
                child: Opacity(
                  opacity: _arcs.value,
                  child: Container(
                    width: 520,
                    height: 520,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF6366F1).withValues(alpha: glow.clamp(0.0, 1.0)),
                          const Color(0xFF6366F1).withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: (1 - _arcs.value).clamp(0.0, 1.0),
                  child: Container(
                    width: width * 0.9 * _streak.value,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0x00FFFFFF),
                          Colors.white,
                          Color(0x00FFFFFF),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF818CF8).withValues(alpha: 0.8),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: groupScale,
                  child: Opacity(
                    opacity: groupOpacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: _scale.value,
                          child: Opacity(
                            opacity: _arcs.value.clamp(0.0, 1.0),
                            child: Transform.rotate(
                              angle: -(1 - _spin.value) * 2 * pi,
                              child: Image.asset('lib/assets/quorum_logo.png', width: 150, height: 150,fit: BoxFit.contain,),
                              ),
                            ),
                          ),
                        const SizedBox(height: 22),
                        _wordmark(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LightBarsPainter extends CustomPainter {
  const _LightBarsPainter({required this.progress, required this.visibility});

  final double progress;
  final double visibility;
  static const int _count = 40;
  static const List<Color> _palette = [
    Color(0xFF3B82F6),
    Color(0xFF6366F1),
    Color(0xFFA855F7),
  ];

  Color _color(double x) {
    if (x < 0.5) return Color.lerp(_palette[0], _palette[1], x / 0.5)!;
    return Color.lerp(_palette[1], _palette[2], (x - 0.5) / 0.5)!;
  }

  double _rand(int i) {
    final v = sin(i * 12.9898) * 43758.5453;
    return v - v.floor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || visibility <= 0) return;

    final cy = size.height / 2;
    final slot = size.width / _count;

    for (var i = 0; i < _count; i++) {
      final x01 = i / (_count - 1);
      final d = (x01 - 0.5).abs() * 2;
      final local = ((progress - d * 0.35) / 0.65).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final maxHeight = size.height * (0.18 + 0.5 * (1 - d) * (0.6 + 0.4 * _rand(i)));
      final h = maxHeight * Curves.easeOutCubic.transform(local);
      final alpha = sin(local * pi) * 0.6 * visibility;
      if (alpha <= 0 || h <= 0) continue;

      final rect = Rect.fromCenter(
        center: Offset(slot * i + slot / 2, cy),
        width: slot * 0.5,
        height: h,
      );
      final c = _color(x01);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.withValues(alpha: 0),
            c.withValues(alpha: alpha),
            c.withValues(alpha: 0),
          ],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightBarsPainter old) =>
      old.progress != progress || old.visibility != visibility;
}