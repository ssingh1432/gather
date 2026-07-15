import 'package:web/web.dart' as web;

const _key = 'gather_remember_me';

/// true/unset = remembered (default). Explicit 'false' means the person
/// unchecked "Remember me" at login, so we sign them out on the next cold
/// start (see main.dart) while still keeping them signed in for the rest of
/// this session.
bool readRememberMe() => web.window.localStorage.getItem(_key) != 'false';

void writeRememberMe(bool remember) {
  if (remember) {
    web.window.localStorage.removeItem(_key);
  } else {
    web.window.localStorage.setItem(_key, 'false');
  }
}
