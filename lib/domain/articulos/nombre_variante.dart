import 'package:unorm_dart/unorm_dart.dart' as unorm;

class NombreVariante {
  const NombreVariante._({required this.value, required this.nameKey});

  factory NombreVariante.fromInput(String? input) {
    final normalized = unorm.nfkc(input ?? '').trim();
    if (normalized.isEmpty) {
      return const NombreVariante._(value: null, nameKey: null);
    }
    if (normalized.runes.length > 160) {
      throw ArgumentError.value(
        input,
        'nombreVariante',
        'No puede exceder 160 caracteres.',
      );
    }
    return NombreVariante._(
      value: normalized,
      nameKey: normalized.toLowerCase(),
    );
  }

  final String? value;
  final String? nameKey;
}
