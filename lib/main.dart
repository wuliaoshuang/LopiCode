import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:material_ui/material_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.boot();
  runApp(LopiCodeApp(services: services));
}
