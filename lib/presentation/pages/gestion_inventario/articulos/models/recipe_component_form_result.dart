import 'package:flutter/foundation.dart';

import '../../../../../domain/inventario/recurso_inventario_listado.dart';

@immutable
class RecipeComponentFormResult {
  const RecipeComponentFormResult({
    required this.resource,
    required this.quantity,
  });

  final RecursoInventarioListado resource;
  final String quantity;
}
