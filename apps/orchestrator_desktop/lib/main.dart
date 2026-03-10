import 'package:flutter/material.dart';

import 'src/ui/graph_editor_page.dart';

void main() {
  runApp(const OrchestrationGraphApp());
}

class OrchestrationGraphApp extends StatelessWidget {
  const OrchestrationGraphApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.light(useMaterial3: true);
    return MaterialApp(
      title: 'WhiteOps Оркестратор',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6E6E)),
        scaffoldBackgroundColor: const Color(0xFFEAF0F4),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        textTheme: base.textTheme.apply(fontFamily: 'Segoe UI'),
      ),
      home: const GraphEditorPage(),
    );
  }
}
