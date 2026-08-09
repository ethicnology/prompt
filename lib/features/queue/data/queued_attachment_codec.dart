import 'dart:convert';
import 'dart:typed_data';

import '../domain/queued_prompt.dart';

/// Encodes [attachments] for the queue's `attachmentsJson` column, or returns
/// `null` when the prompt carries no file.
///
/// The encoded value contains user file content and is only ever written to
/// Prompt's encrypted local database. It must never be logged or exported.
String? encodeQueuedAttachments(List<QueuedAttachment> attachments) {
  if (attachments.isEmpty) {
    return null;
  }
  return jsonEncode([
    for (final attachment in attachments)
      {
        'name': attachment.name,
        'mediaType': attachment.mediaType,
        'base64': base64Encode(attachment.bytes),
      },
  ]);
}

/// Decodes a previously encoded `attachmentsJson` value. A malformed or
/// unreadable value yields an empty list so one corrupt row can never block
/// the whole queue from loading.
List<QueuedAttachment> decodeQueuedAttachments(String? encoded) {
  if (encoded == null || encoded.isEmpty) {
    return const <QueuedAttachment>[];
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return const <QueuedAttachment>[];
    }
    final attachments = <QueuedAttachment>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final name = entry['name'];
      final mediaType = entry['mediaType'];
      final base64Bytes = entry['base64'];
      if (name is! String || mediaType is! String || base64Bytes is! String) {
        continue;
      }
      attachments.add(
        QueuedAttachment(
          name: name,
          mediaType: mediaType,
          bytes: Uint8List.fromList(base64Decode(base64Bytes)),
        ),
      );
    }
    return List.unmodifiable(attachments);
  } on FormatException {
    return const <QueuedAttachment>[];
  }
}
