import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Error devuelto por la impresora (status IPP >= 0x0100) o por HTTP.
class IppException implements Exception {
  const IppException(this.statusCode, [this.message]);

  final int statusCode;
  final String? message;

  @override
  String toString() {
    final name = _statusNames[statusCode] ?? 'error';
    final hex = statusCode.toRadixString(16).padLeft(4, '0');
    final detail = message == null || message!.isEmpty ? '' : ': $message';
    return '$name (0x$hex)$detail';
  }

  static const _statusNames = {
    0x0400: 'client-error-bad-request',
    0x0401: 'client-error-forbidden',
    0x040A: 'client-error-document-format-not-supported',
    0x040B: 'client-error-attributes-or-values-not-supported',
    0x0500: 'server-error-internal-error',
    0x0506: 'server-error-not-accepting-jobs',
    0x0507: 'server-error-busy',
  };
}

/// Cliente IPP/2.0 mínimo (RFC 8011) para enviar un Print-Job con los
/// atributos que nitro_printing no permite: hoja, calidad, color y escalado.
class IppClient {
  IppClient({this.responseTimeout = const Duration(seconds: 60)});

  /// Tiempo máximo para que la impresora responda al trabajo enviado.
  final Duration responseTimeout;
  int _requestId = 0;

  /// Envía [document] como Print-Job y devuelve el `job-id` asignado por la
  /// impresora. Lanza [IppException] si la impresora rechaza el trabajo.
  Future<int?> printJob({
    required Uri printerUri,
    required Uint8List document,
    required String documentFormat,
    required String jobName,
    required String media,
    required int printQuality,
    String colorMode = 'monochrome',
    String scaling = 'fit',
  }) async {
    final request = _IppWriter()
      ..header(operation: 0x0002, requestId: ++_requestId)
      ..group(0x01)
      ..string(0x47, 'attributes-charset', 'utf-8')
      ..string(0x48, 'attributes-natural-language', 'es')
      ..string(0x45, 'printer-uri', printerUri.toString())
      ..string(0x42, 'requesting-user-name', 'qrprintertest')
      ..string(0x42, 'job-name', jobName)
      ..string(0x49, 'document-format', documentFormat)
      ..group(0x02)
      ..string(0x44, 'media', media)
      ..integer(0x23, 'print-quality', printQuality)
      ..string(0x44, 'print-color-mode', colorMode)
      ..string(0x44, 'print-scaling', scaling)
      ..group(0x03);

    var response = await _post(printerUri, request.bytes, document);
    // 426 Upgrade Required: la impresora exige TLS (p.ej. Epson) -> ipps.
    response ??= await _post(
      printerUri.replace(scheme: 'ipps'),
      request.bytes,
      document,
    );
    if (response == null) {
      throw const IppException(426, 'La impresora exige TLS');
    }
    return _parseResponse(response);
  }

  /// Envía el POST HTTP armado a mano sobre un socket.
  ///
  /// No se usa `HttpClient` de dart:io: las HP (Smart Tank 580, DeskJet 2800)
  /// dejan colgadas sus peticiones sin responder, mientras que la misma
  /// petición IPP enviada como lo hace curl (cabeceras estándar, `Host`
  /// primero, sin `accept-encoding`) responde al instante.
  ///
  /// Devuelve `null` si la impresora responde 426 (exige TLS).
  Future<Uint8List?> _post(
    Uri printerUri,
    Uint8List ippRequest,
    Uint8List document,
  ) async {
    final secure = printerUri.scheme == 'ipps';
    final host = printerUri.host;
    final port = printerUri.hasPort ? printerUri.port : 631;
    final path = printerUri.path.isEmpty ? '/' : printerUri.path;

    final Socket socket;
    try {
      socket = secure
          ? await SecureSocket.connect(
              host,
              port,
              timeout: const Duration(seconds: 15),
              // Las impresoras de la red local usan certificados autofirmados.
              onBadCertificate: (_) => true,
            )
          : await Socket.connect(
              host,
              port,
              timeout: const Duration(seconds: 15),
            );
    } on SocketException catch (e) {
      throw IppException(0x0500, 'no se pudo conectar: ${e.message}');
    }

    try {
      final headers =
          'POST $path HTTP/1.1\r\n'
          'Host: $host:$port\r\n'
          'User-Agent: qrprintertest IPP/2.0\r\n'
          'Content-Type: application/ipp\r\n'
          'Content-Length: ${ippRequest.length + document.length}\r\n'
          'Connection: close\r\n'
          '\r\n';
      socket
        ..add(ascii.encode(headers))
        ..add(ippRequest)
        ..add(document);
      await socket.flush();

      // Con `Connection: close` la impresora cierra al terminar la respuesta.
      final builder = BytesBuilder(copy: false);
      await socket.forEach(builder.add).timeout(responseTimeout);
      final response = _HttpResponse.parse(builder.takeBytes());

      if (response.statusCode == HttpStatus.upgradeRequired) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw IppException(
          response.statusCode,
          'HTTP ${response.statusCode}',
        );
      }
      return response.body;
    } on TimeoutException {
      throw IppException(
        0x0507,
        'la impresora no respondió en ${responseTimeout.inSeconds} s',
      );
    } on SocketException catch (e) {
      // Las que exigen TLS (p.ej. Epson) responden 426 y cortan la conexión
      // mientras aún se envía el documento: se reintenta por ipps.
      if (!secure) return null;
      throw IppException(0x0500, 'conexión interrumpida: ${e.message}');
    } finally {
      socket.destroy();
    }
  }

  int? _parseResponse(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const IppException(0x0500, 'Respuesta IPP incompleta');
    }
    final data = ByteData.sublistView(bytes);
    final status = data.getUint16(2);
    int? jobId;
    String? message;

    var offset = 8;
    while (offset < bytes.length) {
      final tag = bytes[offset++];
      if (tag == 0x03) break; // end-of-attributes
      if (tag < 0x10) continue; // delimitador de grupo
      final nameLength = data.getUint16(offset);
      offset += 2;
      final name = utf8.decode(bytes.sublist(offset, offset + nameLength));
      offset += nameLength;
      final valueLength = data.getUint16(offset);
      offset += 2;
      if (name == 'job-id' && tag == 0x21) {
        jobId = data.getInt32(offset);
      } else if (name == 'status-message') {
        message = utf8.decode(
          bytes.sublist(offset, offset + valueLength),
          allowMalformed: true,
        );
      }
      offset += valueLength;
    }

    // 0x0000-0x00FF: successful-ok, ok-ignored-or-substituted-attributes...
    if (status >= 0x0100) throw IppException(status, message);
    return jobId;
  }

  void close() {}
}

