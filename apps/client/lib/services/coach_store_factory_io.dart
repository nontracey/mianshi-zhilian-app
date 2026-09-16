import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../coach/persistence/drift_store.dart';
import '../coach/persistence/drift_store_native.dart';
import 'coach_store_handle.dart';
export 'coach_store_handle.dart';

Future<CoachStoreHandle> openCoachStore() async {
  DriftCoachStore? drift;
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/coach.sqlite');
    await file.parent.create(recursive: true);
    drift = openNativeCoachStoreFile(file);
    await drift.db.ensureSchema();
    return CoachStoreHandle(drift, drift.close);
  } catch (_) {
    await drift?.close();
    return CoachStoreHandle.unavailable('coach_storage_failed');
  }
}
