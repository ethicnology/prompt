import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stt_lab/main.dart';

void main() {
  testWidgets('shows the local comparison variants', (tester) async {
    await tester.pumpWidget(const SttLabApp());

    expect(find.text('STT LAB'), findsOneWidget);
    expect(find.text('Whisper baseline'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Record microphone'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Record microphone'), findsOneWidget);
    expect(find.text('Replay WAV'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Waiting for speech...'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Waiting for speech...'), findsOneWidget);
  });
}
