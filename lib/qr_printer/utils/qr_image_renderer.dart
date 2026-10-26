import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Convierte el texto de un QR en bytes PNG listos para imprimir.
typedef QrImageRenderer = Future<Uint8List> Function(String data);

/// Renderiza el QR sobre fondo blanco con margen (quiet zone), ya que muchas
/// impresoras convierten la transparencia a negro.
Future<Uint8List> renderQrPng(String data, {double size = 600}) async {
  const margin = 40.0;
  final total = size + margin * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, total, total),
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..translate(margin, margin);

  QrPainter(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
  ).paint(canvas, Size.square(size));

  final image = await recorder.endRecording().toImage(
    total.toInt(),
    total.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
