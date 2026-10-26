/// Lógica de la PC: catálogo, ventas recibidas, conflictos y dispositivos.
library;

import 'dart:convert';
import 'dart:io';

import 'backend.dart';
import 'db_abstracta.dart';
import 'sha256.dart';

const _columnasProducto = [
  'id', 'codigo_barras', 'nombre', 'descripcion', 'categoria', 'precio_compra',
  'precio_venta', 'stock', 'stock_minimo', 'tipo_venta', 'fecha_creacion',
  'fecha_actualizacion', 'variantes', 'tamanos', 'conjuntos',
];
const _columnasVenta = [
  'id', 'subtotal', 'descuento', 'total', 'metodo_pago', 'monto_pagado',
  'vuelto', 'fecha', 'nota',
];
const _columnasItem = [
  'id', 'venta_id', 'producto_id', 'producto_nombre', 'codigo_barras',
  'precio_unitario', 'precio_compra', 'cantidad', 'subtotal', 'tipo_venta',
  'variante_talla', 'variante_color', 'variante_color_hex', 'tamano_nombre',
  'tamano_precio', 'conjuntos_elegidos',
];

class PcSyncBackend implements SyncBackend {
  final SyncDb db;
  final DateTime Function() ahora;

  PcSyncBackend(this.db, {DateTime Function()? ahora}) : ahora = ahora ?? DateTime.now;

  /// Acción que la PC pidió al celular ('productos', 'ventas' o 'todo').
  String? accionSolicitada;

  /// Crea o actualiza las tablas de sincronización (baja lógica incluida).
  static Future<void> migrar(SyncDb db) async {
    Future<Set<String>> columnas(String tabla) async =>
        (await db.query('PRAGMA table_info($tabla)')).map((c) => '${c['name']}').toSet();

    if (!(await columnas('productos')).contains('activo')) {
      await db.run('ALTER TABLE productos ADD COLUMN activo INTEGER NOT NULL DEFAULT 1');
    }
    await db.run(
      'CREATE TABLE IF NOT EXISTS ventas_importadas '
      '(id TEXT PRIMARY KEY, importada_en TEXT NOT NULL, dispositivo_id TEXT)',
    );
    if (!(await columnas('ventas_importadas')).contains('dispositivo_id')) {
      await db.run('ALTER TABLE ventas_importadas ADD COLUMN dispositivo_id TEXT');
    }
    await db.run(
      'CREATE TABLE IF NOT EXISTS sync_dispositivos ('
      'id TEXT PRIMARY KEY, nombre TEXT NOT NULL, secreto TEXT NOT NULL, '
      'creado_en TEXT NOT NULL, ultimo_contacto TEXT, ultima_sync TEXT, '
      'ventas_recibidas INTEGER NOT NULL DEFAULT 0, ultimo_error TEXT)',
    );
    await db.run(
      'CREATE TABLE IF NOT EXISTS sync_conflictos ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id TEXT NOT NULL, '
      'producto_id TEXT, producto_nombre TEXT, tipo TEXT NOT NULL, '
      'solicitado INTEGER NOT NULL, descontado INTEGER NOT NULL, '
      'dispositivo_id TEXT, fecha TEXT NOT NULL)',
    );
  }

  // ---------- Dispositivos ----------

  @override
  Future<void> registrarDispositivo(String id, String nombre, String secreto) async {
    final ts = ahora().toIso8601String();
    final existe = await db.query('SELECT id FROM sync_dispositivos WHERE id = ?', [id]);
    if (existe.isEmpty) {
      await db.run(
        'INSERT INTO sync_dispositivos (id, nombre, secreto, creado_en, ultimo_contacto) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, nombre, secreto, ts, ts],
      );
    } else {
      await db.run(
        'UPDATE sync_dispositivos SET nombre = ?, secreto = ?, ultimo_contacto = ? WHERE id = ?',
        [nombre, secreto, ts, id],
      );
    }
  }

  @override
  Future<String?> secretoDe(String dispositivoId) async {
    final f = await db.query(
      'SELECT secreto FROM sync_dispositivos WHERE id = ?',
      [dispositivoId],
    );
    return f.isEmpty ? null : '${f.first['secreto']}';
  }

