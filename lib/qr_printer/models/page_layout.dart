import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Tamaños de hoja, con su keyword IPP `media` (PWG 5101.1).
enum PaperSize {
  carta('Carta', 215.9, 279.4, 'na_letter_8.5x11in'),
  oficio('Oficio', 215.9, 330.2, 'na_foolscap_8.5x13in'),
  legal('Legal', 215.9, 355.6, 'na_legal_8.5x14in'),
  a4('A4', 210, 297, 'iso_a4_210x297mm');

  const PaperSize(this.label, this.widthMm, this.heightMm, this.ippMedia);

  final String label;
  final double widthMm;
  final double heightMm;
  final String ippMedia;
}

/// Calidad de impresión: valor IPP `print-quality` y resolución con la que
/// se rasteriza la hoja.
enum PrintQuality {
  draft('Borrador', 3, 150),
  normal('Normal', 4, 200),
  high('Alta', 5, 300);

  const PrintQuality(this.label, this.ippValue, this.dpi);

  final String label;
  final int ippValue;
  final int dpi;
}

/// Hoja a imprimir y posición/tamaño del QR sobre ella, en milímetros desde
/// la esquina superior izquierda de la hoja.
final class PageLayout extends Equatable {
  const PageLayout({
    required this.paper,
    required this.quality,
    required this.qrSizeMm,
    required this.qrLeftMm,
    required this.qrTopMm,
  });

  factory PageLayout.initial() => const PageLayout(
    paper: PaperSize.carta,
    quality: PrintQuality.draft,
    qrSizeMm: 50,
    qrLeftMm: 0,
    qrTopMm: 20,
  ).centeredHorizontally();

  /// Margen no imprimible. Las impresoras de la red reportan
  /// `media-*-margin-supported = 296` (centésimas de mm) ≈ 3 mm.
  static const marginMm = 3.0;
  static const minQrSizeMm = 15.0;

  final PaperSize paper;
  final PrintQuality quality;
  final double qrSizeMm;
  final double qrLeftMm;
  final double qrTopMm;

  /// Área que la impresora puede imprimir; es lo que se rasteriza y se envía.
  Rect get printableArea => Rect.fromLTWH(
    marginMm,
    marginMm,
    paper.widthMm - marginMm * 2,
    paper.heightMm - marginMm * 2,
  );

  double get maxQrSizeMm => math.min(printableArea.width, printableArea.height);

  Rect get qrRect => Rect.fromLTWH(qrLeftMm, qrTopMm, qrSizeMm, qrSizeMm);

  PageLayout copyWith({
    PaperSize? paper,
    PrintQuality? quality,
    double? qrSizeMm,
    double? qrLeftMm,
    double? qrTopMm,
  }) {
    return PageLayout(
      paper: paper ?? this.paper,
      quality: quality ?? this.quality,
      qrSizeMm: qrSizeMm ?? this.qrSizeMm,
      qrLeftMm: qrLeftMm ?? this.qrLeftMm,
      qrTopMm: qrTopMm ?? this.qrTopMm,
    )._clamped();
  }

  /// Mueve el QR para que su centro quede en [center].
  PageLayout centeredAt(Offset center) => copyWith(
    qrLeftMm: center.dx - qrSizeMm / 2,
    qrTopMm: center.dy - qrSizeMm / 2,
  );

  PageLayout centered() => centeredAt(printableArea.center);

  PageLayout centeredHorizontally() =>
      centeredAt(Offset(printableArea.center.dx, qrTopMm + qrSizeMm / 2));

  /// Mantiene el QR completo dentro del área imprimible.
  PageLayout _clamped() {
    final area = printableArea;
    final size = qrSizeMm.clamp(minQrSizeMm, maxQrSizeMm);
    return PageLayout(
      paper: paper,
      quality: quality,
      qrSizeMm: size,
      qrLeftMm: qrLeftMm.clamp(area.left, area.right - size),
      qrTopMm: qrTopMm.clamp(area.top, area.bottom - size),
    );
  }

  @override
  List<Object?> get props => [paper, quality, qrSizeMm, qrLeftMm, qrTopMm];
}
