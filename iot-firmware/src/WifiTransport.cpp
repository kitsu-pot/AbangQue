#include "WifiTransport.h"
#include <cstring>
#include <strings.h>
#include <algorithm>

namespace {
struct ResponseBuffer {
  abangque::HttpResponse response;
};
}
void WifiTransport::begin() {
  WiFi.persistent(false); // Wi-Fi credentials stay in this private build, not extra Wi-Fi NVS copies.
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(false);
}
void WifiTransport::tick(uint32_t now) {
  if (connected()) {
    wasConnected_ = true; connecting_ = false; waiting_ = false; reconnect_.reset(); return;
  }
  if (wasConnected_) { wasConnected_ = false; connecting_ = false; waiting_ = false; }
  if (connecting_) {
    if (static_cast<uint32_t>(now - startedAt_) < 15000) return;
    WiFi.disconnect(); connecting_ = false; waiting_ = true;
    startedAt_ = now; delay_ = reconnect_.take();
  }
  if (waiting_ && static_cast<uint32_t>(now - startedAt_) < delay_) return;
  WiFi.begin(config_.wifiSsid, config_.wifiPassword);
  connecting_ = true; waiting_ = false; startedAt_ = now;
}
esp_err_t WifiTransport::event(esp_http_client_event_t* e) {
  auto& buffer = *static_cast<ResponseBuffer*>(e->user_data);
  if (e->event_id == HTTP_EVENT_ON_HEADER && e->header_key && e->header_value &&
      strcasecmp(e->header_key, "Retry-After") == 0) {
    uint32_t seconds = 0;
    bool valid = *e->header_value != 0;
    for (const char* p = e->header_value; *p; ++p) {
      if (*p < '0' || *p > '9') { valid = false; break; }
      seconds = std::min(uint32_t{3600}, seconds * 10 + *p - '0');
    }
    if (valid) buffer.response.retryAfterSeconds = seconds;
  }
  return ESP_OK;
}
abangque::HttpResponse WifiTransport::post(const abangque::DeviceRequest& request) {
  ResponseBuffer buffer;
  const uint32_t startedAt = millis();
  const auto withinBudget = [&]() { return static_cast<uint32_t>(millis() - startedAt) < 15000; };
  esp_http_client_config_t options{};
  options.url = request.url.c_str();
  options.cert_pem = *config_.rootCaPem ? config_.rootCaPem : nullptr;
  options.skip_cert_common_name_check = false;
  options.timeout_ms = 8000;
  options.disable_auto_redirect = true;
  options.event_handler = event;
  options.user_data = &buffer;
  options.buffer_size = 1024;
  options.buffer_size_tx = 1024;
  const auto client = esp_http_client_init(&options);
  if (!client) return {};
  bool ok = esp_http_client_set_method(client, HTTP_METHOD_POST) == ESP_OK &&
    esp_http_client_set_header(client, "Content-Type", request.contentType) == ESP_OK &&
    esp_http_client_set_header(client, "Authorization", request.authorization.c_str()) == ESP_OK &&
    esp_http_client_set_header(client, "Accept", "application/json") == ESP_OK;
  // Stream explicitly: bound body memory and check elapsed time BETWEEN blocking
  // SDK calls. Each socket operation has an 8 s timeout; this is not a hard 15 s
  // wall-clock guarantee (DNS/TLS/header processing may take longer).
  if (ok) ok = esp_http_client_open(client, request.body.size()) == ESP_OK;
  size_t written = 0;
  while (ok && written < request.body.size() && withinBudget()) {
    const int n = esp_http_client_write(client, request.body.data() + written, request.body.size() - written);
    if (n <= 0) ok = false;
    else written += n;
  }
  ok = ok && written == request.body.size() && withinBudget();
  if (ok) ok = esp_http_client_fetch_headers(client) >= 0;
  const int status = esp_http_client_get_status_code(client);
  bool oversized = false;
  if (ok) {
    const auto length = esp_http_client_get_content_length(client);
    if (length > 2048) { ok = false; oversized = true; }
  }
  char chunk[256];
  // Always drain esp_http_client_read: fetch_headers can already cache a complete
  // small JSON body, even when is_complete_data_received is true at this point.
  while (ok && withinBudget()) {
    const int n = esp_http_client_read(client, chunk, sizeof(chunk));
    if (n < 0) { ok = false; break; }
    if (n == 0) break;
    if (buffer.response.body.size() + n > 2048) { ok = false; oversized = true; break; }
    buffer.response.body.append(chunk, n);
  }
  ok = ok && withinBudget() && esp_http_client_is_complete_data_received(client);
  // Retain explicit auth rejection even if its body was truncated by a proxy.
  if (oversized) buffer.response.body.clear(); // Never accept a truncated success body.
  if (status == 401 || status == 403 || ok || oversized) buffer.response.status = status;
  esp_http_client_close(client);
  esp_http_client_cleanup(client);
  return buffer.response;
}