  Future<List<Map<String, Object?>>> dispositivos() => db.query(
        'SELECT id, nombre, creado_en, ultimo_contacto, ultima_sync, '
        'ventas_recibidas, ultimo_error FROM sync_dispositivos ORDER BY nombre',
      );

  Future<void> revocarDispositivo(String id) async {
    await db.run('DELETE FROM sync_dispositivos WHERE id = ?', [id]);
  }

  Future<List<Map<String, Object?>>> conflictos({int limite = 100}) => db.query(
        'SELECT * FROM sync_conflictos ORDER BY id DESC LIMIT ?',
        [limite],
      );

  void solicitar(String accion) => accionSolicitada = accion;

  // ---------- Estado y catálogo ----------

  Future<String> versionCatalogo() async {
    final f = await db.query(
      'SELECT COUNT(*) AS c, COALESCE(MAX(fecha_actualizacion), \'\') AS m, '
      'COALESCE(SUM(stock), 0) AS s, '
      'COALESCE(SUM(CASE WHEN activo = 0 THEN 1 ELSE 0 END), 0) AS i, '
      'COALESCE(SUM(precio_venta), 0) AS p FROM productos',
    );
    final r = f.first;
    return sha256Texto('${r['c']}|${r['m']}|${r['s']}|${r['i']}|${r['p']}').substring(0, 16);
  }

  @override
  Future<Map<String, Object?>> estado(String dispositivoId) async {
    await db.run(
      'UPDATE sync_dispositivos SET ultimo_contacto = ? WHERE id = ?',
      [ahora().toIso8601String(), dispositivoId],
    );
    final d = await db.query(
      'SELECT ventas_recibidas FROM sync_dispositivos WHERE id = ?',
      [dispositivoId],
    );
    return {
      'accion': accionSolicitada,
      'catalogoVersion': await versionCatalogo(),
      'ventasRecibidas': d.isEmpty ? 0 : d.first['ventas_recibidas'],
      'ahora': ahora().toIso8601String(),
    };
  }

