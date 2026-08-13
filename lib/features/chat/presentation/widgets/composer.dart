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
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onSubmit,
    this.voiceState,
    this.onVoiceHoldStart,
    this.onVoiceHoldEnd,
    this.onVoiceStop,
    super.key,
  });

  final TextEditingController controller;
  final OpenCodeSlashCommand? command;
  final ValueListenable<List<PromptAttachment>> attachments;
  final ValueChanged<PromptAttachment> onRemoveAttachment;
  final Future<void> Function() onSubmit;
  final ValueListenable<VoiceUiState>? voiceState;
  final Future<void> Function()? onVoiceHoldStart;
  final Future<void> Function()? onVoiceHoldEnd;
  final Future<void> Function()? onVoiceStop;

  @override
  Widget build(BuildContext context) {
    final showKeyboardHint =
        kIsWeb ||
        switch (defaultTargetPlatform) {
          TargetPlatform.linux ||
          TargetPlatform.macOS ||
          TargetPlatform.windows => true,
          _ => false,
        };
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
          if (voiceState case final voiceState?)
            ValueListenableBuilder<VoiceUiState>(
              valueListenable: voiceState,
              builder: (context, state, _) {
                final status = switch (state) {
                  VoiceUnavailable(:final failure) => failure.message,
                  _ => null,
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
          if (voiceState case final voiceState?)
            ValueListenableBuilder<VoiceUiState>(
              valueListenable: voiceState,
              builder: (context, state, _) {
                if (state is VoiceIdle || state is VoiceUnavailable) {
                  return const SizedBox.shrink();
                }
                return _VoiceModeBar(
                  state: state,
                  onHoldStart: onVoiceHoldStart,
                  onHoldEnd: onVoiceHoldEnd,
                  onStop: onVoiceStop,
                );
              },
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                          helperText: showKeyboardHint
                              ? 'Ctrl/Cmd+Enter to queue'
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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

class _VoiceModeBar extends StatelessWidget {
  const _VoiceModeBar({
    required this.state,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onStop,
  });

  final VoiceUiState state;
  final Future<void> Function()? onHoldStart;
  final Future<void> Function()? onHoldEnd;
  final Future<void> Function()? onStop;

  @override
  Widget build(BuildContext context) {
    final recording = state is VoiceRecording;
    final processing = state is VoiceStarting || state is VoiceTranscribing;
    final colorScheme = Theme.of(context).colorScheme;
    final title = switch (state) {
      VoiceRecording() => 'Listening',
      VoiceTranscribing() => 'Finishing transcription',
      VoiceStarting() => 'Opening microphone',
      _ => 'Microphone muted',
    };
    final instruction = switch (state) {
      VoiceRecording() => 'Release to mute',
      VoiceTranscribing() => 'Stop is closing the voice session',
      VoiceStarting() => 'Keep holding to speak',
      _ => 'Hold to talk',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        decoration: BoxDecoration(
          color: recording
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: recording ? colorScheme.primary : colorScheme.outlineVariant,
            width: recording ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '$title. $instruction.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        instruction,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: recording
                    ? 'Recording. Release to mute microphone'
                    : 'Hold to talk. Microphone muted',
                hint: 'Press and hold while speaking, then release',
                onTap: processing
                    ? null
                    : recording
                    ? onHoldEnd == null
                          ? null
                          : () => unawaited(onHoldEnd!())
                    : onHoldStart == null
                    ? null
                    : () => unawaited(onHoldStart!()),
                child: Listener(
                  onPointerDown: processing || onHoldStart == null
                      ? null
                      : (_) => unawaited(onHoldStart!()),
                  onPointerUp: onHoldEnd == null
                      ? null
                      : (_) => unawaited(onHoldEnd!()),
                  onPointerCancel: onHoldEnd == null
                      ? null
                      : (_) => unawaited(onHoldEnd!()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: recording
                          ? colorScheme.primary
                          : colorScheme.primaryContainer,
                      border: Border.all(color: colorScheme.primary, width: 2),
                    ),
                    child: Icon(
                      recording ? Icons.mic_rounded : Icons.mic_off_rounded,
                      size: 34,
                      color: recording
                          ? colorScheme.onPrimary
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    onPressed: onStop == null
                        ? null
                        : () => unawaited(onStop!()),
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: 'Stop voice mode',
                  ),
                  Text('Stop', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
