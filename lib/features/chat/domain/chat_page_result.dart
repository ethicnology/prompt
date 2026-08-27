import 'chat_load_result.dart';
import 'chat_message.dart';

/// Read-only history projection exposed by the repository.
class ChatHistoryState {
  const ChatHistoryState({
    required this.messages,
    required this.hasMore,
    this.cursorUnavailable = false,
    this.loadingOlder = false,
    this.failure,
  });

  final List<ChatMessage> messages;
  final bool hasMore;

  /// The server returned a full page but supplied no usable cursor.
  final bool cursorUnavailable;
  bool get limitedByServer => cursorUnavailable;
  final bool loadingOlder;
  final ChatFailure? failure;
}
