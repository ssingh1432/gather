// Non-web platforms: no separate "remember me" storage layer exists yet,
// so always behave as remembered (the historical/native behavior).
bool readRememberMe() => true;

void writeRememberMe(bool remember) {}
