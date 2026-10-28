import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Studio dB fader with tick scale and double-tap reset to 0.0 dB unity gain.
class VpFader extends StatelessWidget {
  const VpFader({
    super.key,
    required this.valueDb,
    required this.onChanged,
    this.minDb = -60.0,
    this.maxDb = 12.0,
    this.defaultDb = 0.0,
    this.vertical = false,
    this.label,
    this.length = 160,
  });

  final double valueDb;
  final ValueChanged<double> onChanged;
  final double minDb;
  final double maxDb;
  final double defaultDb;
  final bool vertical;
  final String? label;
  final double length;

  String get _dbLabel {
    if (valueDb <= minDb + 0.5) return '-∞ dB';
    final String sign = valueDb > 0 ? '+' : '';
    return '$sign${valueDb.toStringAsFixed(1)} dB';
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    final double normalized =
        ((valueDb - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);

    if (vertical) {
      return GestureDetector(
        onDoubleTap: () => onChanged(defaultDb),
        onVerticalDragUpdate: (d) {
          final double deltaDb = (-d.delta.dy / length) * (maxDb - minDb);
          onChanged((valueDb + deltaDb).clamp(minDb, maxDb));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(label!, style: t.labelSmall),
              ),
            SizedBox(
              width: 38,
              height: length,
              child: CustomPaint(
                painter: _FaderPainter(
                  normalized: normalized,
                  unityNormalized: (0.0 - minDb) / (maxDb - minDb),
                  vertical: true,
                  brightness: b,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _dbLabel,
              style: t.labelSmall?.copyWith(
                fontSize: 10,
                color: AppColors.accentBright,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onDoubleTap: () => onChanged(defaultDb),
      onHorizontalDragUpdate: (d) {
        final double deltaDb = (d.delta.dx / length) * (maxDb - minDb);
        onChanged((valueDb + deltaDb).clamp(minDb, maxDb));
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label!, style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: length,
            height: 24,
            child: CustomPaint(
              painter: _FaderPainter(
                normalized: normalized,
                unityNormalized: (0.0 - minDb) / (maxDb - minDb),
                vertical: false,
                brightness: b,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: AppRadius.chip,
              color: AppColors.surfaceAlt(b),
            ),
            child: Text(
              _dbLabel,
              style: t.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accentBright,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaderPainter extends CustomPainter {
  _FaderPainter({
    required this.normalized,
    required this.unityNormalized,
    required this.vertical,
    required this.brightness,
  });

  final double normalized;
  final double unityNormalized;
  final bool vertical;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint groove = Paint()
      ..color = AppColors.border(brightness)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final Paint fill = Paint()
      ..shader = AppColors.signature.createShader(Offset.zero & size)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final Paint tickPaint = Paint()
      ..color = AppColors.muted(brightness).withValues(alpha: 0.45)
      ..strokeWidth = 1.2;

    if (vertical) {
      final double cx = size.width / 2;
      const double pad = 10;
      final double span = size.height - pad * 2;
      final double thumbY = size.height - pad - normalized * span;
      final double unityY = size.height - pad - unityNormalized * span;

      // Unity 0 dB tick
      canvas.drawLine(Offset(4, unityY), Offset(size.width - 4, unityY), tickPaint);

      // Groove & active fill
      canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), groove);
      canvas.drawLine(Offset(cx, size.height - pad), Offset(cx, thumbY), fill);

      // Studio fader cap
      final RRect cap = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, thumbY), width: 24, height: 12),
        const Radius.circular(4),
      );
      canvas.drawRRect(cap, Paint()..shader = AppColors.signature.createShader(cap.outerRect));
      canvas.drawLine(
        Offset(cx - 7, thumbY),
        Offset(cx + 7, thumbY),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    } else {
      final double cy = size.height / 2;
      const double pad = 8;
      final double span = size.width - pad * 2;
      final double thumbX = pad + normalized * span;
      final double unityX = pad + unityNormalized * span;

      // Unity 0 dB tick
      canvas.drawLine(Offset(unityX, 3), Offset(unityX, size.height - 3), tickPaint);

      // Groove & active fill
      canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), groove);
      canvas.drawLine(Offset(pad, cy), Offset(thumbX, cy), fill);

      // Studio fader cap
      final RRect cap = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(thumbX, cy), width: 12, height: 18),
        const Radius.circular(4),
      );
      canvas.drawRRect(cap, Paint()..shader = AppColors.signature.createShader(cap.outerRect));
      canvas.drawLine(
        Offset(thumbX, cy - 5),
        Offset(thumbX, cy + 5),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaderPainter old) =>
      old.normalized != normalized ||
      old.unityNormalized != unityNormalized ||
      old.vertical != vertical ||
      old.brightness != brightness;
}
