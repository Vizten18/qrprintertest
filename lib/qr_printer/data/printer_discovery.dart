import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:nitro_printing/nitro_printing.dart';

/// Descubre impresoras IPP en la red local vía mDNS / Bonjour.
///
/// Se usa `bonsoir` en vez de `NitroPrinting.startPrinterDiscovery()` porque
/// el descubrimiento de nitro_printing 0.0.6 en Android resuelve servicios en
/// paralelo con `NsdManager.resolveService` (falla en silencio con más de una
/// impresora) y en iOS no reporta errores (p.ej. permiso de red local
/// denegado). Bonsoir encola las resoluciones y propaga los errores.
class PrinterDiscovery {
  const PrinterDiscovery({this.serviceType = '_ipp._tcp'});

  final String serviceType;

  /// Emite cada impresora resuelta. La búsqueda empieza al escuchar el stream
  /// y se detiene al cancelar la suscripción.
  Stream<DiscoveredPrinter> discover() {
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    late final StreamController<DiscoveredPrinter> controller;

    Future<void> stop() async {
      final d = discovery;
      discovery = null;
      await subscription?.cancel();
      subscription = null;
      // Si la búsqueda nunca llegó a iniciar (p.ej. falló `initialize`),
      // `stop` también lanza; no hay nada que detener.
      if (d == null || !d.isReady) return;
      try {
        await d.stop();
      } on Object catch (_) {}
    }

    controller = StreamController<DiscoveredPrinter>(
      onListen: () async {
        try {
          final d = discovery = BonsoirDiscovery(type: serviceType);
          await d.initialize();
          subscription = d.eventStream!.listen(
            (event) {
              switch (event) {
                case BonsoirDiscoveryServiceFoundEvent(:final service):
                  unawaited(service.resolve(d.serviceResolver));
                case BonsoirDiscoveryServiceResolvedEvent(:final service):
                  controller.add(_toPrinter(service));
                default:
                  break;
              }
            },
            onError: controller.addError,
          );
          await d.start();
        } on Object catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      },
      onCancel: stop,
    );
    return controller.stream;
  }

  DiscoveredPrinter _toPrinter(BonsoirService service) {
    // Preferimos la IPv4 ya resuelta: evita depender de que `.local` resuelva
    // dentro del plugin de impresión y de corchetes en URIs IPv6.
    final ipv4 = service.hostAddresses.firstWhere(
      (a) => InternetAddress.tryParse(a)?.type == InternetAddressType.IPv4,
      orElse: () => '',
    );
    final host = ipv4.isNotEmpty
        ? ipv4
        : (service.hostname ?? service.hostAddress ?? service.name).replaceAll(
            RegExp(r'\.$'),
            '',
          );

    var resourcePath = service.attributes['rp'] ?? 'ipp/print';
    if (resourcePath.startsWith('/')) resourcePath = resourcePath.substring(1);

    final uri = 'ipp://$host:${service.port}/$resourcePath';
    return DiscoveredPrinter(
      id: uri,
      name: service.name,
      host: host,
      port: service.port,
      serviceType: service.type,
      uri: uri,
    );
  }
}
