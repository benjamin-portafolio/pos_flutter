import '../local_event_store.dart';
import 'inventory_movement_payload.dart';
import 'recurso_inventario_creado_payload.dart';

/// Descarte de un recurso de inventario autogenerado y realmente vacío.
///
/// Contrato de evento propio del contrato rev. 1 §6.3. Solo existe para
/// `standalone`: el sobre se emite con `delivery_status = not_required`, no se
/// persiste en el servidor y el servidor lo rechaza funcionalmente. La forma
/// canónica no declara `inventory_item_id` porque el agregado del evento ya es
/// el recurso; la referencia `affects` se completa con el identificador que el
/// command service conoce al construir el evento.
class RecursoInventarioDescartadoPayload {
  const RecursoInventarioDescartadoPayload({
    required this.baseEventId,
    required this.triggerProductId,
    required this.triggerProductEventId,
    required this.originVariantId,
    required this.policyVersion,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'recurso_inventario_descartado';

  /// Única versión de política admitida. Un valor distinto se rechaza en el
  /// contrato, antes de evaluar elegibilidad o borrar nada.
  static const supportedPolicyVersion = 1;

  /// Estado de entrega obligatorio: el descarte nunca se envía al servidor.
  static const deliveryStatus = 'not_required';

  /// Último evento del recurso observado; acredita versión y secuencia base.
  final String baseEventId;

  /// Producto responsable de la desvinculación que habilitó el descarte.
  final String triggerProductId;

  /// Evento de producto aplicado que quitó el vínculo de `originVariantId`.
  /// No puede ser el alta del recurso: son eventos de agregados distintos.
  final String triggerProductEventId;

  /// Procedencia comprobada del recurso, igual a la variante desvinculada.
  /// Aquí es obligatoria: sin procedencia explícita no hay descarte posible.
  final String originVariantId;

  /// Versión de la política de descarte que evalúa la elegibilidad.
  final int policyVersion;

  factory RecursoInventarioDescartadoPayload.create({
    required String baseEventId,
    required String triggerProductId,
    required String triggerProductEventId,
    required String originVariantId,
    int policyVersion = supportedPolicyVersion,
  }) {
    final base = InventoryMovementPayload.requiredUuidV4(
      baseEventId,
      'base_event_id',
    );
    final triggerEvent = InventoryMovementPayload.requiredUuidV4(
      triggerProductEventId,
      'trigger_product_event_id',
    );
    if (base == triggerEvent) {
      throw const FormatException(
        'El disparador del descarte no puede ser el alta del recurso.',
      );
    }
    if (policyVersion != supportedPolicyVersion) {
      throw const FormatException('policy_version solo admite 1.');
    }
    return RecursoInventarioDescartadoPayload(
      baseEventId: base,
      triggerProductId: InventoryMovementPayload.requiredUuidV4(
        triggerProductId,
        'trigger_product_id',
      ),
      triggerProductEventId: triggerEvent,
      originVariantId: InventoryMovementPayload.requiredUuidV4(
        originVariantId,
        RecursoInventarioCreadoPayload.originVariantIdField,
      ),
      policyVersion: policyVersion,
    );
  }

  factory RecursoInventarioDescartadoPayload.fromJson(
    Map<String, Object?> json,
  ) {
    _assertOnlyKeys(json, {
      'base_event_id',
      'trigger_product_id',
      'trigger_product_event_id',
      RecursoInventarioCreadoPayload.originVariantIdField,
      'policy_version',
    });
    final policyVersion = json['policy_version'];
    if (policyVersion is! int) {
      throw const FormatException('policy_version debe ser un entero.');
    }
    return RecursoInventarioDescartadoPayload.create(
      baseEventId: _requiredText(json['base_event_id'], 'base_event_id'),
      triggerProductId: _requiredText(
        json['trigger_product_id'],
        'trigger_product_id',
      ),
      triggerProductEventId: _requiredText(
        json['trigger_product_event_id'],
        'trigger_product_event_id',
      ),
      originVariantId: _requiredText(
        json[RecursoInventarioCreadoPayload.originVariantIdField],
        RecursoInventarioCreadoPayload.originVariantIdField,
      ),
      policyVersion: policyVersion,
    );
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'trigger_product_id': triggerProductId,
    'trigger_product_event_id': triggerProductEventId,
    RecursoInventarioCreadoPayload.originVariantIdField: originVariantId,
    'policy_version': policyVersion,
  };

  /// Referencias declaradas por el contrato §6.3. Se declaran y validan en
  /// ambos modos; `standalone` las valida y no las persiste en `event_refs`.
  List<LocalEventRef> refs(String inventoryItemId) {
    return [
      LocalEventRef.affects(
        refType: RecursoInventarioCreadoPayload.aggregateType,
        refId: InventoryMovementPayload.requiredUuidV4(
          inventoryItemId,
          'inventory_item_id',
        ),
      ),
      LocalEventRef.uses(refType: 'product', refId: triggerProductId),
      LocalEventRef.uses(refType: 'product_variant', refId: originVariantId),
    ];
  }
}

void _assertOnlyKeys(Map<String, Object?> value, Set<String> allowed) {
  final unexpected = value.keys.where((key) => !allowed.contains(key)).toList();
  if (unexpected.isNotEmpty) {
    throw FormatException(
      '${RecursoInventarioDescartadoPayload.eventType} contiene campos no '
      'permitidos: ${unexpected.join(', ')}.',
    );
  }
}

String _requiredText(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName es obligatorio.');
  }
  return value.trim();
}
