/// 模型网关层统一导出（纯 Dart，可在无 Flutter 环境单测）。
///
/// 平台 HTTP 传输由应用装配层提供，
/// 避免把 dart:io 拉进 Web 编译图。
library;

export 'errors.dart';
export 'gateway.dart';
export 'http_client.dart';
export 'messages.dart';
export 'proposals.dart';
export 'compat_gateway.dart';
