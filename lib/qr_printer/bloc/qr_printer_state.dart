part of 'qr_printer_bloc.dart';

enum DiscoveryStatus { idle, scanning, failure }

enum PrintStatus { idle, printing, success, failure }

final class QrPrinterState extends Equatable {
  const QrPrinterState({
    required this.qrData,
    this.printers = const [],
    this.discoveryStatus = DiscoveryStatus.idle,
    this.printStatus = PrintStatus.idle,
    this.selectedPrinterId,
    this.message,
  });

  final String qrData;
  final List<DiscoveredPrinter> printers;
  final DiscoveryStatus discoveryStatus;
  final PrintStatus printStatus;
  final String? selectedPrinterId;

  /// Mensaje de resultado (job id o error) para mostrar al usuario.
  final String? message;

  QrPrinterState copyWith({
    String? qrData,
    List<DiscoveredPrinter>? printers,
    DiscoveryStatus? discoveryStatus,
    PrintStatus? printStatus,
    String? selectedPrinterId,
    String? Function()? message,
  }) {
    return QrPrinterState(
      qrData: qrData ?? this.qrData,
      printers: printers ?? this.printers,
      discoveryStatus: discoveryStatus ?? this.discoveryStatus,
      printStatus: printStatus ?? this.printStatus,
      selectedPrinterId: selectedPrinterId ?? this.selectedPrinterId,
      message: message != null ? message() : this.message,
    );
  }

  @override
  List<Object?> get props => [
    qrData,
    printers.map((p) => p.id).toList(),
    discoveryStatus,
    printStatus,
    selectedPrinterId,
    message,
  ];
}
