#pragma once
#include "Reporter.h"
#include <WiFi.h>
#include <esp_http_client.h>

class WifiTransport final : public abangque::NetworkTransport {
 public:
  explicit WifiTransport(const abangque::DeviceConfig& config) : config_(config) {}
  void begin();
  void tick(uint32_t nowMs) override;
  bool connected() const override { return WiFi.status() == WL_CONNECTED; }
  abangque::HttpResponse post(const abangque::DeviceRequest& request) override;
 private:
  static esp_err_t event(esp_http_client_event_t* event);
  const abangque::DeviceConfig& config_;
  abangque::Backoff reconnect_{2000, 60000};
  bool connecting_ = false, waiting_ = false, wasConnected_ = false;
  uint32_t startedAt_ = 0, delay_ = 0;
};
