# Ícono de PuntoÁgil

`app_icon.png` es el símbolo de la P azul con palomita verde, adaptado del logotipo proporcionado por el usuario. Es un PNG de 1024 × 1024 con fondo transparente. Se usa con fondo blanco en el ícono adaptable de Android y en iOS.

Para regenerar los recursos nativos desde la raíz del proyecto:

```sh
dart run flutter_launcher_icons
```

La configuración está en `flutter_launcher_icons.yaml`. Estos archivos son recursos de compilación; no necesitan declararse como assets de Flutter. Los cambios requieren volver a compilar e instalar la aplicación.

Con `flutter_launcher_icons` 0.14.4, revisar el diff de `ios/Runner.xcodeproj/project.pbxproj` después de regenerar: la herramienta puede asignar `AppIcon` a otras opciones de catálogo. `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` debe conservar el valor `YES`; solo `ASSETCATALOG_COMPILER_APPICON_NAME` debe contener `AppIcon`.

## Generación de la imagen

Modo: herramienta integrada de generación de imágenes (`image_gen`), edición con imagen de referencia; después se normalizó el tamaño a 1024 × 1024.

Prompt utilizado:

```text
Use case: precise-object-edit. Asset type: production Flutter mobile app launcher icon foreground. Input image: edit target, the attached PuntoÁgil logo. Extract and faithfully preserve ONLY the upper standalone dark navy blue P monogram with the overlapping bright emerald green checkmark. Remove all wordmarks ('PuntoÁgil', 'PUNTO DE VENTA'), all other lettering, background, haze and large glows. Keep the original silhouette, proportions, orientation and the checkmark's position over the P; do not redesign the brand or add new shapes. Make edges crisp and smooth and use solid rich dark navy (#062D4A) for the P and emerald green (#00C779) for the checkmark, with only very subtle original shading. True transparent background, no baked checkerboard, no white tile, no rounded enclosing container, no cast shadow. Square 1024 by 1024 PNG canvas. Center the full symbol horizontally and vertically with its longest extent occupying about 70 percent of the canvas, all edges fully visible, generous equal transparent safety margins. This is a single isolated brand symbol, no text, no watermark.
```
