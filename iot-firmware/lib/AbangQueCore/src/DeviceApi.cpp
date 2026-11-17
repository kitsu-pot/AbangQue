#include "DeviceApi.h"
#include <ArduinoJson.h>
#include <cstring>

namespace abangque {
bool buildRequest(const DeviceConfig& c, const Fix& fix, Availability status,
                  uint32_t now, int64_t utc, DeviceRequest& request) {
  request = {};
  if (!freshFix(fix, now, utc) || (status != Availability::Full && status != Availability::Available) || !c.jeepneyId ||
      !validIdentifier(c.jeepneyId, 64) || !c.deviceToken || !validToken(c.deviceToken) || !c.apiOrigin) return false;
  char timestamp[25];
  if (!formatUtc(fix.measuredAtMs, timestamp, sizeof(timestamp))) return false;
  JsonDocument doc;
  doc["jeepneyId"] = c.jeepneyId;
  doc["latitude"] = fix.latitude;
  doc["longitude"] = fix.longitude;
  doc["status"] = status == Availability::Full ? "FULL" : "AVAILABLE";
  doc["timestamp"] = timestamp;
  request.url = std::string(c.apiOrigin) + "/api/device-updates";
  request.authorization = std::string("Bearer ") + c.deviceToken;
  serializeJson(doc, request.body);
  return !doc.overflowed();
}
ReportResult classifyResponse(const HttpResponse& r, const std::string& jeepney) {
  // Authentication decisions do not depend on an intermediary returning valid JSON.
  if (r.status == 401) return ReportResult::AuthRejected;
  if (r.status == 403) return ReportResult::AssignmentRejected;
  if (r.status <= 0 || r.status == 408 || r.status == 429 || (r.status >= 500 && r.status <= 599))
    return ReportResult::TransientFailure;
  if (r.body.size() > 2048) return ReportResult::PermanentFailure;
  JsonDocument doc;
  if (deserializeJson(doc, r.body, DeserializationOption::NestingLimit(5))) return ReportResult::PermanentFailure;
  if (r.status == 409 && doc["error"].is<const char*>() &&
      std::strcmp(doc["error"], "DUPLICATE_UPDATE") == 0) return ReportResult::Duplicate;
  if (r.status != 201) return ReportResult::PermanentFailure;
  JsonVariantConst d = doc["data"];
  if (!d["id"].is<const char*>() || !d["jeepneyId"].is<const char*>() ||
      jeepney != d["jeepneyId"].as<std::string>() || !d["source"].is<const char*>() ||
      std::strcmp(d["source"], "device") || !d["isSimulated"].is<bool>() || d["isSimulated"].as<bool>() ||
      !d["receivedAt"].is<const char*>()) return ReportResult::PermanentFailure;
  const std::string id = d["id"].as<std::string>(), received = d["receivedAt"].as<std::string>();
  if (id.empty() || id.find_first_not_of("0123456789") != std::string::npos ||
      received.size() != 24 || received[4] != '-' || received[7] != '-' || received[10] != 'T' ||
      received[13] != ':' || received[16] != ':' || received[19] != '.' || received[23] != 'Z') return ReportResult::PermanentFailure;
  int values[7]{};
  const unsigned starts[] = {0, 5, 8, 11, 14, 17, 20};
  const unsigned lengths[] = {4, 2, 2, 2, 2, 2, 3};
  for (unsigned field = 0; field < 7; ++field) {
    for (unsigned i = starts[field]; i < starts[field] + lengths[field]; ++i) {
      if (received[i] < '0' || received[i] > '9') return ReportResult::PermanentFailure;
      values[field] = values[field] * 10 + received[i] - '0';
    }
  }
  if (!utcEpochMs(values[0], values[1], values[2], values[3], values[4], values[5], values[6]))
    return ReportResult::PermanentFailure;
  return ReportResult::Accepted;
}
}
