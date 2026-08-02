class CategoriaMovidaPayload {
  const CategoriaMovidaPayload({
    required this.baseEventId,
    required this.ordenAnterior,
    required this.ordenNuevo,
    required this.categoriaDesplazadaId,
    required this.categoriaDesplazadaBaseEventId,
    required this.categoriaDesplazadaBaseVersion,
    required this.categoriaDesplazadaBaseServerSequence,
    required this.categoriaDesplazadaOrdenAnterior,
    required this.categoriaDesplazadaOrdenNuevo,
  });

  static const aggregateType = 'category';
  static const eventType = 'categoria_movida';
  static const sortOrderField = 'sort_order';

  final String baseEventId;
  final int ordenAnterior;
  final int ordenNuevo;
  final String categoriaDesplazadaId;
  final String categoriaDesplazadaBaseEventId;
  final int categoriaDesplazadaBaseVersion;
  final int? categoriaDesplazadaBaseServerSequence;
  final int categoriaDesplazadaOrdenAnterior;
  final int categoriaDesplazadaOrdenNuevo;

  factory CategoriaMovidaPayload.fromValues({
    required String baseEventId,
    required int ordenAnterior,
    required int ordenNuevo,
    required String categoriaDesplazadaId,
    required String categoriaDesplazadaBaseEventId,
    required int categoriaDesplazadaBaseVersion,
    required int? categoriaDesplazadaBaseServerSequence,
    required int categoriaDesplazadaOrdenAnterior,
    required int categoriaDesplazadaOrdenNuevo,
  }) {
    return CategoriaMovidaPayload._validated(
      baseEventId: baseEventId,
      ordenAnterior: ordenAnterior,
      ordenNuevo: ordenNuevo,
      categoriaDesplazadaId: categoriaDesplazadaId,
      categoriaDesplazadaBaseEventId: categoriaDesplazadaBaseEventId,
      categoriaDesplazadaBaseVersion: categoriaDesplazadaBaseVersion,
      categoriaDesplazadaBaseServerSequence:
          categoriaDesplazadaBaseServerSequence,
      categoriaDesplazadaOrdenAnterior: categoriaDesplazadaOrdenAnterior,
      categoriaDesplazadaOrdenNuevo: categoriaDesplazadaOrdenNuevo,
    );
  }

  factory CategoriaMovidaPayload.fromJson(Map<String, Object?> json) {
    final changedFields = json['changed_fields'];
    if (changedFields is! List ||
        changedFields.length != 1 ||
        changedFields.single != sortOrderField) {
      throw const FormatException(
        'categoria_movida requiere changed_fields = [sort_order].',
      );
    }

    final changes = _readMap(json['changes'], 'changes');
    final sortOrder = _readMap(changes[sortOrderField], 'changes.sort_order');
    final displaced = _readMap(
      json['displaced_category'],
      'displaced_category',
    );
    final displacedSortOrder = _readMap(
      displaced[sortOrderField],
      'displaced_category.sort_order',
    );

    return CategoriaMovidaPayload._validated(
      baseEventId: _readRequiredString(json['base_event_id'], 'base_event_id'),
      ordenAnterior: _readNonNegativeInt(
        sortOrder['from'],
        'changes.sort_order.from',
      ),
      ordenNuevo: _readNonNegativeInt(sortOrder['to'], 'changes.sort_order.to'),
      categoriaDesplazadaId: _readRequiredString(
        displaced['category_id'],
        'displaced_category.category_id',
      ),
      categoriaDesplazadaBaseEventId: _readRequiredString(
        displaced['base_event_id'],
        'displaced_category.base_event_id',
      ),
      categoriaDesplazadaBaseVersion: _readPositiveInt(
        displaced['base_version'],
        'displaced_category.base_version',
      ),
      categoriaDesplazadaBaseServerSequence: _readNullableNonNegativeInt(
        displaced['base_server_sequence'],
        'displaced_category.base_server_sequence',
      ),
      categoriaDesplazadaOrdenAnterior: _readNonNegativeInt(
        displacedSortOrder['from'],
        'displaced_category.sort_order.from',
      ),
      categoriaDesplazadaOrdenNuevo: _readNonNegativeInt(
        displacedSortOrder['to'],
        'displaced_category.sort_order.to',
      ),
    );
  }

  factory CategoriaMovidaPayload._validated({
    required String baseEventId,
    required int ordenAnterior,
    required int ordenNuevo,
    required String categoriaDesplazadaId,
    required String categoriaDesplazadaBaseEventId,
    required int categoriaDesplazadaBaseVersion,
    required int? categoriaDesplazadaBaseServerSequence,
    required int categoriaDesplazadaOrdenAnterior,
    required int categoriaDesplazadaOrdenNuevo,
  }) {
    final normalizedBaseEventId = _readRequiredString(
      baseEventId,
      'base_event_id',
    );
    final normalizedDisplacedId = _readRequiredString(
      categoriaDesplazadaId,
      'displaced_category.category_id',
    );
    final normalizedDisplacedBaseEventId = _readRequiredString(
      categoriaDesplazadaBaseEventId,
      'displaced_category.base_event_id',
    );
    final previousOrder = _readNonNegativeInt(
      ordenAnterior,
      'changes.sort_order.from',
    );
    final nextOrder = _readNonNegativeInt(ordenNuevo, 'changes.sort_order.to');
    final displacedPreviousOrder = _readNonNegativeInt(
      categoriaDesplazadaOrdenAnterior,
      'displaced_category.sort_order.from',
    );
    final displacedNextOrder = _readNonNegativeInt(
      categoriaDesplazadaOrdenNuevo,
      'displaced_category.sort_order.to',
    );
    final displacedBaseVersion = _readPositiveInt(
      categoriaDesplazadaBaseVersion,
      'displaced_category.base_version',
    );
    final displacedBaseServerSequence = _readNullableNonNegativeInt(
      categoriaDesplazadaBaseServerSequence,
      'displaced_category.base_server_sequence',
    );

    if ((previousOrder - displacedPreviousOrder).abs() != 1 ||
        nextOrder != displacedPreviousOrder ||
        displacedNextOrder != previousOrder) {
      throw const FormatException(
        'categoria_movida debe intercambiar posiciones consecutivas.',
      );
    }

    return CategoriaMovidaPayload(
      baseEventId: normalizedBaseEventId,
      ordenAnterior: previousOrder,
      ordenNuevo: nextOrder,
      categoriaDesplazadaId: normalizedDisplacedId,
      categoriaDesplazadaBaseEventId: normalizedDisplacedBaseEventId,
      categoriaDesplazadaBaseVersion: displacedBaseVersion,
      categoriaDesplazadaBaseServerSequence: displacedBaseServerSequence,
      categoriaDesplazadaOrdenAnterior: displacedPreviousOrder,
      categoriaDesplazadaOrdenNuevo: displacedNextOrder,
    );
  }

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'changed_fields': const [sortOrderField],
    'changes': {
      sortOrderField: {'from': ordenAnterior, 'to': ordenNuevo},
    },
    'displaced_category': {
      'category_id': categoriaDesplazadaId,
      'base_event_id': categoriaDesplazadaBaseEventId,
      'base_version': categoriaDesplazadaBaseVersion,
      'base_server_sequence': categoriaDesplazadaBaseServerSequence,
      sortOrderField: {
        'from': categoriaDesplazadaOrdenAnterior,
        'to': categoriaDesplazadaOrdenNuevo,
      },
    },
  };

  static Map<String, Object?> _readMap(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('categoria_movida requiere $field.');
  }

  static String _readRequiredString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('categoria_movida requiere $field.');
    }
    return value.trim();
  }

  static int _readNonNegativeInt(Object? value, String field) {
    final parsed = _readInt(value);
    if (parsed == null || parsed < 0) {
      throw FormatException('categoria_movida requiere $field entero >= 0.');
    }
    return parsed;
  }

  static int _readPositiveInt(Object? value, String field) {
    final parsed = _readInt(value);
    if (parsed == null || parsed < 1) {
      throw FormatException('categoria_movida requiere $field entero >= 1.');
    }
    return parsed;
  }

  static int? _readNullableNonNegativeInt(Object? value, String field) {
    if (value == null) return null;
    return _readNonNegativeInt(value, field);
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return null;
  }
}
