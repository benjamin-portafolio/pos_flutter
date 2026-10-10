import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/domain/repositories/sale_draft_repository.dart';
import 'package:pos_flutter/main.dart';

import 'support/fake_sale_draft_repository.dart';
import 'support/fake_producto_repository.dart';
import 'support/fake_venta_borrador_command_service.dart';

void main() {
  setUp(() {
    getIt.registerSingleton<SaleDraftRepository>(FakeSaleDraftRepository());
    getIt.registerSingleton<ProductoRepository>(FakeProductoRepository());
    getIt.registerSingleton<VentaBorradorCommandService>(
      FakeVentaBorradorCommandService(),
    );
  });
  tearDown(() => getIt.reset());
  testWidgets('renders main app shell', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('PASTOR'), findsOneWidget);
    expect(find.text('Artículos'), findsWidgets);
    expect(find.text('Caja'), findsOneWidget);
  });
}
