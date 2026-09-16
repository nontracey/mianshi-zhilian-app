/// Explicitly selected local sample channel. Never a real job listing.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../model/http_client.dart';
import 'models.dart';
import 'search_service.dart';

class LocalDemoJobSearchTransport implements JobSearchTransport {
  const LocalDemoJobSearchTransport({this.resultCount = 3});
  final int resultCount;
  static const String demoNoteKey = 'coach_job_search_demo_note';

  @override
  Future<RawSearchResponse> fetch(
    SearchQuery query, {
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled == true) throw HttpCanceledException();
    return RawSearchResponse(
      items: buildDemoJobs(query),
      truncated: false,
      note: 'synthetic local demo results; not real job postings',
    );
  }

  List<RawSearchItem> buildDemoJobs(SearchQuery query) {
    final keywords = query.keywords.trim().isEmpty
        ? '示例岗位'
        : query.keywords.trim();
    final region = (query.region ?? '').trim();
    final seed = sha256
        .convert(utf8.encode(jsonEncode([keywords, region])))
        .toString()
        .substring(0, 16);
    return List.generate(
      resultCount.clamp(0, 6),
      (i) => RawSearchItem(
        title: '$keywords（演示 ${i + 1}）',
        company: '虚构示例公司 ${i + 1}',
        location: region.isEmpty ? null : region,
        externalId: 'demo-$seed-$i',
        snippet: [
          '【演示岗位】$keywords；合成数据，非真实招聘信息。',
          '岗位职责：',
          '1. 围绕 $keywords 分析需求、制定方案并交付可验证成果。',
          '2. 根据实际问题说明方案取舍，和相关人员协作。',
          '任职要求：',
          '1. 能解释 $keywords 的基础概念与适用条件。',
          '2. 能通过具体案例描述问题分析与验证过程。',
          '本示例不代表任何招聘方的要求；请使用真实 JD 确定训练范围。',
        ].join('\n'),
      ),
    );
  }
}