  static Future<String?> _versionImagen(String? ruta) async {
    if (ruta == null || ruta.isEmpty) return null;
    try {
      final f = File(ruta);
      if (!await f.exists()) return null;
      final st = await f.stat();
      return '${st.size}-${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, Object?>> catalogo() async {
    final filas = await db.query(
      'SELECT ${_columnasProducto.join(', ')}, imagen_url FROM productos WHERE activo = 1',
    );
    final productos = <Map<String, Object?>>[];
    for (final f in filas) {
      final p = <String, Object?>{for (final c in _columnasProducto) c: f[c]};
      p['imagen_version'] = await _versionImagen(f['imagen_url'] as String?);
      productos.add(p);
    }
    final eliminados = await db.query('SELECT id FROM productos WHERE activo = 0');
    final categorias = await db.query('SELECT nombre FROM categorias ORDER BY nombre');
    return {
      'version': await versionCatalogo(),
      'productos': productos,
      'eliminados': [for (final e in eliminados) '${e['id']}'],
      'categorias': [for (final c in categorias) '${c['nombre']}'],
    };
  }

  @override
  Future<File?> imagen(String productoId) async {
    final f = await db.query(
      'SELECT imagen_url FROM productos WHERE id = ? AND activo = 1',
      [productoId],
    );
    if (f.isEmpty) return null;
    final ruta = f.first['imagen_url'] as String?;
    if (ruta == null || ruta.isEmpty) return null;
    return File(ruta);
  }

  // ---------- Ventas recibidas ----------

  @override
  Future<List<Map<String, Object?>>> recibirVentas(
    String dispositivoId,
    List<Map<String, Object?>> ventas,
  ) async {
    final resultados = <Map<String, Object?>>[];
    var nuevas = 0;
    for (final venta in ventas) {
      final id = '${venta['id'] ?? ''}';
      try {
        final r = await db.transaction((tx) => _aplicarVenta(tx, dispositivoId, venta));
        if (r['estado'] == 'ok' || r['estado'] == 'conflicto') nuevas++;
        resultados.add(r);
      } catch (e) {
        resultados.add({'id': id, 'estado': 'error', 'mensaje': '$e'});
      }
    }
    if (nuevas > 0) {
      await db.run(
        'UPDATE sync_dispositivos SET ventas_recibidas = ventas_recibidas + ? WHERE id = ?',
        [nuevas, dispositivoId],
      );
    }
    return resultados;
  }

  static int _entero(Object? v, String campo) {
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    throw FormatException('$campo no es un número entero válido');
  }

  static double _decimal(Object? v, String campo) {
    if (v is num) return v.toDouble();
    throw FormatException('$campo no es un número válido');
  }

  Future<Map<String, Object?>> _aplicarVenta(
    SyncDb tx,
    String dispositivoId,
    Map<String, Object?> venta,
  ) async {
    final id = '${venta['id'] ?? ''}';
    if (id.isEmpty) throw const FormatException('Venta sin id');

    final repetida = await tx.query('SELECT id FROM ventas_importadas WHERE id = ?', [id]);
    final existente = await tx.query('SELECT id FROM ventas WHERE id = ?', [id]);
    if (repetida.isNotEmpty || existente.isNotEmpty) {
      return {'id': id, 'estado': 'duplicada', 'mensaje': 'Ya estaba registrada'};
    }

    // Validación completa antes de tocar el inventario.
    _decimal(venta['total'], 'total');
    _decimal(venta['subtotal'], 'subtotal');
    if (DateTime.tryParse('${venta['fecha']}') == null) {
      throw const FormatException('fecha no válida');
    }
    final items = venta['items'];
    if (items is! List || items.isEmpty) {
      throw const FormatException('La venta no tiene productos');
    }
    final itemsValidos = <Map<String, Object?>>[];
    for (final raw in items) {
      if (raw is! Map) throw const FormatException('Producto de venta no válido');
      final it = Map<String, Object?>.from(raw);
      if (_entero(it['cantidad'], 'cantidad') <= 0) {
        throw const FormatException('cantidad debe ser mayor que cero');
      }
      _decimal(it['precio_unitario'], 'precio_unitario');
      _decimal(it['subtotal'], 'subtotal del producto');
      if ('${it['producto_id'] ?? ''}'.isEmpty || '${it['producto_nombre'] ?? ''}'.isEmpty) {
        throw const FormatException('Producto sin id o nombre');
      }
      itemsValidos.add(it);
    }

    final ts = ahora().toIso8601String();
    final conflictos = <Map<String, Object?>>[];
    final filasItems = <Map<String, Object?>>[];

    for (var n = 0; n < itemsValidos.length; n++) {
      final it = itemsValidos[n];
      final cantidad = _entero(it['cantidad'], 'cantidad');
      final idOriginal = '${it['producto_id']}';
      final nombre = '${it['producto_nombre']}';

      var f = await tx.query('SELECT * FROM productos WHERE id = ?', [idOriginal]);
      if (f.isEmpty) {
        final codigo = '${it['codigo_barras'] ?? ''}'.trim();
        if (codigo.isNotEmpty) {
          f = await tx.query(
            'SELECT * FROM productos WHERE codigo_barras = ? AND activo = 1 LIMIT 1',
            [codigo],
          );
        }
      }
      if (f.isEmpty) {
        f = await tx.query(
          'SELECT * FROM productos WHERE nombre = ? COLLATE NOCASE AND activo = 1 LIMIT 1',
          [nombre],
        );
      }

      var idFinal = idOriginal;
      if (f.isEmpty) {
        conflictos.add({
          'producto_id': idOriginal, 'producto_nombre': nombre,
          'tipo': 'producto_desconocido', 'solicitado': cantidad, 'descontado': 0,
        });
      } else {
        final prod = f.first;
        idFinal = '${prod['id']}';
        if (_entero(prod['activo'], 'activo') == 0) {
          conflictos.add({
            'producto_id': idFinal, 'producto_nombre': nombre,
            'tipo': 'producto_eliminado', 'solicitado': cantidad, 'descontado': 0,
          });
        } else {
          final stock = _entero(prod['stock'], 'stock');
          final talla = '${it['variante_talla'] ?? ''}';
          final color = '${it['variante_color'] ?? ''}';
          List<dynamic> variantes = const [];
          var idx = -1;
          if (talla.isNotEmpty || color.isNotEmpty) {
            try {
              variantes = List<dynamic>.from(jsonDecode('${prod['variantes'] ?? '[]'}') as List);
            } catch (_) {
              variantes = [];
            }
            idx = variantes.indexWhere(
              (v) => v is Map && '${v['talla'] ?? ''}' == talla && '${v['color'] ?? ''}' == color,
            );
          }
          var disponible = stock;
          if (idx >= 0) {
            final sv = (variantes[idx]['stock'] as num?)?.toInt() ?? 0;
            disponible = sv < stock ? sv : stock;
          }
          if (disponible < 0) disponible = 0;
          final descontar = cantidad < disponible ? cantidad : disponible;
          if (descontar < cantidad) {
            conflictos.add({
              'producto_id': idFinal, 'producto_nombre': nombre,
              'tipo': 'stock_insuficiente', 'solicitado': cantidad, 'descontado': descontar,
            });
          }
          if (descontar > 0) {
            if (idx >= 0) {
              final v = Map<String, Object?>.from(variantes[idx] as Map);
              v['stock'] = ((v['stock'] as num?)?.toInt() ?? 0) - descontar;
              variantes[idx] = v;
              await tx.run(
                'UPDATE productos SET stock = stock - ?, variantes = ?, fecha_actualizacion = ? WHERE id = ?',
                [descontar, jsonEncode(variantes), ts, idFinal],
              );
            } else {
              await tx.run(
                'UPDATE productos SET stock = stock - ?, fecha_actualizacion = ? WHERE id = ?',
                [descontar, ts, idFinal],
              );
            }
          }
        }
      }

      final fila = <String, Object?>{
        for (final c in _columnasItem)
          if (it.containsKey(c)) c: it[c],
      };
      fila['id'] = '${it['id'] ?? ''}'.isEmpty ? '$id-$n' : '${it['id']}';
      fila['venta_id'] = id;
      fila['producto_id'] = idFinal;
      filasItems.add(fila);
    }

    final filaVenta = <String, Object?>{
      for (final c in _columnasVenta)
        if (venta.containsKey(c)) c: venta[c],
    };
    await _insertar(tx, 'ventas', filaVenta);
    for (final fila in filasItems) {
      await _insertar(tx, 'items_venta', fila);
    }
    await tx.run(
      'INSERT INTO ventas_importadas (id, importada_en, dispositivo_id) VALUES (?, ?, ?)',
      [id, ts, dispositivoId],
    );
    for (final c in conflictos) {
      await tx.run(
        'INSERT INTO sync_conflictos (venta_id, producto_id, producto_nombre, tipo, '
        'solicitado, descontado, dispositivo_id, fecha) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, c['producto_id'], c['producto_nombre'], c['tipo'], c['solicitado'],
          c['descontado'], dispositivoId, ts],
      );
    }

    return {
      'id': id,
      'estado': conflictos.isEmpty ? 'ok' : 'conflicto',
      'mensaje': conflictos.isEmpty
          ? 'Registrada'
          : conflictos
              .map((c) => '${c['producto_nombre']}: ${c['tipo']} '
                  '(pedido ${c['solicitado']}, descontado ${c['descontado']})')
              .join('; '),
      'conflictos': conflictos.length,
    };
  }

  static Future<void> _insertar(SyncDb tx, String tabla, Map<String, Object?> fila) async {
    final cols = fila.keys.toList();
    await tx.run(
      'INSERT INTO $tabla (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
      [for (final c in cols) fila[c]],
    );
  }

  @override
  Future<void> sincronizacionTerminada(String dispositivoId, Map<String, Object?> resumen) async {
    final error = resumen['error'];
    await db.run(
      'UPDATE sync_dispositivos SET ultima_sync = ?, ultimo_error = ? WHERE id = ?',
      [ahora().toIso8601String(), error == null ? null : '$error', dispositivoId],
    );
    if (error == null) accionSolicitada = null;
  }
}
