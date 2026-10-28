import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/mix_controller.dart';
import '../../models/fx_slot.dart';
import '../../models/mix_clip.dart';
import '../../models/mix_project.dart';
import '../../models/mix_track.dart';
import '../../services/audio_convert.dart';
import '../../services/mix_engine_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../utils/app_localization.dart';
import '../../widgets/common/vp_automation_lane.dart';
import '../../widgets/common/vp_eq_canvas.dart';
import '../../widgets/common/vp_knob.dart';
import '../../widgets/common/vp_meter.dart';
import '../../widgets/common/vp_xy_pad.dart';

class MixStudioView extends GetView<MixController> {
  const MixStudioView({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: AppColors.bg(b),
      body: SafeArea(
        child: Column(
          children: [
            _TopProjectBar(controller: controller),
            _TransportBar(controller: controller),
            _StatusToastBanner(controller: controller),
            Expanded(
              flex: 5,
              child: _MultiTrackTimelineArea(controller: controller),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Obx(() {
                final MixEngineService eng = controller.engine;
                return VpMasterMeterBar(
                  peakL: eng.peakL.value,
                  peakR: eng.peakR.value,
                  rmsL: eng.rmsL.value,
                  rmsR: eng.rmsR.value,
                  lufsMomentary: eng.lufsMomentary.value,
                  lufsIntegrated: eng.lufsIntegrated.value,
                  truePeakDb: eng.truePeakDb.value,
                  correlation: eng.correlation.value,
                  clipping: eng.clipping.value,
                );
              }),
            ),
            Expanded(
              flex: 4,
              child: _BottomInspectorSheet(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── A. TOP PROJECT BAR ─────────────────────────────

class _TopProjectBar extends StatelessWidget {
  const _TopProjectBar({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(bottom: BorderSide(color: AppColors.border(b))),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              borderRadius: AppRadius.button,
              gradient: AppColors.signature,
            ),
            child: const Icon(Icons.tune_rounded, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _showRenameDialog(context),
              child: Obx(
                () => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        controller.project.value.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_rounded, size: 14, color: AppColors.muted(b)),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Templates',
            icon: Icon(Icons.dashboard_customize_rounded, size: 19, color: AppColors.muted(b)),
            onSelected: controller.loadTemplate,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'podcast_episode', child: Text('Podcast Episode (3 Tracks)')),
              PopupMenuItem(value: 'song_vocal', child: Text('Song Vocal + Backing')),
              PopupMenuItem(value: 'voiceover_ducking', child: Text('Voiceover + Auto-Ducking')),
              PopupMenuItem(value: 'blank', child: Text('Blank Project')),
            ],
          ),
          Obx(
            () => IconButton(
              tooltip: 'Undo (${controller.undoCount.value})',
              visualDensity: VisualDensity.compact,
              onPressed: controller.undoCount.value > 0 ? controller.undo : null,
              icon: const Icon(Icons.undo_rounded, size: 19),
            ),
          ),
          Obx(
            () => IconButton(
              tooltip: 'Redo (${controller.redoCount.value})',
              visualDensity: VisualDensity.compact,
              onPressed: controller.redoCount.value > 0 ? controller.redo : null,
              icon: const Icon(Icons.redo_rounded, size: 19),
            ),
          ),
          IconButton(
            tooltip: 'Save Project (.vpmix)',
            visualDensity: VisualDensity.compact,
            onPressed: controller.saveProjectToFile,
            icon: const Icon(Icons.save_outlined, size: 19),
          ),
          const SizedBox(width: 4),
          Obx(
            () => FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 32),
              ),
              onPressed: controller.exporting.value ? null : () => _showExportModal(context),
              icon: controller.exporting.value
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 15),
              label: const Text(
                'Export',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final TextEditingController tc =
        TextEditingController(text: controller.project.value.name);
    await Get.dialog(
      AlertDialog(
        title: const Text('Project Name'),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter project title'),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              controller.renameProject(tc.text);
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportModal(BuildContext context) async {
    MixExportFormat selectedFormat = MixExportFormat.wav16;
    bool loopRangeOnly = false;
    bool exportStemsZip = false;
    final TextEditingController titleCtrl =
        TextEditingController(text: controller.project.value.name);
    final TextEditingController artistCtrl =
        TextEditingController(text: 'VocalPolish Studio');
    final TextEditingController albumCtrl =
        TextEditingController(text: 'VocalPolish Sessions');

    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Export Master Mix / Stems'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Target loudness: ${controller.project.value.master.lufsPreset.label} '
                    '(${controller.project.value.master.targetLufs.toStringAsFixed(1)} LUFS · '
                    '${controller.project.value.master.limiterCeilingDb.toStringAsFixed(1)} dBTP)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Audio Format',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<MixExportFormat>(
                    initialValue: selectedFormat,
                    isExpanded: true,
                    items: [
                      for (final MixExportFormat fmt in MixExportFormat.values)
                        DropdownMenuItem(value: fmt, child: Text(fmt.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => selectedFormat = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Export Loop Range Only'),
                    subtitle: Text(
                      '${(controller.project.value.loopStartMs / 1000).toStringAsFixed(1)}s – '
                      '${(controller.project.value.loopEndMs / 1000).toStringAsFixed(1)}s',
                    ),
                    value: loopRangeOnly,
                    onChanged: (v) => setState(() => loopRangeOnly = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Export Individual Track Stems (.ZIP)'),
                    subtitle: Text(
                      'Bundles ${controller.project.value.tracks.length} isolated track WAVs',
                    ),
                    value: exportStemsZip,
                    onChanged: (v) => setState(() => exportStemsZip = v),
                  ),
                  const Divider(height: 16),
                  const Text(
                    'Embedded Metadata Tags',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: artistCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Artist / Host',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: albumCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Album / Podcast Show',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: Get.back, child: const Text('Cancel')),
              OutlinedButton.icon(
                onPressed: () async {
                  Get.back();
                  final MixMasterExportSummary? summary =
                      await controller.exportFinalMix(
                    format: selectedFormat,
                    loopRangeOnly: loopRangeOnly,
                    exportStemsZip: exportStemsZip,
                    metaTitle: titleCtrl.text,
                    metaArtist: artistCtrl.text,
                    metaAlbum: albumCtrl.text,
                    shareAfter: false,
                  );
                  if (summary != null) _showExportSummaryDialog(summary);
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Save'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Get.back();
                  final MixMasterExportSummary? summary =
                      await controller.exportFinalMix(
                    format: selectedFormat,
                    loopRangeOnly: loopRangeOnly,
                    exportStemsZip: exportStemsZip,
                    metaTitle: titleCtrl.text,
                    metaArtist: artistCtrl.text,
                    metaAlbum: albumCtrl.text,
                    shareAfter: true,
                  );
                  if (summary != null) _showExportSummaryDialog(summary);
                },
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Export & Share'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showExportSummaryDialog(MixMasterExportSummary s) async {
    final String sizeKb = (s.fileSizeBytes / 1024.0).toStringAsFixed(1);
    await Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Text('Master Export Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Format: ${s.formatLabel}'),
            const SizedBox(height: 4),
            Text('Integrated Loudness: ${s.lufsOut.toStringAsFixed(1)} LUFS'),
            const SizedBox(height: 4),
            Text('True-Peak Ceiling: ${s.truePeakDb.toStringAsFixed(1)} dBTP'),
            const SizedBox(height: 4),
            Text('Duration: ${(s.durationMs / 1000.0).toStringAsFixed(1)} sec'),
            const SizedBox(height: 4),
            Text('File Size: $sizeKb KB'),
            const SizedBox(height: 8),
            Text(
              s.filePath,
              style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          FilledButton(onPressed: Get.back, child: const Text('Done')),
        ],
      ),
    );
  }
}

// ───────────────────────────── B. TRANSPORT BAR ─────────────────────────────

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(b),
        border: Border(bottom: BorderSide(color: AppColors.border(b))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Skip to Start',
              visualDensity: VisualDensity.compact,
              onPressed: controller.skipToStart,
              icon: const Icon(Icons.skip_previous_rounded, size: 20),
            ),
            Obx(() {
              final bool isPlaying = controller.engine.playing.value;
              return GestureDetector(
                onTap: controller.togglePlay,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isPlaying ? null : AppColors.signature,
                    color: isPlaying ? AppColors.accentBright : null,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              );
            }),
            IconButton(
              tooltip: 'Stop',
              visualDensity: VisualDensity.compact,
              onPressed: controller.stopTransport,
              icon: const Icon(Icons.stop_rounded, size: 20),
            ),
            Obx(() {
              final bool rec = controller.recordingOnTrack.value;
              return IconButton(
                tooltip: rec ? 'Stop Recording Take' : 'Record New Take at Playhead',
                visualDensity: VisualDensity.compact,
                onPressed: controller.toggleRecordOnTrack,
                icon: Icon(
                  rec ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                  color: rec ? AppColors.danger : AppColors.danger.withValues(alpha: 0.8),
                  size: 20,
                ),
              );
            }),
            const SizedBox(width: 6),
            // Timecode readout (mm:ss.ms)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.bg(b),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border(b)),
              ),
              child: Obx(
                () => Text(
                  _formatTimecode(controller.engine.playheadMs.value),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentBright,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Loop toggle
            Obx(() {
              final bool loop = controller.project.value.loopEnabled;
              return _TransportPill(
                icon: Icons.repeat_rounded,
                label: 'Loop',
                active: loop,
                onTap: controller.toggleLoop,
              );
            }),
            const SizedBox(width: 4),
            // Metronome toggle
            Obx(() {
              final bool click = controller.project.value.metronomeEnabled;
              return _TransportPill(
                icon: Icons.av_timer_rounded,
                label: 'Click',
                active: click,
                onTap: controller.toggleMetronome,
              );
            }),
            const SizedBox(width: 4),
            // BPM selector
            Obx(() {
              final int bpm = controller.project.value.bpm.round();
              return _TransportPill(
                icon: Icons.speed_rounded,
                label: '$bpm BPM',
                active: false,
                onTap: () => _showBpmDialog(context),
              );
            }),
            const SizedBox(width: 4),
            // Snap to grid
            Obx(() {
              final bool snap = controller.project.value.snapToGrid;
              return _TransportPill(
                icon: Icons.grid_on_rounded,
                label: 'Snap',
                active: snap,
                onTap: controller.toggleSnapToGrid,
              );
            }),
            const SizedBox(width: 4),
            _TransportPill(
              icon: Icons.bookmark_add_outlined,
              label: 'Marker',
              active: false,
              onTap: () => controller.addMarkerAtPlayhead('Cue'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Zoom Out Timeline',
              visualDensity: VisualDensity.compact,
              onPressed: controller.zoomOut,
              icon: const Icon(Icons.zoom_out_rounded, size: 19),
            ),
            IconButton(
              tooltip: 'Zoom In Timeline',
              visualDensity: VisualDensity.compact,
              onPressed: controller.zoomIn,
              icon: const Icon(Icons.zoom_in_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTimecode(int ms) {
    final int clamped = max(0, ms);
    final int minutes = clamped ~/ 60000;
    final int seconds = (clamped % 60000) ~/ 1000;
    final int tenths = (clamped % 1000) ~/ 100;
    final String mStr = minutes.toString().padLeft(2, '0');
    final String sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr.$tenths';
  }

  Future<void> _showBpmDialog(BuildContext context) async {
    double tempBpm = controller.project.value.bpm;
    await Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Project Tempo (BPM)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${tempBpm.round()} BPM',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Slider(
                  value: tempBpm,
                  min: 50,
                  max: 200,
                  divisions: 150,
                  onChanged: (v) => setState(() => tempBpm = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: Get.back, child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  controller.setBpm(tempBpm);
                  Get.back();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TransportPill extends StatelessWidget {
  const _TransportPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: AppRadius.chip,
          color: active ? AppColors.accent.withValues(alpha: 0.22) : AppColors.surface(b),
          border: Border.all(
            color: active ? AppColors.accentBright : AppColors.border(b),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? AppColors.accentBright : AppColors.muted(b),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.accentBright : AppColors.text(b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusToastBanner extends StatelessWidget {
  const _StatusToastBanner({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Obx(() {
      final String msg = controller.statusBanner.value;
      if (msg.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
        color: AppColors.accent.withValues(alpha: 0.16),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.accentBright),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                msg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text(b),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => controller.statusBanner.value = '',
              child: Icon(Icons.close_rounded, size: 14, color: AppColors.muted(b)),
            ),
          ],
        ),
      );
    });
  }
}

// ───────────────────────────── C. MULTI-TRACK TIMELINE AREA ─────────────────────────────

class _MultiTrackTimelineArea extends StatefulWidget {
  const _MultiTrackTimelineArea({required this.controller});
  final MixController controller;

  @override
  State<_MultiTrackTimelineArea> createState() => _MultiTrackTimelineAreaState();
}

class _MultiTrackTimelineAreaState extends State<_MultiTrackTimelineArea> {
  final ScrollController _hScroll = ScrollController();
  double _basePps = 48.0;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    const double headerWidth = 152.0;

    return GestureDetector(
      onScaleStart: (_) => _basePps = widget.controller.pixelsPerSecond.value,
      onScaleUpdate: (details) {
        if ((details.horizontalScale - 1.0).abs() > 0.02) {
          widget.controller.pixelsPerSecond.value =
              (_basePps * details.horizontalScale).clamp(20.0, 220.0);
        }
      },
      child: Obx(() {
        final MixProject proj = widget.controller.project.value;
        final double pps = widget.controller.pixelsPerSecond.value;
        final int totalMs = max(20000, proj.totalDurationMs + 8000);
        final double canvasWidth = (totalMs / 1000.0) * pps;

        return Column(
          children: [
            // Top row: Add Track header + Time Ruler
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Container(
                    width: headerWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface(b),
                      border: Border(
                        right: BorderSide(color: AppColors.border(b)),
                        bottom: BorderSide(color: AppColors.border(b)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'TRACKS (${proj.tracks.length}/8)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted(b),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: widget.controller.addTrack,
                          child: const Row(
                            children: [
                              Icon(Icons.add_rounded, size: 14, color: AppColors.accentBright),
                              Text(
                                'Add',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accentBright,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) {
                          final int ms = ((d.localPosition.dx / pps) * 1000).round();
                          widget.controller.seekToMs(ms);
                        },
                        onHorizontalDragUpdate: (d) {
                          final int ms = ((d.localPosition.dx / pps) * 1000).round();
                          widget.controller.seekToMs(ms);
                        },
                        child: SizedBox(
                          width: canvasWidth,
                          height: 28,
                          child: Obx(
                            () => CustomPaint(
                              painter: _TimeRulerPainter(
                                pixelsPerSecond: pps,
                                bpm: proj.bpm,
                                playheadMs: widget.controller.engine.playheadMs.value,
                                markers: proj.markers,
                                brightness: b,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Track rows
            Expanded(
              child: ListView.builder(
                itemCount: proj.tracks.length,
                itemBuilder: (context, idx) {
                  final MixTrack track = proj.tracks[idx];
                  final double rowHeight = track.collapsed ? 52.0 : 88.0;
                  return SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        SizedBox(
                          width: headerWidth,
                          child: _TrackHeaderCell(
                            track: track,
                            controller: widget.controller,
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: ScrollController(
                              initialScrollOffset:
                                  _hScroll.hasClients ? _hScroll.offset : 0.0,
                            ),
                            child: _TrackClipLane(
                              track: track,
                              controller: widget.controller,
                              pixelsPerSecond: pps,
                              canvasWidth: canvasWidth,
                              rowHeight: rowHeight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  _TimeRulerPainter({
    required this.pixelsPerSecond,
    required this.bpm,
    required this.playheadMs,
    required this.markers,
    required this.brightness,
  });

  final double pixelsPerSecond;
  final double bpm;
  final int playheadMs;
  final List<TimelineMarker> markers;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bg = Paint()..color = AppColors.surfaceAlt(brightness);
    canvas.drawRect(Offset.zero & size, bg);

    final Paint tickPaint = Paint()
      ..color = AppColors.border(brightness)
      ..strokeWidth = 1.0;

    final int totalSecs = (size.width / pixelsPerSecond).ceil();
    for (int s = 0; s <= totalSecs; s++) {
      final double x = s * pixelsPerSecond;
      canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height), tickPaint);
      if (s % 2 == 0 || pixelsPerSecond >= 60) {
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: '${s}s',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.muted(brightness),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 2));
      }
    }

    // Markers
    for (final TimelineMarker m in markers) {
      final double mx = (m.timeMs / 1000.0) * pixelsPerSecond;
      final Paint mp = Paint()
        ..color = Color(m.colorValue)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(mx, 0), Offset(mx, size.height), mp);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: m.label,
          style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            color: AppColors.warning,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(mx + 3, 12));
    }

    // Playhead triangle
    final double px = (playheadMs / 1000.0) * pixelsPerSecond;
    final Paint playheadPaint = Paint()..color = AppColors.accentBright;
    final Path head = Path()
      ..moveTo(px - 6, 0)
      ..lineTo(px + 6, 0)
      ..lineTo(px, 10)
      ..close();
    canvas.drawPath(head, playheadPaint);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      playheadPaint..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond ||
      oldDelegate.playheadMs != playheadMs ||
      oldDelegate.markers.length != markers.length;
}

class _TrackHeaderCell extends StatelessWidget {
  const _TrackHeaderCell({required this.track, required this.controller});
  final MixTrack track;
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Obx(() {
      final bool selected = controller.selectedTrackId.value == track.id;
      return GestureDetector(
        onTap: () => controller.selectedTrackId.value = track.id,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : AppColors.surface(b),
            border: Border(
              left: BorderSide(color: Color(track.colorValue), width: 4),
              right: BorderSide(color: AppColors.border(b)),
              bottom: BorderSide(color: AppColors.border(b)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text(b),
                      ),
                    ),
                  ),
                  _MiniTrackBtn(
                    label: 'M',
                    active: track.muted,
                    activeColor: AppColors.warning,
                    onTap: () => controller.updateTrackProps(
                      track.id,
                      muted: !track.muted,
                    ),
                  ),
                  const SizedBox(width: 3),
                  _MiniTrackBtn(
                    label: 'S',
                    active: track.solo,
                    activeColor: AppColors.accentBright,
                    onTap: () => controller.updateTrackProps(
                      track.id,
                      solo: !track.solo,
                    ),
                  ),
                  const SizedBox(width: 3),
                  _MiniTrackBtn(
                    label: 'R',
                    active: track.armed,
                    activeColor: AppColors.danger,
                    onTap: () => controller.updateTrackProps(
                      track.id,
                      armed: !track.armed,
                    ),
                  ),
                  const SizedBox(width: 3),
                  _MiniTrackBtn(
                    label: 'A',
                    active: track.showAutomation,
                    activeColor: AppColors.success,
                    onTap: () => controller.updateTrackProps(
                      track.id,
                      showAutomation: !track.showAutomation,
                    ),
                  ),
                  const SizedBox(width: 2),
                  GestureDetector(
                    onTap: () => controller.updateTrackProps(
                      track.id,
                      collapsed: !track.collapsed,
                    ),
                    child: Icon(
                      track.collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      size: 15,
                      color: AppColors.muted(b),
                    ),
                  ),
                ],
              ),
              if (!track.collapsed)
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: track.volumeDb.clamp(-60.0, 12.0),
                          min: -60.0,
                          max: 12.0,
                          activeColor: Color(track.colorValue),
                          onChanged: (v) =>
                              controller.updateTrackProps(track.id, volumeDb: v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${track.volumeDb.toStringAsFixed(0)}dB',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: AppColors.muted(b),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        controller.selectedTrackId.value = track.id;
                        controller.bottomTabIndex.value = 1;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          color: track.fxChain.isNotEmpty
                              ? AppColors.accent.withValues(alpha: 0.25)
                              : AppColors.surfaceAlt(b),
                        ),
                        child: Text(
                          'FX ${track.fxChain.length}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentBright,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _MiniTrackBtn extends StatelessWidget {
  const _MiniTrackBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: active ? activeColor : AppColors.surfaceAlt(b),
          border: Border.all(
            color: active ? activeColor : AppColors.border(b),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: active ? Colors.black : AppColors.muted(b),
          ),
        ),
      ),
    );
  }
}

class _TrackClipLane extends StatelessWidget {
  const _TrackClipLane({
    required this.track,
    required this.controller,
    required this.pixelsPerSecond,
    required this.canvasWidth,
    required this.rowHeight,
  });

  final MixTrack track;
  final MixController controller;
  final double pixelsPerSecond;
  final double canvasWidth;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        controller.selectedTrackId.value = track.id;
        final int ms = ((d.localPosition.dx / pixelsPerSecond) * 1000).round();
        controller.seekToMs(ms);
      },
      child: Container(
        width: canvasWidth,
        height: rowHeight,
        decoration: BoxDecoration(
          color: AppColors.bg(b),
          border: Border(bottom: BorderSide(color: AppColors.border(b))),
        ),
        child: Stack(
          children: [
            // Beat grid lines
            Positioned.fill(
              child: CustomPaint(
                painter: _LaneGridPainter(
                  pixelsPerSecond: pixelsPerSecond,
                  brightness: b,
                ),
              ),
            ),
            // Clips
            for (final MixClip clip in track.clips)
              _TimelineClipTile(
                track: track,
                clip: clip,
                controller: controller,
                pixelsPerSecond: pixelsPerSecond,
                rowHeight: rowHeight,
              ),
            // Interactive Volume Breakpoint Automation Overlay (when 'A' is active)
            if (track.showAutomation)
              Positioned.fill(
                child: VpAutomationLane(
                  points: track.volumeAutomation,
                  pixelsPerSecond: pixelsPerSecond,
                  color: Color(track.colorValue),
                  onAddOrUpdatePoint: (idx, timeMs, valDb, {toggleCurve}) =>
                      controller.addOrUpdateAutomationPoint(
                    track.id,
                    idx,
                    timeMs,
                    valDb,
                    toggleCurve: toggleCurve,
                  ),
                  onDeletePointAt: (idx) =>
                      controller.deleteAutomationPoint(track.id, idx),
                ),
              ),
            // Playhead vertical line
            Obx(() {
              final double px =
                  (controller.engine.playheadMs.value / 1000.0) * pixelsPerSecond;
              return Positioned(
                left: px,
                top: 0,
                bottom: 0,
                child: Container(width: 1.6, color: AppColors.accentBright),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _LaneGridPainter extends CustomPainter {
  _LaneGridPainter({required this.pixelsPerSecond, required this.brightness});
  final double pixelsPerSecond;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = AppColors.border(brightness).withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    final int secs = (size.width / pixelsPerSecond).ceil();
    for (int s = 1; s <= secs; s++) {
      final double x = s * pixelsPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _LaneGridPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond;
}

class _TimelineClipTile extends StatelessWidget {
  const _TimelineClipTile({
    required this.track,
    required this.clip,
    required this.controller,
    required this.pixelsPerSecond,
    required this.rowHeight,
  });

  final MixTrack track;
  final MixClip clip;
  final MixController controller;
  final double pixelsPerSecond;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final double leftPx = (clip.timelineStartMs / 1000.0) * pixelsPerSecond;
    final double widthPx = max(28.0, (clip.durationMs / 1000.0) * pixelsPerSecond);
    final Color trackColor = Color(track.colorValue);

    return Positioned(
      left: leftPx,
      top: 4,
      bottom: 4,
      width: widthPx,
      child: Obx(() {
        final bool isSelected = controller.selectedClipId.value == clip.id;
        return GestureDetector(
          onTap: () => controller.selectClip(track.id, clip.id),
          onHorizontalDragUpdate: (d) {
            final int deltaMs = ((d.delta.dx / pixelsPerSecond) * 1000).round();
            controller.moveClip(track.id, clip.id, clip.timelineStartMs + deltaMs);
          },
          child: Container(
            decoration: BoxDecoration(
              color: trackColor.withValues(alpha: clip.muted ? 0.12 : 0.26),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.white : trackColor,
                width: isSelected ? 1.8 : 1.0,
              ),
            ),
            child: Stack(
              children: [
                // Cached Peak Waveform + Fade curves
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClipWaveformPainter(
                      peaks: clip.peaks,
                      color: trackColor,
                      fadeInFraction:
                          (clip.fadeInMs / max(1, clip.durationMs)).clamp(0.0, 0.5),
                      fadeOutFraction:
                          (clip.fadeOutMs / max(1, clip.durationMs)).clamp(0.0, 0.5),
                    ),
                  ),
                ),
                // Top label bar
                Positioned(
                  left: 6,
                  right: 6,
                  top: 3,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          clip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (clip.useEnhanced && clip.enhancedPath != null) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 11,
                          color: AppColors.accentBright,
                        ),
                      ],
                    ],
                  ),
                ),
                // Left Trim Handle
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      final int deltaMs =
                          ((d.delta.dx / pixelsPerSecond) * 1000).round();
                      controller.trimClipStart(clip.id, deltaMs);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right Trim Handle
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      final int deltaMs =
                          ((d.delta.dx / pixelsPerSecond) * 1000).round();
                      controller.trimClipEnd(clip.id, clip.durationMs + deltaMs);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _ClipWaveformPainter extends CustomPainter {
  _ClipWaveformPainter({
    required this.peaks,
    required this.color,
    required this.fadeInFraction,
    required this.fadeOutFraction,
  });

  final List<double> peaks;
  final Color color;
  final double fadeInFraction;
  final double fadeOutFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final Paint barPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final int n = peaks.length;
    final double midY = size.height * 0.56;
    final double maxAmp = size.height * 0.36;

    for (int i = 0; i < n; i++) {
      final double x = (i / max(1, n - 1)) * size.width;
      final double amp = (peaks[i].clamp(0.05, 1.0)) * maxAmp;
      canvas.drawLine(Offset(x, midY - amp), Offset(x, midY + amp), barPaint);
    }

    // Draw fade-in / fade-out envelope lines
    final Paint envPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.4;
    if (fadeInFraction > 0.01) {
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width * fadeInFraction, 4),
        envPaint,
      );
    }
    if (fadeOutFraction > 0.01) {
      canvas.drawLine(
        Offset(size.width * (1.0 - fadeOutFraction), 4),
        Offset(size.width, size.height),
        envPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClipWaveformPainter oldDelegate) =>
      oldDelegate.peaks != peaks ||
      oldDelegate.fadeInFraction != fadeInFraction ||
      oldDelegate.fadeOutFraction != fadeOutFraction;
}

// ───────────────────────────── D. BOTTOM INSPECTOR SHEET ─────────────────────────────

class _BottomInspectorSheet extends StatelessWidget {
  const _BottomInspectorSheet({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    const List<(IconData, String)> tabs = [
      (Icons.content_cut_rounded, 'Clip'),
      (Icons.auto_fix_high_rounded, 'Track FX'),
      (Icons.equalizer_rounded, 'Master'),
      (Icons.library_music_rounded, 'Library'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(top: BorderSide(color: AppColors.border(b))),
      ),
      child: Column(
        children: [
          // Tab switcher bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(b),
              border: Border(bottom: BorderSide(color: AppColors.border(b))),
            ),
            child: Obx(
              () => Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => controller.bottomTabIndex.value = i,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.chip,
                            gradient: controller.bottomTabIndex.value == i
                                ? AppColors.signature
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                tabs[i].$1,
                                size: 14,
                                color: controller.bottomTabIndex.value == i
                                    ? Colors.white
                                    : AppColors.muted(b),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tabs[i].$2,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: controller.bottomTabIndex.value == i
                                      ? Colors.white
                                      : AppColors.muted(b),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              return switch (controller.bottomTabIndex.value) {
                0 => _ClipInspectorTab(controller: controller),
                1 => _TrackFxInspectorTab(controller: controller),
                2 => _MasterBusInspectorTab(controller: controller),
                _ => _LibraryInspectorTab(controller: controller),
              };
            }),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── TAB 0: CLIP INSPECTOR ─────────────────────────────

class _ClipInspectorTab extends StatelessWidget {
  const _ClipInspectorTab({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Obx(() {
      final MixClip? clip = controller.selectedClip;
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ActionBtn(
                icon: Icons.file_upload_outlined,
                label: 'Import Audio',
                onTap: controller.importAudioFileToSelectedTrack,
              ),
              _ActionBtn(
                icon: Icons.content_cut_rounded,
                label: 'Split @ Playhead',
                onTap: controller.splitSelectedClipAtPlayhead,
              ),
              _ActionBtn(
                icon: Icons.copy_all_rounded,
                label: 'Duplicate',
                onTap: controller.duplicateSelectedClip,
              ),
              _ActionBtn(
                icon: Icons.delete_sweep_rounded,
                label: 'Ripple Delete',
                onTap: () => controller.deleteSelectedClip(ripple: true),
              ),
              _ActionBtn(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                onTap: () => controller.deleteSelectedClip(ripple: false),
              ),
              _ActionBtn(
                icon: Icons.content_copy_rounded,
                label: 'Copy',
                onTap: controller.copySelectedClip,
              ),
              _ActionBtn(
                icon: Icons.content_paste_rounded,
                label: 'Paste',
                onTap: controller.pasteClipAtPlayhead,
              ),
              _ActionBtn(
                icon: Icons.graphic_eq_rounded,
                label: 'Trim Silence',
                onTap: controller.removeSilenceFromSelectedClip,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (clip == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Select any clip on the timeline (or tap Import Audio) to edit gain, fades, time-stretch, pitch, or run AI Voice Enhance.',
                style: TextStyle(fontSize: 12, color: AppColors.muted(b)),
              ),
            )
          else ...[
            // AI Enhance Voice Banner
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: AppRadius.button,
                color: AppColors.surfaceAlt(b),
                border: Border.all(color: AppColors.border(b)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.accentBright,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clip.name,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          clip.enhancedPath != null
                              ? 'AI Enhanced stem ready (non-destructive)'
                              : 'Run VocalPolish AI denoise + polish on this clip',
                          style: TextStyle(fontSize: 11, color: AppColors.muted(b)),
                        ),
                      ],
                    ),
                  ),
                  if (clip.enhancedPath != null)
                    Switch(
                      value: clip.useEnhanced,
                      onChanged: (v) =>
                          controller.updateSelectedClipProps(useEnhanced: v),
                    ),
                  FilledButton.icon(
                    onPressed: controller.enhancingClip.value
                        ? null
                        : controller.enhanceSelectedClipVoice,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                    label: Text(
                      controller.enhancingClip.value ? 'Enhancing...' : 'Enhance Voice',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Knobs row: Clip Gain, Speed (WSOLA), Pitch Semitones, Fade In, Fade Out
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  VpKnob(
                    label: 'Clip Gain',
                    value: clip.gainDb,
                    min: -36.0,
                    max: 12.0,
                    defaultValue: 0.0,
                    unit: ' dB',
                    onChanged: (v) => controller.updateSelectedClipProps(gainDb: v),
                  ),
                  const SizedBox(width: 14),
                  VpKnob(
                    label: 'Speed (WSOLA)',
                    value: clip.stretchRate,
                    min: 0.5,
                    max: 2.0,
                    defaultValue: 1.0,
                    unit: 'x',
                    onChanged: (v) =>
                        controller.updateSelectedClipProps(stretchRate: v),
                  ),
                  const SizedBox(width: 14),
                  VpKnob(
                    label: 'Pitch Shift',
                    value: clip.pitchSemitones,
                    min: -12.0,
                    max: 12.0,
                    defaultValue: 0.0,
                    unit: ' st',
                    onChanged: (v) =>
                        controller.updateSelectedClipProps(pitchSemitones: v),
                  ),
                  const SizedBox(width: 14),
                  VpKnob(
                    label: 'Fade In',
                    value: clip.fadeInMs.toDouble(),
                    min: 0,
                    max: max(100.0, (clip.durationMs ~/ 2).toDouble()),
                    defaultValue: 20,
                    unit: 'ms',
                    onChanged: (v) =>
                        controller.updateSelectedClipProps(fadeInMs: v.round()),
                  ),
                  const SizedBox(width: 14),
                  VpKnob(
                    label: 'Fade Out',
                    value: clip.fadeOutMs.toDouble(),
                    min: 0,
                    max: max(100.0, (clip.durationMs ~/ 2).toDouble()),
                    defaultValue: 20,
                    unit: 'ms',
                    onChanged: (v) =>
                        controller.updateSelectedClipProps(fadeOutMs: v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('Normalize'),
                  selected: clip.normalized,
                  onSelected: (v) =>
                      controller.updateSelectedClipProps(normalized: v),
                ),
                FilterChip(
                  label: const Text('Reverse'),
                  selected: clip.reversed,
                  onSelected: (v) =>
                      controller.updateSelectedClipProps(reversed: v),
                ),
                FilterChip(
                  label: const Text('Mute Clip'),
                  selected: clip.muted,
                  onSelected: (v) => controller.updateSelectedClipProps(muted: v),
                ),
                FilterChip(
                  label: const Text('Preserve Formants'),
                  selected: clip.preserveFormants,
                  onSelected: (v) =>
                      controller.updateSelectedClipProps(preserveFormants: v),
                ),
                for (final FadeCurve curve in FadeCurve.values)
                  ChoiceChip(
                    label: Text('Fade: ${curve.label}'),
                    selected: clip.fadeInCurve == curve,
                    onSelected: (_) => controller.updateSelectedClipProps(
                      fadeInCurve: curve,
                      fadeOutCurve: curve,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'AI STEMS, HARMONY & SURGICAL RESTORATION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.muted(b),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ActionBtn(
                  icon: Icons.call_split_rounded,
                  label: 'Separate Stems',
                  onTap: controller.separateSelectedClipStems,
                ),
                _ActionBtn(
                  icon: Icons.people_alt_rounded,
                  label: 'AI Harmony (+3rd)',
                  onTap: controller.generateHarmonyForSelectedClip,
                ),
                _ActionBtn(
                  icon: Icons.subtitles_off_rounded,
                  label: 'Cut "Um/Uh" Fillers',
                  onTap: controller.cutFillerWordsFromSelectedClip,
                ),
                for (final String pass in const [
                  'De-click',
                  'De-plosive',
                  'De-breath',
                  'De-hum 50/60Hz',
                  'De-clip',
                ])
                  ActionChip(
                    avatar: const Icon(
                      Icons.healing_rounded,
                      size: 13,
                      color: AppColors.accentBright,
                    ),
                    label: Text(
                      pass,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () =>
                        controller.applyRestorationToSelectedClip(pass),
                  ),
              ],
            ),
          ],
        ],
      );
    });
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: AppRadius.button,
          color: AppColors.surfaceAlt(b),
          border: Border.all(color: AppColors.border(b)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.accentBright),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── TAB 1: TRACK FX & VOICE CHANGERS ─────────────────────────────

class _TrackFxInspectorTab extends StatelessWidget {
  const _TrackFxInspectorTab({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Obx(() {
      final MixTrack? track = controller.selectedTrack;
      if (track == null) return const SizedBox.shrink();

      return ListView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: [
          // Track mixing strip (Pan, Reverb Send, Delay Send, Phase, Auto-Duck)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                VpKnob(
                  label: 'Pan',
                  value: track.pan * 100.0,
                  min: -100.0,
                  max: 100.0,
                  defaultValue: 0.0,
                  unit: '%',
                  onChanged: (v) =>
                      controller.updateTrackProps(track.id, pan: v / 100.0),
                ),
                const SizedBox(width: 14),
                VpKnob(
                  label: 'Reverb Send',
                  value: track.reverbSend * 100.0,
                  min: 0.0,
                  max: 100.0,
                  defaultValue: 10.0,
                  unit: '%',
                  onChanged: (v) =>
                      controller.updateTrackProps(track.id, reverbSend: v / 100.0),
                ),
                const SizedBox(width: 14),
                VpKnob(
                  label: 'Delay Send',
                  value: track.delaySend * 100.0,
                  min: 0.0,
                  max: 100.0,
                  defaultValue: 0.0,
                  unit: '%',
                  onChanged: (v) =>
                      controller.updateTrackProps(track.id, delaySend: v / 100.0),
                ),
                const SizedBox(width: 14),
                FilterChip(
                  label: const Text('Ø Phase Invert'),
                  selected: track.phaseInverted,
                  onSelected: (v) =>
                      controller.updateTrackProps(track.id, phaseInverted: v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Auto-Duck Music'),
                  selected: track.autoDuck.enabled,
                  onSelected: (v) =>
                      controller.updateTrackProps(track.id, autoDuckEnabled: v),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(
                    Icons.timeline_rounded,
                    size: 14,
                    color: AppColors.accentBright,
                  ),
                  label: const Text('Write Ducking Curve'),
                  onPressed: () =>
                      controller.generateAutoDuckAutomation(track.id),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 1-Tap Voice Changer Macro Presets
          Text(
            'VOICE CHANGER MACRO PRESETS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.muted(b),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final VoiceChangerPreset preset in VoiceChangerPreset.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      avatar: Icon(preset.icon, size: 15, color: AppColors.accentBright),
                      label: Text(
                        preset.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () =>
                          controller.applyVoiceChangerToSelectedTrack(preset),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // FX Chain Header + Add Effect button
          Row(
            children: [
              Text(
                'INSERT FX CHAIN (${track.fxChain.length}/6)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted(b),
                ),
              ),
              const Spacer(),
              PopupMenuButton<FxType>(
                tooltip: 'Add Insert Effect',
                onSelected: controller.addFxToSelectedTrack,
                itemBuilder: (_) => [
                  for (final FxType ft in FxType.values)
                    PopupMenuItem(
                      value: ft,
                      child: Row(
                        children: [
                          Icon(ft.icon, size: 16, color: AppColors.accentBright),
                          const SizedBox(width: 8),
                          Text(ft.title),
                        ],
                      ),
                    ),
                ],
                child: const Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        size: 15, color: AppColors.accentBright),
                    SizedBox(width: 4),
                    Text(
                      'Add FX',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentBright,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final FxSlot slot in track.fxChain)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: AppRadius.button,
                color: AppColors.surfaceAlt(b),
                border: Border.all(color: AppColors.border(b)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(slot.type.icon, size: 16, color: AppColors.accentBright),
                      const SizedBox(width: 6),
                      Text(
                        slot.type.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: slot.enabled,
                        onChanged: (v) =>
                            controller.updateTrackFxSlot(slot.id, enabled: v),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            controller.removeFxFromSelectedTrack(slot.id),
                        icon: const Icon(Icons.close_rounded, size: 16),
                      ),
                    ],
                  ),
                  if (slot.type == FxType.eq8)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: VpEqCanvas(
                        height: 118,
                        bandFreqsHz: const [80, 220, 650, 2500, 6000, 12000],
                        bandLabels: const [
                          '80Hz',
                          '220Hz',
                          '650Hz',
                          '2.5k',
                          '6k',
                          '12k',
                        ],
                        bandGainsDb: [
                          slot.params['lowShelfDb'] ?? 0.0,
                          slot.params['lowMidDb'] ?? 0.0,
                          slot.params['midDb'] ?? 0.0,
                          slot.params['presenceDb'] ?? 1.5,
                          slot.params['brillianceDb'] ?? 0.5,
                          slot.params['airShelfDb'] ?? 1.0,
                        ],
                        onBandChanged: (idx, gainDb) {
                          const List<String> keys = [
                            'lowShelfDb',
                            'lowMidDb',
                            'midDb',
                            'presenceDb',
                            'brillianceDb',
                            'airShelfDb',
                          ];
                          if (idx >= 0 && idx < keys.length) {
                            controller.updateTrackFxSlot(
                              slot.id,
                              paramUpdates: {keys[idx]: gainDb},
                            );
                          }
                        },
                      ),
                    )
                  else if (slot.type == FxType.reverb)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: VpXyPad(
                              xLabel: 'Room Size',
                              yLabel: 'Damping',
                              x: slot.params['roomSize'] ?? 0.5,
                              y: slot.params['damping'] ?? 0.45,
                              height: 92,
                              onChanged: (nx, ny) => controller.updateTrackFxSlot(
                                slot.id,
                                paramUpdates: {
                                  'roomSize': nx,
                                  'damping': ny,
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          VpKnob(
                            label: 'Wet/Dry',
                            value: slot.wetDry * 100.0,
                            min: 0,
                            max: 100,
                            defaultValue: 35,
                            unit: '%',
                            onChanged: (v) => controller.updateTrackFxSlot(
                              slot.id,
                              wetDry: v / 100.0,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          VpKnob(
                            label: 'Wet/Dry',
                            value: slot.wetDry * 100.0,
                            min: 0,
                            max: 100,
                            defaultValue: 100,
                            unit: '%',
                            onChanged: (v) => controller.updateTrackFxSlot(
                              slot.id,
                              wetDry: v / 100.0,
                            ),
                          ),
                          for (final MapEntry<String, double> entry
                              in slot.params.entries) ...[
                            const SizedBox(width: 12),
                            VpKnob(
                              label: entry.key,
                              value: entry.value,
                              min: _paramMin(entry.key),
                              max: _paramMax(entry.key),
                              defaultValue: entry.value,
                              onChanged: (v) => controller.updateTrackFxSlot(
                                slot.id,
                                paramUpdates: {entry.key: v},
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }

  static double _paramMin(String key) {
    if (key.contains('Db') || key.contains('Gain')) return -24.0;
    if (key.contains('threshold')) return -60.0;
    if (key.contains('Hz') || key.contains('cutoff')) return 20.0;
    return 0.0;
  }

  static double _paramMax(String key) {
    if (key.contains('Db') || key.contains('Gain')) return 24.0;
    if (key.contains('threshold')) return 0.0;
    if (key.contains('Hz') || key.contains('cutoff')) return 16000.0;
    if (key.contains('Ms')) return 1000.0;
    if (key.contains('ratio')) return 20.0;
    return 1.0;
  }
}

// ───────────────────────────── TAB 2: MASTER BUS & SPECTRUM ─────────────────────────────

class _MasterBusInspectorTab extends StatelessWidget {
  const _MasterBusInspectorTab({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final MasterBusConfig master = controller.project.value.master;
      final List<double> spectrum = controller.engine.spectrum24.toList();

      return ListView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: [
          VpSpectrumAnalyzer(
            bands: spectrum,
            correlation: controller.engine.correlation.value,
            height: 64,
          ),
          const SizedBox(height: AppSpacing.xs),
          VpEqCanvas(
            height: 112,
            bandGainsDb: [
              master.eqLowGainDb,
              master.eqLowMidGainDb,
              master.eqMidGainDb,
              master.eqHighMidGainDb,
              master.eqAirGainDb,
            ],
            onBandChanged: (idx, gain) {
              switch (idx) {
                case 0:
                  controller.updateMasterBus(eqLowGainDb: gain);
                case 1:
                  controller.updateMasterBus(eqLowMidGainDb: gain);
                case 2:
                  controller.updateMasterBus(eqMidGainDb: gain);
                case 3:
                  controller.updateMasterBus(eqHighMidGainDb: gain);
                case 4:
                  controller.updateMasterBus(eqAirGainDb: gain);
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Loudness Target Preset chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final LufsPreset preset in LufsPreset.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        '${preset.label} (${preset.targetLufs.toStringAsFixed(0)} LUFS)',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: master.lufsPreset == preset,
                      onSelected: (_) =>
                          controller.updateMasterBus(lufsPreset: preset),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Master Bus Knobs + 5-Band Parametric EQ
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                VpKnob(
                  label: 'Master Gain',
                  value: master.volumeDb,
                  min: -24.0,
                  max: 12.0,
                  defaultValue: 0.0,
                  unit: ' dB',
                  onChanged: (v) => controller.updateMasterBus(volumeDb: v),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: 'Stereo Width',
                  value: master.stereoWidth * 100.0,
                  min: 0.0,
                  max: 200.0,
                  defaultValue: 100.0,
                  unit: '%',
                  onChanged: (v) =>
                      controller.updateMasterBus(stereoWidth: v / 100.0),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: 'True-Peak',
                  value: master.limiterCeilingDb,
                  min: -6.0,
                  max: -0.1,
                  defaultValue: -1.0,
                  unit: ' dBTP',
                  onChanged: (v) =>
                      controller.updateMasterBus(limiterCeilingDb: v),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: '80 Hz Sub',
                  value: master.eqLowGainDb,
                  min: -12.0,
                  max: 12.0,
                  defaultValue: 0.0,
                  unit: ' dB',
                  onChanged: (v) => controller.updateMasterBus(eqLowGainDb: v),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: '250 Hz Body',
                  value: master.eqLowMidGainDb,
                  min: -12.0,
                  max: 12.0,
                  defaultValue: 0.0,
                  unit: ' dB',
                  onChanged: (v) =>
                      controller.updateMasterBus(eqLowMidGainDb: v),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: '1 kHz Mid',
                  value: master.eqMidGainDb,
                  min: -12.0,
                  max: 12.0,
                  defaultValue: 0.0,
                  unit: ' dB',
                  onChanged: (v) => controller.updateMasterBus(eqMidGainDb: v),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: '4 kHz Presence',
                  value: master.eqHighMidGainDb,
                  min: -12.0,
                  max: 12.0,
                  defaultValue: 0.0,
                  unit: ' dB',
                  onChanged: (v) =>
                      controller.updateMasterBus(eqHighMidGainDb: v),
                ),
                const SizedBox(width: 12),
                VpKnob(
                  label: '12 kHz Air',
                  value: master.eqAirGainDb,
                  min: -12.0,
                  max: 12.0,
                  defaultValue: 0.0,
                  unit: ' dB',
                  onChanged: (v) => controller.updateMasterBus(eqAirGainDb: v),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ───────────────────────────── TAB 3: ROYALTY-FREE LIBRARY ─────────────────────────────

class _LibraryInspectorTab extends StatelessWidget {
  const _LibraryInspectorTab({required this.controller});
  final MixController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: [
        Text(
          '1-TAP CREATOR USE-CASE PRESETS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.muted(b),
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final UseCasePreset uc in UseCasePreset.defaults)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(uc.icon, size: 15, color: AppColors.accentBright),
                    label: Text(
                      uc.title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    tooltip: uc.subtitle,
                    onPressed: () => controller.applyUseCasePreset(uc),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'BUILT-IN ROYALTY-FREE LOOPS & BEDS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.muted(b),
          ),
        ),
        const SizedBox(height: 6),
        for (final BuiltInLoopAsset loop in BuiltInLoopAsset.all)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: AppRadius.button,
              color: AppColors.surfaceAlt(b),
              border: Border.all(color: AppColors.border(b)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  size: 18,
                  color: AppColors.accentBright,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loop.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${loop.category} · ${loop.bpm.round()} BPM · ${(loop.durationMs / 1000).toStringAsFixed(0)}s',
                        style: TextStyle(fontSize: 10.5, color: AppColors.muted(b)),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => controller.insertBuiltInLoop(loop),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text('Insert', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
