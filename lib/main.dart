import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'screens/auth/auth_configuration.dart';
import 'screens/auth/supabase_auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final font in {
    'Poppins': 'assets/fonts/poppins/OFL.txt',
    'Plus Jakarta Sans': 'assets/fonts/plus_jakarta_sans/OFL.txt',
  }.entries) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        font.key,
      ], await rootBundle.loadString(font.value));
    });
  }
  final AuthConfiguration configuration;
  try {
    configuration = AuthConfiguration.fromEnvironment();
  } on FormatException catch (error) {
    runApp(JobTrailApp(configurationError: error.message));
    return;
  }
  if (configuration.isMock) {
    runApp(const JobTrailApp());
    return;
  }
  try {
    final provider = await SupabaseAuthProvider.initialize(configuration);
    runApp(JobTrailApp(authProvider: provider, disposeSessionProvider: true));
  } catch (_) {
    runApp(
      const JobTrailApp(
        configurationError: 'Layanan akun gagal dimulai. Periksa konfigurasi dan buka kembali JobTrail.',
      ),
    );
  }
}
