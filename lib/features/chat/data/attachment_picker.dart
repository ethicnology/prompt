import 'package:file_picker/file_picker.dart';

import '../domain/prompt_attachment.dart';

/// Platform file selection is isolated here so presentation never invokes a
/// platform plugin directly. The picker is called only from a user gesture.
abstract interface class AttachmentPicker {
  Future<AttachmentPickResult> pick();
}

class FilePickerAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return const AttachmentPickCancelled();
    }

    final files = result.files;
    if (files.length > PromptAttachment.maxAttachmentCount) {
      _releasePlatformFiles(files);
      return const AttachmentPickRejected('Select up to 5 attachments.');
    }

    var totalBytes = 0;
    final attachments = <PromptAttachment>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _releaseAttachments(attachments);
        _releasePlatformFiles(files);
        return const AttachmentPickRejected(
          'The selected file could not be read into memory.',
        );
      }
      if (bytes.lengthInBytes > PromptAttachment.maxBytesPerAttachment) {
        _releaseAttachments(attachments);
        _releasePlatformFiles(files);
        return const AttachmentPickRejected(
          'Each attachment must be 10 MiB or smaller.',
        );
      }
      totalBytes += bytes.lengthInBytes;
      if (totalBytes > PromptAttachment.maxTotalBytes) {
        _releaseAttachments(attachments);
        _releasePlatformFiles(files);
        return const AttachmentPickRejected(
          'Attachments together must be 25 MiB or smaller.',
        );
      }
      attachments.add(PromptAttachment(name: file.name, bytes: bytes));
    }
    return AttachmentsPicked(List.unmodifiable(attachments));
  }
}

void _releaseAttachments(Iterable<PromptAttachment> attachments) {
  for (final attachment in attachments) {
    attachment.release();
  }
}

void _releasePlatformFiles(Iterable<PlatformFile> files) {
  for (final file in files) {
    file.bytes?.fillRange(0, file.bytes!.length, 0);
  }
}
