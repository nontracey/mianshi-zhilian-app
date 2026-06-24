import 'dart:async';
import 'package:http/http.dart' as http;
import 'route_resolver.dart';

class DownloadCandidate {
  final String url;
  final String sourceLabel;

  const DownloadCandidate({required this.url, required this.sourceLabel});
}

class DownloadSourceResolver {
  static const defaultMirrorPrefix = 'https://ghfast.top';

  /// 内置国内 GitHub 镜像列表（按历史稳定性排序）。
  /// 自动模式下会并发探测延迟，优先使用最快的可达线路。
  static const builtinMirrorPrefixes = [
    'https://ghfast.top',
    'https://gh-proxy.com',
    'https://github.moeyy.xyz',
    'https://ghproxy.net',
    'https://gh.ddlc.top',
  ];

  static List<DownloadCandidate> resolve({
    required String originalUrl,
    String? customMirrorPrefix,
    List<String> additionalMirrors = const [],
    DownloadSourceMode mode = DownloadSourceMode.auto,
    String Function(String url, String mirrorPrefix)? transformUrl,
  }) {
    if (originalUrl.isEmpty) return [];

    final mirrorPrefix = (customMirrorPrefix ?? '').replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final customMirrorUrl = mirrorPrefix.isNotEmpty
        ? (transformUrl?.call(originalUrl, mirrorPrefix) ??
              '$mirrorPrefix/$originalUrl')
        : '';

    final urls = <String>[];
    void add(String url) {
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }

    switch (mode) {
      case DownloadSourceMode.githubOnly:
        add(originalUrl);
      case DownloadSourceMode.mirrorFirst:
        add(customMirrorUrl);
        for (final mirror in additionalMirrors) {
          add(mirror);
        }
        for (final prefix in builtinMirrorPrefixes) {
          add('$prefix/$originalUrl');
        }
        add(originalUrl);
      case DownloadSourceMode.auto:
      case DownloadSourceMode.githubFirst:
        add(originalUrl);
        add(customMirrorUrl);
        for (final mirror in additionalMirrors) {
          add(mirror);
        }
        for (final prefix in builtinMirrorPrefixes) {
          add('$prefix/$originalUrl');
        }
    }

    return urls
        .map(
          (url) => DownloadCandidate(
            url: url,
            sourceLabel: sourceLabel(url, customMirrorPrefix: mirrorPrefix),
          ),
        )
        .toList();
  }

  static Future<List<String>> orderByProbeLatency(List<String> urls) async {
    if (urls.length <= 1) return urls;
    final probes = await Future.wait(urls.map(_probeUrl));
    final byUrl = {for (final probe in probes) probe.url: probe};
    final ordered = List<String>.from(urls)
      ..sort((a, b) {
        final pa = byUrl[a]!;
        final pb = byUrl[b]!;
        if (pa.reachable != pb.reachable) return pa.reachable ? -1 : 1;
        if (!pa.reachable && !pb.reachable) {
          return urls.indexOf(a).compareTo(urls.indexOf(b));
        }
        return pa.elapsed.compareTo(pb.elapsed);
      });
    return ordered;
  }

  static Future<_ProbeResult> _probeUrl(String url) async {
    final client = http.Client();
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request('HEAD', Uri.parse(url));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 3));
      stopwatch.stop();
      return _ProbeResult(
        url: url,
        reachable: response.statusCode >= 200 && response.statusCode < 400,
        elapsed: stopwatch.elapsed,
      );
    } catch (_) {
      stopwatch.stop();
      return _ProbeResult(
        url: url,
        reachable: false,
        elapsed: const Duration(days: 1),
      );
    } finally {
      client.close();
    }
  }

  static String sourceLabel(String url, {String? customMirrorPrefix}) {
    if (customMirrorPrefix != null && customMirrorPrefix.isNotEmpty) {
      final prefix = customMirrorPrefix.replaceAll(RegExp(r'/+$'), '');
      if (url.startsWith(prefix)) {
        return Uri.tryParse(prefix)?.host ?? prefix;
      }
    }
    for (final prefix in builtinMirrorPrefixes) {
      if (url.startsWith(prefix)) {
        return Uri.tryParse(prefix)?.host ?? prefix;
      }
    }
    if (url.contains('github.com')) return 'GitHub';
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url.substring(0, url.length.clamp(0, 30));
    }
  }
}

class _ProbeResult {
  final String url;
  final bool reachable;
  final Duration elapsed;

  const _ProbeResult({
    required this.url,
    required this.reachable,
    required this.elapsed,
  });
}
