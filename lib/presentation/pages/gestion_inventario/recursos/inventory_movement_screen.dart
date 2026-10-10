import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../domain/repositories/recurso_inventario_repository.dart';
import 'models/inventory_movement_draft.dart';
import 'widgets/inventory_form_card.dart';
import 'widgets/inventory_movement_section.dart';

/// Registra un movimiento sobre un recurso ya vinculado, sin nombre ni unidad.
///
/// Reutiliza la misma sección de movimientos del formulario de recursos, así
/// que comparte controles y validaciones. El saldo que muestra se observa
/// desde el repositorio y es el vigente al abrir la pantalla. El movimiento se
/// guarda por separado: no depende de guardar el producto ni de la variante que
/// abrió la pantalla.
class InventoryMovementScreen extends StatefulWidget {
  const InventoryMovementScreen({
    required this.repository,
    required this.inventoryItemId,
    required this.resourceLabel,
    required this.onRegister,
    super.key,
  });

  final RecursoInventarioRepository repository;
  final String inventoryItemId;

  /// Texto de consulta que identifica el recurso o la variante dueña.
  final String resourceLabel;

  final Future<void> Function(InventoryMovementDraft movement) onRegister;

  @override
  State<InventoryMovementScreen> createState() =>
      _InventoryMovementScreenState();
}

class _InventoryMovementScreenState extends State<InventoryMovementScreen> {
  final _movementKey = GlobalKey<InventoryMovementSectionState>();
  StreamSubscription<RecursoInventarioListado?>? _resourceSubscription;
  RecursoInventarioListado? _resource;
  bool _loading = true;
  bool _saving = false;
  bool _canPop = false;
  String? _registerError;

  @override
  void initState() {
    super.initState();
    _resourceSubscription = widget.repository
        .watchRecursoPorId(widget.inventoryItemId)
        .listen(
          (resource) {
            if (!mounted) return;
            setState(() {
              _resource = resource;
              _loading = false;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _resource = null;
              _loading = false;
            });
          },
        );
  }

  @override
  void dispose() {
    _resourceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resource = _resource;
    return PopScope<bool>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        key: const Key('inventory_movement_screen'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('close_inventory_movement_button'),
            onPressed: _saving ? null : _requestClose,
            icon: const Icon(Icons.close),
            tooltip: 'Cancelar',
          ),
          title: const Text('Registrar movimiento'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const Key('register_inventory_movement_button'),
                onPressed: _saving || resource == null ? null : _register,
                style: TextButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('REGISTRAR MOVIMIENTO'),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF2F3F5),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (resource == null)
                  _buildUnavailable(colorScheme)
                else ...[
                  InventoryFormCard(
                    child: ListTile(
                      key: const Key('inventory_movement_resource'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(resource.nombre),
                      subtitle: Text(
                        '${widget.resourceLabel} · Unidad: '
                        '${resource.unidadPredeterminada.nombre} '
                        '(${resource.unidadPredeterminada.simbolo})',
                      ),
                      trailing: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'El nombre y la unidad del recurso no se editan aquí.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Material(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'El movimiento se guarda de forma independiente. '
                      'Permanece registrado aunque después canceles la edición '
                      'del producto o de la variante.',
                      key: const Key('inventory_movement_independent_note'),
                      style: TextStyle(color: colorScheme.onSecondaryContainer),
                    ),
                  ),
                ),
                if (resource != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Movimiento',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  InventoryMovementSection(
                    key: _movementKey,
                    mode: InventoryMovementSectionMode.movement,
                    unit: resource.unidadPredeterminada,
                    currentBalanceAtomic: resource.existenciaAtomica,
                    busy: _saving,
                    quantityRequired: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La existencia resultante es una previsión: puede cambiar '
                    'si ocurren ventas u otros movimientos.',
                    key: const Key('inventory_movement_projection_note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_registerError != null) ...[
                  const SizedBox(height: 16),
                  Material(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _registerError!,
                        key: const Key('inventory_movement_save_error'),
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'El recurso de inventario ya no está disponible.',
          key: const Key('inventory_movement_resource_unavailable'),
          style: TextStyle(color: colorScheme.onErrorContainer),
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (_saving) return;
    final section = _movementKey.currentState;
    if (section == null) return;
    if (!section.validate()) return;
    final draft = section.readDraft();
    if (draft == null) return;
    setState(() {
      _saving = true;
      _registerError = null;
    });
    try {
      await widget.onRegister(draft);
      if (!mounted) return;
      setState(() => _canPop = true);
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _registerError = 'No se pudo registrar el movimiento.';
      });
    }
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!(_movementKey.currentState?.hasPendingChanges ?? false)) {
      setState(() => _canPop = true);
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('inventory_movement_discard_dialog'),
        title: const Text('Descartar cambios'),
        content: const Text(
          'El movimiento capturado no se registrará. ¿Quieres descartarlo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CONTINUAR EDITANDO'),
          ),
          FilledButton(
            key: const Key('discard_inventory_movement_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DESCARTAR'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _canPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.of(context).pop(false);
  }
}
