#pragma once
#include "DeviceApi.h"

namespace abangque {
class Backoff {
 public:
  Backoff(uint32_t initialMs, uint32_t maximumMs) : initial_(initialMs), max_(maximumMs), next_(initialMs) {}
  uint32_t take() { auto delay = next_; next_ = next_ >= max_ / 2 ? max_ : next_ * 2; return delay; }
  void reset() { next_ = initial_; }
 private:
  uint32_t initial_, max_, next_;
};
class ReportSchedule {
 public:
  explicit ReportSchedule(uint32_t intervalMs) : interval_(intervalMs), retry_(intervalMs, 300000) {}
  bool due(uint32_t now) const { return !halted_ && (!scheduled_ || static_cast<uint32_t>(now - since_) >= delay_); }
  void completed(ReportResult result, uint32_t now, uint32_t retryAfterSeconds = 0);
  bool halted() const { return halted_; }
 private:
  uint32_t interval_, since_ = 0, delay_ = 0;
  bool scheduled_ = false, halted_ = false;
  Backoff retry_;
};
}
