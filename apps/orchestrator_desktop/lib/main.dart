import 'package:flutter/material.dart';

import 'src/ui/graph_editor_page.dart';
import 'src/ui/make_tokens.dart';

void main() {
  runApp(const OrchestrationGraphApp());
}

class OrchestrationGraphApp extends StatelessWidget {
  const OrchestrationGraphApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.light(useMaterial3: true);
    return MaterialApp(
      title: 'WhiteOps Orchestrator',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: MakeTokens.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: MakeTokens.shellBg,
        cardTheme: CardThemeData(
          elevation: 0,
          color: MakeTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MakeTokens.radiusLg),
            side: const BorderSide(color: MakeTokens.border),
          ),
        ),
        textTheme: base.textTheme.apply(
          fontFamily: 'Segoe UI',
          bodyColor: MakeTokens.text,
          displayColor: MakeTokens.text,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.72),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: MakeTokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: MakeTokens.primary, width: 1.2),
          ),
        ),
      ),
      home: const GraphEditorPage(),
    );
  }
}
