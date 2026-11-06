import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';

class TurnstileConfig {
  static const String siteKey = String.fromEnvironment('TURNSTILE_SITE_KEY', defaultValue: '0x4AAAAAAF00lBPj1ukeGQUn',);
  static const String baseUrl = String.fromEnvironment('TURNSTILE_BASE_URL', defaultValue: 'https://newquorum.me/');
  static bool get isConfigured => siteKey.isNotEmpty;
}

class TurnstileCaptcha extends StatelessWidget {
  final TurnstileController controller;
  final ValueChanged<String?> onTokenChanged;
  final ValueChanged<String>? onError;

  const TurnstileCaptcha({
    super.key,
    required this.controller,
    required this.onTokenChanged,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    if (!TurnstileConfig.isConfigured) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Security check is not configured.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFEF4444), fontSize: 12),
        ),
      );
    }
    return Center(
      child: CloudflareTurnstile(
        siteKey: TurnstileConfig.siteKey,
        baseUrl: TurnstileConfig.baseUrl,
        controller: controller,
        options: TurnstileOptions(
          theme: TurnstileTheme.dark,
          size: TurnstileSize.normal,
        ),
        onTokenReceived: (token) => onTokenChanged(token),
        onTokenExpired: () => onTokenChanged(null),
        onError: (error) {
          onTokenChanged(null);
          onError?.call('Security check failed to load. Please try again.');
        },
      ),
    );
  }
}