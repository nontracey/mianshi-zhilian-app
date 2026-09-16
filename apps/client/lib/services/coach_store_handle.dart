import '../coach/persistence/coach_store.dart';

/// A failed or unsupported store rejects operations; it never pretends to save data.
class CoachStoreHandle {
  CoachStoreHandle(this.store, this._close, {this.unavailableReasonKey});

  factory CoachStoreHandle.unavailable(String reasonKey) => CoachStoreHandle(
    _UnavailableCoachStore(),
    () async {},
    unavailableReasonKey: reasonKey,
  );

  final CoachStore store;
  final Future<void> Function() _close;
  final String? unavailableReasonKey;
  bool get available => unavailableReasonKey == null;
  Future<void> dispose() => _close();
}

class _UnavailableCoachStore implements CoachStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Persistent coach storage is unavailable');
}
