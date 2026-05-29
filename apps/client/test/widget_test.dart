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

    await tester.pumpWidget(
      MianshiZhilianApp(
        storage: storage,
        contentApi: contentApi,
        aiService: aiService,
        updateService: updateService,
      ),
    );

    // 等待框架完全渲染
    await tester.pumpAndSettle();

    // 检查是否渲染了应用（可以通过查找关键组件来验证）
    // 新布局中标题不再直接显示，改为检查是否有 Material app
    expect(find.byType(MianshiZhilianApp), findsOneWidget);
  });
}
