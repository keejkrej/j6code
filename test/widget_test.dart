import 'package:flutter_test/flutter_test.dart';
import 'package:t3code/main.dart';

void main() {
  testWidgets('T3CodeApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const T3CodeApp());
    expect(find.byType(T3CodeApp), findsOneWidget);
  });
}
