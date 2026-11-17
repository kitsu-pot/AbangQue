#include "DeviceConfig.h"
#include <cstring>
#include <cstdio>

namespace abangque {
namespace {
bool alnum(char c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'); }
bool hex(char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
}
bool validIdentifier(const std::string& s, size_t max) {
  if (s.empty() || s.size() > max || !alnum(s[0])) return false;
  for (char c : s) if (!alnum(c) && c != '_' && c != '-') return false;
  return true;
}
bool validToken(const std::string& s) {
  if (s.size() != 101 || s[36] != '.') return false;
  for (size_t i = 0; i < s.size(); ++i) {
    if (i == 36) continue;
    if (i == 8 || i == 13 || i == 18 || i == 23) { if (s[i] != '-') return false; }
    else if (!hex(s[i])) return false;
  }
  return true;
}
bool validOrigin(const std::string& s, bool allowHttp, bool production) {
  const bool https = s.compare(0, 8, "https://") == 0;
  const bool http = s.compare(0, 7, "http://") == 0;
  if (!https && (!http || production || !allowHttp)) return false;
  std::string authority = s.substr(https ? 8 : 7);
  if (authority.empty() || authority.size() > 253) return false;
  auto colon = authority.find(':');
  std::string host = authority.substr(0, colon);
  if (host.empty() || host.front() == '.' || host.back() == '.' || host.find("..") != std::string::npos) return false;
  for (char c : host) if (!alnum(c) && !(c >= 'a' && c <= 'z') && c != '.' && c != '-') return false;
  if (colon != std::string::npos) {
    const auto port = authority.substr(colon + 1);
    if (port.empty() || port.size() > 5) return false;
    unsigned n = 0;
    for (char c : port) { if (c < '0' || c > '9') return false; n = n * 10 + c - '0'; }
    if (n == 0 || n > 65535) return false;
  }
  if (http) {
    unsigned a, b, c, d; char extra;
    if (std::sscanf(host.c_str(), "%u.%u.%u.%u%c", &a, &b, &c, &d, &extra) != 4 ||
        a > 255 || b > 255 || c > 255 || d > 255) return false;
    char canonical[16]; std::snprintf(canonical, sizeof(canonical), "%u.%u.%u.%u", a, b, c, d);
    if (host != canonical) return false;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }
  return true;
}
bool validConfig(const DeviceConfig& c, bool production) {
  return c.wifiSsid && *c.wifiSsid && std::strlen(c.wifiSsid) <= 32 && c.wifiPassword &&
    c.apiOrigin && validOrigin(c.apiOrigin, c.allowDevelopmentHttp, production) &&
    c.deviceId && validIdentifier(c.deviceId, 96) &&
    c.jeepneyId && validIdentifier(c.jeepneyId, 64) && c.deviceToken && validToken(c.deviceToken) &&
    c.rootCaPem && (std::strncmp(c.apiOrigin, "https://", 8) != 0 ||
      std::strstr(c.rootCaPem, "-----BEGIN CERTIFICATE-----")) &&
    c.reportIntervalMs >= 10000 && c.reportIntervalMs <= 300000 && c.ntpServer && *c.ntpServer &&
    c.gpsBaud >= 4800 && c.gpsBaud <= 115200;
}
}
