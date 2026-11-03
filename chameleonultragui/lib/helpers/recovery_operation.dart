/// Cancellation is cooperative: interrupt calculations or finish the command, then
/// stop before using its result or starting another one. Keep the operation busy
/// until that work settles so retries cannot overlap an in-flight device command.
class RecoveryOperation {
  bool isRunning = false;
  bool isCancelling = false;
  bool wasCancelled = false;
  int generation = 0;
  void Function()? _interrupt;

  void cancel() {
    if (isRunning) {
      isCancelling = true;
      _interrupt?.call();
    }
  }

  void checkCancelled() {
    if (isCancelling) throw const RecoveryCancelled();
  }

  Future<T> wait<T>(Future<T> future, {void Function()? interrupt}) async {
    final previousInterrupt = _interrupt;
    if (interrupt != null) _interrupt = interrupt;
    try {
      final result = await future;
      if (isCancelling) throw const RecoveryCancelled();
      return result;
    } catch (_) {
      if (isCancelling) throw const RecoveryCancelled();
      rethrow;
    } finally {
      _interrupt = previousInterrupt;
    }
  }

  Future<void> run(Future<void> Function() action,
      {void Function()? onCancelled}) async {
    if (isRunning) return;
    generation++;
    isRunning = true;
    isCancelling = false;
    wasCancelled = false;
    try {
      await action();
    } on RecoveryCancelled {
      wasCancelled = true;
      onCancelled?.call();
    } finally {
      isRunning = false;
      isCancelling = false;
    }
  }
}

class RecoveryCancelled implements Exception {
  const RecoveryCancelled();
}
