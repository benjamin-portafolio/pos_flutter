import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../../application/commands/finanzas/categoria_financiera_command_service.dart';
import '../../../../application/commands/finanzas/crear_categoria_financiera_command.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/finanzas/financial_category.dart';
import '../../../../domain/finanzas/financial_direction.dart';
import '../../../../domain/repositories/financial_category_repository.dart';
import '../forms/categoria_financiera_form_screen.dart';
import '../models/categoria_financiera_form_result.dart';

/// Selector de categorías financieras de una dirección (ingreso o gasto):
/// cuadrícula adaptable a tablet con búsqueda. Estado vacío invita a crear una
/// categoría; al crearla desde aquí se selecciona y devuelve automáticamente.
class FinancialCategoryPickerScreen extends StatefulWidget {
  const FinancialCategoryPickerScreen({
    super.key,
    required this.direction,
    this.repository,
    this.commandService,
  });

  final FinancialDirection direction;
  final FinancialCategoryRepository? repository;
  final CategoriaFinancieraCommandService? commandService;

  @override
  State<FinancialCategoryPickerScreen> createState() =>
      _FinancialCategoryPickerScreenState();
}

class _FinancialCategoryPickerScreenState
    extends State<FinancialCategoryPickerScreen> {
  late final Stream<List<FinancialCategory>> _categories =
      (widget.repository ?? getIt<FinancialCategoryRepository>())
          .watchCategories();
  String _query = '';

  CategoriaFinancieraCommandService get _commandService =>
      widget.commandService ?? getIt<CategoriaFinancieraCommandService>();

  String _normalize(String value) => unorm
      .nfkd(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .trim();

  List<FinancialCategory> _filter(List<FinancialCategory> all) {
    final query = _normalize(_query);
    return all
        .where((c) => c.direction == widget.direction)
        .where((c) => query.isEmpty || _normalize(c.name).contains(query))
        .toList();
  }

  Future<void> _crearCategoria() async {
    final result = await Navigator.of(context).push<CategoriaFinancieraFormResult>(
      MaterialPageRoute(
        builder: (_) => CategoriaFinancieraFormScreen(
          direction: widget.direction,
          onSave: (result) => _commandService.crear(
            CrearCategoriaFinancieraCommand(
              categoryId: result.categoryId,
              name: result.name,
              direction: result.direction,
              nature: result.nature,
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    // Creación desde el selector: se selecciona automáticamente al regresar.
    Navigator.of(context).pop(result.toCategory());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Categorías de ${widget.direction.label.toLowerCase()}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('categoria_busqueda'),
              decoration: InputDecoration(
                labelText: 'Buscar categorías',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () => setState(() => _query = ''),
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<FinancialCategory>>(
              stream: _categories,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('No se pudieron cargar las categorías.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = _filter(snapshot.data!);
                if (rows.isEmpty) {
                  return _estadoVacio(
                    hayCategorias: snapshot.data!.isNotEmpty,
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final category = rows[index];
                    return Card(
                      child: InkWell(
                        key: ValueKey('categoria_${category.id}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(category),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                category.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                category.nature.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const Key('categoria_nueva'),
          onPressed: _crearCategoria,
          icon: const Icon(Icons.add),
          label: Text('Nueva categoría'),
        ),
      ),
    );
  }

  Widget _estadoVacio({required bool hayCategorias}) {
    if (hayCategorias) {
      return const Center(
        child: Text('No hay categorías que coincidan.'),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.category_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'Aún no hay categorías de '
              '${widget.direction.label.toLowerCase()}.',
            ),
            const SizedBox(height: 4),
            const Text(
              'Crea una categoría para poder registrar el movimiento.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}