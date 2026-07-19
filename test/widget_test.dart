import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/app/prompt_app.dart';

void main() {
  testWidgets('shows the private server connection form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PromptApp());

    expect(find.text('Connect Prompt'), findsOneWidget);
    expect(find.text('Private server address'), findsOneWidget);
    expect(find.text('Test private connection'), findsOneWidget);
  });
}
