import 'confirm_supplier_order_draft_deletion.dart';
import '../../../../application/commands/proveedores/cancel_supplier_order_command.dart';
import 'supplier_order_detail_screen.dart';
import '../../../../application/commands/articulos/producto_command_service.dart';
import '../../../../application/commands/inventario/inventory_command_service.dart';
import '../../../../application/config/app_config_controller.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../../../domain/repositories/recurso_inventario_repository.dart';
import '../../../../domain/repositories/unidad_inventario_repository.dart';
import '../../../../domain/repositories/proveedor_repository.dart';
import '../../informes/remaining_stock_variant_editor.dart';
import 'package:flutter/material.dart';
import '../../../../domain/proveedores/supplier_order_failed_attempt.dart';
import '../../../../application/commands/proveedores/recover_supplier_order_command.dart';
import '../../../../application/sync/projections/supplier_order_projection_store.dart';
import '../../../../application/sync/supplier_order_operation.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/repositories/supplier_order_repository.dart';
import '../../../../domain/proveedores/replenishment_candidate.dart';
import '../../../../domain/proveedores/replenishment_issue.dart';
import '../../../../domain/proveedores/supplier_order_summary.dart';
import '../../../../application/commands/proveedores/supplier_order_command_service.dart';
import 'supplier_order_forms.dart';
import 'supplier_order_editor_screen.dart';

class SupplierOrdersScreen extends StatefulWidget {
  const SupplierOrdersScreen({this.supplierId, this.onConfigure, super.key});
  final String? supplierId;
  final Future<void> Function(String productId, String variantId)? onConfigure;
  @override
  State<SupplierOrdersScreen> createState() => _SupplierOrdersScreenState();
}

