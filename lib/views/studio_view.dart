import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../controllers/studio_controller.dart';
import '../models/enhance_mode.dart';
import '../models/podcast_presets.dart';
import '../models/vocal_presets.dart';
import '../services/enhance_server.dart';
import '../services/native_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/common/vp_buttons.dart';
import '../widgets/common/vp_pro.dart';
import '../widgets/common/vp_waveform.dart';

class StudioView extends GetView<StudioController> {
  const StudioView({
    super.key,
    this.onOpenMixStudio,
    this.onOpenSubscription,
    this.onOpenProfile,
  });
  final VoidCallback? onOpenMixStudio;
  final VoidCallback? onOpenSubscription;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  _Header(
                    onOpenSubscription: onOpenSubscription,
                    onOpenProfile: onOpenProfile,
                  ),
                  _StepBar(controller),
                  Expanded(
                    child: Obx(() {
                      final Widget page = switch (controller.phase.value) {
                        StudioPhase.select => _SelectPage(controller, onOpenSubscription: onOpenSubscription),
                        StudioPhase.recording => _RecordingPage(controller),
                        StudioPhase.processing => _ProcessingPage(controller),
                        StudioPhase.result => _ResultPage(
                            controller,
                            onOpenMixStudio: onOpenMixStudio,
                          ),
                      };
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(key: ValueKey<StudioPhase>(controller.phase.value), child: page),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.onOpenSubscription, this.onOpenProfile});
  final VoidCallback? onOpenSubscription;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final EnhanceServer server = Get.find();
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              borderRadius: AppRadius.button,
              gradient: AppColors.signature,
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (r) => AppColors.signature.createShader(r),
                child: Text('VocalPolish', style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              Text('48 kHz AI Studio', style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
            ],
          ),
          const Spacer(),
          if (onOpenSubscription != null) ...[
            GestureDetector(
              onTap: onOpenSubscription,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  borderRadius: AppRadius.chip,
                  gradient: AppColors.signature,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('PRO', style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Obx(() {
            final bool on = server.connected.value;
            return InkWell(
              borderRadius: AppRadius.chip,
              onTap: () => _serverDialog(context, server),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.chip,
                  color: AppColors.surface(b),
                  border: Border.all(color: AppColors.border(b)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppColors.success : AppColors.warning),
                    ),
                    const SizedBox(width: 6),
                    Text(on ? 'Studio AI' : 'On-device', style: t.labelMedium),
                  ],
                ),
              ),
            );
          }),
          if (onOpenProfile != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onOpenProfile,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceAlt(b),
                  border: Border.all(color: AppColors.accentBright, width: 1.4),
                ),
                child: const Center(
                  child: Text('AR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _serverDialog(BuildContext context, EnhanceServer server) async {
    final TextEditingController c = TextEditingController(text: server.custom ?? '');
    await Get.dialog(
      AlertDialog(
        title: const Text('Studio AI service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() => Text(
                  server.connected.value
                      ? 'Connected (${server.engine.value}) at ${server.host}'
                      : 'Not reachable. Your phone still processes on-device.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )),
            const SizedBox(height: 12),
            TextField(controller: c, decoration: const InputDecoration(hintText: 'https://voice-edior.onrender.com')),
            const SizedBox(height: 8),
            Text('Connected via Render cloud API', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              await server.setCustomUrl(c.text);
              Get.back();
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    c.dispose();
  }
}

// ───────────────────────────── select ─────────────────────────────

class _SelectPage extends StatelessWidget {
  const _SelectPage(this.c, {this.onOpenSubscription});
  final StudioController c;
  final VoidCallback? onOpenSubscription;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    return ListView(
      children: [
        // Upgraded Studio Hero Banner
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            color: AppColors.surface(b),
            border: Border.all(color: AppColors.border(b)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: const BoxDecoration(
                            borderRadius: AppRadius.chip,
                            gradient: AppColors.signature,
                          ),
                          child: Text(
                            'AI ENGINE v2.5',
                            style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Zero-Noise + Pitch-Adaptive Body', style: t.labelSmall?.copyWith(color: AppColors.accentBright)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('What are you making?', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Obx(() {
                      final String banner = Get.find<AdminController>().broadcastAnnouncement.value;
                      return Text(
                        banner.isNotEmpty
                            ? banner
                            : 'Select your studio chain and filter before capturing or importing.',
                        style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                      );
                    }),
                  ],
                ),
              ),
              if (onOpenSubscription != null)
                IconButton(
                  onPressed: onOpenSubscription,
                  icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.accentBright),
                  tooltip: 'Studio Pro Features',
                ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.08),
        const SizedBox(height: AppSpacing.md),
        Obx(() => Column(
              children: [
                _ModeCard(mode: EnhanceMode.podcast, selected: c.mode.value == EnhanceMode.podcast, onTap: () => c.setMode(EnhanceMode.podcast)),
                const SizedBox(height: AppSpacing.sm),
                _ModeCard(mode: EnhanceMode.vocals, selected: c.mode.value == EnhanceMode.vocals, onTap: () => c.setMode(EnhanceMode.vocals)),
              ],
            )),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Obx(() => c.mode.value == EnhanceMode.vocals ? _VocalPickers(c) : _PodcastPickers(c)),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.noise_control_off_rounded, size: 16),
                label: const Text('Voice Isolation (Café / Street)'),
                selected: c.voiceIsolation.value,
                onSelected: (v) => c.voiceIsolation.value = v,
              ),
              FilterChip(
                avatar: const Icon(Icons.timer_outlined, size: 16),
                label: const Text('10s Quick Preview'),
                selected: c.preview10s.value,
                onSelected: (v) => c.preview10s.value = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        VpButton(label: 'Record in Studio', icon: Icons.fiber_manual_record_rounded, onPressed: c.startRecording),
        const SizedBox(height: AppSpacing.sm),
        VpButton(label: 'Upload a recording', icon: Icons.upload_file_rounded, filled: false, onPressed: c.upload),
        Obx(() => c.error.value.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(c.error.value, style: t.bodyMedium?.copyWith(color: AppColors.danger)),
              )),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.onTap});
  final EnhanceMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: AppRadius.card,
          color: AppColors.surface(b),
          border: Border.all(color: selected ? AppColors.accentBright : AppColors.border(b), width: selected ? 1.8 : 1),
          boxShadow: selected ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 8))] : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: AppRadius.button,
                gradient: selected ? AppColors.signature : null,
                color: selected ? null : AppColors.surfaceAlt(b),
              ),
              child: Icon(mode.icon, color: selected ? Colors.white : AppColors.accent, size: 26),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(mode.title, style: t.titleLarge),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(borderRadius: AppRadius.chip, color: AppColors.surfaceAlt(b)),
                        child: Text(mode.target, style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(mode.tagline, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                ],
              ),
            ),
            Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? AppColors.accentBright : AppColors.border(b)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── recording ─────────────────────────────

