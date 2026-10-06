import 'package:flutter_test/flutter_test.dart';
import 'package:j6code/main.dart';

void main() {
  testWidgets('J6CodeApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const J6CodeApp());
    expect(find.byType(J6CodeApp), findsOneWidget);
  });
}
