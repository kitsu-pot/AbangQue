#pragma once
#include "DeviceConfig.h"

// Copy to .local/local_config.h; edit privately. Never paste secrets into CLI flags.
inline abangque::DeviceConfig makeDeviceConfig() {
  abangque::DeviceConfig c;
  c.wifiSsid = "";
  c.wifiPassword = "";
  c.apiOrigin = ""; // HTTPS origin, or laptop RFC1918 LAN IPv4 origin for isolated HTTP development.
  c.allowDevelopmentHttp = false; // Explicit opt-in; production environment always rejects HTTP.
  c.deviceId = ""; // Actual Admin IoT Devices registration ID.
  c.jeepneyId = ""; // Exact assignment returned by Admin Provision/Rotate.
  c.deviceToken = ""; // One-time credential UUID.secret-hex, WITHOUT the Bearer prefix.
  c.rootCaPem = ""; // PEM trust root for your actual HTTPS server; never call setInsecure().
  c.gpsRxPin = -1; // Set only after checking actual board + GNSS voltage/pinout.
  c.gpsBaud = 9600; // Match receiver's verified NMEA RMC configuration.
  c.fullPin = -1;
  c.availablePin = -1;
  c.inputMode = abangque::InputMode::LatchedContacts;
  c.statusLedPin = -1; // Optional external LED + resistor; no built-in LED assumed.
  c.ledActiveLow = false;
  c.reportIntervalMs = 30000;
  return c;
}
