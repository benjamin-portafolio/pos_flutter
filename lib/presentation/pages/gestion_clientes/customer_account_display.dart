import '../../../domain/creditos/account_entry.dart';

class CustomerAccountDisplay {
  static String money(BigInt value) {
    final n = value.abs(), h = BigInt.from(100);
    return '${value.isNegative ? '-' : ''}\$${n ~/ h}.${(n % h).toString().padLeft(2, '0')}';
  }

  static String status(AccountEntry e) => switch (e.deliveryStatus) {
    'not_required' => 'Registro local',
    'delivered' => 'Sincronizado',
    'conflict' || 'rejected' => 'Requiere atención',
    _ => 'Pendiente de sincronizar',
  };
}
