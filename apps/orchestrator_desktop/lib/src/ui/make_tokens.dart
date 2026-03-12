import 'package:flutter/material.dart';

class MakeTokens {
  static const Color shellBg = Color(0xFFEFF4FB);
  static const Color shellBg2 = Color(0xFFDCE8FB);
  static const Color shellAccent = Color(0xFFC9E5EA);
  static const Color surface = Color(0xECFFFFFF);
  static const Color surfaceStrong = Color(0xF7FFFFFF);
  static const Color border = Color(0x332F497C);
  static const Color text = Color(0xFF122039);
  static const Color muted = Color(0xFF50607C);
  static const Color primary = Color(0xFF0A84FF);
  static const Color success = Color(0xFF14B87A);
  static const Color warning = Color(0xFFF5A524);
  static const Color danger = Color(0xFFF04C63);

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;

  static const List<BoxShadow> softShadow = <BoxShadow>[
    BoxShadow(color: Color(0x261C2A4C), blurRadius: 22, offset: Offset(0, 10)),
  ];

  static Color edgeColor(String relationType) {
    switch (relationType) {
      case 'manager_to_worker':
        return const Color(0xFF0A84FF);
      case 'dependency':
        return const Color(0xFF14B87A);
      case 'feedback':
        return const Color(0xFFF5A524);
      case 'peer':
        return const Color(0xFFF04C63);
      default:
        return const Color(0xFF6B7EA0);
    }
  }

  static ({Color fg, Color bg, Color border}) statusPalette(String status) {
    switch (status) {
      case 'ready':
        return (
          fg: const Color(0xFF0E5D95),
          bg: const Color(0x33278BD6),
          border: const Color(0x66348FCB),
        );
      case 'running':
        return (
          fg: const Color(0xFF0F7D54),
          bg: const Color(0x2E14B87A),
          border: const Color(0x5914B87A),
        );
      case 'retrying':
        return (
          fg: const Color(0xFF8B5D12),
          bg: const Color(0x33F5A524),
          border: const Color(0x66F5A524),
        );
      case 'completed':
        return (
          fg: const Color(0xFF0F7D54),
          bg: const Color(0x2E14B87A),
          border: const Color(0x5914B87A),
        );
      case 'failed':
        return (
          fg: const Color(0xFF9E2A3E),
          bg: const Color(0x33F04C63),
          border: const Color(0x66F04C63),
        );
      case 'canceled':
      case 'skipped':
        return (
          fg: const Color(0xFF6D5C3D),
          bg: const Color(0x26A39063),
          border: const Color(0x59A39063),
        );
      default:
        return (
          fg: const Color(0xFF586C8B),
          bg: const Color(0x1F5E7BAA),
          border: const Color(0x445E7BAA),
        );
    }
  }

  static ({Color bg, Color ring}) rolePalette(String role) {
    switch (role) {
      case 'manager':
        return (bg: const Color(0x332A7CE8), ring: const Color(0xAA2A7CE8));
      case 'reviewer':
        return (bg: const Color(0x3314B87A), ring: const Color(0xAA14B87A));
      default:
        return (bg: const Color(0x330A84FF), ring: const Color(0xAA0A84FF));
    }
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({required this.child, super.key, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: MakeTokens.surface,
        borderRadius: BorderRadius.circular(MakeTokens.radiusLg),
        border: Border.all(color: MakeTokens.border),
        boxShadow: MakeTokens.softShadow,
      ),
      child: child,
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    super.key,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MakeTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(MakeTokens.radiusMd),
        border: Border.all(color: MakeTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MakeTokens.text,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.value,
    super.key,
    this.icon,
    this.bg,
    this.fg,
  });

  final String label;
  final String value;
  final Widget? icon;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final foreground = fg ?? const Color(0xFF324A70);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MakeTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 6)],
          Text(
            '$label: $value',
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
