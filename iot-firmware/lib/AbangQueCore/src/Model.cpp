#include "Model.h"
#include <cmath>
#include <cstdio>

namespace abangque {
namespace {
bool leap(int y) { return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0); }
int monthDays(int y, int m) {
  static const int days[] = {31,28,31,30,31,30,31,31,30,31,30,31};
  return days[m - 1] + (m == 2 && leap(y) ? 1 : 0);
}
}
bool validCoordinates(double lat, double lon) {
  return std::isfinite(lat) && std::isfinite(lon) &&
         lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}
bool plausibleUtc(int64_t ms) {
  return ms >= 1704067200000LL && ms < 4102444800000LL; // 2024..2099
}
bool freshFix(const Fix& fix, uint32_t now, int64_t utc) {
  return fix.valid && validCoordinates(fix.latitude, fix.longitude) &&
    plausibleUtc(utc) && plausibleUtc(fix.measuredAtMs) &&
    static_cast<uint32_t>(now - fix.receivedAtMs) <= 5000 &&
    utc - fix.measuredAtMs <= 5000 && fix.measuredAtMs - utc <= 1000;
}
int64_t utcEpochMs(int y, int m, int d, int h, int min, int s, int ms) {
  if (y < 2024 || y > 2099 || m < 1 || m > 12 || d < 1 ||
      d > monthDays(y, m) || h < 0 || h > 23 || min < 0 || min > 59 ||
      s < 0 || s > 59 || ms < 0 || ms > 999) return 0;
  int days = 0;
  for (int year = 1970; year < y; ++year) days += leap(year) ? 366 : 365;
  for (int month = 1; month < m; ++month) days += monthDays(y, month);
  return (((static_cast<int64_t>(days + d - 1) * 24 + h) * 60 + min) * 60 + s) * 1000 + ms;
}
bool formatUtc(int64_t epoch, char* out, unsigned cap) {
  if (!plausibleUtc(epoch) || cap < 25) return false;
  int days = static_cast<int>(epoch / 86400000);
  int y = 1970, m = 1;
  while (days >= (leap(y) ? 366 : 365)) { days -= leap(y) ? 366 : 365; ++y; }
  while (days >= monthDays(y, m)) { days -= monthDays(y, m); ++m; }
  const int64_t t = epoch % 86400000;
  return std::snprintf(out, cap, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", y, m,
    days + 1, static_cast<int>(t / 3600000), static_cast<int>(t / 60000 % 60),
    static_cast<int>(t / 1000 % 60), static_cast<int>(t % 1000)) == 24;
}
}  // namespace abangque
