import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Vertical level meter with RMS body, falling peak-hold line and clip LED.
class VpDbMeter extends StatefulWidget {
  const VpDbMeter({super.key, required this.rms, required this.peak, this.clip = false, this.height = 120, this.label});
  final double rms, peak;
  final bool clip;
  final double height;
  final String? label;

  @override
  State<VpDbMeter> createState() => _VpDbMeterState();
}

class _VpDbMeterState extends State<VpDbMeter> {
  double _hold = 0;
  double _smooth = 0;

  @override
  void didUpdateWidget(covariant VpDbMeter old) {
    super.didUpdateWidget(old);
    _hold = widget.peak > _hold ? widget.peak : (_hold - 0.012).clamp(0.0, 1.0);
    final double t = widget.rms;
    _smooth = t > _smooth ? t : _smooth + (t - _smooth) * 0.25;
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.clip ? AppColors.record : AppColors.border(b),
            boxShadow: widget.clip ? [BoxShadow(color: AppColors.record.withValues(alpha: 0.7), blurRadius: 8)] : null,
          ),
        ),
        SizedBox(
          width: 14,
          height: widget.height,
          child: CustomPaint(painter: _DbPainter(_smooth, _hold, AppColors.border(b))),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 6),
          Text(widget.label!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted(b))),
        ],
      ],
    );
  }
}

class _DbPainter extends CustomPainter {
  _DbPainter(this.rms, this.hold, this.track);
  final double rms, hold;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(bg, Paint()..color = track.withValues(alpha: 0.7));
    canvas.save();
    canvas.clipRRect(bg);
    final double h = size.height * rms.clamp(0, 1);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - h, size.width, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppColors.success, AppColors.accentBright, AppColors.warning, AppColors.record],
          stops: [0, 0.62, 0.88, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
    final double py = size.height * (1 - hold.clamp(0, 1));
    canvas.drawLine(Offset(0, py), Offset(size.width, py), Paint()..color = Colors.white..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _DbPainter o) => o.rms != rms || o.hold != hold;
}

/// Scrolling mirrored waveform of the live signal while recording.
class VpLiveWave extends StatelessWidget {
  const VpLiveWave({super.key, required this.bars, required this.active, this.height = 120});
  final List<double> bars;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border(b)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: CustomPaint(
        size: Size.infinite,
        painter: _LiveWavePainter(List<double>.of(bars), active, AppColors.border(b)),
      ),
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  _LiveWavePainter(this.bars, this.active, this.mid);
  final List<double> bars;
  final bool active;
  final Color mid;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), Paint()..color = mid..strokeWidth = 1);
    if (bars.isEmpty) return;
    final double step = size.width / bars.length;
    final Paint p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (step * 0.62).clamp(1.5, 6)
      ..shader = AppColors.signature.createShader(Offset.zero & size);
    for (int i = 0; i < bars.length; i++) {
      final double h = (bars[i] * size.height * 0.5).clamp(1.5, size.height / 2);
      final double fade = 0.25 + 0.75 * (i / bars.length);
      p.color = Colors.white.withValues(alpha: active ? fade : 0.35);
      final double x = step * i + step / 2;
      canvas.drawLine(Offset(x, cy - h), Offset(x, cy + h), p);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter o) => true;
}
