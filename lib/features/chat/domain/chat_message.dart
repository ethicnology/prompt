enum ChatMessageRole { user, assistant }

sealed class ChatMessageDetail {
  const ChatMessageDetail({required this.id});

  final String id;
}

class ChatReasoningDetail extends ChatMessageDetail {
  const ChatReasoningDetail({required super.id, required this.text});

  final String text;
}

class ChatToolDetail extends ChatMessageDetail {
  const ChatToolDetail({
    required super.id,
    required this.tool,
    required this.status,
    this.input,
    this.output,
    this.error,
  });

  final String tool;
  final String status;
  final String? input;
  final String? output;
  final String? error;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.text,
    this.details = const [],
    this.error,
  });

  final String id;
  final ChatMessageRole role;
  final DateTime createdAt;
  final String text;
  final List<ChatMessageDetail> details;
  final String? error;
}
