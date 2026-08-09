import 'dart:typed_data';

/// A file selected by the user for a prompt.
///
/// The bytes are intentionally memory-only. Call [release] as soon as the
/// selection is removed or its owning conversation leaves the foreground.
class PromptAttachment {
  factory PromptAttachment({
    required String name,
    required Uint8List bytes,
    String mediaType = 'application/octet-stream',
  }) => PromptAttachment._(name: name, bytes: bytes, mediaType: mediaType);

  PromptAttachment._({
    required this.name,
    required Uint8List this._bytes,
    required this.mediaType,
  });

  static const int maxBytesPerAttachment = 10 * 1024 * 1024;
  static const int maxAttachmentCount = 5;
  static const int maxTotalBytes = 25 * 1024 * 1024;

  final String name;
  final String mediaType;
  Uint8List? _bytes;

  int get byteCount => _bytes?.lengthInBytes ?? 0;
  bool get isReleased => _bytes == null;

  /// Only available while this attachment is owned by the active composer.
  Uint8List get bytes {
    final value = _bytes;
    if (value == null) {
      throw StateError('Attachment bytes were released.');
    }
    return value;
  }

  /// Overwrites the mutable buffer before dropping this object's reference.
  void release() {
    final value = _bytes;
    if (value == null) {
      return;
    }
    value.fillRange(0, value.length, 0);
    _bytes = null;
  }

  @override
  String toString() => 'PromptAttachment(bytes: $byteCount)';
}

sealed class AttachmentPickResult {
  const AttachmentPickResult();
}

class AttachmentsPicked extends AttachmentPickResult {
  const AttachmentsPicked(this.attachments);

  final List<PromptAttachment> attachments;
}

class AttachmentPickCancelled extends AttachmentPickResult {
  const AttachmentPickCancelled();
}

class AttachmentPickRejected extends AttachmentPickResult {
  const AttachmentPickRejected(this.message);

  final String message;
}
