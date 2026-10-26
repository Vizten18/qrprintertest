import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:qrprintertest/qr_printer/data/ipp_client.dart';
import 'package:qrprintertest/qr_printer/data/printer_discovery.dart';
import 'package:qrprintertest/qr_printer/models/models.dart';
import 'package:qrprintertest/qr_printer/utils/page_renderer.dart';

part 'qr_printer_event.dart';
part 'qr_printer_state.dart';

class QrPrinterBloc extends Bloc<QrPrinterEvent, QrPrinterState> {
  QrPrinterBloc({
    required this._ippClient,
    this._discovery = const PrinterDiscovery(),
    this._renderPage = renderPageJpeg,
    this._discoveryTimeout = const Duration(seconds: 15),
    Random? random,
  }) : _random = random ?? Random(),
       super(
         QrPrinterState(
           qrData: _randomText(random ?? Random()),
           layout: PageLayout.initial(),
         ),
       ) {
    on<QrTextGenerated>(_onQrTextGenerated);
    on<PaperSizeChanged>(
      (event, emit) =>
          _updateLayout(emit, (l) => l.copyWith(paper: event.paper)),
    );
    on<PrintQualityChanged>(
      (event, emit) =>
          _updateLayout(emit, (l) => l.copyWith(quality: event.quality)),
    );
    on<QrSizeChanged>(
      (event, emit) => _updateLayout(
        emit,
        // Cambia el tamaño manteniendo el centro del QR.
        (l) => l.copyWith(qrSizeMm: event.sizeMm).centeredAt(l.qrRect.center),
      ),
    );
    on<QrMoved>(
      (event, emit) => _updateLayout(
        emit,
        (l) => l.copyWith(
          qrLeftMm: l.qrLeftMm + event.deltaMm.dx,
          qrTopMm: l.qrTopMm + event.deltaMm.dy,
        ),
      ),
    );
    on<QrPlaced>(
      (event, emit) => _updateLayout(emit, (l) => l.centeredAt(event.centerMm)),
    );
    on<QrCentered>((event, emit) => _updateLayout(emit, (l) => l.centered()));
    on<PrinterDiscoveryStarted>(_onDiscoveryStarted);
    on<PrinterDiscoveryStopped>(_onDiscoveryStopped);
    on<_PrinterDiscovered>(_onPrinterDiscovered);
    on<_PrinterDiscoveryFailed>(_onDiscoveryFailed);
    on<PrinterSelected>(_onPrinterSelected);
  }

  final IppClient _ippClient;
  final PrinterDiscovery _discovery;
  final PageRenderer _renderPage;
  final Random _random;
  final Duration _discoveryTimeout;

  StreamSubscription<NetworkPrinter>? _discoverySubscription;
  Timer? _discoveryTimer;

  static String _randomText(Random random) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(
      12,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'NEXTEP-$code';
  }

  void _updateLayout(
    Emitter<QrPrinterState> emit,
    PageLayout Function(PageLayout layout) update,
  ) {
    emit(state.copyWith(layout: update(state.layout)));
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

    _discoverySubscription = _discovery.discover().listen(
      (printer) => add(_PrinterDiscovered(printer)),
      onError: (Object error) => add(_PrinterDiscoveryFailed(error)),
    );

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

  Future<void> _onDiscoveryFailed(
    _PrinterDiscoveryFailed event,
    Emitter<QrPrinterState> emit,
  ) async {
    await _stopDiscovery();
    emit(
      state.copyWith(
        discoveryStatus: DiscoveryStatus.failure,
        message: () =>
            'No se pudo buscar impresoras: ${event.error}. '
            'Revisa el permiso de red local y que estés en la misma WiFi.',
      ),
    );
  }

  void _onPrinterDiscovered(
    _PrinterDiscovered event,
    Emitter<QrPrinterState> emit,
  ) {
    if (state.printers.contains(event.printer)) return;
    emit(state.copyWith(printers: [...state.printers, event.printer]));
  }

  Future<void> _onPrinterSelected(
    PrinterSelected event,
    Emitter<QrPrinterState> emit,
  ) async {
    if (state.printStatus == PrintStatus.printing) return;

    final printer = event.printer;
    final layout = state.layout;
    emit(
      state.copyWith(
        selectedPrinter: printer,
        printStatus: PrintStatus.printing,
        message: () => null,
      ),
    );

    try {
      final jpeg = await _renderPage(layout, state.qrData);
      final jobId = await _ippClient.printJob(
        printerUri: printer.uri,
        document: jpeg,
        documentFormat: 'image/jpeg',
        jobName: 'QR ${state.qrData}',
        media: layout.paper.ippMedia,
        printQuality: layout.quality.ippValue,
      );
      emit(
        state.copyWith(
          printStatus: PrintStatus.success,
          message: () =>
              'Trabajo ${jobId ?? ''} aceptado por ${printer.name} '
              '(${layout.paper.label}, ${layout.quality.label})',
        ),
      );
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(
        state.copyWith(
          printStatus: PrintStatus.failure,
          message: () => 'La impresora rechazó el trabajo: $error',
        ),
      );
    }
  }

  Future<void> _stopDiscovery() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
  }

  @override
  Future<void> close() async {
    await _stopDiscovery();
    _ippClient.close();
    return super.close();
  }
}
