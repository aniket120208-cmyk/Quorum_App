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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    Widget next = const OnboardingScreen();

    if (await AuthService.instance.hasStoredSession()) {
      try {
        await AuthService.instance.getUserProfile();
        next = const MainNavigationScreen();
      } on ApiException catch (e) {
        next = e.statusCode == null ? const MainNavigationScreen() : SignInScreen();
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}