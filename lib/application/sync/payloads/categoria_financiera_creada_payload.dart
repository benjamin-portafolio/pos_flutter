import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/finanzas/financial_direction.dart';
import '../../../domain/finanzas/financial_nature.dart';
import '../local_event_store.dart';

/// Payload tipado de `categoria_financiera_creada` (contrato §5.1). La
/// categoría se crea vacía en el dispositivo; `name` se normaliza NFKC+trim
/// (1..100 code points) y `direction`/`nature` son explícitas e inmutables
/// desde el alta. Espejo de `CategoriaFinancieraCreadaPayload` de NestJS.
class CategoriaFinancieraCreadaPayload {
  CategoriaFinancieraCreadaPayload._({
    required this.name,
    required this.direction,
    required this.nature,
  });

  static const aggregateType = 'financial_category';
  static const eventType = 'categoria_financiera_creada';

  final String name;
  final FinancialDirection direction;
  final FinancialNature nature;

  factory CategoriaFinancieraCreadaPayload.fromJson(
    Map<String, Object?> json,
  ) {
    final name = categoriaFinancieraName(json['name']);
    final direction = financialDirection(json['direction']);
    final nature = financialNature(json['nature']);
    if (direction == FinancialDirection.income && nature.onlyOut) {
      throw const FormatException('nature no es compatible con la dirección.');
    }
    return CategoriaFinancieraCreadaPayload._(
      name: name,
      direction: direction,
      nature: nature,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'direction': direction.code,
    'nature': nature.code,
  };

  /// Refs declaradas y validadas en ambos modos; standalone no las persiste
  /// (contrato §3.3).
  List<LocalEventRef> refs(String id) => [
    LocalEventRef.affects(refType: aggregateType, refId: id),
  ];
}

/// Nombre de categoría: string NFKC+trim obligatorio de 1..100 code points.
String categoriaFinancieraName(Object? value) {
  if (value is! String) {
    throw const FormatException(
      'El nombre de la categoría financiera es obligatorio.',
    );
  }
  final normalized = unorm.nfkc(value).trim();
  if (normalized.isEmpty) {
    throw const FormatException(
      'El nombre de la categoría financiera es obligatorio.',
    );
  }
  if (normalized.runes.length > 100) {
    throw const FormatException('name debe tener entre 1 y 100 caracteres.');
  }
  return normalized;
}

/// Dirección `in`/`out` (contrato §5.1, error canónico).
FinancialDirection financialDirection(Object? value) {
  if (value is! String) {
    throw const FormatException('direction debe ser in u out.');
  }
  return FinancialDirection.fromCode(value);
}

/// Naturaleza de los 5 valores (contrato §5.1, error canónico).
FinancialNature financialNature(Object? value) {
  if (value is! String) {
    throw const FormatException('nature no está permitida.');
  }
  return FinancialNature.fromCode(value);
}

/// Texto opcional: `null` se conserva; string vacío o solo espacios se
/// normaliza a `null`; el resto se normaliza NFKC+trim con 1..maxLength code
/// points (contrato §5.2).
String? financialOptionalText(Object? value, String fieldName, int maxLength) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$fieldName debe ser texto.');
  }
  final normalized = unorm.nfkc(value).trim();
  if (normalized.isEmpty) return null;
  if (normalized.runes.length > maxLength) {
    throw FormatException(
      '$fieldName debe tener entre 1 y $maxLength caracteres.',
    );
  }
  return normalized;
}