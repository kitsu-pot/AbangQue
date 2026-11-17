#pragma once
#include <Arduino.h>

enum class DeviceStatus { Starting, ConfigurationRequired, Connecting, ClockUnavailable,
  GpsUnavailable, DriverUnknown, Ready, Sent, ReportingError, AuthenticationRejected, Halted };

// Optional one-LED pulse count. Serial supplies the plain-language reason.
class StatusIndicator {
 public:
  void begin(int pin, bool activeLow) { pin_ = pin; low_ = activeLow; if (pin_ >= 0) { pinMode(pin_, OUTPUT); write(false); } }
  void show(DeviceStatus state, uint32_t now) {
    if (pin_ < 0) return;
    if (state == DeviceStatus::Ready) { write(true); return; }
    if (state == DeviceStatus::Sent) { write(now % 200 < 100); return; }
    unsigned pulses = 1;
    switch (state) {
      case DeviceStatus::Connecting: pulses = 2; break;
      case DeviceStatus::ClockUnavailable: pulses = 3; break;
      case DeviceStatus::GpsUnavailable: pulses = 4; break;
      case DeviceStatus::DriverUnknown: pulses = 5; break;
      case DeviceStatus::ReportingError: pulses = 6; break;
      case DeviceStatus::AuthenticationRejected: pulses = 7; break;
      case DeviceStatus::ConfigurationRequired: case DeviceStatus::Halted: pulses = 8; break;
      default: break;
    }
    const auto phase = now % 5000;
    write(phase < pulses * 400 && phase % 400 < 100);
  }
 private:
  void write(bool on) { digitalWrite(pin_, (on != low_) ? HIGH : LOW); }
  int pin_ = -1;
  bool low_ = false;
};

inline const char* statusMessage(DeviceStatus s) {
  switch (s) {
    case DeviceStatus::Starting: return "Starting; physical hardware validation pending";
    case DeviceStatus::ConfigurationRequired: return "Configuration required; reporting disabled";
    case DeviceStatus::Connecting: return "Wi-Fi disconnected/connecting; no API reachability claim";
    case DeviceStatus::ClockUnavailable: return "Wi-Fi connected; synchronized UTC unavailable; reporting paused";
    case DeviceStatus::GpsUnavailable: return "GPS fix unavailable/stale; reporting paused";
    case DeviceStatus::DriverUnknown: return "Driver selection unknown; reporting paused";
    case DeviceStatus::Ready: return "Wi-Fi connected; fresh GPS and driver selection ready";
    case DeviceStatus::Sent: return "API accepted a report; not proof of field accuracy";
    case DeviceStatus::ReportingError: return "Reporting failed/timeout; bounded backoff, outcome may be unconfirmed";
    case DeviceStatus::AuthenticationRejected: return "Authentication/assignment rejected; same credential locked across reboot";
    case DeviceStatus::Halted: return "Reporting halted; inspect configuration/API contract before restarting";
  }
  return "Unknown state";
}
