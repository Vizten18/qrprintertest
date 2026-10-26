import 'package:equatable/equatable.dart';

/// Impresora IPP encontrada en la red local.
final class NetworkPrinter extends Equatable {
  const NetworkPrinter({required this.name, required this.uri});

  final String name;

  /// URI IPP, p.ej. `ipp://192.168.1.5:631/ipp/print`.
  final Uri uri;

  @override
  List<Object?> get props => [uri];
}
