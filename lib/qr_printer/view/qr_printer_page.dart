import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qrprintertest/qr_printer/bloc/qr_printer_bloc.dart';
import 'package:qrprintertest/qr_printer/data/ipp_client.dart';
import 'package:qrprintertest/qr_printer/models/models.dart';
import 'package:qrprintertest/qr_printer/utils/page_renderer.dart';

class QrPrinterPage extends StatelessWidget {
  const QrPrinterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          QrPrinterBloc(ippClient: IppClient())
            ..add(const PrinterDiscoveryStarted()),
      child: const QrPrinterView(),
    );
  }
}

class QrPrinterView extends StatelessWidget {
  const QrPrinterView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<QrPrinterBloc, QrPrinterState>(
      listenWhen: (previous, current) =>
          previous.message != current.message && current.message != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(state.message!)));
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('QR → Impresora')),
        body: const CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _QrTextSection()),
            SliverToBoxAdapter(child: _PagePreview()),
            SliverToBoxAdapter(child: _LayoutControls()),
            SliverToBoxAdapter(child: _PrintersHeader()),
            _PrintersList(),
            SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _QrTextSection extends StatelessWidget {
  const _QrTextSection();

  @override
  Widget build(BuildContext context) {
    final qrData = context.select<QrPrinterBloc, String>(
      (bloc) => bloc.state.qrData,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              qrData,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                context.read<QrPrinterBloc>().add(const QrTextGenerated()),
            icon: const Icon(Icons.refresh),
            label: const Text('Otro QR'),
          ),
        ],
      ),
    );
  }
}

/// Hoja a escala. Usa el mismo [PagePainter] que la impresión, así que lo que
/// se ve es lo que sale.
class _PagePreview extends StatelessWidget {
  const _PagePreview();

  @override
  Widget build(BuildContext context) {
    final (layout, qrData) = context
        .select<QrPrinterBloc, (PageLayout, String)>(
          (bloc) => (bloc.state.layout, bloc.state.qrData),
        );
    final paper = layout.paper;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Container(
            height: 380,
            alignment: Alignment.center,
            child: AspectRatio(
              aspectRatio: paper.widthMm / paper.heightMm,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = constraints.maxWidth / paper.widthMm;
                  final area = layout.printableArea;
                  final qr = layout.qrRect;
                  return GestureDetector(
                    onTapUp: (details) => context.read<QrPrinterBloc>().add(
                      QrPlaced(details.localPosition / scale),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: kElevationToShadow[3],
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: PagePainter(
                                layout: layout,
                                qrData: qrData,
                              ),
                            ),
                          ),
                          // Margen no imprimible.
                          Positioned.fromRect(
                            rect: Rect.fromLTRB(
                              area.left * scale,
                              area.top * scale,
                              area.right * scale,
                              area.bottom * scale,
                            ),
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fromRect(
                            rect: Rect.fromLTWH(
                              qr.left * scale,
                              qr.top * scale,
                              qr.width * scale,
                              qr.height * scale,
                            ),
                            child: _DraggableQr(
                              onMoved: (delta) => context
                                  .read<QrPrinterBloc>()
                                  .add(QrMoved(delta / scale)),
                              borderColor: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${paper.label} · ${paper.widthMm.round()}×'
            '${paper.heightMm.round()} mm — arrastra el QR o toca la hoja',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Zona sobre el QR que captura el arrastre de inmediato, para que gane al
/// scroll vertical de la página.
class _DraggableQr extends StatelessWidget {
  const _DraggableQr({required this.onMoved, required this.borderColor});

  final ValueChanged<Offset> onMoved;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        ImmediateMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              ImmediateMultiDragGestureRecognizer
            >(
              ImmediateMultiDragGestureRecognizer.new,
              (recognizer) => recognizer.onStart = (_) => _QrDrag(onMoved),
            ),
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _QrDrag extends Drag {
  _QrDrag(this.onMoved);

  final ValueChanged<Offset> onMoved;

  @override
  void update(DragUpdateDetails details) => onMoved(details.delta);
}

class _LayoutControls extends StatelessWidget {
  const _LayoutControls();

  @override
  Widget build(BuildContext context) {
    final layout = context.select<QrPrinterBloc, PageLayout>(
      (bloc) => bloc.state.layout,
    );
    final bloc = context.read<QrPrinterBloc>();
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Hoja', style: textTheme.labelLarge),
          const SizedBox(height: 4),
          SegmentedButton<PaperSize>(
            showSelectedIcon: false,
            segments: [
              for (final paper in PaperSize.values)
                ButtonSegment(value: paper, label: Text(paper.label)),
            ],
            selected: {layout.paper},
            onSelectionChanged: (s) => bloc.add(PaperSizeChanged(s.single)),
          ),
          const SizedBox(height: 12),
          Text('Calidad', style: textTheme.labelLarge),
          const SizedBox(height: 4),
          SegmentedButton<PrintQuality>(
            showSelectedIcon: false,
            segments: [
              for (final quality in PrintQuality.values)
                ButtonSegment(value: quality, label: Text(quality.label)),
            ],
            selected: {layout.quality},
            onSelectionChanged: (s) => bloc.add(PrintQualityChanged(s.single)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tamaño del QR: ${layout.qrSizeMm.round()} mm',
                  style: textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => bloc.add(const QrCentered()),
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Centrar'),
              ),
            ],
          ),
          Slider(
            value: layout.qrSizeMm,
            min: PageLayout.minQrSizeMm,
            max: layout.maxQrSizeMm,
            label: '${layout.qrSizeMm.round()} mm',
            onChanged: (value) => bloc.add(QrSizeChanged(value)),
          ),
          Text(
            'Posición: ${layout.qrLeftMm.round()} mm desde la izquierda, '
            '${layout.qrTopMm.round()} mm desde arriba',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PrintersHeader extends StatelessWidget {
  const _PrintersHeader();

  @override
  Widget build(BuildContext context) {
    final status = context.select<QrPrinterBloc, DiscoveryStatus>(
      (bloc) => bloc.state.discoveryStatus,
    );
    final isScanning = status == DiscoveryStatus.scanning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Toca una impresora para imprimir',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton(
            onPressed: () => context.read<QrPrinterBloc>().add(
              isScanning
                  ? const PrinterDiscoveryStopped()
                  : const PrinterDiscoveryStarted(),
            ),
            child: Text(isScanning ? 'Detener' : 'Buscar'),
          ),
        ],
      ),
    );
  }
}

class _PrintersList extends StatelessWidget {
  const _PrintersList();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<QrPrinterBloc>().state;

    if (state.printers.isEmpty) {
      final text = switch (state.discoveryStatus) {
        DiscoveryStatus.scanning => 'Buscando impresoras…',
        DiscoveryStatus.failure => 'No se pudo buscar impresoras',
        DiscoveryStatus.idle => 'No se encontraron impresoras',
      };
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(text)),
        ),
      );
    }

    final isPrinting = state.printStatus == PrintStatus.printing;
    return SliverList.builder(
      itemCount: state.printers.length,
      itemBuilder: (context, index) {
        final printer = state.printers[index];
        final isSelected = printer == state.selectedPrinter;
        return ListTile(
          leading: const Icon(Icons.print),
          title: Text(printer.name),
          subtitle: Text(printer.uri.toString()),
          selected: isSelected,
          trailing: isSelected && isPrinting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          onTap: isPrinting
              ? null
              : () => context.read<QrPrinterBloc>().add(
                  PrinterSelected(printer),
                ),
        );
      },
    );
  }
}
