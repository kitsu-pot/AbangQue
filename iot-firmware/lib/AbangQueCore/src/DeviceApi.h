#pragma once
#include "DeviceConfig.h"
#include <string>

namespace abangque {
struct DeviceRequest {
  std::string url, authorization, body;
  const char* contentType = "application/json";
};
struct HttpResponse {
  int status = 0; // 0 = DNS/socket/TLS/timeout/transport failure; never an HTTP acceptance.
  std::string body;
  uint32_t retryAfterSeconds = 0;
};
enum class ReportResult { Accepted, Duplicate, TransientFailure, AuthRejected, AssignmentRejected, PermanentFailure };
bool buildRequest(const DeviceConfig& config, const Fix& fix, Availability availability,
                  uint32_t nowMs, int64_t utcMs, DeviceRequest& request);
ReportResult classifyResponse(const HttpResponse& response, const std::string& jeepneyId);
}
