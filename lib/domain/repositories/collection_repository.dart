import '../cobros/collection_entry.dart';

abstract interface class CollectionRepository {
  /// Stream reutilizable con snapshot inicial para cada suscriptor.
  /// Incluye cobros locales aplicados, aun pendientes o con incidencia de entrega.
  Stream<List<CollectionEntry>> watchCollections();
}
