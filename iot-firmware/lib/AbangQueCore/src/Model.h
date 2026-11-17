#pragma once
#include <cstdint>

namespace abangque {
enum class Availability { Unknown, Full, Available };
enum class InputMode { LatchedContacts, MomentaryButtons };

struct Fix {
  double latitude = 0;
  double longitude = 0;
  int64_t measuredAtMs = 0;
  uint32_t receivedAtMs = 0;
  bool valid = false;
};

bool validCoordinates(double latitude, double longitude);
bool freshFix(const Fix& fix, uint32_t nowMs, int64_t utcMs);
bool plausibleUtc(int64_t utcMs);
// UTC conversion is independent of the host timezone and time_t width.
int64_t utcEpochMs(int year, int month, int day, int hour, int minute,
                   int second, int millisecond);
bool formatUtc(int64_t epochMs, char* output, unsigned capacity);
}  // namespace abangque
