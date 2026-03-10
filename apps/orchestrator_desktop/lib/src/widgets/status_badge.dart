import 'package:flutter/material.dart';

import '../models/orchestrator_models.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final palette = _statusPalette(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        taskStatusLabel(status),
        style: TextStyle(
          color: palette.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  _BadgePalette _statusPalette(String value) {
    switch (value) {
      case 'queued':
        return const _BadgePalette(
          foreground: Color(0xFF495A73),
          background: Color(0xFFE8EEF7),
          border: Color(0xFFC6D6ED),
        );
      case 'planning':
        return const _BadgePalette(
          foreground: Color(0xFF195D7C),
          background: Color(0xFFDDF3FF),
          border: Color(0xFF9BD7F3),
        );
      case 'running':
        return const _BadgePalette(
          foreground: Color(0xFF105A4F),
          background: Color(0xFFDCF8F1),
          border: Color(0xFF9AE4D2),
        );
      case 'cancel_requested':
        return const _BadgePalette(
          foreground: Color(0xFF745003),
          background: Color(0xFFFFF3D5),
          border: Color(0xFFFFD888),
        );
      case 'completed':
        return const _BadgePalette(
          foreground: Color(0xFF0F6A22),
          background: Color(0xFFDCFAE2),
          border: Color(0xFF9EE5AD),
        );
      case 'failed':
        return const _BadgePalette(
          foreground: Color(0xFF8A1B1B),
          background: Color(0xFFFFE4E4),
          border: Color(0xFFF7A8A8),
        );
      case 'canceled':
        return const _BadgePalette(
          foreground: Color(0xFF6F4B09),
          background: Color(0xFFFFECCD),
          border: Color(0xFFFFCB80),
        );
      default:
        return const _BadgePalette(
          foreground: Color(0xFF4B4E57),
          background: Color(0xFFEEF0F4),
          border: Color(0xFFD2D6E0),
        );
    }
  }
}

class _BadgePalette {
  const _BadgePalette({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}