class _IppWriter {
  final _builder = BytesBuilder();

  Uint8List get bytes => _builder.toBytes();

  void header({required int operation, required int requestId}) {
    _builder.add([0x02, 0x00]); // IPP/2.0
    _uint16(operation);
    _uint32(requestId);
  }

  void group(int tag) => _builder.addByte(tag);

  void string(int valueTag, String name, String value) {
    final encoded = utf8.encode(value);
    _attributeName(valueTag, name);
    _uint16(encoded.length);
    _builder.add(encoded);
  }

  /// `integer` (0x21) o `enum` (0x23).
  void integer(int valueTag, String name, int value) {
    _attributeName(valueTag, name);
    _uint16(4);
    _uint32(value);
  }

  void _attributeName(int valueTag, String name) {
    final encoded = utf8.encode(name);
    _builder.addByte(valueTag);
    _uint16(encoded.length);
    _builder.add(encoded);
  }

  void _uint16(int value) => _builder.add([(value >> 8) & 0xFF, value & 0xFF]);

  void _uint32(int value) {
    _uint16((value >> 16) & 0xFFFF);
    _uint16(value & 0xFFFF);
  }
}

/// Respuesta HTTP/1.1 mínima: status, cuerpo con `Content-Length` o
/// `Transfer-Encoding: chunked` y salto de respuestas `100 Continue`.
class _HttpResponse {
  const _HttpResponse(this.statusCode, this.body);

  factory _HttpResponse.parse(Uint8List raw) {
    var offset = 0;
    while (true) {
      final headerEnd = _indexOf(raw, _crlfCrlf, offset);
      if (headerEnd < 0) {
        throw const IppException(0x0500, 'Respuesta HTTP incompleta');
      }
      final lines = latin1.decode(raw.sublist(offset, headerEnd)).split('\r\n');
      final statusCode = int.parse(lines.first.split(' ')[1]);
      offset = headerEnd + 4;
      if (statusCode == 100) continue;

      final headers = {
        for (final line in lines.skip(1))
          if (line.contains(':'))
            line.substring(0, line.indexOf(':')).trim().toLowerCase(): line
                .substring(line.indexOf(':') + 1)
                .trim(),
      };
      final rest = raw.sublist(offset);
      if (headers['transfer-encoding']?.toLowerCase() == 'chunked') {
        return _HttpResponse(statusCode, _dechunk(rest));
      }
      final length = int.tryParse(headers['content-length'] ?? '');
      return _HttpResponse(
        statusCode,
        length == null || length > rest.length ? rest : rest.sublist(0, length),
      );
    }
  }

  final int statusCode;
  final Uint8List body;

  static const _crlf = [13, 10];
  static const _crlfCrlf = [13, 10, 13, 10];

  static Uint8List _dechunk(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < data.length) {
      final lineEnd = _indexOf(data, _crlf, offset);
      if (lineEnd < 0) break;
      final sizeText = latin1.decode(data.sublist(offset, lineEnd));
      final size = int.parse(sizeText.split(';').first.trim(), radix: 16);
      if (size == 0) break;
      offset = lineEnd + 2;
      out.add(data.sublist(offset, offset + size));
      offset += size + 2;
    }
    return out.takeBytes();
  }

  static int _indexOf(Uint8List data, List<int> pattern, int start) {
    for (var i = start; i <= data.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
