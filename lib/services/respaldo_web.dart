import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'database_service.dart';

/// Genera el JSON que entiende el botón "Restaurar copia" de la web de la
/// tienda y "Subir respaldo" de la app del celular.
class RespaldoWeb {
  static String _slug(String texto) {
    final s = texto
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'sin-categoria' : s;
  }

  static String _mime(String ruta) => switch (p.extension(ruta).toLowerCase()) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.gif' => 'image/gif',
        '.bmp' => 'image/bmp',
        _ => 'image/jpeg',
      };

  /// Devuelve el JSON y la cantidad de productos incluidos.
  static Future<({String json, int productos})> generar() async {
    final db = DatabaseService.instance;
    final productos = await db.obtenerProductos();
    final nombresCategorias = await db.obtenerCategorias();

    final categorias = <String, Map<String, Object?>>{};
    void agregarCategoria(String nombre) {
      final id = 'c${_slug(nombre)}';
      categorias.putIfAbsent(id, () => {'id': id, 'name': nombre, 'icon': '📁'});
    }

    // Incluye también las categorías que aún no tienen productos.
    for (final c in nombresCategorias) {
      if (c.trim().isNotEmpty) agregarCategoria(c.trim());
    }

    final productosWeb = <Map<String, Object?>>[];
    for (final producto in productos) {
      final categoria = (producto.categoria ?? '').trim().isEmpty
          ? 'General'
          : producto.categoria!.trim();
      agregarCategoria(categoria);

      var imagen = '';
      final ruta = producto.imagenUrl;
      if (ruta != null && ruta.isNotEmpty) {
        final archivo = File(ruta);
        if (await archivo.exists()) {
          imagen =
              'data:${_mime(ruta)};base64,${base64Encode(await archivo.readAsBytes())}';
        }
      }

      final descripcion = (producto.descripcion ?? '').trim();
      productosWeb.add({
        'id': producto.id,
        'name': producto.nombre,
        'cat': 'c${_slug(categoria)}',
        'price': producto.precioVenta,
        'old': null,
        'stock': producto.stock,
        'image': imagen,
        'desc': descripcion.isEmpty ? 'Producto de calidad.' : descripcion,
        'featured': false,
      });
    }

    final json = const JsonEncoder.withIndent('  ').convert({
      'cats': categorias.values.toList(),
      'prods': productosWeb,
      'cfg': <String, Object?>{},
    });
    return (json: json, productos: productosWeb.length);
  }
}
