// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _key = 'gather_remember_me';

/// true/unset = remembered (default). Explicit 'false' means the person
/// unchecked "Remember me" at login, so we sign them out on the next cold
/// start (see main.dart) while still keeping them signed in for the rest of
/// this session.
bool readRememberMe() => html.window.localStorage[_key] != 'false';

void writeRememberMe(bool remember) {
  if (remember) {
    html.window.localStorage.remove(_key);
  } else {
    html.window.localStorage[_key] = 'false';
  }
}
