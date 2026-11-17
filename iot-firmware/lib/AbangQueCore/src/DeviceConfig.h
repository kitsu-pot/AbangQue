#pragma once
#include "Model.h"
#include <string>

namespace abangque {
struct DeviceConfig {
  const char* wifiSsid = "";
  const char* wifiPassword = "";
  const char* apiOrigin = "";
  const char* deviceId = ""; // Local inventory only; bearer credential identifies it on the API.
  const char* jeepneyId = ""; // Copy the ADMIN-PROVISIONED assignment, never choose another vehicle.
  const char* deviceToken = "";
  const char* rootCaPem = "";
  const char* ntpServer = "pool.ntp.org";
  bool allowDevelopmentHttp = false;
  int gpsRxPin = -1; // No implied board wiring. Receive-only UART; no GNSS commands.
  unsigned gpsBaud = 9600; // Provisional, must match identified receiver.
  int fullPin = -1;
  int availablePin = -1;
  InputMode inputMode = InputMode::LatchedContacts;
  int statusLedPin = -1;
  bool ledActiveLow = false;
  uint32_t reportIntervalMs = 30000;
};
bool validIdentifier(const std::string& value, size_t maxLength);
bool validToken(const std::string& token);
bool validOrigin(const std::string& origin, bool allowDevelopmentHttp, bool production);
bool validConfig(const DeviceConfig& config, bool production);
}
