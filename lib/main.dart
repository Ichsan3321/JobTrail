import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app.dart';

void main() {
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
  runApp(const JobTrailApp());
}
