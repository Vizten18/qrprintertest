part of 'qr_printer_bloc.dart';

enum DiscoveryStatus { idle, scanning, failure }

enum PrintStatus { idle, printing, success, failure }

final class QrPrinterState extends Equatable {
  const QrPrinterState({
    required this.qrData,
    required this.layout,
    this.printers = const [],
    this.discoveryStatus = DiscoveryStatus.idle,
    this.printStatus = PrintStatus.idle,
    this.selectedPrinter,
    this.message,
  });

  final String qrData;
  final PageLayout layout;
  final List<NetworkPrinter> printers;
  final DiscoveryStatus discoveryStatus;
  final PrintStatus printStatus;
  final NetworkPrinter? selectedPrinter;

  /// Mensaje de resultado (job id o error) para mostrar al usuario.
  final String? message;

  QrPrinterState copyWith({
    String? qrData,
    PageLayout? layout,
    List<NetworkPrinter>? printers,
    DiscoveryStatus? discoveryStatus,
    PrintStatus? printStatus,
    NetworkPrinter? selectedPrinter,
    String? Function()? message,
  }) {
    return QrPrinterState(
      qrData: qrData ?? this.qrData,
      layout: layout ?? this.layout,
      printers: printers ?? this.printers,
      discoveryStatus: discoveryStatus ?? this.discoveryStatus,
      printStatus: printStatus ?? this.printStatus,
      selectedPrinter: selectedPrinter ?? this.selectedPrinter,
      message: message != null ? message() : this.message,
    );
  }

  @override
  List<Object?> get props => [
    qrData,
    layout,
    printers,
    discoveryStatus,
    printStatus,
    selectedPrinter,
    message,
  ];
}
