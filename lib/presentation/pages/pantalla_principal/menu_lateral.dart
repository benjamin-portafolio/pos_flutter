import '../caja/cash_management_screen.dart';
import '../cuenta/declarar_saldo_cuenta_screen.dart';
import '../gestion_clientes/clientes_screen.dart';
import 'package:flutter/material.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/presentation/pages/finanzas/ingresos_y_gastos_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_mesa/table_management.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_page.dart';

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Encabezado
          Container(
            color: Colors.blue,
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Text("M", style: TextStyle(color: Colors.black)),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Miradent",
                            style: TextStyle(color: Colors.white),
                          ),
                          Text(
                            "+524341548804",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit, color: Colors.white),
                  ],
                ),
                SizedBox(height: 10),
                Container(
                  color: Colors.purple,
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "PREMIUM\nUsted es nuestro Usuario Premium",
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Icon(Icons.expand_more, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _CashMenuTile(),
          const _BankMenuTile(),
          // Usuario
          ListTile(
            title: Text("BENJAMÍN ALVARADO GONZÁLEZ (staff)"),
            subtitle: Text("orejonnar@gmail.com"),
            trailing: Text(
              "EDITAR PERFIL",
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Gestión",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // Opciones del menú
          ListTile(
            leading: Icon(Icons.settings),
            title: Text("Configuracion"),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => const SyncSettingsPage(),
                  ),
                );
              });
            },
          ),
          const _InventoryMenuTile(),
          ListTile(
            leading: Icon(Icons.swap_horiz),
            title: Text("Ingresos y gastos"),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => const IngresosYGastosScreen(),
                  ),
                );
              });
            },
          ),
          ListTile(
            leading: Icon(Icons.people),
            title: Text("Gestión de clientes"),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                navigator.push(
                  MaterialPageRoute(builder: (_) => const ClientesScreen()),
                );
              });
            },
          ),
          ListTile(
            leading: Icon(Icons.table_chart),
            title: Text("Gestión de la mesa"),
            trailing: _buildBadge(19),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TableManagementScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// La entrada de inventarios muestra cuantas variantes estan dadas de alta.
/// El conteo viene del catalogo local y se actualiza solo cuando cambia. La
/// consulta se abre una vez: el drawer se reconstruye con frecuencia.
class _InventoryMenuTile extends StatefulWidget {
  const _InventoryMenuTile();

  @override
  State<_InventoryMenuTile> createState() => _InventoryMenuTileState();
}

class _InventoryMenuTileState extends State<_InventoryMenuTile> {
  late final Stream<int> _variantCount = getIt<ProductoRepository>()
      .watchVariantesActivasCount();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _variantCount,
      builder: (context, snapshot) {
        return ListTile(
          leading: const Icon(Icons.inventory),
          title: const Text("Gestión de inventarios"),
          trailing: _buildBadge(snapshot.data ?? 0),
          onTap: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              navigator.push(
                MaterialPageRoute(
                  builder: (context) => const InventoryManagementScreen(),
                ),
              );
            });
          },
        );
      },
    );
  }
}

Widget _buildBadge(int count) {
  return count > 0
      ? Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
          child: Text(
            count.toString(),
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        )
      : SizedBox.shrink();
}

/// La entrada de saldo en cuenta solo existe cuando la declaracion esta
/// habilitada en la instalacion. Es una pantalla aparte de caja: el saldo
/// bancario no es efectivo de cajon.
class _BankMenuTile extends StatelessWidget {
  const _BankMenuTile();

  @override
  Widget build(BuildContext context) {
    final controller = getIt<AppConfigController>();
    return StreamBuilder<AppConfig>(
      initialData: controller.config,
      stream: controller.changes,
      builder: (context, snapshot) {
        if (snapshot.data?.bankEnabled != true) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.account_balance),
          title: const Text('Saldo en cuenta bancaria'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DeclararSaldoCuentaScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

/// La entrada de caja solo existe cuando la captura esta habilitada en la
/// instalacion. Escucha el ajuste para reflejarse sin reiniciar la app.
class _CashMenuTile extends StatelessWidget {
  const _CashMenuTile();

  @override
  Widget build(BuildContext context) {
    final controller = getIt<AppConfigController>();
    return StreamBuilder<AppConfig>(
      initialData: controller.config,
      stream: controller.changes,
      builder: (context, snapshot) {
        if (snapshot.data?.cashEnabled != true) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.point_of_sale),
          title: const Text('Apertura y corte de caja'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CashManagementScreen(),
              ),
            );
          },
        );
      },
    );
  }
}
