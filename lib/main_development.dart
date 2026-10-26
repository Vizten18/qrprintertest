import 'package:qrprintertest/app/app.dart';
import 'package:qrprintertest/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
