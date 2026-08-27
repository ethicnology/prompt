import 'opencode_chat_api.dart';

export 'opencode_chat_api.dart'
    show
        OpenCodeFileDiffRecord,
        OpenCodeGenericToolPresentationRecord,
        OpenCodeMessageDetailRecord,
        OpenCodeMessagePage,
        OpenCodeMessageRecord,
        OpenCodeReasoningRecord,
        OpenCodeTaskPresentationRecord,
        OpenCodeTodoPresentationItemRecord,
        OpenCodeTodoPresentationRecord,
        OpenCodeTodoRecord,
        OpenCodeToolBlockKindRecord,
        OpenCodeToolBlockRecord,
        OpenCodeToolPresentationRecord,
        OpenCodeToolRecord;

/// Stable chat data boundary used by [ChatRepository].
///
/// The implementation remains private to the data layer; this façade keeps
/// the existing constructor and method surface unchanged for callers.
class OpenCodeChatService extends OpenCodeChatApi {
  OpenCodeChatService(super.transport);
}
