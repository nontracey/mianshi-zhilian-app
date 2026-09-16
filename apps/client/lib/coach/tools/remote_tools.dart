/// Bounded remote tools for one coach turn. Only locally granted tools enter
/// this registry. Server descriptions and results remain untrusted data.
library;

import '../model/messages.dart';
import '../model/http_client.dart';

class CoachRemoteTools {
  CoachRemoteTools({
    required this.specs,
    required this.execute,
    required this.close,
  });
  final List<ToolSpec> specs;
  final Future<String> Function(ToolCall call, CancelToken cancel) execute;
  final void Function() close;
}

typedef CoachRemoteToolsProvider =
    Future<CoachRemoteTools> Function(CancelToken cancel);
