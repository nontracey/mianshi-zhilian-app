/// 教练持久化层 barrel。
///
/// 只导出 [CoachStore] 与 [InMemoryCoachStore]（纯 Dart，无 Flutter/drift 依赖），
/// 便于单测与上层直接 import。Drift 实现见 [drift_store.dart] / [database.dart]
/// （依赖 dart:io + sqlite，仅原生平台使用，勿从此 barrel 引入以免污染纯 VM 测试）。
library;

export 'coach_store.dart';
export 'extension_records.dart';
export 'workflow_repository.dart';
