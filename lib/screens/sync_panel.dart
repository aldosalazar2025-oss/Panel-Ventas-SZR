import 'dart:async';
import 'package:flutter/material.dart';
import '../sync/servicio_pc.dart';
import '../theme/app_theme.dart';

/// Sección "Sincronización" de Ajustes (PC): conecta el celular por Wi-Fi local.
class SincronizacionPanel extends StatefulWidget {
  const SincronizacionPanel({super.key});

  @override
  State<SincronizacionPanel> createState() => _SincronizacionPanelState();
}

class _SincronizacionPanelState extends State<SincronizacionPanel> {
  final _srv = ServicioSyncPc.instance;
  List<String> _ips = [];
  String? _accion;
  bool _hayDispositivoConectado = false;
  bool _iniciando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refrescar();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refrescar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refrescar() async {
    if (!mounted) return;
    final backend = await _srv.backend();
    final disp = await backend.dispositivos();
    final ips = _srv.activo ? await _srv.direccionesIp() : <String>[];
    if (!mounted) return;
    setState(() {
      _ips = ips;
      _accion = backend.accionSolicitada;
      _hayDispositivoConectado = disp.any(_conectado);
    });
  }

  static bool _conectado(Map<String, Object?> d) {
    final t = DateTime.tryParse('${d['ultimo_contacto'] ?? ''}');
    return t != null && DateTime.now().difference(t).inSeconds < 30;
  }

  void _aviso(String texto, {Color color = AppTheme.success}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
  }

  Future<void> _iniciar() async {
    setState(() => _iniciando = true);
    try {
      await _srv.iniciar();
      await _refrescar();
    } catch (e) {
      _aviso('No se pudo iniciar la conexión: $e', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  Future<void> _detener() async {
    await _srv.detener();
    await _refrescar();
    _aviso('Conexión detenida. Tus datos no se borraron.');
  }

  Future<void> _pedir(String accion, String texto) async {
    if (!_srv.activo) {
      _aviso('Primero inicia la conexión', color: AppTheme.warning);
      return;
    }
    await _srv.solicitar(accion);
    await _refrescar();
    _aviso(_hayDispositivoConectado
        ? '$texto: se pidió al teléfono, lo hará en unos segundos.'
        : '$texto: queda pendiente hasta que el teléfono se conecte.');
  }

  Future<void> _verEstado() async {
    final backend = await _srv.backend();
    final dispositivos = await backend.dispositivos();
    final conflictos = await backend.conflictos(limite: 30);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Estado de sincronización'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Servicio: ${_srv.activo ? 'ACTIVO' : 'detenido'}'),
                  if (_accion != null) Text('Operación pendiente: $_accion'),
                  const SizedBox(height: 12),
                  const Text('Dispositivos', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (dispositivos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Ningún celular emparejado todavía.'),
                    ),
                  for (final d in dispositivos)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _conectado(d) ? Icons.circle : Icons.circle_outlined,
                                  size: 12,
                                  color: _conectado(d) ? AppTheme.success : AppTheme.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${d['nombre']} — ${_conectado(d) ? 'conectado' : 'sin conexión'}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await backend.revocarDispositivo('${d['id']}');
                                    dispositivos.remove(d);
                                    setLocal(() {});
                                  },
                                  child: const Text('Olvidar'),
                                ),
                              ],
                            ),
                            Text('Última sincronización: ${_fecha(d['ultima_sync'])}'),
                            Text('Ventas recibidas: ${d['ventas_recibidas']}'),
                            if (d['ultimo_error'] != null)
                              Text('Último error: ${d['ultimo_error']}',
                                  style: const TextStyle(color: AppTheme.error)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text('Avisos de inventario (${conflictos.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                    'Ocurren cuando una venta del teléfono pedía más unidades de las que '
                    'quedaban. La venta se guardó igual y el stock quedó en 0, nunca negativo.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (conflictos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Sin avisos.'),
                    ),
                  for (final c in conflictos)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${c['producto_nombre']}'),
                      subtitle: Text(
                        '${_tipo('${c['tipo']}')} · pedido ${c['solicitado']}, '
                        'descontado ${c['descontado']} · ${_fecha(c['fecha'])}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  }

  static String _tipo(String t) => switch (t) {
        'stock_insuficiente' => 'Stock insuficiente',
        'producto_eliminado' => 'Producto dado de baja',
        'producto_desconocido' => 'Producto no existe en la PC',
        _ => t,
      };

  static String _fecha(Object? iso) {
    final f = DateTime.tryParse('${iso ?? ''}');
    if (f == null) return 'nunca';
    String d(int n) => n.toString().padLeft(2, '0');
    return '${d(f.day)}/${d(f.month)}/${f.year} ${d(f.hour)}:${d(f.minute)}';
  }

  Widget _caja({required List<Widget> hijos}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final activo = _srv.activo;
    return Column(
      children: [
        _caja(hijos: [
          Row(
            children: [
              Icon(Icons.wifi_tethering,
                  color: activo ? AppTheme.success : AppTheme.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  activo
                      ? (_hayDispositivoConectado
                          ? 'Conexión activa · celular conectado'
                          : 'Conexión activa · esperando al celular')
                      : 'Conexión detenida',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (activo) ...[
            const SizedBox(height: 10),
            if (_ips.isEmpty)
              const Text('No se encontró una red. Conecta la PC al Wi-Fi.')
            else
              for (final ip in _ips)
                SelectableText('Dirección en el celular:  $ip   ·   Puerto: ${_srv.puerto}',
                    style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Código de emparejamiento: '),
                SelectableText(
                  _srv.codigo,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'El celular y la PC deben estar en la misma red Wi-Fi. Si Windows '
              'pregunta por el Firewall, permite el acceso en redes privadas.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
          if (_accion != null) ...[
            const SizedBox(height: 8),
            Text('Pendiente: $_accion (se hará cuando el celular responda)',
                style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: activo || _iniciando ? null : _iniciar,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar conexión'),
              ),
              OutlinedButton.icon(
                onPressed: activo ? _detener : null,
                icon: const Icon(Icons.stop),
                label: const Text('Detener conexión'),
              ),
            ],
          ),
        ]),
        _caja(hijos: [
          const Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'La PC es la principal: el celular recibe de aquí el catálogo y '
            'las existencias, y le envía las ventas.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _pedir('productos', 'Sincronizar productos'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Sincronizar productos'),
              ),
              FilledButton.icon(
                onPressed: () => _pedir('ventas', 'Recibir ventas'),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('Recibir ventas de Android'),
              ),
              FilledButton.icon(
                onPressed: () => _pedir('todo', 'Sincronizar todo'),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar todo'),
              ),
              OutlinedButton.icon(
                onPressed: _verEstado,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Ver estado de sincronización'),
              ),
            ],
          ),
        ]),
      ],
    );
  }
}
