import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:orchestrator_desktop/main.dart';

void main() {
  testWidgets('renders redesigned graph editor shell', (tester) async {
    tester.view.physicalSize = const ui.Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const OrchestrationGraphApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Схема оркестрации'), findsOneWidget);
    expect(find.textContaining('Desktop graph editor'), findsOneWidget);
    expect(find.text('Состояние схемы'), findsOneWidget);
    expect(find.text('Палитра'), findsOneWidget);
    expect(find.text('Управление запуском'), findsOneWidget);
  });
}
