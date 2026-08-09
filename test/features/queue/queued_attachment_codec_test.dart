import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/queue/data/queued_attachment_codec.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';

void main() {
  test('round-trips attachments through the queue column', () {
    final encoded = encodeQueuedAttachments([
      QueuedAttachment(
        name: 'notes.txt',
        mediaType: 'text/plain',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ]);

    final decoded = decodeQueuedAttachments(encoded);

    expect(decoded, hasLength(1));
    expect(decoded.single.name, 'notes.txt');
    expect(decoded.single.mediaType, 'text/plain');
    expect(decoded.single.bytes, [1, 2, 3]);
  });

  test('encodes nothing when no file is attached', () {
    expect(encodeQueuedAttachments(const []), isNull);
    expect(decodeQueuedAttachments(null), isEmpty);
  });

  test('drops malformed entries instead of failing the whole queue', () {
    expect(decodeQueuedAttachments('not json'), isEmpty);
    expect(
      decodeQueuedAttachments(
        jsonEncode([
          {'name': 'x'},
        ]),
      ),
      isEmpty,
    );
  });
}
