import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// En Windows no se usa cámara: el lector de código de barras USB escribe el
/// código como si fuera teclado y termina con Enter. También se puede
/// escribir el código a mano.
class ScannerScreen extends StatefulWidget {
  final String titulo;
  const ScannerScreen({super.key, this.titulo = 'Escanear'});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _aceptar() {
    final codigo = _ctrl.text.trim();
    if (codigo.isEmpty) return;
    Navigator.pop(context, codigo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner, size: 72, color: AppTheme.primary),
                const SizedBox(height: 16),
                const Text(
                  'Pasa el producto por el lector de código de barras\n'
                  'o escribe el código y pulsa Enter.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Código de barras',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _aceptar(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _aceptar,
                    child: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
