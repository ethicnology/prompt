import 'package:file_picker/file_picker.dart';

/// Selects a user-owned GGML model only after an explicit UI action.
abstract interface class VoiceModelPicker {
  Future<String?> pickModelFromUserAction();
}

class FilePickerVoiceModelPicker implements VoiceModelPicker {
  const FilePickerVoiceModelPicker();

  @override
  Future<String?> pickModelFromUserAction() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bin', 'gguf'],
      allowMultiple: false,
    );
    return result?.files.single.path;
  }
}
