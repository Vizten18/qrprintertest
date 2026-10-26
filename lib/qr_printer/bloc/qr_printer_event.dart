part of 'qr_printer_bloc.dart';

sealed class QrPrinterEvent extends Equatable {
  const QrPrinterEvent();

  @override
  List<Object?> get props => [];
}

/// Genera un nuevo texto random para el QR.
final class QrTextGenerated extends QrPrinterEvent {
  const QrTextGenerated();
}

final class PaperSizeChanged extends QrPrinterEvent {
  const PaperSizeChanged(this.paper);

  final PaperSize paper;

  @override
  List<Object?> get props => [paper];
}

final class PrintQualityChanged extends QrPrinterEvent {
  const PrintQualityChanged(this.quality);

  final PrintQuality quality;

  @override
  List<Object?> get props => [quality];
}

final class QrSizeChanged extends QrPrinterEvent {
  const QrSizeChanged(this.sizeMm);

  final double sizeMm;

  @override
  List<Object?> get props => [sizeMm];
}

/// El QR se arrastra [deltaMm] sobre la hoja.
final class QrMoved extends QrPrinterEvent {
  const QrMoved(this.deltaMm);

  final Offset deltaMm;

  @override
  List<Object?> get props => [deltaMm];
}

/// Se toca la hoja: el QR se centra en [centerMm].
final class QrPlaced extends QrPrinterEvent {
  const QrPlaced(this.centerMm);

  final Offset centerMm;

  @override
  List<Object?> get props => [centerMm];
}

final class QrCentered extends QrPrinterEvent {
  const QrCentered();
}

/// Inicia la búsqueda de impresoras en la red (mDNS / Bonjour `_ipp._tcp`).
final class PrinterDiscoveryStarted extends QrPrinterEvent {
  const PrinterDiscoveryStarted();
}

/// Detiene la búsqueda de impresoras.
final class PrinterDiscoveryStopped extends QrPrinterEvent {
  const PrinterDiscoveryStopped();
}

/// Se selecciona una impresora: se imprime la hoja actual en ella.
final class PrinterSelected extends QrPrinterEvent {
  const PrinterSelected(this.printer);

  final NetworkPrinter printer;

  @override
  List<Object?> get props => [printer];
}

final class _PrinterDiscovered extends QrPrinterEvent {
  const _PrinterDiscovered(this.printer);

  final NetworkPrinter printer;

  @override
  List<Object?> get props => [printer];
}

final class _PrinterDiscoveryFailed extends QrPrinterEvent {
  const _PrinterDiscoveryFailed(this.error);

  final Object error;

  @override
  List<Object?> get props => [error];
}
