#pragma once
#include "RetryPolicy.h"

namespace abangque {
class Clock {
 public:
  virtual ~Clock() = default;
  virtual uint32_t monotonicMs() const = 0;
  virtual int64_t utcMs() const = 0; // 0 when not synchronized / no longer trusted.
};
class NetworkTransport {
 public:
  virtual ~NetworkTransport() = default;
  virtual void tick(uint32_t nowMs) = 0;
  virtual bool connected() const = 0;
  // Called only from the network worker. Implement timeouts and authenticated TLS.
  // Future cellular adapter must preserve headers, body, timestamps and no redirects.
  virtual HttpResponse post(const DeviceRequest& request) = 0;
};
struct SensorSnapshot {
  Fix fix;
  Availability availability = Availability::Unknown;
};
class Reporter {
 public:
  Reporter(const DeviceConfig& config, NetworkTransport& network, Clock& clock)
    : config_(config), network_(network), clock_(clock), schedule_(config.reportIntervalMs) {}
  bool tick(const SensorSnapshot& sensors);
  ReportResult lastResult() const { return result_; }
  bool halted() const { return externallyBlocked_ || schedule_.halted(); }
  void block() { externallyBlocked_ = true; }
 private:
  const DeviceConfig& config_;
  NetworkTransport& network_;
  Clock& clock_;
  ReportSchedule schedule_;
  ReportResult result_ = ReportResult::TransientFailure;
  int64_t lastAttemptedTimestamp_ = 0;
  bool externallyBlocked_ = false;
};
}
