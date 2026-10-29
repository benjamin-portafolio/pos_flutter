/// Contract only: does not start remote services or promote standalone history.
class SaleAdjustmentDeliveryPolicy {
  static Map<String, Object?> forMode(
    String mode, {
    required bool integrationVerified,
  }) {
    if (mode != 'standalone' && mode != 'server_sync') {
      throw const FormatException('Modo inválido.');
    }
    if (mode == 'server_sync' && !integrationVerified) {
      throw StateError(
        'Se requiere compatibilidad verificada para registrar ajustes en modo servidor.',
      );
    }
    return {
      'delivery_status': mode == 'standalone' ? 'not_required' : 'pending',
      'persist_refs': mode == 'server_sync',
    };
  }

  /// statuses: pending/accepted/conflict/rejected/not_required; null = unavailable.
  /// Never substitutes a local sequence or adjustment revision for the base sequence.
  static Map<String, Object?> resolveBase(
    String baseEventId,
    List<String> dependencies,
    Map<String, Map<String, Object?>> events,
  ) {
    var waiting = false;
    for (final id in {...dependencies, baseEventId}) {
      final e = events[id];
      if (e != null &&
          ['conflict', 'rejected', 'not_required'].contains(e['status'])) {
        return {'status': 'incident', 'base_server_sequence': null};
      }
      if (e == null || e['status'] == 'pending') {
        waiting = true;
        continue;
      }
      if (e['status'] != 'accepted' ||
          e['server_sequence'] is! int ||
          (e['server_sequence'] as int) <= 0 ||
          (e['server_sequence'] as int) > 9007199254740991) {
        throw const FormatException('Dependencia oficial inválida.');
      }
    }
    return waiting
        ? {'status': 'pending', 'base_server_sequence': null}
        : {
            'status': 'ready',
            'base_server_sequence': events[baseEventId]!['server_sequence'],
          };
  }
}
