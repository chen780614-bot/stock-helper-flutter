import 'package:flutter_test/flutter_test.dart';
import 'package:stock_helper/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const StockHelperApp());
    expect(find.text('股票助手'), findsOneWidget);
  });
}
