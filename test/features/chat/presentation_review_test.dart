import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
import 'package:prompt/features/chat/presentation/widgets/session_artifacts_panel.dart';
import 'package:prompt/features/chat/presentation/widgets/transcript.dart';

void main() {
  final message = ChatMessage(
    id: 'message-1',
    role: ChatMessageRole.assistant,
    createdAt: DateTime(2024),
    text: 'A readable response',
  );

  testWidgets('history control is accessible at every desktop width', (
    tester,
  ) async {
    for (final width in [900.0, 920.0, 1024.0, 1100.0]) {
      await tester.binding.setSurfaceSize(Size(width, 500));
      await tester.pumpWidget(
        MaterialApp(
          home: Transcript(
            messages: [message],
            onRefresh: () async {},
            onLoadOlder: () {},
            hasMore: true,
            loadingOlder: false,
            limitedByServer: false,
            controller: ScrollController(),
            onRevert: (_) {},
            desktop: width >= 900,
          ),
        ),
      );
      expect(find.text('Load earlier messages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('limited history is explicit and loading has live semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Transcript(
          messages: [message],
          onRefresh: () async {},
          onLoadOlder: () {},
          hasMore: false,
          loadingOlder: false,
          limitedByServer: true,
          controller: ScrollController(),
          onRevert: (_) {},
        ),
      ),
    );
    expect(find.text('History may be limited by this server'), findsOneWidget);
  });

  testWidgets(
    'large diff starts with a bounded preview and expands explicitly',
    (tester) async {
      final patch = List.generate(200, (index) => '+line $index').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: SingleChildScrollView(
                child: SessionArtifactsPanel(
                  state: SessionArtifactsReady(
                    todos: const [],
                    diffs: [
                      SessionFileDiff(
                        file: 'large.txt',
                        patch: patch,
                        additions: 200,
                        deletions: 0,
                      ),
                    ],
                  ),
                  onRefresh: ({messageId}) async {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('+line 199'), findsNothing);
      expect(find.text('Load full patch'), findsOneWidget);
      await tester.ensureVisible(find.text('Load full patch'));
      await tester.tap(find.text('Load full patch'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump();
      expect(find.text('Load full patch'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
