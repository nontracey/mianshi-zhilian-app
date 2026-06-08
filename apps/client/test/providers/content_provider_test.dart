import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(http.Response('{}', 200).bodyBytes),
      200,
    );
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    return http.Response('{}', 200);
  }

  @override
  void close() {}
}

class MockContentApiService extends ContentApiService {
  Map<String, dynamic>? _manifestResponse;
  Object? _manifestError;
  final Map<String, Map<String, dynamic>> _domainResponses = {};
  final Map<String, Map<String, dynamic>> _topicResponses = {};
  Completer<Map<String, dynamic>>? _manifestBlocker;
  bool _blockerConsumed = false;

  MockContentApiService()
      : super(baseUrl: 'http://test.com', httpClient: _MockHttpClient());

  void setManifestResponse(Map<String, dynamic>? manifest) {
    _manifestResponse = manifest;
  }

  void setManifestError(Object? error) {
    _manifestError = error;
  }

  void setDomainResponse(String domainId, Map<String, dynamic> json) {
    _domainResponses[domainId] = json;
  }

  void setTopicResponse(String path, Map<String, dynamic> json) {
    _topicResponses[path] = json;
  }

  void blockManifestOnce() {
    _manifestBlocker = Completer<Map<String, dynamic>>();
    _blockerConsumed = false;
  }

  void completeManifestWith(Map<String, dynamic> data) {
    _manifestBlocker?.complete(data);
    _manifestBlocker = null;
  }

  @override
  Future<Map<String, dynamic>> fetchManifest() async {
    if (_manifestBlocker != null && !_blockerConsumed) {
      _blockerConsumed = true;
      return await _manifestBlocker!.future;
    }
    if (_manifestError != null) throw _manifestError!;
    return _manifestResponse ?? {'domains': <dynamic>[]};
  }

  @override
  Future<Domain> fetchDomain(String domainId, {String? entry}) async {
    final json = _domainResponses[domainId];
    if (json == null) throw Exception('No domain response for $domainId');
    return Domain.fromJson(json);
  }

  @override
  Future<Topic> fetchTopic(String topicPath) async {
    final json = _topicResponses[topicPath];
    if (json == null) throw Exception('No topic response for $topicPath');
    return Topic.fromJson(json);
  }
}

