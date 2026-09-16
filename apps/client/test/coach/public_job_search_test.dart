import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/jobs/models.dart';
import 'package:mianshi_zhilian/coach/jobs/search_service.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/services/job_search_transport.dart';
import 'package:mianshi_zhilian/services/zhaopin_public_search.dart';

String page({
  String keyword = 'Java',
  bool verification = false,
  List<Map<String, Object?>>? items,
}) =>
    '<html><script>__INITIAL_STATE__=${jsonEncode({
      'queryParams': {'keyWords': keyword},
      'pageIndex': 1,
      'isVerification': verification,
      'listResponseCode': 200,
      'positionList': items ?? [
            {
              'name': 'Synthetic Java role',
              'companyName': 'Synthetic company',
              'workCity': '杭州',
              'salary60': '20000-30000元',
              'positionURL': 'http://www.zhaopin.com/jobdetail/CC123J456.htm',
              'number': 'CC123J456',
              'publishTime': '2026-09-12 12:00:00',
              'workingExp': '3-5年',
              'jobLabels': [
                {'name': 'Java'},
              ],
            },
          ],
    })};</script></html>';

void main() {
  test(
    'public page maps source fields, upgrades pinned links, and retains partial-result metadata',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.host, 'www.zhaopin.com');
        expect(request.url.queryParameters['kw'], 'Java');
        expect(request.headers.containsKey('Authorization'), false);
        expect(request.followRedirects, false);
        return http.Response(
          page(),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final adapter = WebSearchJobAdapter(
        transport: ZhaopinPublicSearchTransport(client: client),
        idGen: IdGenerator(),
      );
      final result = await adapter.searchResult(
        SearchQuery(keywords: 'Java', region: '杭州'),
      );
      expect(result.truncated, true);
      final card = result.cards.single;
      expect(card.company, 'Synthetic company');
      expect(card.platform, JobPlatform.zhaopin);
      expect(Uri.parse(card.url!).scheme, 'https');
      expect(card.hasFullJdText, false);
      expect(card.postedAt, DateTime(2026, 9, 12, 12));
    },
  );
  test(
    'verification, changed markup and mismatched queries fail rather than report zero jobs',
    () {
      for (final body in [
        page(verification: true),
        page(keyword: 'Other'),
        '<html>login</html>',
        '<script>__INITIAL_STATE__={};alert(1)</script>',
      ]) {
        expect(
          () => ZhaopinPublicSearchTransport.parsePage(
            body,
            SearchQuery(keywords: 'Java'),
          ),
          throwsA(isA<JobSearchProtocolException>()),
        );
      }
      expect(
        ZhaopinPublicSearchTransport.parsePage(
          page(items: []),
          SearchQuery(keywords: 'Java'),
        ).items,
        isEmpty,
      );
    },
  );
  test(
    'local city filtering is partial and unsafe result URLs are discarded',
    () {
      final result = ZhaopinPublicSearchTransport.parsePage(
        page(),
        SearchQuery(keywords: 'Java', region: '上海'),
      );
      expect(result.items, isEmpty);
      expect(result.truncated, true);
      for (final url in [
        'https://evil.example/jobdetail/CC123.htm',
        'javascript:alert(1)',
        'https://secret@www.zhaopin.com/jobdetail/CC123.htm',
      ]) {
        expect(
          ZhaopinPublicSearchTransport.parsePage(
            page(
              items: [
                {'name': 'Synthetic', 'positionURL': url},
              ],
            ),
            SearchQuery(keywords: 'Java'),
          ).items,
          isEmpty,
        );
      }
    },
  );
  test(
    'unsupported filters and cancellation make no network request',
    () async {
      final client = MockClient(
        (_) async => throw StateError('must not request'),
      );
      addTearDown(client.close);
      final transport = ZhaopinPublicSearchTransport(client: client);
      await expectLater(
        transport.fetch(SearchQuery(keywords: 'Java', salary: '20k')),
        throwsA(isA<JobSearchProtocolException>()),
      );
      await expectLater(
        transport.fetch(
          SearchQuery(keywords: 'Java'),
          cancel: CancelToken()..cancel(),
        ),
        throwsA(isA<HttpCanceledException>()),
      );
    },
  );
}
