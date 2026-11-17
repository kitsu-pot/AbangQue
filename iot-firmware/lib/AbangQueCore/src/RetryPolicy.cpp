#include "RetryPolicy.h"
#include <algorithm>

namespace abangque {
void ReportSchedule::completed(ReportResult result, uint32_t now, uint32_t retryAfter) {
  since_ = now;
  scheduled_ = true;
  if (result == ReportResult::AuthRejected || result == ReportResult::AssignmentRejected ||
      result == ReportResult::PermanentFailure) { halted_ = true; return; }
  if (result == ReportResult::TransientFailure) {
    // Retry-After delta seconds: clamp untrusted values to 1 hour; no tight loops.
    delay_ = std::max(retry_.take(), std::min(retryAfter, uint32_t{3600}) * 1000);
  } else { retry_.reset(); delay_ = interval_; }
}
}
