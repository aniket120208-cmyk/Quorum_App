import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/screens/sign_in_screen/sign_in_screen.dart';
import 'package:quorum_app/screens/verify_email_screen/verify_email_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  final RegExp _nameRegex = RegExp(r"^[a-zA-Z\s]{2,50}$");
  final RegExp _emailRegex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");

  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasLetter => RegExp(r'[A-Za-z]').hasMatch(_passwordController.text);
  bool get _hasDigit => RegExp(r'[0-9]').hasMatch(_passwordController.text);
  bool get _hasSpecialChar => RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(_passwordController.text);
  bool get _isPasswordValid => _hasMinLength && _hasLetter && _hasDigit && _hasSpecialChar;
  bool get _passwordsMatch => _passwordController.text.isNotEmpty && _passwordController.text == _confirmPasswordController.text;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false) || !_isPasswordValid || !_passwordsMatch) {
      setState(() {
        _autoValidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      await AuthService.instance.register(
        name: _nameController.text.trim(),
        email: email,
        password: password,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(email: email, password: password),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final message = e.isRateLimited
          ? 'Too many sign-up attempts. Please wait a few minutes and try again.'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showPasswordHints = _passwordController.text.isNotEmpty;
    final bool showConfirmError = _confirmPasswordController.text.isNotEmpty && !_passwordsMatch;

    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: _autoValidateMode,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 36),
                              const Text(
                                'Create your account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Start your journey with Quorum',
                                style: TextStyle(
                                  color: Color(0xFF8E95A9),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F1118).withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFF2C3246),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('Full name'),
                                    const SizedBox(height: 8),
                                    _buildTextField(
                                      controller: _nameController,
                                      hintText: 'Enter your name',
                                      prefixIcon: Icons.person_outline_rounded,
                                      keyboardType: TextInputType.name,
                                      validator: (value) {
                                        final text = value?.trim() ?? '';
                                        if (text.isEmpty) {
                                          return 'Name is required';
                                        }
                                        if (!_nameRegex.hasMatch(text)) {
                                          return 'Enter a valid name (letters only)';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                    _buildLabel('Work email'),
                                    const SizedBox(height: 8),
                                    _buildTextField(
                                      controller: _emailController,
                                      hintText: 'example@company.com',
                                      prefixIcon: Icons.mail_outline_rounded,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (value) {
                                        final text = value?.trim() ?? '';
                                        if (text.isEmpty) {
                                          return 'Email is required';
                                        }
                                        if (!_emailRegex.hasMatch(text)) {
                                          return 'Enter a valid email address';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                    _buildLabel('Password'),
                                    const SizedBox(height: 8),
                                    _buildTextField(
                                      controller: _passwordController,
                                      hintText: 'Create a strong password',
                                      prefixIcon: Icons.lock_outline_rounded,
                                      obscureText: _obscurePassword,
                                      hasError: showPasswordHints && !_isPasswordValid,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                          color: const Color(0xFF7E8497),
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword = !_obscurePassword;
                                          });
                                        },
                                      ),
                                      validator: (value) {
                                        final text = value ?? '';
                                        if (text.isEmpty) {
                                          return 'Password is required';
                                        }
                                        if (!_isPasswordValid) {
                                          return 'Please meet all password requirements';
                                        }
                                        return null;
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
                                    const SizedBox(height: 20),
                                    _buildLabel('Confirm Password'),
                                    const SizedBox(height: 8),
                                    _buildTextField(
                                      controller: _confirmPasswordController,
                                      hintText: 'Confirm password',
                                      prefixIcon: Icons.lock_outline_rounded,
                                      obscureText: _obscureConfirmPassword,
                                      hasError: showConfirmError,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                          color: const Color(0xFF7E8497),
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureConfirmPassword = !_obscureConfirmPassword;
                                          });
                                        },
                                      ),
                                      validator: (value) {
                                        final text = value ?? '';
                                        if (text.isEmpty) {
                                          return 'Please confirm your password';
                                        }
                                        if (text != _passwordController.text) {
                                          return 'Passwords do not match';
                                        }
                                        return null;
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
                                    const SizedBox(height: 28),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _submitForm,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF3B4AF5),
                                          disabledBackgroundColor: const Color(0xFF3B4AF5).withValues(alpha: 0.5),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                height: 22,
                                                width: 22,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : const Text(
                                                'Create account',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20.0),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Already have an account? ',
                                        style: TextStyle(
                                          color: Color(0xFF8E95A9),
                                          fontSize: 14,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => const SignInScreen(),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            color: Color(0xFF5663F6),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    bool hasError = false,
  }) {
    final borderColor = hasError ? const Color(0xFFEF4444) : Colors.transparent;
    final focusedBorderColor = hasError ? const Color(0xFFEF4444) : const Color(0xFF4C4FE8);

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),
      cursorColor: const Color(0xFF4C4FE8),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1E212A),
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF575D71),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          prefixIcon,
          color: hasError ? const Color(0xFFEF4444) : const Color(0xFF7E8497),
          size: 20,
        ),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: hasError ? BorderSide(color: borderColor, width: 1.2) : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: hasError ? const BorderSide(color: Color(0xFFEF4444), width: 1.2) : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: focusedBorderColor,
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFFE53935),
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFFE53935),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}