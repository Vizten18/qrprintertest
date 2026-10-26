import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nitro_printing/nitro_printing.dart';
import 'package:qrprintertest/qr_printer/utils/qr_image_renderer.dart';

part 'qr_printer_event.dart';
part 'qr_printer_state.dart';

class QrPrinterBloc extends Bloc<QrPrinterEvent, QrPrinterState> {
  QrPrinterBloc({
    required this._printing,
    this._renderQr = renderQrPng,
    this._discoveryTimeout = const Duration(seconds: 15),
    Random? random,
  }) : _random = random ?? Random(),
       super(QrPrinterState(qrData: _randomText(random ?? Random()))) {
    on<QrTextGenerated>(_onQrTextGenerated);
    on<PrinterDiscoveryStarted>(_onDiscoveryStarted);
    on<PrinterDiscoveryStopped>(_onDiscoveryStopped);
    on<_PrinterDiscovered>(_onPrinterDiscovered);
    on<PrinterSelected>(_onPrinterSelected);
  }

  final NitroPrinting _printing;
  final QrImageRenderer _renderQr;
  final Random _random;
  final Duration _discoveryTimeout;

  StreamSubscription<DiscoveredPrinter>? _discoverySubscription;
  Timer? _discoveryTimer;

  static String _randomText(Random random) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(
      12,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'NEXTEP-$code';
  }

  void _onQrTextGenerated(
    QrTextGenerated event,
    Emitter<QrPrinterState> emit,
  ) {
    emit(state.copyWith(qrData: _randomText(_random)));
  }

  Future<void> _onDiscoveryStarted(
    PrinterDiscoveryStarted event,
    Emitter<QrPrinterState> emit,
  ) async {
    await _stopDiscovery();
    emit(
      state.copyWith(
        printers: [],
        discoveryStatus: DiscoveryStatus.scanning,
        message: () => null,
      ),
    );

    _discoverySubscription = _printing.onPrinterDiscovered().listen(
      (printer) => add(_PrinterDiscovered(printer)),
    );

    final started = await _printing.startPrinterDiscovery();
    if (!started) {
      await _stopDiscovery();
      emit(
        state.copyWith(
          discoveryStatus: DiscoveryStatus.failure,
          message: () => 'No se pudo iniciar la búsqueda de impresoras',
        ),
      );
      return;
    }

    _discoveryTimer = Timer(
      _discoveryTimeout,
      () => add(const PrinterDiscoveryStopped()),
    );
  }

  Future<void> _onDiscoveryStopped(
    PrinterDiscoveryStopped event,
    Emitter<QrPrinterState> emit,
  ) async {
    await _stopDiscovery();
    emit(state.copyWith(discoveryStatus: DiscoveryStatus.idle));
  }

  void _onPrinterDiscovered(
    _PrinterDiscovered event,
    Emitter<QrPrinterState> emit,
  ) {
    final printer = event.printer;
    // Una misma impresora puede anunciarse varias veces (IPv4/IPv6, ipp/ipps).
    final exists = state.printers.any(
      (p) => p.id == printer.id || p.uri == printer.uri,
    );
    if (exists) return;
    emit(state.copyWith(printers: [...state.printers, printer]));
  }

  Future<void> _onPrinterSelected(
    PrinterSelected event,
    Emitter<QrPrinterState> emit,
  ) async {
    if (state.printStatus == PrintStatus.printing) return;

    final printer = event.printer;
    emit(
      state.copyWith(
        selectedPrinterId: printer.id,
        printStatus: PrintStatus.printing,
        message: () => null,
      ),
    );

    try {
      final png = await _renderQr(state.qrData);
      final result = await _printing.printImage(
        png,
        settings: PrintSettings(
          // URI IPP de la impresora, p.ej. ipp://192.168.1.5:631/ipp/print
          printerId: printer.uri.isNotEmpty ? printer.uri : printer.host,
          jobName: 'QR ${state.qrData}',
          showPrintDialog: false,
          fitToPage: true,
          color: false,
        ),
      );

      emit(
        state.copyWith(
          printStatus: result.success
              ? PrintStatus.success
              : PrintStatus.failure,
          message: () => result.success
              ? 'Enviado a ${printer.name} (job ${result.jobId})'
              : 'Error al imprimir: ${result.errorMessage} '
                    '(${result.errorCode})',
        ),
      );
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(
        state.copyWith(
          printStatus: PrintStatus.failure,
          message: () => 'Error al imprimir: $error',
        ),
      );
    }
  }

  Future<void> _stopDiscovery() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    if (_discoverySubscription == null) return;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    await _printing.stopPrinterDiscovery();
  }

  @override
  Future<void> close() async {
    await _stopDiscovery();
    return super.close();
  }
}
