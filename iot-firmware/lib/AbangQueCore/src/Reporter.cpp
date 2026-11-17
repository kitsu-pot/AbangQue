#include "Reporter.h"

namespace abangque {
bool Reporter::tick(const SensorSnapshot& s) {
  const auto now = clock_.monotonicMs();
  network_.tick(now);
  if (halted() || !schedule_.due(now) || !network_.connected() ||
      s.fix.measuredAtMs <= lastAttemptedTimestamp_) return false;
  DeviceRequest request;
  if (!buildRequest(config_, s.fix, s.availability, now, clock_.utcMs(), request)) return false;
  // No queue and no blind replay after an uncertain timeout. Next attempt needs
  // a new measured fix and the CURRENT driver selection, at the scheduled time.
  lastAttemptedTimestamp_ = s.fix.measuredAtMs;
  const auto response = network_.post(request);
  result_ = classifyResponse(response, config_.jeepneyId);
  schedule_.completed(result_, clock_.monotonicMs(), response.retryAfterSeconds);
  return true;
}
}