class _RecordingPage extends StatelessWidget {
  const _RecordingPage(this.c);
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final NativeEngine e = c.engine;
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    return Column(
      children: [
        const SizedBox(height: AppSpacing.md),
        Obx(() => Text(c.mode.value.title, style: t.labelLarge?.copyWith(color: AppColors.muted(b)))),
        const SizedBox(height: 6),
        Obx(() => Text(formatDuration(e.elapsedMs.value), style: t.displayMedium)),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Obx(() => VpLiveWave(bars: e.bars.toList(), active: true, height: 150))),
              const SizedBox(width: AppSpacing.sm),
              Obx(() => VpDbMeter(rms: e.levels.value.inRms, peak: e.levels.value.inPeak, clip: e.levels.value.clip, height: 112, label: 'IN')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(() => e.native && e.headphones.value
            ? VpCard(
                onTap: () => e.setMonitor(!e.monitor.value),
                child: Row(
                  children: [
                    Icon(Icons.headphones_rounded, color: e.monitor.value ? AppColors.accentBright : AppColors.muted(b)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.monitor.value ? 'Hearing your voice cleaned live' : 'Hear your voice cleaned live', style: t.titleMedium)),
                    Switch(value: e.monitor.value, onChanged: (v) => e.setMonitor(v)),
                  ],
                ),
              )
            : const SizedBox.shrink()),
        const Spacer(),
        Text(
          'Stay quiet for the first two seconds — it helps the engine learn your room.',
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
        ),
        const SizedBox(height: AppSpacing.md),
        VpRecordButton(recording: true, onPressed: c.stopRecording),
        TextButton(onPressed: c.cancelRecording, child: const Text('Cancel')),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

// ───────────────────────────── processing ─────────────────────────────

class _ProcessingPage extends StatelessWidget {
  const _ProcessingPage(this.c);
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Obx(() => VpProgressRing(
                progress: c.progress.value <= 0.02 ? 0.02 : c.progress.value,
                size: 150,
                child: Text('${(c.progress.value * 100).round()}%', style: t.headlineMedium),
              )),
          const SizedBox(height: AppSpacing.lg),
          Obx(() => Text(c.stage.value, style: t.titleLarge, textAlign: TextAlign.center)),
          const SizedBox(height: 6),
          Obx(() => Text(
                c.mode.value == EnhanceMode.podcast ? 'Making it studio-clean speech' : 'Tuning to your voice',
                style: t.bodyMedium?.copyWith(color: AppColors.muted(b)),
              )),
          Obx(() => c.note.value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                  child: Text(c.note.value, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: AppColors.warning)),
                )),
          Obx(() => c.server.wakingUp.value
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: VpCard(
                    child: Column(
                      children: [
                        Text(
                          'Waking up cloud AI (15–30s on free plan)...',
                          style: t.labelMedium?.copyWith(color: AppColors.warning),
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: c.switchToOnDeviceNow,
                          icon: const Icon(Icons.phone_android_rounded, size: 16),
                          label: const Text('Use On-Device Engine Now'),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink()),
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            onPressed: c.cancelProcessing,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel Processing'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── result ─────────────────────────────

class _ResultPage extends StatelessWidget {
  const _ResultPage(this.c, {this.onOpenMixStudio});
  final StudioController c;
  final VoidCallback? onOpenMixStudio;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    return ListView(
      children: [
        Text('Your ${c.mode.value == EnhanceMode.podcast ? 'podcast' : 'vocal'} is ready', style: t.headlineMedium)
            .animate()
            .fadeIn()
            .slideY(begin: 0.1),
        const SizedBox(height: AppSpacing.md),
        Obx(() => _Segmented(
              leftLabel: 'Original',
              rightLabel: 'Enhanced',
              rightOn: !c.listenOriginal.value,
              onChanged: (right) => c.setListenOriginal(!right),
            )),
        const SizedBox(height: AppSpacing.md),
        VpCard(
          child: Column(
            children: [
              Obx(() => VpWaveform(
                    samples: (c.listenOriginal.value ? c.originalWave : c.enhancedWave).toList(),
                    height: 110,
                    progress: c.progressFraction,
                    onScrub: c.seek,
                  )),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Obx(() => IconButton.filled(
                        onPressed: c.togglePlay,
                        iconSize: 30,
                        icon: Icon(c.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      )),
                  const SizedBox(width: AppSpacing.sm),
                  Obx(() => Text('${formatDuration(c.positionMs.value)} / ${formatDuration(c.durationMs.value)}', style: t.labelLarge)),
                  const Spacer(),
                  Obx(
                    () => FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Match A/B Loudness', style: TextStyle(fontSize: 11)),
                      selected: c.loudnessMatchedAb.value,
                      onSelected: (v) => c.loudnessMatchedAb.value = v,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Obx(
                () => Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: AppColors.muted(b)),
                    const SizedBox(width: 6),
                    Text(
                      'Strength ${(c.strength.value * 100).round()}%',
                      style: t.labelMedium,
                    ),
                    Expanded(
                      child: Slider(
                        value: c.strength.value,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: c.setStrength,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(() => c.mode.value == EnhanceMode.vocals ? _VocalPickers(c, live: true) : _PodcastPickers(c, live: true)),
        Obx(() => c.mode.value == EnhanceMode.podcast ? const _PodcastPromise(done: true) : const SizedBox.shrink()),
        const SizedBox(height: AppSpacing.md),
        Obx(() {
          final EnhanceStats? s = c.stats.value;
          if (s == null) return const SizedBox.shrink();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(Icons.volume_up_rounded, 'Loudness', '${s.lufsOut.toStringAsFixed(1)} LUFS'),
              if (s.cleanerDb >= 3) _Chip(Icons.blur_off_rounded, 'Background', '${s.cleanerDb.round()} dB cleaner'),
              if (c.mode.value == EnhanceMode.vocals && s.f0 > 0)
                _Chip(Icons.music_note_rounded, 'Voice', '${_cap(s.voiceType)} · ${s.f0.round()} Hz'),
              if (s.stereo) const _Chip(Icons.surround_sound_rounded, 'Output', 'Stereo'),
              _Chip(Icons.auto_awesome_rounded, 'Engine', s.engine),
            ],
          );
        }),
        Obx(() => c.note.value.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(c.note.value, style: t.bodySmall?.copyWith(color: AppColors.warning)),
              )),
        const SizedBox(height: AppSpacing.lg),
        Obx(() => VpButton(
              label: c.savedTo.value.isEmpty ? 'Save to device' : 'Saved · ${c.savedTo.value}',
              icon: c.savedTo.value.isEmpty ? Icons.download_rounded : Icons.check_rounded,
              filled: true,
              onPressed: c.save,
            )),
        const SizedBox(height: AppSpacing.sm),
        VpButton(label: 'Share', icon: Icons.ios_share_rounded, filled: false, onPressed: c.share),
        const SizedBox(height: AppSpacing.sm),
        Center(child: TextButton(onPressed: c.reset, child: Text('New recording', style: TextStyle(color: AppColors.muted(b))))),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: AppRadius.button,
        color: AppColors.surface(b),
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accentBright),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
              Text(value, style: t.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.leftLabel, required this.rightLabel, required this.rightOn, required this.onChanged});
  final String leftLabel, rightLabel;
  final bool rightOn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    Widget seg(String label, bool on, VoidCallback tap) => Expanded(
          child: GestureDetector(
            onTap: tap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(borderRadius: AppRadius.chip, gradient: on ? AppColors.signature : null),
              child: Center(
                child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: on ? Colors.white : AppColors.muted(b))),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Row(children: [seg(leftLabel, !rightOn, () => onChanged(false)), seg(rightLabel, rightOn, () => onChanged(true))]),
    );
  }
}


// ───────────────────────────── step bar ─────────────────────────────

class _StepBar extends StatelessWidget {
  const _StepBar(this.c);
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    const List<String> labels = ['Choose', 'Capture', 'Result'];
    return Obx(() {
      final int cur = c.step;
      Widget dot(int i) {
        final bool done = i < cur;
        final bool on = i == cur;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: (done || on) ? AppColors.signature : null,
                color: (done || on) ? null : AppColors.surfaceAlt(b),
                border: Border.all(color: (done || on) ? Colors.transparent : AppColors.border(b)),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.muted(b))),
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[i], style: Theme.of(context).textTheme.labelSmall?.copyWith(color: on ? AppColors.text(b) : AppColors.muted(b))),
          ],
        );
      }

      Widget line(int i) => Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                height: 2,
                decoration: BoxDecoration(
                  gradient: i < cur ? AppColors.signature : null,
                  color: i < cur ? null : AppColors.border(b),
                  borderRadius: AppRadius.chip,
                ),
              ),
            ),
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [dot(0), line(0), dot(1), line(1), dot(2)]),
      );
    });
  }
}

