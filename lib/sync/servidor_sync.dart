/// Servicio local de la PC. Escucha en la red Wi-Fi y atiende al celular.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backend.dart';
import 'protocolo.dart';

class ServidorSync {
  final SyncBackend backend;
  final int puerto;
  final int Function() ahoraMs;

  ServidorSync(
    this.backend, {
    this.puerto = puertoPredeterminado,
    int Function()? ahoraMs,
  }) : ahoraMs = ahoraMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  HttpServer? _servidor;
  String _codigo = '';
  String _sal = '';
  final CacheNonces _nonces = CacheNonces();
  final Map<String, ({int fallos, int bloqueadoHasta})> _intentos = {};

  bool get activo => _servidor != null;
  String get codigo => _codigo;
  int get puertoReal => _servidor?.port ?? puerto;

  /// Inicia el servicio y devuelve el código de emparejamiento.
  Future<String> iniciar({String? codigo, InternetAddress? direccion}) async {
    if (_servidor != null) return _codigo;
    _codigo = codigo ?? _generarCodigo();
    _sal = aleatorioHex(8);
    _servidor = await HttpServer.bind(direccion ?? InternetAddress.anyIPv4, puerto);
    _servidor!.listen(_atender, onError: (_) {});
    return _codigo;
  }

  Future<void> detener() async {
    final s = _servidor;
    _servidor = null;
    _codigo = '';
    await s?.close(force: true);
  }

  static String _generarCodigo() {
    final n = int.parse(aleatorioHex(4), radix: 16) % 1000000;
    return n.toString().padLeft(6, '0');
  }

  Future<void> _atender(HttpRequest req) async {
    try {
      final ruta = req.uri.path;
      final cuerpo = await _leerCuerpo(req);

      if (req.method == 'GET' && ruta == '/api/ping') {
        return await _json(req, 200, {'app': appPanel, 'protocolo': versionProtocolo, 'sal': _sal});
      }
      if (req.method == 'POST' && ruta == '/api/emparejar') {
        return await _emparejar(req, cuerpo);
      }

      // Todo lo demás exige una solicitud firmada.
      final id = req.headers.value('x-dispositivo') ?? '';
      final tiempoTexto = req.headers.value('x-tiempo') ?? '';
      final nonce = req.headers.value('x-nonce') ?? '';
      final firma = req.headers.value('x-firma') ?? '';
      final tiempo = int.tryParse(tiempoTexto);
      if (id.isEmpty || tiempo == null || nonce.length < 8 || firma.isEmpty) {
        return await _json(req, 401, {'error': 'Solicitud sin credenciales'});
      }
      final secreto = await backend.secretoDe(id);
      if (secreto == null) {
        return await _json(req, 401, {'error': 'Dispositivo no autorizado'});
      }
      final ahora = ahoraMs();
      if ((ahora - tiempo).abs() > toleranciaRelojMs) {
        return await _json(req, 401, {'error': 'La hora del dispositivo no coincide con la de la PC'});
      }
      final rutaCompleta = req.uri.hasQuery ? '${req.uri.path}?${req.uri.query}' : req.uri.path;
      final esperada = firmarSolicitud(secreto, req.method, rutaCompleta, tiempo, nonce, cuerpo);
      if (!igualesConstante(esperada, firma)) {
        return await _json(req, 401, {'error': 'Firma no válida'});
      }
      if (!_nonces.registrar(nonce, ahora)) {
        return await _json(req, 401, {'error': 'Solicitud repetida'});
      }

      await _rutaFirmada(req, ruta, cuerpo, id, secreto, nonce);
    } catch (e) {
      try {
        await _json(req, 500, {'error': 'Error interno: $e'});
      } catch (_) {}
    }
  }