class _SupplierOrdersScreenState extends State<SupplierOrdersScreen> {
  late final repository = getIt<SupplierOrderRepository>();
  late final candidates = repository.watchCandidates();
  late final orders = repository.watchOrders();
  late final issues = repository.watchIssues();
  late final failed = repository.watchFailedAttempts();
  String search = '';
  bool busy = false;
  Future<void> _configure(String productId, String variantId) async {
    if (widget.onConfigure != null) {
      await widget.onConfigure!(productId, variantId);
      return;
    }
    try {
      await RemainingStockVariantEditor(
        repository: getIt<ProductoRepository>(),
        commands: getIt<ProductoCommandService>(),
        resources: getIt<RecursoInventarioRepository>(),
        units: getIt<UnidadInventarioRepository>(),
        inventoryCommands: getIt<InventoryCommandService>(),
        suppliers: getIt<ProveedorRepository>(),
        config: getIt<AppConfigController>(),
      ).open(context, productoId: productId, varianteId: variantId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _open(String id, {bool detail = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => detail
            ? SupplierOrderDetailScreen(orderId: id)
            : SupplierOrderEditorScreen(orderId: id),
      ),
    );
  }

  Future<void> _deleteDraft(SupplierOrderSummary summary) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final order = await getIt<SupplierOrderProjectionStore>().find(
        summary.id,
      );
      if (!mounted) return;
      if (order == null || order.status != 'draft') {
        throw StateError('El pedido dejó de ser borrador. Revisa el listado.');
      }
      if (!await confirmSupplierOrderDraftDeletion(
            context,
            order.document.supplierNameSnapshot,
          ) ||
          !mounted) {
        return;
      }
      await getIt<SupplierOrderCommandService>().cancel(
        CancelSupplierOrderCommand(
          eventId: const Uuid().v4(),
          orderId: order.id,
          baseEventId: order.lastEventId!,
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar el borrador: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _recover(SupplierOrderFailedAttempt attempt) async {
    final source = await getIt<SupplierOrderProjectionStore>().eventById(
      attempt.eventId,
    );
    if (source == null) return;
    final doc = SupplierOrderOperation.decode(source).document;
    if (doc == null) return;
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar intención en otro borrador'),
        content: Text(
          '${attempt.reason}\nSe copiarán las cantidades, precios y notas del intento original. El pedido vigente se conserva. Revisa el nuevo borrador antes de confirmar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear borrador recuperado'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final id = const Uuid().v4();
      await getIt<SupplierOrderCommandService>().recover(
        RecoverSupplierOrderCommand(
          eventId: const Uuid().v4(),
          orderId: id,
          sourceEventId: source.eventId,
          itemIds: {for (final l in doc.items) l.id: const Uuid().v4()},
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (mounted) await _open(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _prepare(List<ReplenishmentCandidate> rows) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final id = const Uuid().v4();
      final selected = rows
          .where((c) => c.isCurrent && c.suggestedAtomic > 0)
          .toList();
      if (selected.length > 50) {
        throw StateError(
          'Hay más de 50 partidas. Filtra la selección para preparar otro pedido.',
        );
      }
      final doc = orderDocument(
        id: id,
        base: null,
        supplierId: selected.first.supplierId,
        name: selected.first.supplierName,
        phone: selected.first.supplierPhone,
        currency: 'MXN',
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        items: selected
            .map((c) => candidateLine(c, const Uuid().v4(), c.suggestedAtomic))
            .toList(),
      );
      if (mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                SupplierOrderEditorScreen(orderId: id, initialDocument: doc),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos a proveedores'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: StreamBuilder<List<SupplierOrderSummary>>(
            stream: orders,
            builder: (context, snapshot) => TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Sugerencias'),
                _orderTab('Borradores', {'draft'}, snapshot.data),
                _orderTab('Pendientes de recibir', {
                  'confirmed',
                  'partial',
                }, snapshot.data),
                _orderTab('Historial', {
                  'cancelled',
                  'closed',
                  'received',
                }, snapshot.data),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar proveedor o producto',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Las sugerencias usan el saldo y los pedidos conocidos en esta terminal.',
                      ),
                    ),
                    StreamBuilder<List<ReplenishmentCandidate>>(
                      stream: candidates,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return ListTile(
                            title: Text(
                              'No se pudieron calcular las sugerencias: ${snapshot.error}',
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final groups = <String, List<ReplenishmentCandidate>>{};
                        for (final c in snapshot.data!) {
                          if (!c.isCurrent ||
                              c.targetAtomic == null ||
                              (widget.supplierId != null &&
                                  c.supplierId != widget.supplierId)) {
                            continue;
                          }
                          if (!'${c.productName} ${c.variantName ?? ''} ${c.supplierName}'
                              .toLowerCase()
                              .contains(search)) {
                            continue;
                          }
                          groups.putIfAbsent(c.supplierId, () => []).add(c);
                        }
                        if (groups.isEmpty) {
                          return ListTile(
                            title: Text(
                              search.isEmpty
                                  ? 'No hay sugerencias disponibles.'
                                  : 'No hay sugerencias para esta búsqueda.',
                            ),
                          );
                        }
                        return Column(
                          children: groups.values
                              .map(
                                (rows) => Card(
                                  child: ExpansionTile(
                                    key: PageStorageKey(
                                      'supplier_suggestions_${rows.first.supplierId}',
                                    ),
                                    title: Text(rows.first.supplierName),
                                    subtitle: Text(
                                      '${rows.length} ${rows.length == 1 ? 'producto' : 'productos'} · ${rows.where((c) => c.suggestedAtomic > 0).length} por reponer',
                                    ),
                                    children: [
                                      ...rows.map(
                                        (c) => ListTile(
                                          title: Text(
                                            '${c.productName} ${c.variantName ?? ''}',
                                          ),
                                          subtitle: Text(
                                            'Saldo: ${candidateQuantity(c, c.balanceAtomic)} · Objetivo: ${candidateQuantity(c, c.targetAtomic!)} · Pendiente: ${candidateQuantity(c, c.pendingAtomic)} ${c.unitSymbol}\nSugerido: ${candidateQuantity(c, c.suggestedAtomic)} ${c.unitSymbol}',
                                          ),
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed:
                                            busy ||
                                                !rows.any(
                                                  (c) => c.suggestedAtomic > 0,
                                                )
                                            ? null
                                            : () => _prepare(rows),
                                        child: const Text('Preparar pedido'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    StreamBuilder<List<ReplenishmentIssue>>(
                      stream: issues,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const ListTile(
                            title: Text('No se pudo revisar la configuración.'),
                          );
                        }
                        final rows = snapshot.data ?? <ReplenishmentIssue>[];
                        if (rows.isEmpty) return const SizedBox.shrink();
                        return Card(
                          child: ExpansionTile(
                            key: const PageStorageKey(
                              'supplier_configuration_issues',
                            ),
                            leading: const Icon(Icons.settings_outlined),
                            title: Text(
                              'Configuración por revisar (${rows.length})',
                            ),
                            subtitle: const Text(
                              'Despliega para ver los avisos y corregirlos.',
                            ),
                            children: [
                              for (final issue in rows)
                                ListTile(
                                  title: Text(issue.name),
                                  subtitle: Text(issue.reason),
                                  trailing: TextButton(
                                    onPressed: () => _configure(
                                      issue.productId,
                                      issue.variantId,
                                    ),
                                    child: const Text('Corregir'),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Continúa un pedido guardado. Los borradores no reservan cantidades.',
                      ),
                    ),
                    _orderList(
                      {'draft'},
                      emptyMessage:
                          'No tienes borradores guardados. Prepara un pedido desde Sugerencias.',
                    ),
                    StreamBuilder<List<SupplierOrderFailedAttempt>>(
                      stream: failed,
                      builder: (context, snapshot) => Column(
                        children: [
                          if (snapshot.hasError)
                            const ListTile(
                              title: Text(
                                'No se pudieron cargar los intentos fallidos.',
                              ),
                            ),
                          if (snapshot.hasData && snapshot.data!.isNotEmpty)
                            const ListTile(
                              title: Text('Intentos fallidos'),
                              subtitle: Text(
                                'Revisa los intentos que necesitan atención.',
                              ),
                            ),
                          for (final attempt
                              in snapshot.data ??
                                  <SupplierOrderFailedAttempt>[])
                            ListTile(
                              title: Text(
                                '${attempt.supplierName} · ${attempt.status}',
                              ),
                              subtitle: Text(attempt.reason),
                              onTap: attempt.canRecoverDraft
                                  ? () => _recover(attempt)
                                  : null,
                              trailing: const Icon(Icons.restore),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  child: _orderList({'confirmed', 'partial'}),
                ),
                SingleChildScrollView(
                  child: _orderList({'cancelled', 'closed', 'received'}),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _orderTab(
    String label,
    Set<String> states,
    List<SupplierOrderSummary>? rows,
  ) {
    final count = rows
        ?.where(
          (o) =>
              states.contains(o.status) &&
              (widget.supplierId == null || o.supplierId == widget.supplierId),
        )
        .length;
    return Tab(
      key: ValueKey('supplier_orders_tab_${states.first}'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null) ...[
            const SizedBox(width: 8),
            Badge(label: Text('$count')),
          ],
        ],
      ),
    );
  }

  String _savedDate(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}';
  }

  Widget _orderList(
    Set<String> states, {
    String emptyMessage = 'No hay pedidos en esta sección.',
  }) => StreamBuilder<List<SupplierOrderSummary>>(
    stream: orders,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const ListTile(
          title: Text('No se pudieron cargar los pedidos.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data!.where(
        (o) =>
            states.contains(o.status) &&
            (widget.supplierId == null || o.supplierId == widget.supplierId) &&
            o.supplierName.toLowerCase().contains(search),
      );
      if (rows.isEmpty) {
        return ListTile(
          title: Text(
            search.isEmpty
                ? emptyMessage
                : 'No hay pedidos para esta búsqueda.',
          ),
        );
      }
      return Column(
        children: rows
            .map(
              (o) => ListTile(
                key: ValueKey(o.id),
                title: Text(o.supplierName),
                subtitle: Text(
                  o.status == 'draft'
                      ? 'Guardado el ${_savedDate(o.occurredAtMs)}\nTotal estimado: ${o.totalMinor == null ? 'Sin precio conocido' : '\$${orderMoney(o.totalMinor)} MXN'}${o.overlaps ? '\nHay pedidos abiertos que se solapan. Revisa cantidades antes de comprar.' : ''}${o.issue == null ? '' : '\n${o.issue}'}'
                      : '${o.status} · ${o.deliveryStatus} · ${o.id}\n${orderMoney(o.totalMinor)}${o.overlaps ? '\nHay pedidos abiertos que se solapan. Revisa cantidades antes de comprar.' : ''}${o.issue == null ? '' : '\n${o.issue}'}',
                ),
                trailing: o.status == 'draft'
                    ? IconButton(
                        tooltip: 'Eliminar borrador',
                        onPressed: busy ? null : () => _deleteDraft(o),
                        icon: const Icon(Icons.delete_outline),
                      )
                    : null,
                onTap: busy
                    ? null
                    : () => _open(o.id, detail: o.status != 'draft'),
              ),
            )
            .toList(),
      );
    },
  );
}
