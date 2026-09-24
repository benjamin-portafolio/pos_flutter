import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../../domain/ventas/confirmed_sale.dart';
import '../../caja/sale_receipt_screen.dart';
import 'cliente_compra_card.dart';

/// Historial de compras (ventas confirmadas) del cliente.
///
/// Filtra por el cliente seleccionado, ordena de la más reciente a la más
/// antigua y carga la lista por grupos sin perder las tarjetas anteriores.
/// El total mostrado en el título siempre es el conteo real de compras.
class ClienteComprasSection extends StatefulWidget {
  const ClienteComprasSection({
    required this.clienteId,
    this.repository,
    super.key,
  });

  final String clienteId;
  final ConfirmedSaleRepository? repository;

  /// Compras mostradas en el primer grupo y en cada "Cargar más".
  static const int pageSize = 5;

  @override
  State<ClienteComprasSection> createState() => _ClienteComprasSectionState();
}

class _ClienteComprasSectionState extends State<ClienteComprasSection> {
  late final ConfirmedSaleRepository _repository;
  late Stream<List<ConfirmedSale>> _sales;
  bool _expanded = true;
  int _visible = ClienteComprasSection.pageSize;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? getIt<ConfirmedSaleRepository>();
    _sales = _repository.watchSales();
  }

  void _retry() {
    setState(() => _sales = _repository.watchSales());
  }

  void _open(ConfirmedSale sale) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SaleReceiptScreen(
          saleId: sale.id,
          repository: _repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConfirmedSale>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(context);
        if (!snapshot.hasData) return _loading(context);
        final sales = snapshot.data!
            .where((sale) => sale.clienteId == widget.clienteId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final count = sales.length;
        final visible = _visible > count ? count : _visible;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, count),
            if (_expanded) ...[
              if (sales.isEmpty)
                _empty(context)
              else ...[
                for (final sale in sales.take(visible))
                  ClienteCompraCard(
                    key: ValueKey('cliente_compra_${sale.id}'),
                    sale: sale,
                    onTap: () => _open(sale),
                  ),
                if (visible < count) _loadMore(context),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, int count) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Compras ($count)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Center(child: CircularProgressIndicator()),
  );

  Widget _error(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        children: [
          Text(
            'No se pudieron cargar las compras.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: Text(
        'Este cliente aún no tiene compras.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _loadMore(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton(
      onPressed: () =>
          setState(() => _visible += ClienteComprasSection.pageSize),
      child: const Text('Cargar más'),
    ),
  );
}