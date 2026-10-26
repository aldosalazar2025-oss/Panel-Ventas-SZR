import 'dart:io';
import '../services/database_service.dart';
import 'pc_backend.dart';
import 'servidor_sync.dart';
import 'sqflite_adapter.dart';

/// Mantiene el servicio de sincronización activo mientras la app está abierta.
class ServicioSyncPc {
  ServicioSyncPc._();
  static final ServicioSyncPc instance = ServicioSyncPc._();

  ServidorSync? _srv;
  PcSyncBackend? _backend;

  Future<PcSyncBackend> backend() async {
    _backend ??= PcSyncBackend(SqfliteSyncDb(await DatabaseService.instance.database));
    return _backend!;
  }

  bool get activo => _srv?.activo ?? false;
  String get codigo => _srv?.codigo ?? '';
  int get puerto => _srv?.puertoReal ?? 8765;

  /// Direcciones IP de esta PC en la red (la del Wi-Fi suele ser 192.168.x.x).
  Future<List<String>> direccionesIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses) a.address,
    ];
  }

  Future<void> iniciar() async {
    final b = await backend();
    _srv ??= ServidorSync(b);
    await _srv!.iniciar();
  }

  Future<void> detener() async {
    await _srv?.detener();
  }

  Future<void> solicitar(String accion) async => (await backend()).solicitar(accion);
}
