import 'package:flutter/material.dart';

import '../../../../../domain/articulos/importe_comercial_codec.dart';
import '../../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../../domain/inventario/movimiento_inventario.dart';
import '../../../../../domain/inventario/tipo_movimiento_inventario.dart';
import '../../../../../domain/inventario/unidad_inventario.dart';
import '../../../../../domain/repositories/recurso_inventario_repository.dart';
import 'inventory_form_card.dart';

/// Consulta reactiva del libro de movimientos del recurso, sin modificarlo.
class InventoryMovementHistory extends StatefulWidget {
  const InventoryMovementHistory({
    required this.repository,
    required this.inventoryItemId,
    required this.unit,
    super.key,
  });

  final RecursoInventarioRepository repository;
  final String inventoryItemId;
  final UnidadInventario unit;

  @override
  State<InventoryMovementHistory> createState() =>
      _InventoryMovementHistoryState();
}

class _InventoryMovementHistoryState extends State<InventoryMovementHistory> {
  static const _pageSize = 20;
  int _limit = _pageSize;
  String? _type;
  DateTimeRange? _period;
  late Stream<List<MovimientoInventario>> _stream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant InventoryMovementHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.inventoryItemId != widget.inventoryItemId) {
      _limit = _pageSize;
      _subscribe();
    }
  }

  void _subscribe() {
    final end = _period?.end;
    _stream = widget.repository.watchMovimientos(
      widget.inventoryItemId,
      movementType: _type,
      desde: _period?.start,
      hasta: end == null ? null : DateTime(end.year, end.month, end.day + 1),
      limit: _limit + 1,
    );
  }

  void _changeFilters() {
    _limit = _pageSize;
    _subscribe();
  }

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final period = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _period,
      helpText: 'Periodo del historial',
      saveText: 'APLICAR',
      confirmText: 'APLICAR',
    );
    if (!mounted || period == null) return;
    setState(() {
      _period = period;
      _changeFilters();
    });
  }

  static String _typeLabel(String code) => switch (code) {
    'initial_balance' => 'Existencia inicial',
    'stock_receipt' => 'Reposición',
    'manual_adjustment' => 'Ajuste manual',
    'sale_consumption' => 'Consumo por venta',
    'sale_void_restock' => 'Restitución por cancelación',
    'sale_return_restock' => 'Devolución de venta',
    'reversal' => 'Reversión',
    _ => 'Otro movimiento ($code)',
  };

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${_shortDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _quantity(MovimientoInventario movement) =>
      '${movement.quantityDeltaAtomic > 0 ? '+' : ''}'
      '${const InventoryQuantityCodec().formatAtomic(movement.quantityDeltaAtomic, widget.unit)} '
      '${widget.unit.simbolo}';

  Widget _direction(MovimientoInventario movement) => Icon(
    movement.quantityDeltaAtomic > 0 ? Icons.south_west : Icons.north_east,
    semanticLabel: movement.quantityDeltaAtomic > 0 ? 'Entrada' : 'Salida',
    color: movement.quantityDeltaAtomic > 0
        ? Colors.green.shade800
        : Colors.red.shade800,
  );

  Widget _details(MovimientoInventario movement) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (movement.reason != null) Text(movement.reason!),
      Text(
        movement.totalCostMinor == null
            ? 'Sin costo registrado'
            : 'Costo total: \$${const ImporteComercialCodec().format(movement.totalCostMinor!)}',
      ),
      if (movement.saleId != null)
        SelectableText('Venta: ${movement.saleId}')
      else if (movement.saleItemId != null)
        SelectableText('Línea de venta: ${movement.saleItemId}'),
      if (movement.reversalOfMovementId != null)
        SelectableText('Compensa movimiento: ${movement.reversalOfMovementId}'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('inventory_movement_history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Historial de movimientos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                key: const Key('inventory_history_type'),
                initialValue: _type ?? 'all',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('Todos')),
                  for (final type in TipoMovimientoInventario.values)
                    DropdownMenuItem(
                      value: type.code,
                      child: Text(_typeLabel(type.code)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _type = value == 'all' ? null : value;
                  _changeFilters();
                }),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('inventory_history_period'),
              onPressed: _pickPeriod,
              icon: const Icon(Icons.date_range),
              label: Text(
                _period == null
                    ? 'Periodo: todos'
                    : '${_shortDate(_period!.start)} – ${_shortDate(_period!.end)}',
              ),
            ),
            if (_period != null)
              IconButton(
                tooltip: 'Quitar filtro de periodo',
                onPressed: () => setState(() {
                  _period = null;
                  _changeFilters();
                }),
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<MovimientoInventario>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('No se pudo cargar el historial.'),
                  TextButton(
                    onPressed: () => setState(_subscribe),
                    child: const Text('REINTENTAR'),
                  ),
                ],
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final movements = snapshot.data ?? const <MovimientoInventario>[];
            if (movements.isEmpty) {
              return const Text(
                'No hay movimientos para los filtros seleccionados.',
              );
            }
            final visible = movements.take(_limit).toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 900) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          dataRowMinHeight: 80,
                          dataRowMaxHeight: double.infinity,
                          columns: const [
                            DataColumn(label: Text('Fecha y hora')),
                            DataColumn(label: Text('Tipo')),
                            DataColumn(label: Text('Cantidad'), numeric: true),
                            DataColumn(label: Text('Detalle')),
                          ],
                          rows: visible
                              .map(
                                (movement) => DataRow(
                                  cells: [
                                    DataCell(
                                      Text(_date(movement.createdAtLocal)),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          _direction(movement),
                                          const SizedBox(width: 8),
                                          Text(
                                            _typeLabel(movement.movementType),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text(_quantity(movement))),
                                    DataCell(
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: SizedBox(
                                          width: 320,
                                          child: _details(movement),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final movement in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InventoryFormCard(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(_date(movement.createdAtLocal)),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _direction(movement),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _typeLabel(movement.movementType),
                                          ),
                                        ),
                                        Text(
                                          _quantity(movement),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _details(movement),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (movements.length > _limit)
                  TextButton(
                    key: const Key('inventory_history_load_more'),
                    onPressed: () => setState(() {
                      _limit += _pageSize;
                      _subscribe();
                    }),
                    child: const Text('Cargar más'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
