import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/vp_buttons.dart';
import 'main_shell_view.dart';

class SignupView extends StatefulWidget {
  const SignupView({super.key});

  @override
  State<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<SignupView> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  String _selectedRole = 'Podcaster';
  bool _obscure = true;
  bool _agreeTerms = true;
  bool _loading = false;

  static const List<(String, IconData)> _roles = [
    ('Podcaster', Icons.podcasts_rounded),
    ('Vocalist', Icons.mic_external_on_rounded),
    ('Voiceover', Icons.movie_filter_rounded),
    ('Streamer', Icons.headset_mic_rounded),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeSignup() async {
    if (_loading) return;
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passCtrl.text.length < 6) {
      Get.snackbar(
        'Check Fields',
        'Please enter your name, a valid email, and a password of at least 6 characters.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.danger,
        colorText: Colors.white,
      );
      return;
    }
    setState(() => _loading = true);
    final String? err = await Get.find<AdminController>().signupWithMongo(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      role: _selectedRole,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      Get.snackbar(
        'Registration Failed',
        err,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.danger,
        colorText: Colors.white,
      );
      return;
    }
    Get.offAll(
      () => const MainShellView(),
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accentBright.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Bar
                      Row(
                        children: [
                          IconButton(
                            onPressed: Get.back,
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                          ),
                          const SizedBox(width: 4),
                          Text('Create Studio Pass', style: t.titleLarge),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.chip,
                              gradient: AppColors.signature,
                            ),
                            child: Text(
                              '7-DAY PRO TRIAL',
                              style: t.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Build your sound\nin seconds',
                        style: t.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ).animate().fadeIn().slideY(begin: 0.1),
                      const SizedBox(height: 6),
                      Text(
                        'Unlock AI spectral noise removal, speaking-driven theatrical bass, and broadcast LUFS mastering.',
                        style: t.bodyMedium?.copyWith(color: AppColors.muted(b)),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Creator Role Selector
                      Text('Primary Creator Focus', style: t.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (String role, IconData icon) in _roles)
                            GestureDetector(
                              onTap: () => setState(() => _selectedRole = role),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.chip,
                                  gradient:
                                      _selectedRole == role ? AppColors.signature : null,
                                  color: _selectedRole == role ? null : AppColors.surface(b),
                                  border: Border.all(
                                    color: _selectedRole == role
                                        ? Colors.transparent
                                        : AppColors.border(b),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 16,
                                      color: _selectedRole == role
                                          ? Colors.white
                                          : AppColors.accentBright,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      role,
                                      style: t.labelLarge?.copyWith(
                                        color: _selectedRole == role
                                            ? Colors.white
                                            : AppColors.text(b),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Form Card
                      VpCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Creator / Studio Name', style: t.labelLarge),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Your name or show title',
                                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text('Work Email', style: t.labelLarge),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'you@studio.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text('Create Password', style: t.labelLarge),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                hintText: 'Minimum 6 characters',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: _agreeTerms,
                                    activeColor: AppColors.accent,
                                    onChanged: (v) => setState(() => _agreeTerms = v ?? true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'I agree to the VocalPolish Studio Terms & Audio Privacy Policy.',
                                    style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            VpButton(
                              label: _loading
                                  ? 'Creating Workspace...'
                                  : 'Launch Studio Workspace',
                              icon: Icons.rocket_launch_rounded,
                              onPressed: _completeSignup,
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.08),

                      const SizedBox(height: AppSpacing.lg),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Already registered? ',
                              style: t.bodyMedium?.copyWith(color: AppColors.muted(b)),
                            ),
                            GestureDetector(
                              onTap: Get.back,
                              child: ShaderMask(
                                shaderCallback: (r) => AppColors.signature.createShader(r),
                                child: Text(
                                  'Sign In',
                                  style: t.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
