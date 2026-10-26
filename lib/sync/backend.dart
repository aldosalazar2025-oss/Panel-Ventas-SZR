library;

import 'dart:io';

/// Lo que el servidor necesita de la PC. Lo implementa [PcSyncBackend].
abstract class SyncBackend {
  /// Guarda un dispositivo emparejado con su secreto.
  Future<void> registrarDispositivo(String id, String nombre, String secreto);

  /// Secreto de un dispositivo autorizado (null si no existe o fue revocado).
  Future<String?> secretoDe(String dispositivoId);

  Future<Map<String, Object?>> estado(String dispositivoId);
  Future<Map<String, Object?>> catalogo();
  Future<File?> imagen(String productoId);
  Future<List<Map<String, Object?>>> recibirVentas(
    String dispositivoId,
    List<Map<String, Object?>> ventas,
  );
  Future<void> sincronizacionTerminada(String dispositivoId, Map<String, Object?> resumen);
}
