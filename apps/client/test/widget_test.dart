import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/main.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/ai_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';

void main() {
  testWidgets('renders learning workspace', (tester) async {
    final storage = StorageService();
    final contentApi = ContentApiService();
    final aiService = AiService();
    final updateService = UpdateService();

    await tester.pumpWidget(MianshiZhilianApp(
      storage: storage,
      contentApi: contentApi,
      aiService: aiService,
      updateService: updateService,
    ));

    expect(find.text('学习中心'), findsOneWidget);
  });
}
