import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';

void main() {
  test('accepts unknown message fields without losing known content', () {
    final record = OpenCodeMessageRecord.fromJson({
      'futureField': {'ignored': true},
      'info': {
        'id': 'message-1',
        'role': 'assistant',
        'time': {'created': 42},
      },
      'parts': [
        {'type': 'text', 'text': 'hello'},
      ],
    });

    expect(record.text, 'hello');
    expect(record.id, 'message-1');
  });

  test('rejects a message with missing required fields', () {
    expect(
      () => OpenCodeMessageRecord.fromJson({'info': {}, 'parts': []}),
      throwsFormatException,
    );
  });

  test('keeps an unknown tool in the bounded generic presentation', () {
    final record = OpenCodeMessageRecord.fromJson({
      'info': {
        'id': 'message-1',
        'role': 'assistant',
        'time': {'created': 42},
      },
      'parts': [
        {
          'id': 'tool-1',
          'type': 'tool',
          'tool': 'future_tool',
          'state': {
            'input': {'value': 'known input'},
            'output': 'result',
          },
        },
      ],
    });

    final tool = record.details.single as OpenCodeToolRecord;
    final presentation =
        tool.presentation! as OpenCodeGenericToolPresentationRecord;
    expect(presentation.blocks.first.text, contains('known input'));
    expect(presentation.blocks.last.text, 'result');
  });

  test('parses artifact records with optional fields absent', () {
    final todo = OpenCodeTodoRecord.fromJson({
      'content': 'Review',
      'status': 'pending',
      'priority': 'medium',
    });
    final diff = OpenCodeFileDiffRecord.fromJson({
      'additions': 2,
      'deletions': 1,
    });

    expect(todo.id, isNull);
    expect(diff.file, isEmpty);
    expect(diff.patch, isEmpty);
  });
}
