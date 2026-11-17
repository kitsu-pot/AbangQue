#include "GpsReader.h"
#include <cstring>
#include <cstdlib>
#include <cmath>

namespace abangque {
namespace {
int hex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}
bool digits(const char* s, size_t n) {
  for (size_t i = 0; i < n; ++i) if (s[i] < '0' || s[i] > '9') return false;
  return true;
}
int pair(const char* s) { return (s[0] - '0') * 10 + s[1] - '0'; }
bool coordinate(const char* s, const char* hemisphere, bool latitude, double& out) {
  const size_t whole = latitude ? 4 : 5, n = std::strlen(s);
  if (n < whole || !digits(s, whole)) return false;
  if (n > whole && (s[whole] != '.' || n == whole + 1 || !digits(s + whole + 1, n - whole - 1))) return false;
  if (std::strlen(hemisphere) != 1) return false;
  const char positive = latitude ? 'N' : 'E', negative = latitude ? 'S' : 'W';
  if (*hemisphere != positive && *hemisphere != negative) return false;
  const double raw = std::strtod(s, nullptr);
  const int degrees = static_cast<int>(raw / 100);
  const double minutes = raw - degrees * 100;
  if (minutes >= 60 || degrees > (latitude ? 90 : 180)) return false;
  out = (degrees + minutes / 60) * (*hemisphere == negative ? -1 : 1);
  return std::isfinite(out) && std::fabs(out) <= (latitude ? 90 : 180);
}
int64_t timestamp(const char* time, const char* date) {
  const size_t n = std::strlen(time);
  if (n < 6 || !digits(time, 6) || std::strlen(date) != 6 || !digits(date, 6)) return 0;
  int ms = 0;
  if (n > 6) {
    if (time[6] != '.' || n < 8 || n > 10 || !digits(time + 7, n - 7)) return 0;
    int scale = 100;
    for (size_t i = 7; i < n; ++i) { ms += (time[i] - '0') * scale; scale /= 10; }
  }
  return utcEpochMs(2000 + pair(date + 4), pair(date + 2), pair(date),
                    pair(time), pair(time + 2), pair(time + 4), ms);
}
}
void NmeaGpsReader::feed(char c, uint32_t now) {
  if (c == '$') { length_ = 0; line_[length_++] = c; return; }
  if (!length_) return;
  if (c == '\r') return;
  if (c == '\n') { line_[length_] = 0; parse(now); length_ = 0; return; }
  if (length_ + 1 >= sizeof(line_) || c < 32 || c > 126) { invalidate(); return; }
  line_[length_++] = c;
}
void NmeaGpsReader::parse(uint32_t now) {
  if (length_ < 7 || std::strncmp(line_ + 3, "RMC,", 4) != 0) return;
  const bool previouslyValid = fix_.valid;
  fix_.valid = false;
  const bool talker = std::strncmp(line_ + 1, "GP", 2) == 0 ||
    std::strncmp(line_ + 1, "GN", 2) == 0 || std::strncmp(line_ + 1, "GL", 2) == 0 ||
    std::strncmp(line_ + 1, "GA", 2) == 0 || std::strncmp(line_ + 1, "GB", 2) == 0 ||
    std::strncmp(line_ + 1, "BD", 2) == 0;
  char* star = std::strchr(line_, '*');
  if (!talker || !star || std::strlen(star) != 3 || hex(star[1]) < 0 || hex(star[2]) < 0) return;
  unsigned sum = 0;
  for (char* p = line_ + 1; p != star; ++p) sum ^= static_cast<unsigned char>(*p);
  if (sum != static_cast<unsigned>(hex(star[1]) * 16 + hex(star[2]))) return;
  *star = 0;
  char* fields[16]{};
  size_t count = 1;
  fields[0] = line_;
  for (char* p = line_; *p; ++p) {
    if (*p == ',') { *p = 0; if (count == 16) return; fields[count++] = p + 1; }
  }
  if (count < 10 || std::strcmp(fields[2], "A") != 0) return;
  // Newer NMEA mode: reject simulated/manual/dead-reckoned/no-fix positions.
  if (count > 12 && std::strlen(fields[12]) &&
      !(std::strlen(fields[12]) == 1 && std::strchr("ADFR", fields[12][0]))) return;
  // M10 emits navStatus=V to mean it supplies NO navigational-safety status.
  // This is distinct from fields[2]=V (invalid fix), which is always rejected.
  if (count > 13 && std::strlen(fields[13]) &&
      std::strcmp(fields[13], "S") != 0 && std::strcmp(fields[13], "V") != 0) return;
  Fix next;
  if (!coordinate(fields[3], fields[4], true, next.latitude) ||
      !coordinate(fields[5], fields[6], false, next.longitude)) return;
  next.measuredAtMs = timestamp(fields[1], fields[9]);
  if (!next.measuredAtMs || next.measuredAtMs < newestTimestamp_) return;
  if (next.measuredAtMs == newestTimestamp_) {
    // Multiple talkers may repeat a fix. Keep its ORIGINAL receive time.
    fix_.valid = previouslyValid;
    return;
  }
  next.receivedAtMs = now;
  next.valid = true;
  fix_ = next;
  newestTimestamp_ = next.measuredAtMs;
}
}
