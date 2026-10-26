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

/// Inicia la búsqueda de impresoras en la red (mDNS / Bonjour `_ipp._tcp`).
final class PrinterDiscoveryStarted extends QrPrinterEvent {
  const PrinterDiscoveryStarted();
}

/// Detiene la búsqueda de impresoras.
final class PrinterDiscoveryStopped extends QrPrinterEvent {
  const PrinterDiscoveryStopped();
}

/// Se selecciona una impresora: se imprime el QR activo en ella.
final class PrinterSelected extends QrPrinterEvent {
  const PrinterSelected(this.printer);

  final DiscoveredPrinter printer;

  @override
  List<Object?> get props => [printer.id];
}

final class _PrinterDiscovered extends QrPrinterEvent {
  const _PrinterDiscovered(this.printer);

  final DiscoveredPrinter printer;

  @override
  List<Object?> get props => [printer.id];
}

final class _PrinterDiscoveryFailed extends QrPrinterEvent {
  const _PrinterDiscoveryFailed(this.error);

  final Object error;

  @override
  List<Object?> get props => [error];
}
