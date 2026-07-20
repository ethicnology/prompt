enum ChatMessageRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.text,
  });

  final String id;
  final ChatMessageRole role;
  final DateTime createdAt;
  final String text;
}
