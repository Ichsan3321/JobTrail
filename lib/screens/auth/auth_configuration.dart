enum AuthCallback { confirmation, recovery }

class AuthConfiguration {
  AuthConfiguration({
    required String mode,
    required String projectUrl,
    required this.publishableKey,
    required String webOrigin,
  }) : isMock = mode == 'mock',
       project = Uri.tryParse(projectUrl),
       web = Uri.tryParse(webOrigin) {
    if (mode != 'mock' && mode != 'supabase') {
      throw const FormatException(
        'Gunakan JOBTRAIL_AUTH_MODE supabase atau mock.',
      );
    }
    if (isMock) return;
    final backend = project;
    if (!_isOrigin(backend) ||
        backend!.scheme != 'https' ||
        !RegExp(r'^[a-z0-9-]+\.supabase\.co$').hasMatch(backend.host) ||
        backend.hasPort) {
      throw const FormatException(
        'Isi JOBTRAIL_SUPABASE_URL dengan origin HTTPS project Supabase.',
      );
    }
    if (!RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(publishableKey)) {
      throw const FormatException(
        'Isi JOBTRAIL_SUPABASE_PUBLISHABLE_KEY dengan publishable key project.',
      );
    }
    final site = web;
    if (!_isOrigin(site) ||
        (site!.scheme != 'https' &&
            (site.scheme != 'http' ||
                !const [
                  'localhost',
                  '127.0.0.1',
                  '::1',
                ].contains(site.host)))) {
      throw const FormatException(
        'JOBTRAIL_WEB_ORIGIN harus berupa origin HTTPS atau HTTP loopback.',
      );
    }
  }

  factory AuthConfiguration.fromEnvironment() => AuthConfiguration(
    mode: const String.fromEnvironment(
      'JOBTRAIL_AUTH_MODE',
      defaultValue: 'supabase',
    ),
    projectUrl: const String.fromEnvironment('JOBTRAIL_SUPABASE_URL'),
    publishableKey: const String.fromEnvironment(
      'JOBTRAIL_SUPABASE_PUBLISHABLE_KEY',
    ),
    webOrigin: const String.fromEnvironment(
      'JOBTRAIL_WEB_ORIGIN',
      defaultValue: 'http://localhost:3000',
    ),
  );

  final bool isMock;
  final Uri? project;
  final Uri? web;
  final String publishableKey;

  static const _androidScheme = 'com.example.jobtrail';

  static bool _isOrigin(Uri? uri) =>
      uri != null &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path.isEmpty || uri.path == '/');

  Uri redirect(AuthCallback flow, {required bool onWeb}) {
    final name = flow == AuthCallback.recovery ? 'recovery' : 'confirm';
    return onWeb
        ? web!.replace(path: '/', queryParameters: {'auth': name})
        : Uri(scheme: _androidScheme, host: 'auth', path: '/$name');
  }

  AuthCallback? callback(Uri uri, {required bool onWeb}) {
    if (uri.userInfo.isNotEmpty) return null;
    for (final flow in AuthCallback.values) {
      final expected = redirect(flow, onWeb: onWeb);
      if (uri.scheme == expected.scheme &&
          uri.host == expected.host &&
          uri.port == expected.port &&
          uri.path == expected.path &&
          (!onWeb ||
              uri.queryParametersAll['auth']?.length == 1 &&
                  uri.queryParameters['auth'] ==
                      expected.queryParameters['auth'])) {
        return flow;
      }
    }
    return null;
  }
}
