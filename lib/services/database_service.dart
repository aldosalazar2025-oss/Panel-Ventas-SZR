import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../sync/pc_backend.dart';
import '../sync/sqflite_adapter.dart';
import 'package:path/path.dart';
import '../models/producto.dart';
import '../models/variante_producto.dart';
import '../models/venta.dart';

class DatabaseService {
  static Database? _database;
  static final DatabaseService instance = DatabaseService._init();
  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('szrventas.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Windows: SQLite por FFI, guardado en la carpeta de datos del usuario.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final carpeta = await getApplicationSupportDirectory();
    await carpeta.create(recursive: true);
    final path = join(carpeta.path, filePath);
    return await openDatabase(
      path,
      version: 8,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  static const _defaultCategories = ['Bebidas', 'Alimentos', 'Otros'];

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.delete(
        'categorias',
        where: 'nombre NOT IN (?, ?, ?)',
        whereArgs: _defaultCategories,
      );
      for (final cat in _defaultCategories) {
        await db.insert(
          'categorias',
          {'nombre': cat},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE productos ADD COLUMN tipo_venta TEXT NOT NULL DEFAULT 'unidad'",
      );
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN tipo_venta TEXT NOT NULL DEFAULT 'unidad'",
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        "ALTER TABLE productos ADD COLUMN variantes TEXT",
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN variante_talla TEXT",
      );
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN variante_color TEXT",
      );
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN variante_color_hex TEXT",
      );
    }
    if (oldVersion < 7) {
      await _crearTablaVentasImportadas(db);
    }
    if (oldVersion < 8) {
      // Sincronización por Wi-Fi: baja lógica de productos, dispositivos y conflictos.
      await PcSyncBackend.migrar(SqfliteSyncDb(db));
    }
    if (oldVersion < 6) {
      await db.execute(
        "ALTER TABLE productos ADD COLUMN tamanos TEXT",
      );
      await db.execute(
        "ALTER TABLE productos ADD COLUMN conjuntos TEXT",
      );
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN tamano_nombre TEXT",
      );
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN tamano_precio REAL",
      );
      await db.execute(
        "ALTER TABLE items_venta ADD COLUMN conjuntos_elegidos TEXT",
      );
    }
  }

  Future<void> _crearTablaVentasImportadas(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ventas_importadas '
      '(id TEXT PRIMARY KEY, importada_en TEXT NOT NULL)',
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await _crearTablaVentasImportadas(db);
    await db.execute('''
      CREATE TABLE productos (
        id TEXT PRIMARY KEY, codigo_barras TEXT NOT NULL, nombre TEXT NOT NULL,
        descripcion TEXT, categoria TEXT, precio_compra REAL NOT NULL DEFAULT 0,
        precio_venta REAL NOT NULL, stock INTEGER NOT NULL DEFAULT 0,
        stock_minimo INTEGER NOT NULL DEFAULT 5, tipo_venta TEXT NOT NULL DEFAULT 'unidad',
        imagen_url TEXT, fecha_creacion TEXT NOT NULL, fecha_actualizacion TEXT NOT NULL,
        variantes TEXT, tamanos TEXT, conjuntos TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ventas (
        id TEXT PRIMARY KEY, subtotal REAL NOT NULL, descuento REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL, metodo_pago TEXT NOT NULL, monto_pagado REAL,
        vuelto REAL, fecha TEXT NOT NULL, nota TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE items_venta (
        id TEXT PRIMARY KEY, venta_id TEXT NOT NULL, producto_id TEXT NOT NULL,
        producto_nombre TEXT NOT NULL, codigo_barras TEXT, precio_unitario REAL NOT NULL,
        precio_compra REAL NOT NULL DEFAULT 0, cantidad INTEGER NOT NULL,
        subtotal REAL NOT NULL, tipo_venta TEXT NOT NULL DEFAULT 'unidad', imagen_url TEXT,
        variante_talla TEXT, variante_color TEXT, variante_color_hex TEXT,
        tamano_nombre TEXT, tamano_precio REAL, conjuntos_elegidos TEXT,
        FOREIGN KEY (venta_id) REFERENCES ventas (id),
        FOREIGN KEY (producto_id) REFERENCES productos (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE categorias (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT NOT NULL UNIQUE)
    ''');
    for (final cat in _defaultCategories) {
      await db.insert('categorias', {'nombre': cat});
    }
    await db.execute('CREATE INDEX idx_prod_codigo ON productos (codigo_barras)');
    await db.execute('CREATE INDEX idx_ventas_fecha ON ventas (fecha)');
    await db.execute('CREATE INDEX idx_items_venta ON items_venta (venta_id)');
    await PcSyncBackend.migrar(SqfliteSyncDb(db));
  }

  Future<Producto?> obtenerProducto(String id) async {
    final db = await database;
    final maps = await db.query('productos', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Producto.fromMap(maps.first);
  }

  Future<void> insertarProducto(Producto p) async {
    final db = await database;
    await db.insert('productos', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Producto>> obtenerProductos() async {
    final db = await database;
    final maps = await db.query('productos', where: 'activo = 1', orderBy: 'nombre ASC');
    return maps.map((m) => Producto.fromMap(m)).toList();
  }

  Future<Producto?> buscarPorCodigoBarras(String codigo) async {
    final db = await database;
    final maps = await db.query('productos', where: 'codigo_barras LIKE ? AND activo = 1', whereArgs: ['%$codigo%']);
    if (maps.isEmpty) return null;
    
    for (final map in maps) {
      final codigosStr = map['codigo_barras'] as String? ?? '';
      final codigos = codigosStr.split(',').map((c) => c.trim());
      if (codigos.contains(codigo.trim())) {
        return Producto.fromMap(map);
      }
    }
    return null;
  }

  /// Busca si alguno de [codigos] ya pertenece a otro producto (distinto de [excluirId]).
  /// Devuelve el producto dueño del código duplicado, o null si ninguno está repetido.
  Future<Producto?> buscarProductoConCodigoDuplicado(
    List<String> codigos, {
    String? excluirId,
  }) async {
    final db = await database;
    for (final codigoRaw in codigos) {
      final codigo = codigoRaw.trim();
      if (codigo.isEmpty) continue;
      final maps = await db.query(
        'productos',
        where: 'codigo_barras LIKE ? AND activo = 1',
        whereArgs: ['%$codigo%'],
      );
      for (final map in maps) {
        final id = map['id'] as String;
        if (excluirId != null && id == excluirId) continue;
        final codigosStr = map['codigo_barras'] as String? ?? '';
        final codigosExistentes = codigosStr.split(',').map((c) => c.trim());
        if (codigosExistentes.contains(codigo)) {
          return Producto.fromMap(map);
        }
      }
    }
    return null;
  }

  Future<List<Producto>> buscarProductos(String query) async {
    final db = await database;
    final maps = await db.query('productos',
      where: '(nombre LIKE ? OR codigo_barras LIKE ?) AND activo = 1',
      whereArgs: ['%$query%', '%$query%'], orderBy: 'nombre ASC');
    return maps.map((m) => Producto.fromMap(m)).toList();
  }

  Future<void> actualizarProducto(Producto p) async {
    final db = await database;
    await db.update('productos', {...p.toMap(), 'activo': 1}, where: 'id = ?', whereArgs: [p.id]);
  }

  /// Baja lógica: el producto deja de verse y de venderse, pero el historial
  /// de ventas lo conserva y la sincronización avisa al celular que ya no existe.
  Future<void> eliminarProducto(String id) async {
    final db = await database;
    await db.update(
      'productos',
      {'activo': 0, 'fecha_actualizacion': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> actualizarStock(String productoId, int nuevoStock) async {
    final db = await database;
    await db.update('productos',
      {'stock': nuevoStock, 'fecha_actualizacion': DateTime.now().toIso8601String()},
      where: 'id = ?', whereArgs: [productoId]);
  }

  Future<List<Producto>> obtenerProductosStockBajo() async {
    final db = await database;
    final maps = await db.query('productos', where: 'stock <= stock_minimo AND activo = 1', orderBy: 'stock ASC');
    return maps.map((m) => Producto.fromMap(m)).toList();
  }

  Future<int> contarProductos() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM productos WHERE activo = 1');
    return r.first['c'] as int;
  }

  Future<void> registrarVenta(Venta venta) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('ventas', venta.toMap());
      for (final item in venta.items) {
        await txn.insert('items_venta', item.toMap());
        if (item.tieneVariante) {
          await _descontarStockVariante(
            txn,
            productoId: item.productoId,
            talla: item.varianteTalla ?? '',
            color: item.varianteColor ?? '',
            cantidad: item.cantidad,
          );
        } else {
          await txn.rawUpdate(
            'UPDATE productos SET stock = stock - ?, fecha_actualizacion = ? WHERE id = ?',
            [item.cantidad, DateTime.now().toIso8601String(), item.productoId]);
        }
      }
    });
  }

  /// Descuenta el stock de la combinación talla/color específica dentro
  /// de un producto, y mantiene el stock total del producto sincronizado
  /// como la suma de sus variantes.
  Future<void> _descontarStockVariante(
    Transaction txn, {
    required String productoId,
    required String talla,
    required String color,
    required int cantidad,
  }) async {
    final maps = await txn.query(
      'productos',
      where: 'id = ?',
      whereArgs: [productoId],
    );
    if (maps.isEmpty) return;
    final producto = Producto.fromMap(maps.first);

    final idx = producto.variantes.indexWhere(
      (v) => v.talla == talla && v.color == color,
    );

    final nuevasVariantes = List<VarianteProducto>.from(producto.variantes);
    if (idx >= 0) {
      final v = nuevasVariantes[idx];
      nuevasVariantes[idx] = v.copyWith(stock: v.stock - cantidad);
    }

    await txn.update(
      'productos',
      {
        'stock': producto.stock - cantidad,
        'variantes':
            jsonEncode(nuevasVariantes.map((v) => v.toMap()).toList()),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productoId],
    );
  }

  Future<List<Venta>> obtenerVentas({DateTime? desde, DateTime? hasta, int? limite}) async {
    final db = await database;
    String where = '';
    List<dynamic> args = [];
    if (desde != null) { where += 'fecha >= ?'; args.add(desde.toIso8601String()); }
    if (hasta != null) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'fecha <= ?'; args.add(hasta.toIso8601String());
    }
    final ventaMaps = await db.query('ventas',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null, orderBy: 'fecha DESC', limit: limite);
    List<Venta> ventas = [];
    for (final vm in ventaMaps) {
      final im = await db.query('items_venta', where: 'venta_id = ?', whereArgs: [vm['id']]);
      ventas.add(Venta.fromMap(vm, im.map((m) => ItemVenta.fromMap(m)).toList()));
    }
    return ventas;
  }

  Future<Venta?> obtenerVenta(String id) async {
    final db = await database;
    final vm = await db.query('ventas', where: 'id = ?', whereArgs: [id]);
    if (vm.isEmpty) return null;
    final im = await db.query('items_venta', where: 'venta_id = ?', whereArgs: [id]);
    return Venta.fromMap(vm.first, im.map((m) => ItemVenta.fromMap(m)).toList());
  }

  Future<void> eliminarVenta(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('items_venta', where: 'venta_id = ?', whereArgs: [id]);
      await txn.delete('ventas', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> eliminarTodasLasVentas() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('items_venta');
      await txn.delete('ventas');
    });
  }

  Future<List<Venta>> ventasDelDia() async {
    final h = DateTime.now();
    return obtenerVentas(
      desde: DateTime(h.year, h.month, h.day),
      hasta: DateTime(h.year, h.month, h.day, 23, 59, 59));
  }

  Future<Map<String, double>> resumenDiario() async {
    final ventas = await ventasDelDia();
    double tv = 0, tg = 0;
    for (final v in ventas) { tv += v.total; tg += v.gananciaTotal; }
    return {'ventas': tv, 'ganancias': tg, 'transacciones': ventas.length.toDouble()};
  }

  Future<List<Map<String, dynamic>>> resumenPorDias(int dias) async {
    final db = await database;
    final ahora = DateTime.now();
    List<Map<String, dynamic>> r = [];
    for (int i = dias - 1; i >= 0; i--) {
      final d = ahora.subtract(Duration(days: i));
      final inicio = DateTime(d.year, d.month, d.day);
      final fin = DateTime(d.year, d.month, d.day, 23, 59, 59);
      final m = await db.rawQuery(
        'SELECT COALESCE(SUM(total),0) as total FROM ventas WHERE fecha >= ? AND fecha <= ?',
        [inicio.toIso8601String(), fin.toIso8601String()]);
      r.add({'fecha': inicio, 'total': (m.first['total'] as num).toDouble()});
    }
    return r;
  }

  Future<List<String>> obtenerCategorias() async {
    final db = await database;
    final maps = await db.query('categorias', orderBy: 'nombre ASC');
    return maps.map((m) => m['nombre'] as String).toList();
  }

  Future<void> agregarCategoria(String nombre) async {
    final db = await database;
    await db.insert('categorias', {'nombre': nombre}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> eliminarCategoria(String nombre) async {
    final db = await database;
    await db.delete('categorias', where: 'nombre = ?', whereArgs: [nombre]);
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }

  /// Registra en este panel las ventas hechas en la app del celular:
  /// descuenta el stock (por id, código de barras o nombre) y, si el archivo
  /// trae precios, las guarda también en el historial. Una venta ya
  /// importada (mismo id) se ignora, así que no se descuenta dos veces.
  Future<ResultadoImportVentas> importarVentasApp(
    List<Map<String, dynamic>> ventas,
  ) async {
    final db = await database;
    final r = ResultadoImportVentas();

    await db.transaction((txn) async {
      for (final v in ventas) {
        final idVenta = v['id']?.toString() ?? '';
        if (idVenta.isEmpty) continue;

        final yaImportada = await txn.query(
          'ventas_importadas',
          where: 'id = ?',
          whereArgs: [idVenta],
          limit: 1,
        );
        final yaExiste = await txn.query(
          'ventas',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [idVenta],
          limit: 1,
        );
        if (yaImportada.isNotEmpty || yaExiste.isNotEmpty) {
          r.repetidas++;
          continue;
        }

        final rawItems = [
          for (final i in (v['items'] is List ? v['items'] as List : []))
            if (i is Map) Map<String, dynamic>.from(i),
        ];
        final conPrecios = rawItems.isNotEmpty &&
            rawItems.every((i) => i['precio_unitario'] is num);
        final itemsHistorial = <ItemVenta>[];

        for (var n = 0; n < rawItems.length; n++) {
          final raw = rawItems[n];
          final nombre = raw['nombre']?.toString().trim() ?? '';
          final codigo = raw['codigo_barras']?.toString().trim() ?? '';
          final cantidad = (raw['cantidad'] as num?)?.toInt() ?? 0;
          if (cantidad <= 0) continue;

          // Busca el producto: id, luego código de barras, luego nombre.
          Map<String, Object?>? producto;
          final idProducto = raw['producto_id']?.toString() ?? '';
          if (idProducto.isNotEmpty) {
            final f = await txn.query('productos',
                where: 'id = ?', whereArgs: [idProducto], limit: 1);
            if (f.isNotEmpty) producto = f.first;
          }
          if (producto == null && codigo.isNotEmpty) {
            final f = await txn.query('productos',
                where: 'codigo_barras = ?', whereArgs: [codigo], limit: 1);
            if (f.isNotEmpty) producto = f.first;
          }
          if (producto == null && nombre.isNotEmpty) {
            final f = await txn.query('productos',
                where: 'nombre = ? COLLATE NOCASE',
                whereArgs: [nombre],
                limit: 1);
            if (f.isNotEmpty) producto = f.first;
          }

          final talla = raw['variante_talla']?.toString() ?? '';
          final color = raw['variante_color']?.toString() ?? '';

          if (producto == null) {
            r.noEncontrados.add(nombre.isEmpty ? '(sin nombre)' : nombre);
          } else {
            final id = producto['id'].toString();
            final stockActual = (producto['stock'] as num?)?.toInt() ?? 0;
            if (stockActual < cantidad) {
              r.stockInsuficiente.add(
                '${producto['nombre']} (había $stockActual, se vendieron $cantidad)',
              );
            }
            if (talla.isNotEmpty || color.isNotEmpty) {
              await _descontarStockVariante(
                txn,
                productoId: id,
                talla: talla,
                color: color,
                cantidad: cantidad,
              );
            } else {
              await txn.rawUpdate(
                'UPDATE productos SET stock = MAX(0, stock - ?), '
                'fecha_actualizacion = ? WHERE id = ?',
                [cantidad, DateTime.now().toIso8601String(), id],
              );
            }
            r.unidades += cantidad;
          }

          if (conPrecios) {
            itemsHistorial.add(ItemVenta(
              id: '$idVenta-imp-$n',
              ventaId: idVenta,
              productoId: producto?['id']?.toString() ?? idProducto,
              productoNombre: nombre.isEmpty
                  ? (producto?['nombre']?.toString() ?? '(sin nombre)')
                  : nombre,
              codigoBarras: codigo,
              precioUnitario: (raw['precio_unitario'] as num).toDouble(),
              precioCompra: (raw['precio_compra'] as num?)?.toDouble() ?? 0,
              cantidad: cantidad,
              subtotal: (raw['subtotal'] as num?)?.toDouble() ??
                  (raw['precio_unitario'] as num).toDouble() * cantidad,
              tipoVenta: raw['tipo_venta']?.toString() ?? TipoVenta.unidad,
              varianteTalla: talla.isEmpty ? null : talla,
              varianteColor: color.isEmpty ? null : color,
              varianteColorHex: raw['variante_color_hex']?.toString(),
              tamanoNombre: raw['tamano_nombre']?.toString(),
            ));
          }
        }

        if (conPrecios && itemsHistorial.isNotEmpty) {
          final total = (v['total'] as num?)?.toDouble() ??
              itemsHistorial.fold<double>(0, (s, i) => s + i.subtotal);
          final venta = Venta(
            id: idVenta,
            items: itemsHistorial,
            subtotal: (v['subtotal'] as num?)?.toDouble() ?? total,
            descuento: (v['descuento'] as num?)?.toDouble() ?? 0,
            total: total,
            metodoPago: v['metodo_pago']?.toString() ?? 'efectivo',
            montoPagado: (v['monto_pagado'] as num?)?.toDouble(),
            vuelto: (v['vuelto'] as num?)?.toDouble(),
            fecha: DateTime.tryParse(v['fecha']?.toString() ?? ''),
            nota: v['nota']?.toString(),
          );
          await txn.insert('ventas', venta.toMap());
          for (final item in itemsHistorial) {
            await txn.insert('items_venta', item.toMap());
          }
          r.enHistorial++;
        }

        await txn.insert('ventas_importadas', {
          'id': idVenta,
          'importada_en': DateTime.now().toIso8601String(),
        });
        r.nuevas++;
      }
    });

    return r;
  }
}

/// Resultado de importar un archivo de ventas de la app.
class ResultadoImportVentas {
  int nuevas = 0;
  int repetidas = 0;
  int unidades = 0;
  int enHistorial = 0;
  final Set<String> noEncontrados = {};
  final List<String> stockInsuficiente = [];
}
