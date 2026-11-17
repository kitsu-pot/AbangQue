#include <Arduino.h>
#include <atomic>
#include <esp_log.h>
#include <driver/gpio.h>
#include "DeviceConfig.h"
#include "DriverInput.h"
#include "GpsReader.h"
#include "Reporter.h"
#include "WifiTransport.h"
#include "TimeSync.h"
#include "StatusIndicator.h"
#include "AuthLock.h"

#if __has_include("local_config.h")
#include "local_config.h"
#else
static abangque::DeviceConfig makeDeviceConfig() { return {}; }
#endif

using namespace abangque;
namespace {
const DeviceConfig config = makeDeviceConfig();
NmeaGpsReader gps;
DriverInput driver(config.inputMode);
HardwareSerial gnss(2);
TimeSync clockSource;
WifiTransport network(config);
StatusIndicator indicator;
SensorSnapshot sharedSensors;
portMUX_TYPE sensorMutex = portMUX_INITIALIZER_UNLOCKED;
std::atomic<bool> connected{false}, authRejected{false}, halted{false}, attempted{false};
std::atomic<ReportResult> lastResult{ReportResult::TransientFailure};
std::atomic<uint32_t> resultAt{0};
bool configured = false;

bool allowedPin(int pin, bool pullupOrOutput) {
  if (pin == -1) return true;
  // Conservative classic-ESP32 restrictions, NOT a replacement for the actual board schematic.
  if (pin < 0 || !GPIO_IS_VALID_GPIO(pin) || pin == 0 || pin == 1 || pin == 2 || pin == 3 ||
      (pin >= 6 && pin <= 12) || pin == 15 || pin == 16 || pin == 17) return false;
  return !pullupOrOutput || GPIO_IS_VALID_OUTPUT_GPIO(pin);
}
bool validPins() {
  const int pins[] = {config.gpsRxPin, config.fullPin, config.availablePin, config.statusLedPin};
  for (unsigned i = 0; i < 4; ++i) {
    if (!allowedPin(pins[i], i > 0)) return false;
    for (unsigned j = i + 1; j < 4; ++j) if (pins[i] >= 0 && pins[i] == pins[j]) return false;
  }
  return (config.fullPin == -1) == (config.availablePin == -1);
}
void networkWorker(void*) {
  AuthLock lock;
  bool blocked = false;
  if (!lock.begin(config.deviceToken, blocked)) { halted.store(true); vTaskDelete(nullptr); return; }
  Reporter reporter(config, network, clockSource);
  if (blocked) { reporter.block(); authRejected.store(true); }
  network.begin();
  clockSource.begin(config.ntpServer);
  for (;;) {
    SensorSnapshot snapshot;
    portENTER_CRITICAL(&sensorMutex); snapshot = sharedSensors; portEXIT_CRITICAL(&sensorMutex);
    if (reporter.tick(snapshot)) {
      const auto result = reporter.lastResult();
      lastResult.store(result); resultAt.store(millis()); attempted.store(true);
      if (result == ReportResult::AuthRejected || result == ReportResult::AssignmentRejected) {
        authRejected.store(true);
        if (!lock.reject()) halted.store(true);
      }
    }
    connected.store(network.connected());
    if (reporter.halted()) halted.store(true);
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}
DeviceStatus currentStatus(uint32_t now, const SensorSnapshot& snapshot) {
  if (!configured) return DeviceStatus::ConfigurationRequired;
  if (authRejected.load()) return DeviceStatus::AuthenticationRejected;
  if (halted.load()) return DeviceStatus::Halted;
  if (!connected.load()) return DeviceStatus::Connecting;
  if (!clockSource.utcMs()) return DeviceStatus::ClockUnavailable;
  if (!freshFix(snapshot.fix, now, clockSource.utcMs())) return DeviceStatus::GpsUnavailable;
  if (snapshot.availability == Availability::Unknown) return DeviceStatus::DriverUnknown;
  if (attempted.load() && lastResult.load() == ReportResult::TransientFailure) return DeviceStatus::ReportingError;
  if (attempted.load() && lastResult.load() == ReportResult::Accepted && now - resultAt.load() < 1000) return DeviceStatus::Sent;
  return DeviceStatus::Ready;
}
}
void setup() {
  Serial.begin(115200);
  esp_log_level_set("*", ESP_LOG_NONE); // No SDK request/header dumps.
  Serial.println(statusMessage(DeviceStatus::Starting));
#ifdef ABANGQUE_PRODUCTION
  constexpr bool production = true;
#else
  constexpr bool production = false;
#endif
  configured = validConfig(config, production) && validPins();
  if (!configured) return;
  indicator.begin(config.statusLedPin, config.ledActiveLow);
  if (config.fullPin >= 0) { pinMode(config.fullPin, INPUT_PULLUP); pinMode(config.availablePin, INPUT_PULLUP); }
  if (config.gpsRxPin >= 0) {
    gnss.setRxBufferSize(1024);
    gnss.begin(config.gpsBaud, SERIAL_8N1, config.gpsRxPin, -1, false);
  }
  if (xTaskCreate(networkWorker, "abangque-network", 12288, nullptr, 1, nullptr) != pdPASS) halted.store(true);
}
void loop() {
  const uint32_t now = millis();
  if (configured) {
    if (config.gpsRxPin >= 0) {
      if (gnss.available() > 768) {
        // Discard a backlog rather than stamp old serial bytes as a fresh reception.
        while (gnss.available()) gnss.read();
        gps.invalidate();
      }
      for (unsigned n = 0; n < 256 && gnss.available(); ++n) gps.feed(static_cast<char>(gnss.read()), now);
    }
    if (config.fullPin >= 0 && driver.sample(digitalRead(config.fullPin) == LOW,
        digitalRead(config.availablePin) == LOW, now)) {
      Serial.println(driver.state() == Availability::Full ? "Driver selected FULL" :
        driver.state() == Availability::Available ? "Driver selected AVAILABLE" : "Driver selection UNKNOWN");
    }
  }
  SensorSnapshot snapshot{gps.latest(), driver.state()};
  portENTER_CRITICAL(&sensorMutex); sharedSensors = snapshot; portEXIT_CRITICAL(&sensorMutex);
  const auto status = currentStatus(now, snapshot);
  static DeviceStatus previous = DeviceStatus::Starting;
  if (status != previous) { Serial.println(statusMessage(status)); previous = status; }
  indicator.show(status, now);
  delay(5); // Yield to Wi-Fi/worker; no network I/O or debounce waits in this loop.
}
