#pragma once
#include "Reporter.h"
#include <Arduino.h>
#include <atomic>
#include <sys/time.h>
#include <esp_sntp.h>

class TimeSync final : public abangque::Clock {
 public:
  void begin(const char* server) {
    sntp_set_time_sync_notification_cb([](timeval*) {
      synchronizedAt_.store(millis()); synchronized_.store(true);
    });
    configTime(0, 0, server);
  }
  uint32_t monotonicMs() const override { return millis(); }
  int64_t utcMs() const override {
    if (!synchronized_.load() || static_cast<uint32_t>(millis() - synchronizedAt_.load()) > 86400000)
      return 0;
    timeval now{}; gettimeofday(&now, nullptr);
    const int64_t ms = static_cast<int64_t>(now.tv_sec) * 1000 + now.tv_usec / 1000;
    return abangque::plausibleUtc(ms) ? ms : 0;
  }
 private:
  static std::atomic<bool> synchronized_;
  static std::atomic<uint32_t> synchronizedAt_;
};
