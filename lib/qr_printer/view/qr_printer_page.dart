import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nitro_printing/nitro_printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrprintertest/qr_printer/bloc/qr_printer_bloc.dart';

class QrPrinterPage extends StatelessWidget {
  const QrPrinterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          QrPrinterBloc(printing: NitroPrinting.instance)
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
            SliverToBoxAdapter(child: _QrSection()),
            SliverToBoxAdapter(child: _PrintersHeader()),
            _PrintersList(),
          ],
        ),
      ),
    );
  }
}

class _QrSection extends StatelessWidget {
  const _QrSection();

  @override
  Widget build(BuildContext context) {
    final qrData = context.select<QrPrinterBloc, String>(
      (bloc) => bloc.state.qrData,
    );
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: qrData, size: 220),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(qrData, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                context.read<QrPrinterBloc>().add(const QrTextGenerated()),
            icon: const Icon(Icons.refresh),
            label: const Text('Generar otro QR'),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Impresoras en la red',
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

    return SliverList.builder(
      itemCount: state.printers.length,
      itemBuilder: (context, index) {
        final printer = state.printers[index];
        final isSelected = printer.id == state.selectedPrinterId;
        final isPrinting =
            isSelected && state.printStatus == PrintStatus.printing;
        return ListTile(
          leading: const Icon(Icons.print),
          title: Text(printer.name),
          subtitle: Text(
            printer.uri.isNotEmpty ? printer.uri : printer.host,
          ),
          selected: isSelected,
          trailing: isPrinting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          onTap: state.printStatus == PrintStatus.printing
              ? null
              : () => context.read<QrPrinterBloc>().add(
                  PrinterSelected(printer),
                ),
        );
      },
    );
  }
}
