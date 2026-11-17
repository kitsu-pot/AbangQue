#pragma once
#include "Model.h"

namespace abangque {
// Two independent active-low contacts make open/contradictory wiring detectable.
class DriverInput {
 public:
  explicit DriverInput(InputMode mode, uint32_t debounceMs = 50)
      : mode_(mode), debounceMs_(debounceMs) {}
  bool sample(bool fullPressed, bool availablePressed, uint32_t nowMs);
  Availability state() const { return state_; }
 private:
  InputMode mode_;
  uint32_t debounceMs_, changedAt_ = 0;
  int candidate_ = -1, stable_ = -1;
  Availability state_ = Availability::Unknown;
};
}
