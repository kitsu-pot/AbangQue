#pragma once
#include <Preferences.h>
#include <mbedtls/sha256.h>

// Persist only a digest of a rejected token. A replacement credential clears the
// lock; power cycling the SAME rejected token does not create an authentication loop.
class AuthLock {
 public:
  bool begin(const char* token, bool& blocked) {
    unsigned char digest[32];
    if (mbedtls_sha256_ret(reinterpret_cast<const unsigned char*>(token), strlen(token), digest, 0)) return false;
    for (unsigned i = 0; i < 32; ++i) snprintf(fingerprint_ + i * 2, 3, "%02x", digest[i]);
    if (!preferences_.begin("abangque-auth", false)) return false;
    const String rejected = preferences_.getString("rejected", "");
    blocked = rejected == fingerprint_;
    if (!blocked && rejected.length() && !preferences_.remove("rejected")) return false;
    return true;
  }
  bool reject() { return preferences_.putString("rejected", fingerprint_) == 64; }
 private:
  Preferences preferences_;
  char fingerprint_[65]{};
};
