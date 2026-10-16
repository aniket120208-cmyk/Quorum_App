import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/sign_in_screen/sign_in_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({required this.email, super.key,});  
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =  List.generate(6, (_) => FocusNode());
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  int _resendSeconds = 30;
  Timer? _timer;

  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasLetter => RegExp(r'[A-Za-z]').hasMatch(_newPasswordController.text);
  bool get _hasDigit => RegExp(r'[0-9]').hasMatch(_newPasswordController.text);
  bool get _hasSpecialChar => RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(_newPasswordController.text);
  bool get _isPasswordValid => _hasMinLength && _hasLetter && _hasDigit && _hasSpecialChar;
  bool get _passwordsMatch => _newPasswordController.text.isNotEmpty && _newPasswordController.text == _confirmPasswordController.text;
  bool get _isFormValid {
    final bool allOtpFilled = _otpControllers.every((c) => c.text.trim().isNotEmpty);
    return allOtpFilled && _isPasswordValid && _passwordsMatch;
  }

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    for (final controller in _otpControllers) {
      controller.addListener(() => setState(() {}));
    }
    _newPasswordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _handleOtpPaste(String pastedText) {
    final digits = pastedText.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    for (int i = 0; i < 6; i++) {
      if (i < digits.length) {
        _otpControllers[i].text = digits[i];
      }
    }
    final focusIndex = (digits.length >= 6) ? 5 : digits.length;
    _otpFocusNodes[focusIndex].requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showPasswordHints = _newPasswordController.text.isNotEmpty;
    final bool showConfirmError = _confirmPasswordController.text.isNotEmpty && !_passwordsMatch;
    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 36),
                  const Text(
                    'Reset your password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Color(0xFF9E9EA7),
                        fontSize: 15,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: "We've sent a 6-digit code to\n"),
                        TextSpan(
                          text: widget.email,
                          style: const TextStyle(
                            color: Color(0xFF5D5FEF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13151B).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF262A34),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verification code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            6,
                            (index) => _buildOtpField(index),
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'New password',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildPasswordField(
                          controller: _newPasswordController,
                          hintText: 'Create a strong password',
                          obscureText: _obscureNewPassword,
                          hasError: showPasswordHints && !_isPasswordValid,
                          onToggleVisibility: () {
                            setState(() {
                              _obscureNewPassword = !_obscureNewPassword;
                            });
                          },
                        ),
                        if (showPasswordHints) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _buildRequirementChip('8+ chars', _hasMinLength),
                              _buildRequirementChip('1 letter', _hasLetter),
                              _buildRequirementChip('1 number', _hasDigit),
                              _buildRequirementChip('1 special', _hasSpecialChar),
                            ],
                          ),
                        ],
                        const SizedBox(height: 22),
                        const Text(
                          'Confirm password',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildPasswordField(
                          controller: _confirmPasswordController,
                          hintText: 'Confirm password',
                          obscureText: _obscureConfirmPassword,
                          hasError: showConfirmError,
                          onToggleVisibility: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                        if (showConfirmError) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Passwords do not match',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Didn't receive the code?",
                              style: TextStyle(
                                color: Color(0xFF9E9EA7),
                                fontSize: 13,
                              ),
                            ),
                            GestureDetector(
                              onTap: _resendSeconds == 0
                                  ? _startResendTimer
                                  : null,
                              child: Text(
                                _resendSeconds > 0
                                    ? 'Resend (${_resendSeconds}s)'
                                    : 'Resend',
                                style: TextStyle(
                                  color: _resendSeconds > 0
                                      ? const Color(0xFF9E9EA7)
                                      : const Color(0xFF5D5FEF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        AnimatedOpacity(
                          opacity: _isFormValid ? 1.0 : 0.35,
                          duration: const Duration(milliseconds: 200),
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isFormValid
                                  ? () {
                                      final otp = _otpControllers.map((c) => c.text).join();
                                      final newPassword = _newPasswordController.text;
                                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => SignInScreen()));
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4C3AE3),
                                disabledBackgroundColor: const Color(0xFF4C3AE3).withOpacity(0.9),
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Reset password',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementChip(String label, bool isValid) {
    final color = isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: color,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildOtpField(int index) {
    return SizedBox(
      width: 44,
      height: 48,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        inputFormatters: [
          LengthLimitingTextInputFormatter(6),
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF22252D),
          hintText: 'x',
          hintStyle: const TextStyle(
            color: Color(0xFF5A5E6B),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF323642), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF323642), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF5D5FEF), width: 1.5),
          ),
        ),
        onChanged: (value) {
          if (value.length > 1) {
            _handleOtpPaste(value);
            return;
          }
          if (value.isNotEmpty && index < 5) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    bool hasError = false,
  }) {
    final borderColor = hasError ? const Color(0xFFEF4444) : const Color(0xFF323642);
    final focusedBorderColor = hasError ? const Color(0xFFEF4444) : const Color(0xFF5D5FEF);

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF22252D),
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: hasError ? const Color(0xFFEF4444) : const Color(0xFF7A8090),
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: const Color(0xFF7A8090),
            size: 20,
          ),
          onPressed: onToggleVisibility,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusedBorderColor, width: 1.5),
        ),
      ),
    );
  }
}