import 'models.dart';

/// Browser entry points are separate from API adapters. Opening a search page
/// never manufactures job cards or claims access to a platform's private API.
class JobPlatformEntry {
  const JobPlatformEntry(
    this.platform,
    this.origin,
    this.path,
    this.keywordParameter,
  );
  final JobPlatform platform;
  final String origin;
  final String path;
  final String keywordParameter;
  Uri searchUri(String keywords) => Uri.parse(origin).replace(
    path: path,
    queryParameters: keywords.trim().isEmpty
        ? null
        : {keywordParameter: keywords.trim()},
  );
}

const mainstreamJobPlatforms = [
  JobPlatformEntry(
    JobPlatform.boss,
    'https://www.zhipin.com',
    '/web/geek/job',
    'query',
  ),
  JobPlatformEntry(
    JobPlatform.liepin,
    'https://www.liepin.com',
    '/zhaopin/',
    'key',
  ),
  JobPlatformEntry(
    JobPlatform.zhaopin,
    'https://www.zhaopin.com',
    '/sou/',
    'kw',
  ),
  JobPlatformEntry(
    JobPlatform.lagou,
    'https://www.lagou.com',
    '/wn/jobs',
    'kd',
  ),
];
