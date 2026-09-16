/// 岗位链接解析与平台识别（§6.7）：从粘贴文本提取 URL、规范化、识别平台与岗位 ID。
library;

import 'models.dart';

/// 解析后的岗位链接。
class ParsedJobLink {
  ParsedJobLink({
    required this.url,
    required this.platform,
    this.externalJobId,
    this.canonicalUrl,
  });

  final String url;
  final JobPlatform platform;
  final String? externalJobId;
  final String? canonicalUrl;
}

final _urlRegExp = RegExp(r'https?://[^\s，。、）)】\]]+', caseSensitive: false);

/// 从可能含说明文字的输入中提取第一个 URL。
String? extractFirstUrl(String input) {
  final match = _urlRegExp.firstMatch(input);
  return match?.group(0)?.replaceAll(RegExp(r'[。，、]+$'), '');
}

/// 识别平台（按域名）。未知平台返回 [JobPlatform.unknown]。
JobPlatform detectPlatform(Uri uri) {
  final host = uri.host.toLowerCase();
  bool matches(String domain) => host == domain || host.endsWith('.$domain');
  if (matches('zhipin.com')) return JobPlatform.boss;
  if (matches('liepin.com')) return JobPlatform.liepin;
  if (matches('lagou.com')) return JobPlatform.lagou;
  if (matches('zhaopin.com')) return JobPlatform.zhaopin;
  if (matches('hzzrc.com')) return JobPlatform.hangzhou;
  return JobPlatform.unknown;
}

/// 从 URL 路径中提取平台岗位 ID（各平台不同，未识别返回 null）。
String? extractExternalJobId(Uri uri, JobPlatform platform) {
  switch (platform) {
    case JobPlatform.boss:
      // 例如 /job_detail/xxxx.html
      final m = RegExp(r'/job_detail/([a-zA-Z0-9]+)').firstMatch(uri.path);
      return m?.group(1);
    case JobPlatform.liepin:
      final m = RegExp(r'/job/([a-zA-Z0-9]+)').firstMatch(uri.path);
      return m?.group(1);
    default:
      final seg = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      return seg;
  }
}

/// 归一化 URL：去掉跟踪参数、规范 scheme/host。
String canonicalizeUrl(String url) {
  final uri = Uri.parse(url);
  final cleaned = uri.replace(
    queryParameters: Map.fromEntries(
      uri.queryParameters.entries.where((e) => !_isTrackingParam(e.key)),
    ),
    fragment: '',
  );
  return cleaned.toString();
}

bool _isTrackingParam(String key) {
  const tracking = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'spm',
    'from',
    'rcmd',
  };
  return tracking.contains(key.toLowerCase());
}

/// 解析粘贴文本中的岗位链接。返回 null 表示没有可识别链接（应引导用户粘贴文本或打开平台）。
ParsedJobLink? parseJobLink(String input) {
  final raw = extractFirstUrl(input);
  if (raw == null) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
    return null;
  }
  final url = canonicalizeUrl(raw);
  final uri = Uri.parse(url);
  final platform = detectPlatform(uri);
  final externalJobId = extractExternalJobId(uri, platform);
  return ParsedJobLink(
    url: url,
    platform: platform,
    externalJobId: externalJobId,
    canonicalUrl: url,
  );
}

extension _LastOrNull<E> on Iterable<E> {
  E? get lastOrNull => isEmpty ? null : last;
}
