import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../capabilities/capabilities.dart';
import '../../../voice/voice.dart';
import '../../domain/prompt_attachment.dart';

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.command,
    required this.commands,
    required this.attachments,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onSelectCommand,
    required this.onSubmit,
    this.voiceState,
    this.hasSelectedVoiceModel,
    this.onVoicePressed,
    this.executionLabel,
    this.onSelectExecution,
    super.key,
  });

  final TextEditingController controller;
  final OpenCodeSlashCommand? command;
  final List<OpenCodeSlashCommand> commands;
  final ValueListenable<List<PromptAttachment>> attachments;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<PromptAttachment> onRemoveAttachment;
  final Future<void> Function(List<OpenCodeSlashCommand>) onSelectCommand;
  final Future<void> Function() onSubmit;
  final ValueListenable<VoiceUiState>? voiceState;
  final ValueListenable<bool>? hasSelectedVoiceModel;
  final Future<void> Function()? onVoicePressed;
  final String? executionLabel;
  final VoidCallback? onSelectExecution;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<List<PromptAttachment>>(
            valueListenable: attachments,
            builder: (context, selected, _) {
              if (selected.isEmpty) {
                return const SizedBox.shrink();
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final attachment in selected)
                        InputChip(
                          label: Text(
                            '${attachment.name} · '
                            '${_formatBytes(attachment.byteCount)}',
                          ),
                          onDeleted: () => onRemoveAttachment(attachment),
                          deleteButtonTooltipMessage: 'Remove attachment',
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (executionLabel != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.tune_rounded, size: 17),
                label: Text(executionLabel!),
                onPressed: onSelectExecution,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (voiceState case final voiceState?)
            ValueListenableBuilder<VoiceUiState>(
              valueListenable: voiceState,
              builder: (context, state, _) {
                final status = switch (state) {
                  VoiceStarting() => 'Starting local voice input.',
                  VoiceRecording() =>
                    'Listening locally. Voice text appears in the composer.',
                  VoiceTranscribing() => 'Finishing local transcription.',
                  VoiceUnavailable(:final failure) => failure.message,
                  VoiceIdle() || VoiceTranscriptReady() => null,
                };
                if (status == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Semantics(
                    liveRegion: true,
                    label: 'Voice input status: $status',
                    child: Text(status),
                  ),
                );
              },
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: () => unawaited(onPickAttachments()),
                icon: const Icon(Icons.attach_file_rounded),
                tooltip: 'Add attachment',
              ),
              if (commands.isNotEmpty)
                IconButton(
                  onPressed: () => unawaited(onSelectCommand(commands)),
                  icon: const Icon(Icons.code_rounded),
                  tooltip: 'Choose slash command',
                ),
              Expanded(
                child: Semantics(
                  label: command == null
                      ? 'Prompt composer'
                      : 'Arguments for /${command!.name}',
                  hint: command == null
                      ? 'Enter a prompt; it joins the send queue'
                      : 'Enter command arguments; it joins the send queue',
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): () =>
                          unawaited(onSubmit()),
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): () =>
                          unawaited(onSubmit()),
                    },
                    child: Focus(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          labelText: command == null
                              ? null
                              : '/${command!.name}',
                          hintText: command == null
                              ? 'Message this session…'
                              : command!.description ?? 'Command arguments…',
                          helperText: 'Ctrl/Cmd+Enter to queue',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (voiceState case final voiceState?)
                ValueListenableBuilder<VoiceUiState>(
                  valueListenable: voiceState,
                  builder: (context, state, _) => ValueListenableBuilder<bool>(
                    valueListenable:
                        hasSelectedVoiceModel ??
                        const _StaticBoolListenable(false),
                    builder: (context, hasModel, _) {
                      if (!hasModel) return const SizedBox.shrink();
                      final recording = state is VoiceRecording;
                      final busy =
                          state is VoiceStarting || state is VoiceTranscribing;
                      return IconButton.filledTonal(
                        onPressed: busy || onVoicePressed == null
                            ? null
                            : () => unawaited(onVoicePressed!()),
                        icon: Icon(recording ? Icons.stop : Icons.mic),
                        tooltip: recording
                            ? 'Stop voice input'
                            : 'Start voice input',
                      );
                    },
                  ),
                ),
              if (voiceState != null) const SizedBox(width: 8),
              // Disabled while there is nothing to queue, so tapping send can
              // never look like a silent failure.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) =>
                    ValueListenableBuilder<List<PromptAttachment>>(
                      valueListenable: attachments,
                      builder: (context, selected, _) {
                        final canSubmit =
                            value.text.trim().isNotEmpty ||
                            command != null ||
                            selected.isNotEmpty;
                        return IconButton.filled(
                          onPressed: canSubmit
                              ? () => unawaited(onSubmit())
                              : null,
                          icon: const Icon(Icons.send),
                          tooltip: command == null
                              ? 'Queue this prompt'
                              : 'Queue command',
                        );
                      },
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaticBoolListenable extends ValueListenable<bool> {
  const _StaticBoolListenable(this.value);

  @override
  final bool value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
