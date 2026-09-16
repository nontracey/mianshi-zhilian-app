import 'coach_store_handle.dart';
import 'package:drift/wasm.dart';
import '../coach/persistence/database.dart';
import '../coach/persistence/drift_store.dart';
export 'coach_store_handle.dart';

/// Same transactional schema as native. Never silently fall back to memory or
/// unsafe per-tab IndexedDB: a successful save must survive a browser restart.
Future<CoachStoreHandle> openCoachStore() async {
  DriftCoachStore? store;
  try {
    final opened = await WasmDatabase.open(
      databaseName: 'coach',
      sqlite3Uri: Uri.base.resolve('sqlite3.wasm'),
      driftWorkerUri: Uri.base.resolve('drift_worker.js'),
    );
    if (opened.chosenImplementation == WasmStorageImplementation.inMemory ||
        opened.chosenImplementation ==
            WasmStorageImplementation.unsafeIndexedDb) {
      await opened.resolvedExecutor.executor.close();
      return CoachStoreHandle.unavailable('coach_storage_web_unavailable');
    }
    store = DriftCoachStore(CoachDatabase(opened.resolvedExecutor));
    await store.db.ensureSchema();
    return CoachStoreHandle(store, store.close);
  } catch (_) {
    await store?.close();
    return CoachStoreHandle.unavailable('coach_storage_failed');
  }
}
