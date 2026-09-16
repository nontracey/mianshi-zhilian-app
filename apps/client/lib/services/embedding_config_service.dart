/// Optional, endpoint-bound embedding configuration. Keys never enter the coach
/// database. A model/dimension change uses a new vector space automatically.
library;

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../coach/knowledge/embedding.dart';
import '../coach/model/http_client.dart';
import '../coach/persistence/coach_store.dart';
import '../coach/persistence/extension_records.dart';
import 'coach_http_client.dart';
import 'storage_service.dart';

class HttpEmbeddingProvider implements BatchEmbeddingProvider, EmbeddingCache {
  HttpEmbeddingProvider({
    required this.http,
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.dimension,
  });
  final HttpClient http;
  final String endpoint, model, apiKey;
  @override
  final int dimension;
  final Map<String, List<double>> _cache = {};
  @override
  void clearCache() => _cache.clear();
  @override
  String get profileId =>
      sha256.convert(utf8.encode('$endpoint:$model:$dimension')).toString();
  @override
  Future<List<double>> embed(String text) async =>
      (await embedBatch([text])).single;
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final keys = texts
        .map((t) => sha256.convert(utf8.encode(t)).toString())
        .toList();
    final missing = [
      for (var i = 0; i < texts.length; i++)
        if (!_cache.containsKey(keys[i])) i,
    ];
    if (missing.isNotEmpty) {
      final cancel = CancelToken();
      final response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'input': missing.map((i) => texts[i]).toList(),
            }),
            cancel: cancel,
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Embedding timed out');
            },
          );
      if (!response.isOk)
        throw StateError('Embedding request failed (${response.statusCode})');
      final data = (jsonDecode(response.body) as Map)['data'];
      if (data is! List || data.length != missing.length)
        throw const FormatException('Embedding result count mismatch');
      final byIndex = <int, List<double>>{};
      for (final item in data) {
        final index = item['index'];
        final vector = (item['embedding'] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        if (index is! int ||
            index < 0 ||
            index >= missing.length ||
            byIndex.containsKey(index) ||
            vector.length != dimension ||
            vector.any((v) => !v.isFinite))
          throw const FormatException('Invalid embedding vector');
        byIndex[index] = vector;
      }
      for (var i = 0; i < missing.length; i++) {
        _cache[keys[missing[i]]] = byIndex[i]!;
      }
    }
    final result = keys.map((k) => _cache[k]!).toList();
    while (_cache.length > 1024) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }
}

class EmbeddingConfigService extends ChangeNotifier {
  EmbeddingConfigService({
    required this.store,
    required this.storage,
    required this.profileId,
  });
  final CoachStore store;
  final StorageService storage;
  final String profileId;
  final CoachHttpClient _http = CoachHttpClient();
  String endpoint = '', model = '';
  int dimension = 0;
  bool enabled = false;
  HttpEmbeddingProvider? provider;
  String _slot(String url) =>
      'embedding_${sha256.convert(utf8.encode('$profileId:$url'))}';
  Future<void> load() async {
    final record = await store.getExtension(
      profileId,
      CoachExtensionKind.embeddingConfigMetadata,
      'default',
    );
    final value = record?.value ?? {};
    endpoint = value['endpoint'] as String? ?? '';
    model = value['model'] as String? ?? '';
    dimension = value['dimension'] as int? ?? 0;
    enabled = value['enabled'] == true;
    provider = enabled
        ? HttpEmbeddingProvider(
            http: _http,
            endpoint: endpoint,
            model: model,
            apiKey: await storage.readSecret(_slot(endpoint)) ?? '',
            dimension: dimension,
          )
        : null;
    notifyListeners();
  }

  Future<void> save({
    required String endpoint,
    required String model,
    required int dimension,
    required bool enabled,
    String? key,
  }) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (enabled &&
        (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            model.trim().isEmpty ||
            dimension < 1 ||
            dimension > 32768)) {
      throw const FormatException('Invalid embedding configuration');
    }
    if (key != null && !await storage.writeSecret(_slot(endpoint.trim()), key))
      throw StateError('Secure storage write failed');
    final old = await store.getExtension(
      profileId,
      CoachExtensionKind.embeddingConfigMetadata,
      'default',
    );
    await store.putExtension(
      CoachExtensionRecord(
        profileId: profileId,
        kind: CoachExtensionKind.embeddingConfigMetadata,
        id: 'default',
        revision: (old?.revision ?? 0) + 1,
        updatedAt: DateTime.now(),
        value: {
          'endpoint': endpoint.trim(),
          'model': model.trim(),
          'dimension': dimension,
          'enabled': enabled,
        },
      ),
    );
    await load();
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
