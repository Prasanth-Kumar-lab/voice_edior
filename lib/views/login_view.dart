import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/vp_buttons.dart';
import 'main_shell_view.dart';
import 'signup_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _enterStudio() async {
    if (_loading) return;
    setState(() => _loading = true);
    final AdminController adm = Get.find<AdminController>();
    final String? err = await adm.loginWithMongo(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      Get.snackbar(
        'Access Denied',
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

  void _enterGuestMode() {
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
            top: -120,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accent.withValues(alpha: 0.24), Colors.transparent],
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
                      // Top Header
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.button,
                              gradient: AppColors.signature,
                              boxShadow: AppShadows.glow(),
                            ),
                            child: const Icon(
                              Icons.graphic_eq_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (r) => AppColors.signature.createShader(r),
                                child: Text(
                                  'VocalPolish',
                                  style: t.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                'Studio AI Suite',
                                style: t.labelSmall?.copyWith(color: AppColors.muted(b)),
                              ),
                            ],
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _enterGuestMode,
                            child: Text(
                              'Guest Mode',
                              style: t.labelLarge?.copyWith(color: AppColors.accentBright),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Welcome back,\nCreator',
                        style: t.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ).animate().fadeIn().slideY(begin: 0.1),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to access your AI podcast filters, theatrical bass presets, and multi-track Mix Studio.',
                        style: t.bodyMedium?.copyWith(color: AppColors.muted(b)),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Studio Form Card
                      VpCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Email Address', style: t.labelLarge),
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
                            Text('Password', style: t.labelLarge),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
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
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: _remember,
                                    activeColor: AppColors.accent,
                                    onChanged: (v) => setState(() => _remember = v ?? true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Keep me signed in',
                                  style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => Get.snackbar(
                                    'Password Reset',
                                    'A studio recovery link has been sent to your email.',
                                    snackPosition: SnackPosition.BOTTOM,
                                  ),
                                  child: Text(
                                    'Forgot?',
                                    style: t.labelMedium?.copyWith(
                                      color: AppColors.accentBright,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            VpButton(
                              label: _loading ? 'Signing In...' : 'Sign In to Studio',
                              icon: Icons.login_rounded,
                              onPressed: _enterStudio,
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.08),

                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.border(b))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR CONTINUE WITH',
                              style: t.labelSmall?.copyWith(
                                color: AppColors.muted(b),
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: AppColors.border(b))),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: _SocialButton(
                              icon: Icons.g_mobiledata_rounded,
                              label: 'Google',
                              onTap: _enterGuestMode,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _SocialButton(
                              icon: Icons.apple_rounded,
                              label: 'Apple ID',
                              onTap: _enterGuestMode,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Don't have a studio account? ",
                              style: t.bodyMedium?.copyWith(color: AppColors.muted(b)),
                            ),
                            GestureDetector(
                              onTap: () => Get.to(
                                () => const SignupView(),
                                transition: Transition.rightToLeftWithFade,
                              ),
                              child: ShaderMask(
                                shaderCallback: (r) => AppColors.signature.createShader(r),
                                child: Text(
                                  'Create Account',
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

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return InkWell(
      borderRadius: AppRadius.button,
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: AppRadius.button,
          color: AppColors.surface(b),
          border: Border.all(color: AppColors.border(b)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: AppColors.text(b)),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
