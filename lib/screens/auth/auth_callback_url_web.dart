import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? state, JSString title, JSString url);

void clearAuthCallbackUrl() => _replaceState(null, ''.toJS, '/'.toJS);
