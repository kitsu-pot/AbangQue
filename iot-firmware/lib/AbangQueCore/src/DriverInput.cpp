#include "DriverInput.h"

namespace abangque {
bool DriverInput::sample(bool full, bool available, uint32_t now) {
  const auto before = state_;
  const int raw = (full ? 1 : 0) | (available ? 2 : 0);
  if (raw != candidate_) {
    candidate_ = raw;
    changedAt_ = now;
    // Inhibit reports during latched-switch movement or contradictory buttons.
    if (mode_ == InputMode::LatchedContacts || raw == 3) state_ = Availability::Unknown;
  }
  if (static_cast<uint32_t>(now - changedAt_) >= debounceMs_) {
    // Latched contacts re-establish state even after bouncing back to the same side.
    if (mode_ == InputMode::LatchedContacts || raw != stable_) {
      if (raw == 1) state_ = Availability::Full;
      else if (raw == 2) state_ = Availability::Available;
      else if (raw == 3 || mode_ == InputMode::LatchedContacts) state_ = Availability::Unknown;
      stable_ = raw;
    }
  }
  return state_ != before;
}
}
