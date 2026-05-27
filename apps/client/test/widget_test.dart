import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/main.dart';

void main() {
  testWidgets('renders learning workspace', (tester) async {
    await tester.pumpWidget(const MianshiZhilianApp());

    expect(find.text('学习中心'), findsOneWidget);
    expect(find.text('Java 核心与中间件'), findsWidgets);
  });
}
