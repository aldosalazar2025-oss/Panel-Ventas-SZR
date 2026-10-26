import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../providers/carrito_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/peso_formatter.dart';
import '../utils/sound_player.dart';
import '../widgets/peso_cantidad_dialog.dart';
import '../widgets/variante_selector_dialog.dart';
import '../widgets/tamano_conjunto_selector_dialog.dart';
import '../models/producto.dart';
import '../models/venta.dart';
import 'revisar_orden_screen.dart';
import 'inventario_screen.dart';

/// Pantalla de venta para PC: catálogo y buscador a la izquierda, carrito a
/// la derecha. El lector de código de barras USB escribe en el buscador:
/// al pulsar Enter se agrega el producto con ese código.
class PosDesktopScreen extends StatefulWidget {
  const PosDesktopScreen({super.key});

  @override
  State<PosDesktopScreen> createState() => _PosDesktopScreenState();
}

class _PosDesktopScreenState extends State<PosDesktopScreen> {
  final _db = DatabaseService.instance;
  final _busquedaCtrl = TextEditingController();
  final _busquedaFocus = FocusNode();

  List<Producto> _productos = [];
  List<String> _categorias = [];
  String _query = '';
  String? _categoria;
  String _moneda = 'S/';
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _busquedaFocus.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final productos = await _db.obtenerProductos();
    final categorias = await _db.obtenerCategorias();
    if (!mounted) return;
    final simbolo = prefs.getString('moneda_simbolo')?.trim() ?? '';
    setState(() {
      _productos = productos;
      _categorias = categorias;
      _moneda = simbolo.isEmpty ? 'S/' : simbolo;
      _cargando = false;
    });
  }

  String _dinero(double v) => CurrencyFormatter.format(v, _moneda);

  List<Producto> get _filtrados {
    final q = _query.trim().toLowerCase();
    return _productos.where((p) {
      if (_categoria != null && p.categoria != _categoria) return false;
      if (q.isEmpty) return true;
      return p.nombre.toLowerCase().contains(q) ||
          p.codigoBarras.toLowerCase().contains(q);
    }).toList();
  }

  void _aviso(String texto, Color color) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: color,
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
          width: 420,
        ),
      );
  }

  void _enfocarBusqueda() {
    if (mounted) _busquedaFocus.requestFocus();
  }

  /// Enter en el buscador: si es un código de barras, agrega el producto;
  /// si solo hay un resultado por nombre, también lo agrega.
  Future<void> _alEnviarBusqueda(String texto) async {
    final codigo = texto.trim();
    if (codigo.isEmpty) return;

    final porCodigo = await _db.buscarPorCodigoBarras(codigo);
    if (!mounted) return;
    if (porCodigo != null) {
      _busquedaCtrl.clear();
      setState(() => _query = '');
      await _agregar(porCodigo, desdeCodigo: true);
      _enfocarBusqueda();
      return;
    }

    final lista = _filtrados;
    if (lista.length == 1) {
      _busquedaCtrl.clear();
      setState(() => _query = '');
      await _agregar(lista.first);
      _enfocarBusqueda();
      return;
    }

    if (lista.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Código $codigo no encontrado'),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
            width: 460,
            action: SnackBarAction(
              label: 'AGREGAR',
              textColor: Colors.white,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InventarioScreen(codigoInicial: codigo),
                  ),
                );
                await _cargar();
              },
            ),
          ),
        );
    }
  }

  /// Agrega un producto al carrito respetando variantes, tamaños/extras y peso.
  Future<void> _agregar(Producto p, {bool desdeCodigo = false}) async {
    final carrito = context.read<CarritoProvider>();

    if (p.tieneVariantes) {
      final variante = await showVarianteSelectorDialog(
        context: context,
        producto: p,
        enCarrito: (v) =>
            carrito.cantidadEnCarritoVariante(p.id, v.talla, v.color),
      );
      if (variante == null || !mounted) return;
      SoundPlayer.ping();
      carrito.agregarProducto(p, variante: variante);
      _avisoAgregado(p.nombre, p.precioVenta,
          bajo: variante.stock <= p.stockMinimo, stock: '${variante.stock} und');
      return;
    }

    if (p.tieneTamanos || p.conjuntos.isNotEmpty) {
      final seleccion =
          await showTamanoConjuntoSelectorDialog(context: context, producto: p);
      if (seleccion == null || !mounted) return;
      SoundPlayer.ping();
      carrito.agregarProducto(
        p,
        tamano: seleccion.tamano,
        opcionesElegidas: seleccion.opciones,
      );
      _avisoAgregado(p.nombre, seleccion.tamano?.precio ?? p.precioVenta,
          bajo: p.stock <= p.stockMinimo, stock: p.formatoStock);
      return;
    }

    if (p.esPeso) {
      final disponible = p.stock - carrito.cantidadEnCarrito(p.id);
      if (disponible <= 0) {
        _aviso('${p.nombre} — agotado (${p.formatoStock})', AppTheme.warning);
        return;
      }
      final gramos = await showPesoCantidadDialog(
        context: context,
        producto: p,
        monedaSimbolo: _moneda,
        stockDisponible: disponible,
      );
      if (gramos == null || !mounted) return;
      SoundPlayer.ping();
      carrito.agregarProducto(p, cantidad: gramos);
      _avisoAgregado(p.nombre, p.precioVenta,
          bajo: p.stock <= p.stockMinimo, stock: p.formatoStock);
      return;
    }

    SoundPlayer.ping();
    carrito.agregarProducto(p);
    _avisoAgregado(p.nombre, p.precioVenta,
        bajo: p.stock <= p.stockMinimo, stock: p.formatoStock);
  }

  void _avisoAgregado(String nombre, double precio,
      {required bool bajo, required String stock}) {
    if (bajo) {
      _aviso('$nombre — Stock bajo o agotado ($stock)', AppTheme.warning);
    } else {
      _aviso('$nombre agregado  ${_dinero(precio)}', AppTheme.success);
    }
  }

  Future<void> _editarPeso(int index, ItemVenta item) async {
    final producto = await _db.obtenerProducto(item.productoId);
    if (!mounted) return;
    final stock = producto?.stock ?? item.cantidad;
    final gramos = await showPesoCantidadDialog(
      context: context,
      producto: producto ??
          Producto(
            id: item.productoId,
            codigoBarras: item.codigoBarras,
            nombre: item.productoNombre,
            precioCompra: item.precioCompra,
            precioVenta: item.precioUnitario,
            stock: stock,
            tipoVenta: TipoVenta.peso,
          ),
      monedaSimbolo: _moneda,
      stockDisponible: stock,
      cantidadInicial: item.cantidad,
    );
    if (gramos == null || !mounted) return;
    context.read<CarritoProvider>().actualizarCantidad(index, gramos);
  }

  Future<void> _cobrar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RevisarOrdenScreen()),
    );
    await _cargar();
    _enfocarBusqueda();
  }

  String _detalleItem(ItemVenta i) {
    final partes = <String>[
      if (i.tieneVariante) i.etiquetaVariante,
      if (i.tieneTamano) i.tamanoNombre!,
      if (i.conjuntosElegidos.isNotEmpty) i.etiquetaExtras,
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vender'),
        actions: [
          IconButton(
            tooltip: 'Actualizar productos',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(flex: 3, child: _panelCatalogo()),
                const VerticalDivider(width: 1),
                SizedBox(width: 400, child: _panelCarrito()),
              ],
            ),
    );
  }

  // ---------- Catálogo ----------

  Widget _panelCatalogo() {
    final lista = _filtrados;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _busquedaCtrl,
            focusNode: _busquedaFocus,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Escanea el código o busca por nombre (Enter para agregar)',
              prefixIcon: Icon(Icons.qr_code_scanner),
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: _alEnviarBusqueda,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: _categoria == null,
                  onSelected: (_) => setState(() => _categoria = null),
                ),
                for (final c in _categorias) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(c),
                    selected: _categoria == c,
                    onSelected: (v) => setState(() => _categoria = v ? c : null),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: lista.isEmpty
                ? Center(
                    child: Text(
                      _productos.isEmpty
                          ? 'Aún no hay productos. Agrégalos en Inventario.'
                          : 'Ningún producto coincide.',
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisExtent: 210,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _tarjetaProducto(lista[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaProducto(Producto p) {
    final agotado = p.agotado;
    final colorStock = agotado
        ? AppTheme.error
        : p.stockBajo
            ? AppTheme.warning
            : AppTheme.textSecondary;
    final ruta = p.imagenUrl;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: () async {
          await _agregar(p);
          _enfocarBusqueda();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: (ruta != null && ruta.isNotEmpty)
                  ? Image.file(
                      File(ruta),
                      fit: BoxFit.cover,
                      cacheWidth: 380,
                      errorBuilder: (_, _, _) => _sinFoto(),
                    )
                  : _sinFoto(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        p.precioLabel(_dinero),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      Text(
                        p.formatoStock,
                        style: TextStyle(fontSize: 12, color: colorStock),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sinFoto() => Container(
        color: AppTheme.bgGrey,
        child: const Center(
          child: Icon(Icons.inventory_2_outlined, size: 40, color: AppTheme.textMuted),
        ),
      );

  // ---------- Carrito ----------

  Widget _panelCarrito() {
    return Consumer<CarritoProvider>(
      builder: (context, carrito, _) {
        final items = carrito.items;
        return Container(
          color: AppTheme.bgWhite,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Venta actual (${carrito.totalItems})',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (items.isNotEmpty)
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Vaciar venta'),
                              content: const Text('¿Quitar todos los productos del carrito?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Vaciar'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) carrito.limpiar();
                          _enfocarBusqueda();
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Vaciar'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'Escanea o toca un producto\npara empezar la venta.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _filaCarrito(carrito, i, items[i]),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Column(
                  children: [
                    if (carrito.descuento > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Descuento'),
                          Text('-${_dinero(carrito.descuento)}'),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _dinero(carrito.total),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: carrito.isEmpty ? null : _cobrar,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text(
                          'Cobrar',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filaCarrito(CarritoProvider carrito, int index, ItemVenta item) {
    final detalle = _detalleItem(item);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productoNombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (detalle.isNotEmpty)
                  Text(
                    detalle,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                Text(
                  item.esPeso
                      ? '${PesoFormatter.formatGrams(item.cantidad)} × ${_dinero(item.precioUnitario)}/kg'
                      : '${_dinero(item.precioUnitario)} c/u',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.esPeso)
            IconButton(
              tooltip: 'Cambiar peso',
              onPressed: () => _editarPeso(index, item),
              icon: const Icon(Icons.scale_outlined),
            )
          else ...[
            IconButton(
              tooltip: 'Restar',
              visualDensity: VisualDensity.compact,
              onPressed: item.cantidad > 1
                  ? () => carrito.actualizarCantidad(index, item.cantidad - 1)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${item.cantidad}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Sumar',
              visualDensity: VisualDensity.compact,
              onPressed: () => carrito.actualizarCantidad(index, item.cantidad + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
          SizedBox(
            width: 76,
            child: Text(
              _dinero(item.subtotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Quitar',
            visualDensity: VisualDensity.compact,
            onPressed: () => carrito.eliminarItem(index),
            icon: const Icon(Icons.close, color: AppTheme.error),
          ),
        ],
      ),
    );
  }
}
