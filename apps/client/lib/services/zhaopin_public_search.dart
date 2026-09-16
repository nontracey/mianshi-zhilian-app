import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../coach/jobs/models.dart';
import '../coach/jobs/search_service.dart';
import '../coach/model/http_client.dart';
import 'job_search_transport.dart';

/// Reads only the public search page. Never evaluates scripts, submits login
/// credentials or treats a verification page as an empty search result.
class ZhaopinPublicSearchTransport implements JobSearchTransport {
  ZhaopinPublicSearchTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client;

  final http.Client? _client;
  final Duration timeout;
  static const maxResponseBytes = 2 * 1024 * 1024;

  @override
  Future<RawSearchResponse> fetch(
    SearchQuery query, {
    CancelToken? cancel,
  }) async {
    if (query.keywords.trim().isEmpty ||
        query.page != 1 ||
        query.pageSize < 1 ||
        (query.salary?.trim().isNotEmpty ?? false) ||
        (query.experience?.trim().isNotEmpty ?? false) ||
        (query.platform != null && query.platform != JobPlatform.zhaopin)) {
      throw const JobSearchProtocolException(
        'Public search supports keywords and local city filtering on the first page only',
      );
    }
    if (cancel?.isCancelled ?? false) throw HttpCanceledException();
    final token = CancelToken();
    var finished = false;
    cancel?.whenCancelled.then((_) {
      if (!finished) token.cancel();
    });
    final client = _client ?? http.Client();
    try {
      return await (() async {
        final request = http.AbortableRequest(
          'GET',
          Uri.https('www.zhaopin.com', '/sou/', {'kw': query.keywords.trim()}),
          abortTrigger: token.whenCancelled,
        )..followRedirects = false;
        final response = await client.send(request);
        if (response.statusCode != 200) {
          token.cancel();
          throw JobSearchProtocolException(
            'Public search returned HTTP ${response.statusCode}',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            token.cancel();
            throw const JobSearchProtocolException(
              'Public search response is too large',
            );
          }
          bytes.addAll(chunk);
        }
        if (token.isCancelled) throw HttpCanceledException();
        return parsePage(utf8.decode(bytes), query);
      })().timeout(
        timeout,
        onTimeout: () {
          token.cancel();
          throw TimeoutException('Public job search timed out', timeout);
        },
      );
    } on http.RequestAbortedException {
      throw HttpCanceledException();
    } finally {
      finished = true;
      if (_client == null) client.close();
    }
  }

  static RawSearchResponse parsePage(String page, SearchQuery query) {
    if (utf8.encode(page).length > maxResponseBytes) {
      throw const JobSearchProtocolException(
        'Public search response is too large',
      );
    }
    Object? decoded;
    for (final script in html.parse(page).querySelectorAll('script')) {
      final text = script.text.trim();
      final match = RegExp(r'^__INITIAL_STATE__\s*=\s*').firstMatch(text);
      if (match == null) continue;
      var json = text.substring(match.end).trim();
      if (json.endsWith(';')) json = json.substring(0, json.length - 1);
      try {
        decoded = jsonDecode(json);
      } on FormatException {
        throw const JobSearchProtocolException(
          'Public search data format changed',
        );
      }
      break;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['isVerification'] != false ||
        decoded['listResponseCode'] != 200 ||
        decoded['positionList'] is! List ||
        decoded['queryParams'] is! Map ||
        (decoded['queryParams'] as Map)['keyWords'] != query.keywords.trim() ||
        decoded['pageIndex'] != 1) {
      throw const JobSearchProtocolException(
        'Public search is unavailable or requires verification; open the recruitment platform',
      );
    }
    final items = <RawSearchItem>[];
    final region = query.region?.trim() ?? '';
    final seen = <String>{};
    for (final row in decoded['positionList'] as List) {
      if (row is! Map<String, dynamic>) continue;
      String value(String key) =>
          row[key] is String ? (row[key] as String).trim() : '';
      final title = value('name');
      final uri = Uri.tryParse(
        value('positionURL').isEmpty
            ? value('positionUrl')
            : value('positionURL'),
      );
      if (title.isEmpty ||
          uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host != 'www.zhaopin.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !RegExp(r'^/jobdetail/[A-Za-z0-9]+\.htm$').hasMatch(uri.path))
        continue;
      final url = uri
          .replace(scheme: 'https', query: '', fragment: '')
          .toString();
      if (!seen.add(url)) continue;
      final city = value('workCity');
      if (region.isNotEmpty && !city.contains(region)) continue;
      final labels = row['jobLabels'];
      items.add(
        RawSearchItem(
          title: title,
          company: value('companyName'),
          location: [
            city,
            value('cityDistrict'),
            value('streetName'),
          ].where((s) => s.isNotEmpty).join(' · '),
          salary: value('salary60'),
          url: url,
          externalId: value('number'),
          postedAt: DateTime.tryParse(value('publishTime')),
          snippet: [
            value('workingExp'),
            value('education'),
            if (labels is List)
              ...labels
                  .whereType<Map>()
                  .map((l) => l['name'])
                  .whereType<String>(),
          ].where((s) => s.isNotEmpty).join(' · '),
        ),
      );
    }
    // SSR is only an initial selection, even when the page reports more jobs.
    return RawSearchResponse(
      items: items.take(query.pageSize.clamp(1, 20)).toList(),
      truncated: true,
    );
  }
}
