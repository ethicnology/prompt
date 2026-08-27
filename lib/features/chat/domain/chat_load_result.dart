import 'chat_message.dart';

sealed class ChatLoadResult {
  const ChatLoadResult();
}

class ChatLoaded extends ChatLoadResult {
  const ChatLoaded(
    this.messages, {
    this.hasMore = false,
    this.cursorUnavailable = false,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final bool cursorUnavailable;
}

class ChatOlderLoaded extends ChatLoadResult {
  const ChatOlderLoaded(
    this.messages, {
    required this.hasMore,
    this.cursorUnavailable = false,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final bool cursorUnavailable;
}

class ChatLoadFailed extends ChatLoadResult {
  const ChatLoadFailed(this.failure);

  final ChatFailure failure;
}

enum ChatFailure { unauthorized, unavailable, unexpectedResponse }

extension ChatFailureMessage on ChatFailure {
  String get message {
    return switch (this) {
      ChatFailure.unauthorized => 'The server rejected the saved credentials.',
      ChatFailure.unavailable =>
        'Prompt cannot reach the server. Check WireGuard or Tailscale and try again.',
      ChatFailure.unexpectedResponse =>
        'The server returned a conversation Prompt could not read.',
    };
  }
}