// ───────────────────────────── presets (Vocals) ─────────────────────────────

class _VocalPickers extends StatelessWidget {
  const _VocalPickers(this.c, {this.live = false});
  final StudioController c;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (live)
          Row(
            children: [
              Expanded(child: Text('Try another sound', style: t.titleMedium)),
              Obx(() => c.rendering.value
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const SizedBox.shrink()),
            ],
          ),
        if (live) const SizedBox(height: AppSpacing.sm),
        _label(context, 'Tone', Icons.equalizer_rounded),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final VocalTone tone in VocalTone.all)
                  _PresetChip(label: tone.label, selected: c.tone.value == tone, onTap: () => c.selectTone(tone)),
              ],
            )),
        Obx(() => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(c.tone.value.blurb, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
            )),
        const SizedBox(height: AppSpacing.md),
        _label(context, 'Space', Icons.surround_sound_rounded),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final VocalSpace space in VocalSpace.all)
                  _PresetChip(label: space.label, selected: c.space.value == space, onTap: () => c.selectSpace(space)),
              ],
            )),
        Obx(() => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(c.space.value.blurb, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
            )),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: live ? VpCard(child: body) : body,
    );
  }

  Widget _label(BuildContext context, String text, IconData icon) {
    final Brightness b = Theme.of(context).brightness;
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accentBright),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted(b))),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: AppRadius.chip,
          gradient: selected ? AppColors.signature : null,
          color: selected ? null : AppColors.surface(b),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border(b)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppColors.accentBright,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? Colors.white : AppColors.text(b),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── presets (Podcast) ─────────────────────────────

