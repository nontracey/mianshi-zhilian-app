// Platform-specific persistent storage with an explicit availability result.
export 'coach_store_factory_web.dart'
    if (dart.library.io) 'coach_store_factory_io.dart';
