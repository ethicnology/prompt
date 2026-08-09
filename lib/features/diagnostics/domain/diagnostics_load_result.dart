import 'diagnostics_snapshot.dart';

sealed class DiagnosticsLoadResult {
  const DiagnosticsLoadResult();
}

class DiagnosticsLoaded extends DiagnosticsLoadResult {
  const DiagnosticsLoaded(this.snapshot);

  final DiagnosticsSnapshot snapshot;
}

class DiagnosticsLoadFailed extends DiagnosticsLoadResult {
  const DiagnosticsLoadFailed(this.failure);

  final DiagnosticsFailure failure;
}

enum DiagnosticsFailure { unavailable, unauthorized, unexpectedResponse }
