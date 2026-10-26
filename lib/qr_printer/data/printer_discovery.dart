import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:qrprintertest/qr_printer/models/models.dart';

/// Descubre impresoras IPP en la red local vía mDNS / Bonjour.
///
/// Bonsoir usa NSD (Android) / Bonjour (iOS), encola las resoluciones de
/// servicios y propaga errores (p.ej. permiso de red local denegado).
class PrinterDiscovery {
  const PrinterDiscovery({this.serviceType = '_ipp._tcp'});

  final String serviceType;

  /// Emite cada impresora resuelta. La búsqueda empieza al escuchar el stream
  /// y se detiene al cancelar la suscripción.
  Stream<NetworkPrinter> discover() {
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    late final StreamController<NetworkPrinter> controller;

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

    controller = StreamController<NetworkPrinter>(
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

  NetworkPrinter _toPrinter(BonsoirService service) {
    // Preferimos la IPv4 ya resuelta: evita depender de que `.local` resuelva
    // y de corchetes en URIs IPv6.
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

    final resourcePath = service.attributes['rp'] ?? 'ipp/print';
    return NetworkPrinter(
      name: service.name,
      uri: Uri(
        scheme: 'ipp',
        host: host,
        port: service.port,
        path: resourcePath.startsWith('/') ? resourcePath : '/$resourcePath',
      ),
    );
  }
}
