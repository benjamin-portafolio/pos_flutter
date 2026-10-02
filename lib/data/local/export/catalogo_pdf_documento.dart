/// Lo que el catálogo PDF muestra, ya agrupado y ya ordenado.
///
/// Es un modelo aparte del render porque el PDF es binario y no se puede
/// inspeccionar en un test: la composición vive en datos y la escritura en
/// pixeles, y cada una se prueba por su lado. El render no decide ni un nombre,
/// ni un orden, ni un precio: solo dibuja lo que este modelo dice.
///
/// No comparte contrato de columnas con el CSV (D8): el PDF es una
/// presentación para el cliente, no un archivo que se reimporta.
class CatalogoPdfDocumento {
  const CatalogoPdfDocumento({
    required this.negocio,
    required this.generado,
    required this.categorias,
    this.telefono,
  });

  /// Nombre del negocio. Va en el título y en el pie de cada página.
  final String negocio;

  /// Teléfono de contacto. Cuando es null el pie omite la línea de contacto en
  /// vez de imprimir un dato inventado.
  final String? telefono;

  /// Momento de la generación, que es también la fecha que ve el cliente.
  final DateTime generado;

  /// Categorías en el orden en que salen: primero las que tienen nombre por
  /// orden alfabético, y al final las que no lo tienen.
  final List<CatalogoPdfCategoria> categorias;

  /// Artículos distintos del catálogo, uno por producto y no por variante.
  int get articulos {
    var total = 0;
    for (final categoria in categorias) {
      total += categoria.articulos.length;
    }
    return total;
  }

  /// Líneas del catálogo, una por variante activa.
  int get lineas {
    var total = 0;
    for (final categoria in categorias) {
      for (final articulo in categoria.articulos) {
        total += articulo.lineas.length;
      }
    }
    return total;
  }
}

/// Categoría con su encabezado en el PDF y los artículos que le pertenecen.
class CatalogoPdfCategoria {
  const CatalogoPdfCategoria({required this.nombre, required this.articulos});

  final String nombre;
  final List<CatalogoPdfArticulo> articulos;
}

/// Producto del catálogo. El nombre se escribe una sola vez, en su primera
/// línea, y las siguientes líneas muestran solo el nombre de la variante.
class CatalogoPdfArticulo {
  const CatalogoPdfArticulo({required this.nombre, required this.lineas});

  final String nombre;
  final List<CatalogoPdfLinea> lineas;
}

/// Línea del catálogo, una por variante activa.
///
/// La etiqueta de unidad no es decorativa: sin ella "Arroz 28" no dice si son
/// kilos o piezas, así que viaja en el modelo y nunca se puede omitir al
/// dibujar.
class CatalogoPdfLinea {
  const CatalogoPdfLinea({
    required this.precioVentaMinor,
    required this.etiquetaUnidad,
    this.nombreVariante,
    this.codigoBarras,
  });

  /// Nombre de la variante, o null cuando el producto tiene una sola.
  final String? nombreVariante;

  /// Código de barras de la variante, en texto legible. También es el contenido
  /// del QR, y solo se dibuja QR cuando existe.
  final String? codigoBarras;

  /// Precio de venta en centavos, como en el resto del dominio.
  final int precioVentaMinor;

  /// "por kg", "por unidad": la unidad a la que corresponde el precio.
  final String etiquetaUnidad;

  bool get tieneCodigoBarras => codigoBarras != null;
}
