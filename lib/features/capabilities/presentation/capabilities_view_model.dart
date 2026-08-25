import 'package:flutter/foundation.dart';

import '../../connection/connection.dart';
import '../data/capabilities_repository.dart';
import '../domain/capabilities_load_result.dart';
import '../domain/open_code_capabilities.dart';

sealed class CapabilitiesUiState {
  const CapabilitiesUiState();
}

class CapabilitiesIdle extends CapabilitiesUiState {
  const CapabilitiesIdle();
}

class CapabilitiesLoading extends CapabilitiesUiState {
  const CapabilitiesLoading();
}

class CapabilitiesReady extends CapabilitiesUiState {
  const CapabilitiesReady(this.capabilities);

  final OpenCodeCapabilities capabilities;
}

class CapabilitiesEmpty extends CapabilitiesUiState {
  const CapabilitiesEmpty();
}

class CapabilitiesError extends CapabilitiesUiState {
  const CapabilitiesError(this.failure);

  final CapabilitiesFailure failure;
}

class CapabilitiesViewModel extends ValueNotifier<CapabilitiesUiState> {
  CapabilitiesViewModel(this._repository) : super(const CapabilitiesIdle());

  final CapabilitiesRepository _repository;
  ServerProfile? _profile;
  int _request = 0;

  Future<void> load(ServerProfile profile) async {
    _profile = profile;
    final request = ++_request;
    value = const CapabilitiesLoading();
    final result = await _repository.load(profile);
    if (request != _request) {
      return;
    }
    value = switch (result) {
      CapabilitiesLoaded(:final capabilities) when capabilities.isEmpty =>
        const CapabilitiesEmpty(),
      CapabilitiesLoaded(:final capabilities) => CapabilitiesReady(
        capabilities,
      ),
      CapabilitiesLoadFailed(:final failure) => CapabilitiesError(failure),
    };
  }

  Future<void> retry() async {
    final profile = _profile;
    if (profile != null) {
      await load(profile);
    }
  }
}
