import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';

void main() {
  test('release overwrites and drops memory-only attachment bytes', () {
    final bytes = Uint8List.fromList([4, 5, 6]);
    final attachment = PromptAttachment(name: 'private.txt', bytes: bytes);

    attachment.release();

    expect(attachment.isReleased, isTrue);
    expect(bytes, everyElement(0));
    expect(() => attachment.bytes, throwsStateError);
  });
}
