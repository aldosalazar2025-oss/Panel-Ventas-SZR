import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/respaldo_web.dart';
import '../theme/app_theme.dart';

/// Sección "Web y App" de Ajustes: exportar productos a la web e importar
/// las ventas hechas en la app del celular (descuenta el stock de este panel).
class WebAppPanel extends StatefulWidget {
  const WebAppPanel({super.key});

  @override
  State<WebAppPanel> createState() => _WebAppPanelState();
}

class _WebAppPanelState extends State<WebAppPanel> {
  bool _exportando = false;
  bool _importando = false;

  void _aviso(String texto, Color color, {int segundos = 5}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: color,
          duration: Duration(seconds: segundos),
        ),
      );
  }

  Future<void> _crearRespaldoWeb() async {
    setState(() => _exportando = true);
    try {
      final r = await RespaldoWeb.generar();
      if (r.productos == 0) {
        _aviso('No hay productos para respaldar', AppTheme.warning);
        return;
      }
      final fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final bytes = utf8.encode(r.json);
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar respaldo para la web',
        fileName: 'copia-tienda-$fecha-pc.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (ruta == null) {
        _aviso('Guardado cancelado', AppTheme.warning);
        return;
      }
      // En Windows el selector solo devuelve la ruta: el archivo se escribe aquí.
      final destino = ruta.toLowerCase().endsWith('.json') ? ruta : '$ruta.json';
      await File(destino).writeAsBytes(bytes);
      _aviso('Respaldo para la web guardado (${r.productos} productos):\n$destino',
          AppTheme.success, segundos: 8);
    } catch (e) {
      _aviso('No se pudo crear el respaldo: $e', AppTheme.error, segundos: 8);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _importarVentas() async {
    setState(() => _importando = true);
    try {
      final elegido = await FilePicker.platform.pickFiles(
        dialogTitle: 'Elegir archivo de ventas de la app',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final ruta = elegido?.files.single.path;
      if (ruta == null) return;

      final contenido = jsonDecode(await File(ruta).readAsString());
      if (contenido is! Map ||
          contenido['formato'] != 'szr-ventas' ||
          contenido['ventas'] is! List) {
        throw Exception(
          'Este archivo no es de ventas. En la app usa '
          'Configuración avanzada → "Enviar ventas al panel".',
        );
      }

      final lista = [
        for (final v in contenido['ventas'] as List)
          if (v is Map) Map<String, dynamic>.from(v),
      ];
      final r = await DatabaseService.instance.importarVentasApp(lista);
      if (!mounted) return;
      await _mostrarResultado(r);
    } catch (e) {
      _aviso('No se pudieron importar las ventas: $e', AppTheme.error, segundos: 8);
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<void> _mostrarResultado(ResultadoImportVentas r) {
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            t,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.warning,
            ),
          ),
        );

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ventas importadas'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ventas nuevas: ${r.nuevas}'),
                Text('Unidades descontadas del stock: ${r.unidades}'),
                if (r.enHistorial > 0)
                  Text('Agregadas al historial: ${r.enHistorial}'),
                if (r.repetidas > 0)
                  Text('Ya estaban importadas (se ignoraron): ${r.repetidas}'),
                if (r.noEncontrados.isNotEmpty) ...[
                  titulo('No se encontraron en este panel (no se descontó):'),
                  for (final n in r.noEncontrados) Text('• $n'),
                ],
                if (r.stockInsuficiente.isNotEmpty) ...[
                  titulo('Se vendió más de lo que había (quedó en 0):'),
                  for (final n in r.stockInsuficiente) Text('• $n'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _accion({
    required IconData icono,
    required String titulo,
    required String texto,
    required Widget boton,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 22, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              texto,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            boton,
          ],
        ),
      ),
    );
  }

  Widget _cargando() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _accion(
          icono: Icons.language,
          titulo: 'Respaldo para la web',
          texto: 'Crea el archivo para subir a la web.',
          boton: FilledButton.icon(
            onPressed: _exportando ? null : _crearRespaldoWeb,
            icon: _exportando ? _cargando() : const Icon(Icons.file_download_outlined),
            label: Text(_exportando ? 'Creando...' : 'Crear respaldo para la web'),
          ),
        ),
        _accion(
          icono: Icons.phone_android,
          titulo: 'Importar ventas de la app',
          texto: 'Sube las ventas realizadas en tu dispositivo para actualizar el stock.',
          boton: FilledButton.icon(
            onPressed: _importando ? null : _importarVentas,
            icon: _importando ? _cargando() : const Icon(Icons.upload_file),
            label: Text(_importando ? 'Importando...' : 'Importar ventas de la app'),
          ),
        ),
      ],
    );
  }
}
