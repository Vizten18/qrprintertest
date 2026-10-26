import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:qrprintertest/qr_printer/models/models.dart';

/// Convierte la hoja ([PageLayout] + texto del QR) en bytes JPEG listos para
/// enviar a la impresora.
typedef PageRenderer =
    Future<Uint8List> Function(PageLayout layout, String qrData);

/// Pinta la hoja en milímetros. Lo usan tanto la previsualización como
/// [renderPageJpeg], así lo que se ve es exactamente lo que se imprime.
class PagePainter extends CustomPainter {
  PagePainter({required this.layout, required this.qrData})
    : _qr = QrImage(QrCode(payload: QrPayload.fromString(qrData)));

  final PageLayout layout;
  final String qrData;
  final QrImage _qr;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = layout.paper;
    canvas
      ..save()
      // Escala de mm a la unidad del canvas (px de pantalla o de impresión).
      ..scale(size.width / paper.widthMm)
      ..drawRect(
        Rect.fromLTWH(0, 0, paper.widthMm, paper.heightMm),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    _paintQr(canvas, layout.qrRect);
    canvas.restore();
  }

  void _paintQr(Canvas canvas, Rect rect) {
    final count = _qr.moduleCount;
    final module = rect.width / count;
    final path = Path();
    for (var row = 0; row < count; row++) {
      // Une módulos oscuros contiguos de la fila en un solo rectángulo para
      // evitar costuras entre módulos al rasterizar.
      var col = 0;
      while (col < count) {
        if (!_qr.isDark(row, col)) {
          col++;
          continue;
        }
        final start = col;
        while (col < count && _qr.isDark(row, col)) {
          col++;
        }
        path.addRect(
          Rect.fromLTWH(
            rect.left + start * module,
            rect.top + row * module,
            (col - start) * module,
            module,
          ),
        );
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF000000)
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(PagePainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.qrData != qrData;
}

/// Rasteriza solo el área imprimible de la hoja a la resolución de la calidad
/// elegida. Como la imagen tiene la misma proporción que el área imprimible,
/// la impresora con `print-scaling=fit` la coloca 1:1 dentro de sus márgenes.
Future<Uint8List> renderPageJpeg(PageLayout layout, String qrData) async {
  final pxPerMm = layout.quality.dpi / 25.4;
  final area = layout.printableArea;
  final width = (area.width * pxPerMm).round();
  final height = (area.height * pxPerMm).round();
  final pageSize = Size(
    layout.paper.widthMm * pxPerMm,
    layout.paper.heightMm * pxPerMm,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(-area.left * pxPerMm, -area.top * pxPerMm);
  PagePainter(layout: layout, qrData: qrData).paint(canvas, pageSize);

  final image = await recorder.endRecording().toImage(width, height);
  final rgba = await image.toByteData();
  image.dispose();

  // Codificar JPEG de una hoja completa tarda; se hace fuera del hilo de UI.
  final bytes = rgba!.buffer.asUint8List();
  return Isolate.run(
    () => img.encodeJpg(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        numChannels: 4,
      ),
      quality: 90,
    ),
  );
}