  Future<void> _rutaFirmada(
    HttpRequest req,
    String ruta,
    List<int> cuerpo,
    String id,
    String secreto,
    String nonce,
  ) async {
    if (req.method == 'GET' && ruta == '/api/estado') {
      return await _jsonFirmado(req, secreto, nonce, await backend.estado(id));
    }
    if (req.method == 'GET' && ruta == '/api/catalogo') {
      return await _jsonFirmado(req, secreto, nonce, await backend.catalogo());
    }
    if (req.method == 'GET' && ruta.startsWith('/api/imagen/')) {
      final productoId = Uri.decodeComponent(ruta.substring('/api/imagen/'.length));
      final archivo = await backend.imagen(productoId);
      if (archivo == null || !await archivo.exists()) {
        return await _jsonFirmado(req, secreto, nonce, {'error': 'Sin imagen'}, codigo: 404);
      }
      final bytes = await archivo.readAsBytes();
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.binary;
      req.response.headers.set('x-firma-respuesta', firmarRespuesta(secreto, nonce, bytes));
      req.response.add(bytes);
      return await req.response.close();
    }
    if (req.method == 'POST' && ruta == '/api/ventas') {
      final datos = jsonDecode(utf8.decode(cuerpo));
      if (datos is! Map || datos['ventas'] is! List) {
        return await _jsonFirmado(req, secreto, nonce, {'error': 'Formato no válido'}, codigo: 400);
      }
      final ventas = [
        for (final v in datos['ventas'] as List)
          if (v is Map) Map<String, Object?>.from(v),
      ];
      final resultados = await backend.recibirVentas(id, ventas);
      return await _jsonFirmado(req, secreto, nonce, {'resultados': resultados});
    }
    if (req.method == 'POST' && ruta == '/api/sync/fin') {
      final datos = jsonDecode(utf8.decode(cuerpo));
      await backend.sincronizacionTerminada(
        id,
        datos is Map ? Map<String, Object?>.from(datos) : <String, Object?>{},
      );
      return await _jsonFirmado(req, secreto, nonce, {'ok': true});
    }
    return await _jsonFirmado(req, secreto, nonce, {'error': 'Ruta desconocida'}, codigo: 404);
  }

  Future<void> _emparejar(HttpRequest req, List<int> cuerpo) async {
    final origen = req.connectionInfo?.remoteAddress.address ?? '?';
    final ahora = ahoraMs();
    final estado = _intentos[origen];
    if (estado != null && estado.bloqueadoHasta > ahora) {
      return await _json(req, 429, {'error': 'Demasiados intentos. Espera un minuto.'});
    }
    if (_codigo.isEmpty) {
      return await _json(req, 409, {'error': 'La PC no está esperando emparejamientos'});
    }
    Map<String, dynamic> datos;
    try {
      datos = Map<String, dynamic>.from(jsonDecode(utf8.decode(cuerpo)) as Map);
    } catch (_) {
      return await _json(req, 400, {'error': 'Formato no válido'});
    }
    final id = '${datos['dispositivoId'] ?? ''}';
    final nombre = '${datos['nombre'] ?? 'Android'}';
    final nonce = '${datos['nonce'] ?? ''}';
    final prueba = '${datos['prueba'] ?? ''}';
    if (id.length < 8 || nonce.length < 8) {
      return await _json(req, 400, {'error': 'Datos incompletos'});
    }
    final secreto = derivarSecreto(_codigo, id, _sal, nonce);
    if (!igualesConstante(pruebaEmparejamiento(secreto), prueba)) {
      final fallos = (estado?.fallos ?? 0) + 1;
      _intentos[origen] = (
        fallos: fallos >= 5 ? 0 : fallos,
        bloqueadoHasta: fallos >= 5 ? ahora + 60000 : 0,
      );
      return await _json(req, 403, {'error': 'Código incorrecto'});
    }
    _intentos.remove(origen);
    await backend.registrarDispositivo(id, nombre, secreto);
    return await _json(req, 200, {'ok': true});
  }

  Future<List<int>> _leerCuerpo(HttpRequest req) async {
    final bytes = <int>[];
    await for (final parte in req) {
      bytes.addAll(parte);
      if (bytes.length > 50 * 1024 * 1024) {
        throw ErrorSync('Solicitud demasiado grande');
      }
    }
    return bytes;
  }

  Future<void> _json(HttpRequest req, int codigo, Object datos) async {
    req.response.statusCode = codigo;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(datos));
    await req.response.close();
  }

  Future<void> _jsonFirmado(
    HttpRequest req,
    String secreto,
    String nonce,
    Object datos, {
    int codigo = 200,
  }) async {
    final bytes = utf8.encode(jsonEncode(datos));
    req.response.statusCode = codigo;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('x-firma-respuesta', firmarRespuesta(secreto, nonce, bytes));
    req.response.add(bytes);
    await req.response.close();
  }
}
