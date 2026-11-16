import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/deep_link_service.dart';
import 'package:quorum_app/api/push_service.dart';
import 'package:quorum_app/app_navigator.dart';
import 'package:quorum_app/screens/splash_screen/splash_screen.dart';
import 'package:quorum_app/widgets/quorumbot_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.instance.init();
  DeepLinkService.instance.start();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090A10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class NoGlowScrollBehavior extends MaterialScrollBehavior {
  const NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const NoGlowScrollBehavior(),
      title: 'Quorum',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A10),
        fontFamily: 'sans-serif',
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
      ),
      builder: (context, child) => UltronHost(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}