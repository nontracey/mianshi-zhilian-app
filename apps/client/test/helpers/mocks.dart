import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mianshi_zhilian/services/ai_service.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/endpoint_fallback_client.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

@GenerateMocks([
  http.Client,
  AiService,
  ContentApiService,
  EndpointFallbackClient,
  StorageService,
])
void main() {}