void main() {
  late MockContentApiService api;
  late ContentProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = MockContentApiService();
    provider = ContentProvider(api, StorageService());
  });

  group('initial state', () {
    test('domains=[], topics={}, isLoading=false, error=null', () {
      expect(provider.domains, isEmpty);
      expect(provider.topics, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });
  });

  group('loadContent', () {
    test('populates domains list from API manifest', () async {
      api.setManifestResponse({
        'domains': [
          {
            'id': 'java',
            'title': 'Java',
            'description': 'Java desc',
            'topicCount': 5,
          },
          {
            'id': 'agent',
            'title': 'Agent',
            'description': 'Agent desc',
            'topicCount': 3,
          },
        ],
        'contentVersion': null,
        'defaultDomain': 'nonexistent',
      });
      api.setDomainResponse('java', {
        'id': 'java',
        'title': 'Java Full',
        'description': 'Java full desc',
        'categories': [],
      });
      api.setDomainResponse('agent', {
        'id': 'agent',
        'title': 'Agent Full',
        'description': 'Agent full desc',
        'categories': [],
      });

      await provider.loadContent();

      expect(provider.domains.length, 2);
      expect(provider.domains[0].id, 'java');
      expect(provider.domains[1].id, 'agent');
      expect(provider.manifest, isNotNull);
    });

    test('isLoading true during load, false after', () async {
      api.setManifestResponse({
        'domains': [
          {
            'id': 'java',
            'title': 'Java',
            'description': 'Java',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
        'defaultDomain': 'nonexistent',
      });
      api.setDomainResponse('java', {
        'id': 'java',
        'title': 'Java',
        'description': 'Java',
        'categories': [],
      });

      expect(provider.isLoading, false);

      final future = provider.loadContent();
      expect(provider.isLoading, true);

      await future;
      expect(provider.isLoading, false);
    });

    test('sets error field on API failure', () async {
      api.setManifestError(Exception('Network error'));

      await provider.loadContent();

      expect(provider.error, isNotNull);
      expect(provider.isLoading, false);
    });

    test('epoch check prevents stale updates from concurrent calls', () async {
      api.setManifestResponse({
        'domains': [
          {
            'id': 'java',
            'title': 'Java',
            'description': 'Java',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
      });
      api.setDomainResponse('java', {
        'id': 'java',
        'title': 'Java Full',
        'description': 'Java',
        'categories': [],
      });
      api.blockManifestOnce();

      provider.loadContent();

      api.setManifestResponse({
        'domains': [
          {
            'id': 'agent',
            'title': 'Agent',
            'description': 'Agent',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
      });
      api.setDomainResponse('agent', {
        'id': 'agent',
        'title': 'Agent Full',
        'description': 'Agent',
        'categories': [],
      });

      await provider.loadContent();

      expect(provider.domains.length, 1);
      expect(provider.domains[0].id, 'agent');

      api.completeManifestWith({
        'domains': [
          {
            'id': 'java',
            'title': 'Old Java',
            'description': 'Old',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
      });
      await Future(() {});

      expect(provider.domains.length, 1);
      expect(provider.domains[0].id, 'agent');
      expect(provider.isLoading, false);
    });
  });

  group('topics and domain access', () {
    test('getTopicsByDomain returns empty list for unknown domain', () {
      expect(provider.getTopicsByDomain('unknown'), isEmpty);
    });

    test('findTopic returns Topic for valid topicId', () async {
      api.setManifestResponse({
        'domains': [
          {
            'id': 'java',
            'title': 'Java',
            'description': 'Java',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
        'defaultDomain': 'nonexistent',
      });
      api.setDomainResponse('java', {
        'id': 'java',
        'title': 'Java Full',
        'description': 'Java full',
        'categories': [
          {
            'id': 'jvm',
            'title': 'JVM',
            'topics': ['topics/java/jvm-runtime-data-area.json'],
          },
        ],
      });
      api.setTopicResponse('topics/java/jvm-runtime-data-area.json', {
        'id': 'java.jvm.runtime-data-area',
        'domain': 'java',
        'category': 'jvm',
        'title': 'Runtime Data Area',
        'summary': 'JVM runtime data area overview',
        'order': 1,
      });

      await provider.loadContent();
      await provider.loadDomainTopics('java');

      final topic = provider.findTopic('java.jvm.runtime-data-area');
      expect(topic, isNotNull);
      expect(topic!.title, 'Runtime Data Area');
    });

    test('findTopic returns null for invalid topicId', () {
      expect(provider.findTopic('nonexistent'), isNull);
    });
  });

  group('cache management', () {
    test('clearAllCache clears topics and notifies', () async {
      api.setManifestResponse({
        'domains': [
          {
            'id': 'java',
            'title': 'Java',
            'description': 'Java',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
        'defaultDomain': 'nonexistent',
      });
      api.setDomainResponse('java', {
        'id': 'java',
        'title': 'Java Full',
        'description': 'Java full',
        'categories': [
          {
            'id': 'jvm',
            'title': 'JVM',
            'topics': ['topics/java/jvm-runtime-data-area.json'],
          },
        ],
      });
      api.setTopicResponse('topics/java/jvm-runtime-data-area.json', {
        'id': 'java.jvm.runtime-data-area',
        'domain': 'java',
        'category': 'jvm',
        'title': 'Runtime Data Area',
        'summary': 'Test',
        'order': 1,
      });

      await provider.loadContent();
      await provider.loadDomainTopics('java');

      expect(provider.topics, isNotEmpty);

      await provider.clearAllCache();

      expect(provider.topics, isEmpty);
    });
  });

  group('switchContentEnv', () {
    test('clears everything and reloads', () async {
      api.setManifestResponse({
        'domains': [
          {
            'id': 'java',
            'title': 'Java',
            'description': 'Java',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
        'defaultDomain': 'nonexistent',
      });
      api.setDomainResponse('java', {
        'id': 'java',
        'title': 'Java Full',
        'description': 'Java',
        'categories': [],
      });

      await provider.loadContent();
      expect(provider.domains.length, 1);
      expect(provider.manifest, isNotNull);

      api.setManifestResponse({
        'domains': [
          {
            'id': 'agent',
            'title': 'Agent',
            'description': 'Agent',
            'topicCount': 1,
          },
        ],
        'contentVersion': null,
        'defaultDomain': 'nonexistent',
      });
      api.setDomainResponse('agent', {
        'id': 'agent',
        'title': 'Agent Full',
        'description': 'Agent',
        'categories': [],
      });

      await provider.switchContentEnv('http://new.test.com');

      expect(provider.domains.length, 1);
      expect(provider.domains[0].id, 'agent');
      expect(provider.topics, isEmpty);
      expect(provider.error, isNull);
    });
  });
}
