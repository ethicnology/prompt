/// A generic outcome type for operations that can fail with a typed,
/// expected failure. Repositories return a [Result] instead of throwing so
/// callers can pattern-match on success or failure without depending on
/// exception types crossing a repository boundary.
///
/// Unexpected programmer errors are not represented here; they should keep
/// propagating as thrown errors instead of being disguised as an [Err].
sealed class Result<T, F> {
  const Result();
}

class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);

  final T value;
}

class Err<T, F> extends Result<T, F> {
  const Err(this.failure);

  final F failure;
}
