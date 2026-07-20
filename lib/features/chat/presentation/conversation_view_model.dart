import 'package:flutter/foundation.dart';

import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../data/chat_repository.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';

sealed class ConversationUiState {
  const ConversationUiState();
}

class ConversationLoading extends ConversationUiState {
  const ConversationLoading();
}

class ConversationReady extends ConversationUiState {
  const ConversationReady(this.messages);

  final List<ChatMessage> messages;
}

class ConversationError extends ConversationUiState {
  const ConversationError(this.failure);

  final ChatFailure failure;
}

class ConversationViewModel extends ValueNotifier<ConversationUiState> {
  ConversationViewModel(this._repository) : super(const ConversationLoading());

  final ChatRepository _repository;

  Future<void> load(ServerProfile profile, OpenCodeSession session) async {
    value = const ConversationLoading();
    final result = await _repository.load(profile, session);
    switch (result) {
      case ChatLoaded(:final messages):
        value = ConversationReady(messages);
      case ChatLoadFailed(:final failure):
        value = ConversationError(failure);
    }
  }
}
