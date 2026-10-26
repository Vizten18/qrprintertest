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
  IppClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _httpClient;
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

    final response = await _post(printerUri, request.bytes, document);
    return _parseResponse(response);
  }

  Future<Uint8List> _post(
    Uri printerUri,
    Uint8List ippRequest,
    Uint8List document,
  ) async {
    // IPP viaja sobre HTTP: ipp://host:631/path -> http://host:631/path
    final httpUri = printerUri.replace(
      scheme: printerUri.scheme == 'ipps' ? 'https' : 'http',
      port: printerUri.hasPort ? printerUri.port : 631,
    );
    final request = await _httpClient.postUrl(httpUri);
    request.headers
      ..contentType = ContentType('application', 'ipp')
      ..contentLength = ippRequest.length + document.length;
    request
      ..add(ippRequest)
      ..add(document);
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    if (response.statusCode != HttpStatus.ok) {
      throw IppException(response.statusCode, 'HTTP ${response.statusCode}');
    }
    return builder.takeBytes();
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

  void close() => _httpClient.close(force: true);
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
