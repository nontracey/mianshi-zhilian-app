/// 岗位搜索服务（§6.7）。真实搜索通道由注入的 [JobSearchTransport] 提供，
/// 适配器只负责把原始结果映射成 [JobCard]；未配置时明确给出连接入口，不伪造结果。
library;

import '../domain/common.dart';
import '../model/http_client.dart';
import 'link_parser.dart';
import 'models.dart';

/// 原始搜索结果项（来自搜索通道，字段可能不完整）。
class RawSearchItem {
  RawSearchItem({
    required this.title,
    this.company,
    this.location,
    this.salary,
    this.url,
    this.snippet,
    this.postedAt,
    this.externalId,
  });

  final String title;
  final String? company;
  final String? location;
  final String? salary;
  final String? url;
  final String? snippet;
  final DateTime? postedAt;
  final String? externalId;

  factory RawSearchItem.fromJson(Map<String, dynamic> json) => RawSearchItem(
    title: json['title'] as String? ?? '',
    company: json['company'] as String?,
    location: json['location'] as String?,
    salary: json['salary'] as String?,
    url: json['url'] as String?,
    snippet: json['snippet'] as String?,
    postedAt: json['postedAt'] == null
        ? null
        : DateTime.tryParse(json['postedAt'] as String),
    externalId: json['externalId'] as String?,
  );
}

/// 原始搜索响应。
class RawSearchResponse {
  RawSearchResponse({required this.items, this.truncated = false, this.note});
  final List<RawSearchItem> items;

  /// 是否因为限额/分页只拿到部分结果。
  final bool truncated;
  final String? note;
}

/// 搜索通道数据来源（注入式：真实 Web Search API / 搜索 MCP / 平台适配器）。
abstract class JobSearchTransport {
  Future<RawSearchResponse> fetch(SearchQuery query, {CancelToken? cancel});
}

class JobSearchResult {
  const JobSearchResult({
    required this.cards,
    this.truncated = false,
    this.note,
  });
  final List<JobCard> cards;
  final bool truncated;
  final String? note;
}

/// 岗位发现服务接口。
abstract class JobDiscoveryService {
  /// 返回可加入“我的 JD”的岗位卡片。未选中的结果不创建目标。
  Future<List<JobCard>> search(SearchQuery query, {CancelToken? cancel});
  Future<JobSearchResult> searchResult(
    SearchQuery query, {
    CancelToken? cancel,
  }) async => JobSearchResult(cards: await search(query, cancel: cancel));
}

/// 基于注入 transport 的通用搜索适配器：把原始结果映射成 [JobCard]。
///
/// 这是 V1 的“一条经过验证、可在 App 内返回真实岗位卡”的搜索通道接入点；
/// 真实覆盖率由所注入的 transport 决定，适配器本身不编造岗位。
class WebSearchJobAdapter extends JobDiscoveryService {
  WebSearchJobAdapter({
    required this.transport,
    required this.idGen,
    this.platform = JobPlatform.custom,
    this.defaultUrl,
    this.completeness,
  });

  final JobSearchTransport transport;
  final IdGenerator idGen;
  final JobPlatform platform;
  final String? defaultUrl;

  /// 固定完整度标记。演示通道传 `'demo'`，让 UI 如实标注合成数据。
  final String? completeness;

  @override
  Future<List<JobCard>> search(
    SearchQuery query, {
    CancelToken? cancel,
  }) async => (await searchResult(query, cancel: cancel)).cards;

  @override
  Future<JobSearchResult> searchResult(
    SearchQuery query, {
    CancelToken? cancel,
  }) async {
    final resp = await transport.fetch(query, cancel: cancel);
    final cards = resp.items.map((item) {
      final url = item.url ?? defaultUrl;
      final plat = url != null ? detectPlatform(Uri.parse(url)) : platform;
      return JobCard(
        id: idGen.next(),
        platform: plat,
        externalJobId: item.externalId,
        title: item.title,
        company: item.company,
        location: item.location,
        salaryText: item.salary,
        url: url,
        postedAt: item.postedAt,
        description: item.snippet,
        completeness: completeness ?? (url == null ? 'link_only' : 'summary'),
      );
    }).toList();
    return JobSearchResult(
      cards: cards,
      truncated: resp.truncated,
      note: resp.note,
    );
  }
}
