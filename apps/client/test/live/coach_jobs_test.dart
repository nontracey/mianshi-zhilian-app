import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/jobs/models.dart';
import 'package:mianshi_zhilian/coach/jobs/search_service.dart';
import 'package:mianshi_zhilian/services/zhaopin_public_search.dart';

void main() {
  test(
    'live public Zhaopin page returns real summary cards through the production adapter',
    () async {
      HttpOverrides.global = null;
      final client = IOClient(
        HttpClient()..findProxy = HttpClient.findProxyFromEnvironment,
      );
      addTearDown(client.close);
      final service = WebSearchJobAdapter(
        transport: ZhaopinPublicSearchTransport(client: client),
        idGen: IdGenerator(),
      );
      final result = await service.searchResult(SearchQuery(keywords: 'Java'));
      expect(result.cards, isNotEmpty);
      expect(result.truncated, true);
      for (final card in result.cards) {
        expect(card.platform, JobPlatform.zhaopin);
        expect(card.title, isNotEmpty);
        expect(card.url, startsWith('https://www.zhaopin.com/jobdetail/'));
        expect(card.completeness, 'summary');
      }
    },
    skip: Platform.environment['COACH_LIVE_JOBS'] != '1',
  );
}
