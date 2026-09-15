import 'package:flutter/material.dart';

import '../../application/commands/venta_borrador_command_service.dart';
import '../../core/di/injection.dart';
import '../../domain/repositories/producto_repository.dart';
import '../../domain/repositories/sale_draft_repository.dart';
import '../pages/articulos/article_search_screen.dart';

class ArticleSearchBar extends StatelessWidget {
  const ArticleSearchBar({
    this.productoRepository,
    this.saleDraftRepository,
    this.ventaBorradorCommandService,
    this.onOpenCaja,
    this.showQuickAdd = true,
    super.key,
  });

  final SaleDraftRepository? saleDraftRepository;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final VoidCallback? onOpenCaja;
  final ProductoRepository? productoRepository;
  final bool showQuickAdd;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              readOnly: true,
              showCursor: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArticleSearchScreen(
                    saleDraftRepository: saleDraftRepository,
                    ventaBorradorCommandService: ventaBorradorCommandService,
                    onOpenCaja: onOpenCaja,
                    productoRepository:
                        productoRepository ?? getIt<ProductoRepository>(),
                  ),
                ),
              ),
              decoration: InputDecoration(
                hintText: 'Quiero vender…',
                prefixIcon: Icon(Icons.search, color: primaryColor),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed: null,
            tooltip: 'Código de barras',
            disabledColor: primaryColor,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          if (showQuickAdd) ...[
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: null,
              tooltip: 'Alta rápida de artículo',
              disabledColor: primaryColor,
              icon: const Icon(Icons.bolt),
            ),
          ],
        ],
      ),
    );
  }
}
