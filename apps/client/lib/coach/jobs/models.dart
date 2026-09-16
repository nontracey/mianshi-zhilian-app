/// 岗位搜索与 JD 导入的数据模型（§6.7）。
library;

import '../domain/goal.dart';

/// 搜索通道模式。
///
/// 三种状态必须严格区分：
/// - [off]：用户没配任何通道 —— UI 如实说“未配置”，给链接导入/粘贴的替代入口；
/// - [custom]：用户自配的搜索服务 —— 真实结果，覆盖范围由用户自己的服务决定；
/// - [demo]：本机合成通道 —— 让用户能走通流程，但**必须**标注为演示数据。
abstract final class JobSearchMode {
  static const String off = 'off';
  static const String custom = 'custom';
  static const String demo = 'demo';
  static const String zhaopinPublic = 'zhaopin-public';

  /// 未知/损坏取值一律回落 [off]：宁可如实说“未配置”，也不能冒充真实结果。
  static String normalize(String? value) => switch (value) {
    custom => custom,
    zhaopinPublic => zhaopinPublic,
    demo => demo,
    _ => off,
  };
}

/// 招聘平台（用于去重与能力声明：“可检索 / 可导入 / 需本人打开”）。
enum JobPlatform {
  unknown,
  boss,
  liepin,
  lagou,
  zhaopin,
  hangzhou,

  /// 本机演示通道：合成岗位，不是真实招聘信息。
  demo,
  custom,
}

extension JobPlatformX on JobPlatform {
  /// l10n key（UI 层用 `l10n.get(key)` 取文案）。本层不含用户可见文案。
  String get l10nKey {
    switch (this) {
      case JobPlatform.boss:
        return 'coach_platform_boss';
      case JobPlatform.liepin:
        return 'coach_platform_liepin';
      case JobPlatform.lagou:
        return 'coach_platform_lagou';
      case JobPlatform.zhaopin:
        return 'coach_platform_zhaopin';
      case JobPlatform.hangzhou:
        return 'coach_platform_hangzhou';
      case JobPlatform.demo:
        return 'coach_platform_demo';
      case JobPlatform.custom:
        return 'coach_platform_custom';
      case JobPlatform.unknown:
        return 'coach_platform_unknown';
    }
  }

  String toStorage() => name;
}

JobPlatform platformFromStorage(String? v) => JobPlatform.values.firstWhere(
  (e) => e.name == v,
  orElse: () => JobPlatform.unknown,
);

/// 岗位卡片：搜索结果或导入来源。
class JobCard {
  JobCard({
    required this.id,
    required this.platform,
    this.externalJobId,
    required this.title,
    this.company,
    this.location,
    this.salaryText,
    this.url,
    this.postedAt,
    this.expiresAt,
    this.description,
    this.completeness = 'full',
  });

  final String id;
  final JobPlatform platform;
  final String? externalJobId;
  final String title;
  final String? company;
  final String? location;
  final String? salaryText;
  final String? url;
  final DateTime? postedAt;
  final DateTime? expiresAt;
  final String? description;

  /// 'full' / 'partial' / 'summary' / 'link_only' / 'demo'。
  ///
  /// 'demo' 表示本机合成数据，UI 必须明确标注，不能当真实岗位展示。
  final String completeness;

  /// 未读到 JD 正文（或为合成数据）时，补齐前不生成具体验收标准。
  bool get hasFullJdText => completeness == 'full';

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.toStorage(),
    'externalJobId': externalJobId,
    'title': title,
    'company': company,
    'location': location,
    'salaryText': salaryText,
    'url': url,
    'postedAt': postedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'description': description,
    'completeness': completeness,
  };
}

/// 用户搜索条件。
class SearchQuery {
  SearchQuery({
    required this.keywords,
    this.region,
    this.experience,
    this.salary,
    this.platform,
    this.page = 1,
    this.pageSize = 20,
  });

  final String keywords;
  final String? region;
  final String? experience;
  final String? salary;
  final JobPlatform? platform;
  final int page;
  final int pageSize;

  SearchQuery copyWith({int? page}) => SearchQuery(
    keywords: keywords,
    region: region,
    experience: experience,
    salary: salary,
    platform: platform,
    page: page ?? this.page,
    pageSize: pageSize,
  );

  Map<String, String> toParams() {
    final m = <String, String>{
      'q': keywords,
      'page': page.toString(),
      'size': pageSize.toString(),
    };
    if (region != null) m['region'] = region!;
    if (experience != null) m['experience'] = experience!;
    if (salary != null) m['salary'] = salary!;
    if (platform != null) m['platform'] = platform!.name;
    return m;
  }
}

/// JD 导入/提取状态（§6.7）。抓取时间不能冒充发布时间；下架后保留快照并标注。
enum JobImportStatus { pending, partial, complete, failed, takenDown }

/// JD 导入结果：一个目标 JD + 其能力要求清单 + 提取状态。
class JobImportResult {
  JobImportResult({
    required this.goal,
    required this.requirements,
    required this.status,
    this.notes = const [],
  });

  final Goal goal;
  final List<GoalRequirement> requirements;
  final JobImportStatus status;
  final List<String> notes;
}
