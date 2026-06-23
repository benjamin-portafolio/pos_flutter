import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/main.dart';

void main() {
  testWidgets('renders main app shell', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('CERVECERIA MAESTRA Y Ta...'), findsOneWidget);
    expect(find.text('Artículos'), findsWidgets);
    expect(find.text('Caja'), findsOneWidget);
  });
}