class _PodcastPickers extends StatelessWidget {
  const _PodcastPickers(this.c, {this.live = false});
  final StudioController c;
  final bool live;

  Widget _label(BuildContext context, String text, IconData icon) {
    final Brightness b = Theme.of(context).brightness;
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accentBright),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted(b))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (live) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Try another sound',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Obx(() => c.rendering.value
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else ...[
          _label(context, 'Voice Profile', Icons.record_voice_over_rounded),
          const SizedBox(height: 8),
        ],
        Obx(() {
          final List<PodcastTone> tones = Get.find<AdminController>().dynamicPodcastTones;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final PodcastTone tone in tones)
                _PresetChip(
                  label: tone.label,
                  icon: tone.icon,
                  selected: c.podTone.value.id == tone.id,
                  onTap: () => c.selectPodcastTone(tone),
                ),
            ],
          );
        }),
        Obx(() {
          final PodcastTone tone = c.podTone.value;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: AppRadius.button,
                color: AppColors.surfaceAlt(b),
                border: Border.all(color: AppColors.border(b)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.chip,
                      color: tone.id == 'theatrical'
                          ? AppColors.warning.withValues(alpha: 0.2)
                          : AppColors.accent.withValues(alpha: 0.2),
                    ),
                    child: Text(
                      tone.tag.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: tone.id == 'theatrical'
                            ? AppColors.warning
                            : AppColors.accentBright,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tone.blurb,
                      style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: live ? VpCard(child: body) : body,
    );
  }
}

// ───────────────────────────── podcast promise / summary ─────────────────────────────

class _PodcastPromise extends StatelessWidget {
  const _PodcastPromise({this.done = false});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    const List<String> items = [
      'Background noise and hum removed',
      'Room echo reduced, voice kept natural',
      'Voice enhanced: tone, presence and air',
      'De-essed, evened out, -16 LUFS and peak-safe',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: VpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(done ? 'What was done' : 'What you get', style: t.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final String i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                    const SizedBox(width: 10),
                    Expanded(child: Text(i, style: t.bodyMedium?.copyWith(color: done ? null : AppColors.muted(b)))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
