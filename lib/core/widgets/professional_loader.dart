import 'dart:math' as math;
import 'package:flutter/material.dart';

class ProfessionalLoader extends StatefulWidget {
  final double size;
  final Color? color;
  final String? label;

  const ProfessionalLoader({super.key, this.size = 48, this.color, this.label});

  @override
  State<ProfessionalLoader> createState() => _ProfessionalLoaderState();
}

class _ProfessionalLoaderState extends State<ProfessionalLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _rotation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = widget.color ??
        (isDark ? const Color(0xFF00E5FF) : const Color(0xFF4A148C));
    final secondaryColor =
        isDark ? const Color(0xFFB388FF) : const Color(0xFF00B8D4);
    final s = widget.size;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _rotation,
          builder: (_, __) {
            return CustomPaint(
              size: Size(s, s),
              painter: _CompassPainter(
                rotation: _rotation.value,
                primaryColor: accentColor,
                secondaryColor: secondaryColor,
                isDark: isDark,
              ),
            );
          },
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.label!,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double rotation;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;

  _CompassPainter({
    required this.rotation,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy);

    final ringPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.08;
    canvas.drawCircle(Offset(cx, cy), radius * 0.88, ringPaint);

    final tickPaint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30) * math.pi / 180;
      final isCardinal = i % 3 == 0;
      tickPaint.color = isCardinal
          ? primaryColor
          : primaryColor.withValues(alpha: isDark ? 0.3 : 0.2);
      final outerR = radius * 0.84;
      final innerR = radius * (isCardinal ? 0.72 : 0.78);
      canvas.drawLine(
        Offset(cx + outerR * math.sin(angle), cy - outerR * math.cos(angle)),
        Offset(cx + innerR * math.sin(angle), cy - innerR * math.cos(angle)),
        tickPaint,
      );
    }

    final textStyle = TextStyle(
      color: primaryColor.withValues(alpha: 0.6),
      fontSize: radius * 0.18,
      fontWeight: FontWeight.w700,
    );
    const cardinals = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final angle = (i * 90) * math.pi / 180;
      final textR = radius * 0.58;
      final tp = TextPainter(text: TextSpan(text: cardinals[i], style: textStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(cx + textR * math.sin(angle) - tp.width / 2, cy - textR * math.cos(angle) - tp.height / 2));
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withValues(alpha: 0.08),
          primaryColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.45));
    canvas.drawCircle(Offset(cx, cy), radius * 0.45, glowPaint);

    final dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), radius * 0.06, dotPaint);

    final needleAngle = rotation * 2 * math.pi;
    final needleLength = radius * 0.55;

    final northPaint = Paint()
      ..shader = LinearGradient(
        colors: [primaryColor, secondaryColor],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(cx - 2, cy - needleLength, 4, needleLength))
      ..strokeWidth = radius * 0.05
      ..strokeCap = StrokeCap.round;
    final northEnd = Offset(
      cx + needleLength * math.sin(needleAngle),
      cy - needleLength * math.cos(needleAngle),
    );
    canvas.drawLine(Offset(cx, cy), northEnd, northPaint);

    final southPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.25)
      ..strokeWidth = radius * 0.04
      ..strokeCap = StrokeCap.round;
    final southEnd = Offset(
      cx - (needleLength * 0.65) * math.sin(needleAngle),
      cy + (needleLength * 0.65) * math.cos(needleAngle),
    );
    canvas.drawLine(Offset(cx, cy), southEnd, southPaint);

    final tipPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(northEnd, radius * 0.05, tipPaint);
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.rotation != rotation;
}

class FullScreenLoader extends StatelessWidget {
  final String? label;
  final bool barrier;
  const FullScreenLoader({super.key, this.label, this.barrier = true});

  @override
  Widget build(BuildContext context) {
    final widget = Center(
      child: ProfessionalLoader(size: 56, label: label),
    );
    if (!barrier) return widget;
    return Material(
      color: Colors.black26,
      child: widget,
    );
  }
}
