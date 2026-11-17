#include <unity.h>
#include <ArduinoJson.h>
#include "DeviceApi.h"
#include "DriverInput.h"
#include "GpsReader.h"
#include "Reporter.h"
#include <cmath>
#include <cstring>
#include <cstdio>
#include <limits>

// Isolated synthetic fixtures. This executable has no Wi-Fi, serial or HTTP adapter.
using namespace abangque;
static const char* testToken = "12345678-1234-4234-8234-123456789abc.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
static const int64_t utc = utcEpochMs(2026, 11, 17, 12, 35, 19, 250);
DeviceConfig fixtureConfig() {
  DeviceConfig c;
  c.wifiSsid = "DEMO-UNIT-TEST";
  c.apiOrigin = "http://192.168.1.2:3000";
  c.allowDevelopmentHttp = true;
  c.deviceId = "TEST-DEVICE";
  c.jeepneyId = "TEST-JEEP";
  c.deviceToken = testToken;
  return c;
}
Fix fixtureFix() { return {48.1173, 11.5166666667, utc, 1000, true}; }
std::string nmea(const std::string& body) {
  unsigned sum = 0; for (char c : body) sum ^= static_cast<unsigned char>(c);
  char checksum[8]; std::snprintf(checksum, sizeof(checksum), "*%02X\r\n", sum);
  return "$" + body + checksum;
}
void feed(NmeaGpsReader& gps, const std::string& body, uint32_t now = 1000) {
  for (char c : nmea(body)) gps.feed(c, now);
}
const char* goodRmc = "GNRMC,123519.250,A,4807.038,N,01131.000,E,0.0,0.0,171126,,,A";
HttpResponse success() {
  return {201, R"({"data":{"id":"1","jeepneyId":"TEST-JEEP","source":"device","isSimulated":false,"receivedAt":"2026-11-17T12:35:19.250Z"}})", 0};
}
struct FakeClock : Clock {
  uint32_t ms = 1000; int64_t utcTime = utc;
  uint32_t monotonicMs() const override { return ms; }
  int64_t utcMs() const override { return utcTime; }
  void advance(uint32_t n) { ms += n; utcTime += n; }
};
struct FakeNetwork : NetworkTransport {
  bool online = true; unsigned calls = 0; HttpResponse response = success();
  DeviceRequest last; FakeClock* clock = nullptr; uint32_t duration = 0;
  void tick(uint32_t) override {}
  bool connected() const override { return online; }
  HttpResponse post(const DeviceRequest& r) override {
    ++calls; last = r; if (clock) clock->advance(duration); return response;
  }
};
void setUp() {}
void tearDown() {}

void gps_reads_coherent_rmc() {
  NmeaGpsReader gps; feed(gps, goodRmc);
  const auto f = gps.latest(); TEST_ASSERT_TRUE(f.valid);
  TEST_ASSERT_DOUBLE_WITHIN(0.000001, 48.1173, f.latitude);
  TEST_ASSERT_DOUBLE_WITHIN(0.000001, 11.5166666667, f.longitude);
  TEST_ASSERT_EQUAL_INT64(utc, f.measuredAtMs);
}
void gps_rejects_checksum_and_missing_fix() {
  NmeaGpsReader gps;
  feed(gps, "GPRMC,123519.250,V,4807.038,N,01131.000,E,0,0,171126,,,N");
  TEST_ASSERT_FALSE(gps.latest().valid);
  auto bad = nmea(goodRmc); bad[12] = '8'; for (char c : bad) gps.feed(c, 1000);
  TEST_ASSERT_FALSE(gps.latest().valid);
  feed(gps, goodRmc); TEST_ASSERT_TRUE(gps.latest().valid);
  feed(gps, "GNRMC,123520.250,V,,,,,,,171126,,,N"); TEST_ASSERT_FALSE(gps.latest().valid);
}
void gps_rejects_invalid_coordinate_formats() {
  for (const char* coordinate : {"9100.000", "4860.000", "4807oops", "NaN", "-4807.000", "9000.001", "4807."}) {
    NmeaGpsReader gps;
    feed(gps, std::string("GPRMC,123519,A,") + coordinate + ",N,01131.000,E,0,0,171126,,,A");
    TEST_ASSERT_FALSE(gps.latest().valid);
  }
  NmeaGpsReader gps;
  feed(gps, "GPRMC,123519,A,4807.038,Q,18100.000,E,0,0,171126,,,A");
  TEST_ASSERT_FALSE(gps.latest().valid);
}
void gps_negative_and_boundary_coordinates() {
  NmeaGpsReader gps; feed(gps, "GPRMC,123519,A,9000.000,S,18000.000,W,0,0,171126,,,D");
  TEST_ASSERT_TRUE(gps.latest().valid);
  TEST_ASSERT_EQUAL_DOUBLE(-90, gps.latest().latitude);
  TEST_ASSERT_EQUAL_DOUBLE(-180, gps.latest().longitude);
  TEST_ASSERT_FALSE(validCoordinates(std::numeric_limits<double>::quiet_NaN(), 0));
  TEST_ASSERT_FALSE(validCoordinates(0, std::numeric_limits<double>::infinity()));
}
void gps_rejects_simulated_estimated_or_manual_modes() {
  for (const char mode : {'S', 'E', 'M', 'N'}) {
    NmeaGpsReader gps;
    feed(gps, std::string("GPRMC,123519,A,4807.038,N,01131.000,E,0,0,171126,,,") + mode);
    TEST_ASSERT_FALSE(gps.latest().valid);
  }
}
void gps_accepts_m10_no_navigation_status_but_requires_valid_fix() {
  NmeaGpsReader gps;
  feed(gps, "GNRMC,123519,A,4807.038,N,01131.000,E,0,0,171126,,,A,V");
  TEST_ASSERT_TRUE(gps.latest().valid);
  feed(gps, "GNRMC,123520,V,4807.038,N,01131.000,E,0,0,171126,,,N,V");
  TEST_ASSERT_FALSE(gps.latest().valid);
}
void gps_does_not_refresh_repeated_timestamp() {
  NmeaGpsReader gps; feed(gps, goodRmc); feed(gps, goodRmc, 6500);
  TEST_ASSERT_TRUE(gps.latest().valid);
  TEST_ASSERT_EQUAL_UINT32(1000, gps.latest().receivedAtMs);
  TEST_ASSERT_FALSE(freshFix(gps.latest(), 6500, utc + 5500));
}
void gps_rejects_out_of_order_and_recovers() {
  NmeaGpsReader gps; feed(gps, goodRmc);
  feed(gps, "GPRMC,123518,A,4807.038,N,01131.000,E,0,0,171126,,,A");
  TEST_ASSERT_FALSE(gps.latest().valid);
  feed(gps, "GPRMC,123520,A,4807.038,N,01131.000,E,0,0,171126,,,A");
  TEST_ASSERT_TRUE(gps.latest().valid);
}
void gps_rejects_bad_dates_times_and_partial_sentences() {
  for (const char* time : {"246000", "123560", "123519.1234", "123519x", ""}) {
    NmeaGpsReader gps; feed(gps, std::string("GPRMC,") + time + ",A,4807.038,N,01131.000,E,0,0,171126,,,A");
    TEST_ASSERT_FALSE(gps.latest().valid);
  }
  NmeaGpsReader gps; feed(gps, "GPRMC,123519,A,4807.038,N,01131.000,E,0,0,300226,,,A");
  TEST_ASSERT_FALSE(gps.latest().valid);
  for (char c : std::string("$GPRMC,123519")) gps.feed(c, 0);
  TEST_ASSERT_FALSE(gps.latest().valid);
}
void gps_no_module_gga_only_or_overflow_means_no_fix() {
  NmeaGpsReader gps; TEST_ASSERT_FALSE(gps.latest().valid);
  feed(gps, "GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,");
  TEST_ASSERT_FALSE(gps.latest().valid);
  feed(gps, goodRmc); gps.feed('$', 1000);
  for (unsigned n = 0; n < 200; ++n) gps.feed('x', 1000);
  TEST_ASSERT_FALSE(gps.latest().valid);
}
void freshness_checks_measurement_reception_and_clock() {
  auto f = fixtureFix();
  TEST_ASSERT_TRUE(freshFix(f, 6000, utc + 5000));
  TEST_ASSERT_FALSE(freshFix(f, 6001, utc + 5001));
  f.receivedAtMs = 20000; // Old buffered data arriving now is still old.
  TEST_ASSERT_FALSE(freshFix(f, 20000, utc + 19000));
  TEST_ASSERT_FALSE(freshFix(f, 20000, 0));
  TEST_ASSERT_FALSE(freshFix(f, 20000, utc - 1001));
  TEST_ASSERT_TRUE(freshFix(f, 20000, utc - 1000));
}
void utc_is_validated_and_formatted_without_timezone_dependence() {
  char output[25]; TEST_ASSERT_TRUE(formatUtc(utc, output, sizeof(output)));
  TEST_ASSERT_EQUAL_STRING("2026-11-17T12:35:19.250Z", output);
  TEST_ASSERT_EQUAL_INT64(0, utcEpochMs(2026, 2, 29, 0, 0, 0, 0));
  TEST_ASSERT_NOT_EQUAL(0, utcEpochMs(2028, 2, 29, 0, 0, 0, 0));
  TEST_ASSERT_FALSE(formatUtc(utc, output, 24));
}
void latched_switch_boots_unknown_then_debounces() {
  DriverInput d(InputMode::LatchedContacts); TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  d.sample(false, true, 0); d.sample(false, true, 49); TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  TEST_ASSERT_TRUE(d.sample(false, true, 50)); TEST_ASSERT_EQUAL(Availability::Available, d.state());
  TEST_ASSERT_FALSE(d.sample(false, true, 51));
}
void latched_switch_bounce_open_and_conflict_inhibit_reporting() {
  DriverInput d(InputMode::LatchedContacts); d.sample(true, false, 0); d.sample(true, false, 50);
  d.sample(false, true, 60); d.sample(true, false, 70); d.sample(true, false, 119);
  TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  d.sample(true, false, 120); TEST_ASSERT_EQUAL(Availability::Full, d.state());
  d.sample(false, false, 130); TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  d.sample(true, true, 200); d.sample(true, true, 250); TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
}
void momentary_buttons_retain_manual_choice_offline_but_not_after_restart() {
  DriverInput d(InputMode::MomentaryButtons); d.sample(false, false, 0); d.sample(false, false, 50);
  TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  d.sample(true, false, 100); d.sample(true, false, 150); d.sample(false, false, 160); d.sample(false, false, 210);
  TEST_ASSERT_EQUAL(Availability::Full, d.state());
  d.sample(false, false, 100000); TEST_ASSERT_EQUAL(Availability::Full, d.state());
  DriverInput restarted(InputMode::MomentaryButtons); restarted.sample(false, false, 0); restarted.sample(false, false, 50);
  TEST_ASSERT_EQUAL(Availability::Unknown, restarted.state());
}
void momentary_conflict_requires_unambiguous_selection() {
  DriverInput d(InputMode::MomentaryButtons); d.sample(false, true, 0); d.sample(false, true, 50);
  d.sample(true, true, 60); TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  d.sample(true, true, 110); d.sample(false, false, 120); d.sample(false, false, 170);
  TEST_ASSERT_EQUAL(Availability::Unknown, d.state());
  d.sample(true, false, 200); d.sample(true, false, 250); TEST_ASSERT_EQUAL(Availability::Full, d.state());
}
void debounce_and_backoff_survive_millis_wrap() {
  DriverInput d(InputMode::LatchedContacts); d.sample(true, false, UINT32_MAX - 20); d.sample(true, false, 30);
  TEST_ASSERT_EQUAL(Availability::Full, d.state());
  ReportSchedule s(30000); s.completed(ReportResult::Accepted, UINT32_MAX - 10000);
  TEST_ASSERT_FALSE(s.due(19998)); TEST_ASSERT_TRUE(s.due(19999));
}
void request_matches_exact_device_contract() {
  DeviceRequest request; const auto c = fixtureConfig();
  TEST_ASSERT_TRUE(buildRequest(c, fixtureFix(), Availability::Full, 1000, utc, request));
  TEST_ASSERT_EQUAL_STRING("http://192.168.1.2:3000/api/device-updates", request.url.c_str());
  TEST_ASSERT_EQUAL_STRING("application/json", request.contentType);
  TEST_ASSERT_EQUAL_STRING((std::string("Bearer ") + testToken).c_str(), request.authorization.c_str());
  JsonDocument doc; TEST_ASSERT_FALSE(deserializeJson(doc, request.body));
  TEST_ASSERT_EQUAL(5, doc.size());
  TEST_ASSERT_EQUAL_STRING("TEST-JEEP", doc["jeepneyId"]);
  TEST_ASSERT_EQUAL_STRING("FULL", doc["status"]);
  TEST_ASSERT_EQUAL_STRING("2026-11-17T12:35:19.250Z", doc["timestamp"]);
  TEST_ASSERT_TRUE(doc["latitude"].is<double>());
  TEST_ASSERT_TRUE(doc["longitude"].is<double>());
  TEST_ASSERT_EQUAL(std::string::npos, request.body.find(testToken));
  TEST_ASSERT_EQUAL(std::string::npos, request.body.find("deviceId"));
}
void request_refuses_missing_unknown_stale_invalid_fix() {
  DeviceRequest r; auto c = fixtureConfig(); auto f = fixtureFix();
  TEST_ASSERT_FALSE(buildRequest(c, f, Availability::Unknown, 1000, utc, r));
  TEST_ASSERT_FALSE(buildRequest(c, f, static_cast<Availability>(99), 1000, utc, r));
  TEST_ASSERT_FALSE(buildRequest(c, f, Availability::Full, 7000, utc + 6000, r));
  f.valid = false; TEST_ASSERT_FALSE(buildRequest(c, f, Availability::Full, 1000, utc, r));
  f = fixtureFix(); f.latitude = 91; TEST_ASSERT_FALSE(buildRequest(c, f, Availability::Full, 1000, utc, r));
  TEST_ASSERT_TRUE(r.body.empty());
}
void device_identity_and_token_are_strict() {
  auto c = fixtureConfig(); TEST_ASSERT_TRUE(validConfig(c, false));
  TEST_ASSERT_FALSE(validToken("admin-session")); TEST_ASSERT_FALSE(validToken(std::string(testToken) + "\r\n"));
  c.deviceId = "bad id"; TEST_ASSERT_FALSE(validConfig(c, false));
  c = fixtureConfig(); c.jeepneyId = ""; TEST_ASSERT_FALSE(validConfig(c, false));
  c = fixtureConfig(); c.reportIntervalMs = 9999; TEST_ASSERT_FALSE(validConfig(c, false));
}
void configuration_has_no_implicit_secrets_or_default_reporting() {
  DeviceConfig c; TEST_ASSERT_FALSE(validConfig(c, false));
  TEST_ASSERT_EQUAL(-1, c.gpsRxPin); TEST_ASSERT_EQUAL(-1, c.fullPin); TEST_ASSERT_EQUAL(-1, c.statusLedPin);
}
void url_policy_rejects_cleartext_production_and_redirect_style_origins() {
  TEST_ASSERT_TRUE(validOrigin("https://api.example.test", false, true));
  TEST_ASSERT_TRUE(validOrigin("http://192.168.1.2:3000", true, false));
  TEST_ASSERT_FALSE(validOrigin("http://192.168.1.2:3000", true, true));
  TEST_ASSERT_FALSE(validOrigin("http://192.168.1.2:3000", false, false));
  for (const char* s : {"http://127.0.0.1:3000", "http://example.test", "http://8.8.8.8", "https://u:p@api.test", "https://api.test/path", "https://api.test/", "https://api.test?x=1", "https://api.test#x", "https://api.test:0", "https://api.test:65536", "https://api.test\r\nX:y"})
    TEST_ASSERT_FALSE(validOrigin(s, true, false));
  auto c = fixtureConfig(); c.apiOrigin = "https://api.example.test";
  TEST_ASSERT_FALSE(validConfig(c, true)); // HTTPS requires supplied trust root.
}
void response_requires_valid_device_provenance() {
  TEST_ASSERT_EQUAL(ReportResult::Accepted, classifyResponse(success(), "TEST-JEEP"));
  TEST_ASSERT_EQUAL(ReportResult::PermanentFailure, classifyResponse(success(), "WRONG-JEEP"));
  for (const char* body : {"{}", "not-json", R"({"data":{"source":"simulated","isSimulated":true}})"})
    TEST_ASSERT_EQUAL(ReportResult::PermanentFailure, classifyResponse({201, body, 0}, "TEST-JEEP"));
  TEST_ASSERT_EQUAL(ReportResult::PermanentFailure, classifyResponse({302, "{}", 0}, "TEST-JEEP"));
  auto invalidTime = success();
  invalidTime.body.replace(invalidTime.body.find("2026-11-17"), 10, "2026-02-30");
  TEST_ASSERT_EQUAL(ReportResult::PermanentFailure, classifyResponse(invalidTime, "TEST-JEEP"));
}
void errors_are_classified_for_retry_or_operator_action() {
  for (int code : {0, -1, 408, 429, 500, 503})
    TEST_ASSERT_EQUAL(ReportResult::TransientFailure, classifyResponse({code, "", 0}, "TEST-JEEP"));
  TEST_ASSERT_EQUAL(ReportResult::AuthRejected, classifyResponse({401, "", 0}, "TEST-JEEP"));
  TEST_ASSERT_EQUAL(ReportResult::AssignmentRejected, classifyResponse({403, "", 0}, "TEST-JEEP"));
  for (int code : {400, 404, 413, 415})
    TEST_ASSERT_EQUAL(ReportResult::PermanentFailure, classifyResponse({code, "{}", 0}, "TEST-JEEP"));
  TEST_ASSERT_EQUAL(ReportResult::Duplicate, classifyResponse({409, R"({"error":"DUPLICATE_UPDATE"})", 0}, "TEST-JEEP"));
  TEST_ASSERT_EQUAL(ReportResult::PermanentFailure, classifyResponse({409, R"({"error":"OTHER"})", 0}, "TEST-JEEP"));
}
void retry_backoff_is_bounded_and_resets_on_success() {
  Backoff backoff(30000, 300000);
  for (uint32_t expected : {30000,60000,120000,240000,300000,300000}) TEST_ASSERT_EQUAL_UINT32(expected, backoff.take());
  backoff.reset(); TEST_ASSERT_EQUAL_UINT32(30000, backoff.take());
  ReportSchedule s(30000); s.completed(ReportResult::TransientFailure, 1000, 90);
  TEST_ASSERT_FALSE(s.due(90999)); TEST_ASSERT_TRUE(s.due(91000));
  s.completed(ReportResult::Accepted, 91000); TEST_ASSERT_TRUE(s.due(121000));
}
void rejected_or_revoked_credentials_halt_all_future_requests() {
  for (int code : {401,403}) {
    auto c = fixtureConfig(); FakeNetwork n; FakeClock clock; n.response = {code, R"({"error":"UNAUTHORIZED"})", 0};
    Reporter reporter(c, n, clock); SensorSnapshot s{fixtureFix(), Availability::Full};
    TEST_ASSERT_TRUE(reporter.tick(s)); TEST_ASSERT_TRUE(reporter.halted());
    clock.advance(300000); s.fix = {48, 11, clock.utcTime, clock.ms, true};
    TEST_ASSERT_FALSE(reporter.tick(s)); TEST_ASSERT_EQUAL(1, n.calls);
  }
}
void restored_auth_lock_signal_blocks_reporter() {
  auto c = fixtureConfig(); FakeNetwork n; FakeClock clock; Reporter reporter(c, n, clock);
  reporter.block(); TEST_ASSERT_FALSE(reporter.tick({fixtureFix(), Availability::Full})); TEST_ASSERT_EQUAL(0, n.calls);
}
void no_gps_no_clock_unknown_switch_or_offline_never_sends() {
  auto c = fixtureConfig(); FakeNetwork n; FakeClock clock; Reporter reporter(c, n, clock);
  TEST_ASSERT_FALSE(reporter.tick({}));
  TEST_ASSERT_FALSE(reporter.tick({fixtureFix(), Availability::Unknown}));
  clock.utcTime = 0; TEST_ASSERT_FALSE(reporter.tick({fixtureFix(), Availability::Full}));
  clock.utcTime = utc; n.online = false; TEST_ASSERT_FALSE(reporter.tick({fixtureFix(), Availability::Full}));
  TEST_ASSERT_EQUAL(0, n.calls);
}
void timeout_does_not_replay_or_retimestamp_old_gps() {
  auto c = fixtureConfig(); FakeNetwork n; FakeClock clock;
  n.clock = &clock; n.duration = 8000; n.response = {};
  Reporter reporter(c, n, clock); SensorSnapshot s{fixtureFix(), Availability::Full};
  TEST_ASSERT_TRUE(reporter.tick(s)); TEST_ASSERT_EQUAL(9000, clock.ms);
  const auto firstBody = n.last.body;
  clock.advance(30000); TEST_ASSERT_FALSE(reporter.tick(s)); // Old fix not resent even though due.
  s.fix = {48, 11, clock.utcTime, clock.ms, true}; s.availability = Availability::Available;
  TEST_ASSERT_TRUE(reporter.tick(s)); TEST_ASSERT_EQUAL(2, n.calls);
  JsonDocument doc; deserializeJson(doc, n.last.body); TEST_ASSERT_EQUAL_STRING("AVAILABLE", doc["status"]);
  TEST_ASSERT_TRUE(firstBody != n.last.body);
}
void reconnect_uses_current_selection_and_new_fix_without_queue() {
  auto c = fixtureConfig(); FakeNetwork n; FakeClock clock; Reporter reporter(c, n, clock);
  n.online = false; SensorSnapshot s{fixtureFix(), Availability::Available};
  TEST_ASSERT_FALSE(reporter.tick(s)); clock.advance(60000);
  n.online = true; TEST_ASSERT_FALSE(reporter.tick(s));
  s.fix = {48, 11, clock.utcTime, clock.ms, true}; s.availability = Availability::Full;
  TEST_ASSERT_TRUE(reporter.tick(s)); TEST_ASSERT_EQUAL(1, n.calls);
  TEST_ASSERT_FALSE(reporter.tick(s));
}

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--contract-fixture") == 0) {
    DeviceRequest request;
    if (!buildRequest(fixtureConfig(), fixtureFix(), Availability::Full, 1000, utc, request)) return 1;
    JsonDocument fixture; fixture["body"] = serialized(request.body);
    fixture["authorization"] = request.authorization; fixture["contentType"] = request.contentType;
    std::string json; serializeJson(fixture, json); std::puts(json.c_str()); return 0;
  }
  UNITY_BEGIN();
  RUN_TEST(gps_reads_coherent_rmc);
  RUN_TEST(gps_rejects_checksum_and_missing_fix);
  RUN_TEST(gps_rejects_invalid_coordinate_formats);
  RUN_TEST(gps_negative_and_boundary_coordinates);
  RUN_TEST(gps_rejects_simulated_estimated_or_manual_modes);
  RUN_TEST(gps_accepts_m10_no_navigation_status_but_requires_valid_fix);
  RUN_TEST(gps_does_not_refresh_repeated_timestamp);
  RUN_TEST(gps_rejects_out_of_order_and_recovers);
  RUN_TEST(gps_rejects_bad_dates_times_and_partial_sentences);
  RUN_TEST(gps_no_module_gga_only_or_overflow_means_no_fix);
  RUN_TEST(freshness_checks_measurement_reception_and_clock);
  RUN_TEST(utc_is_validated_and_formatted_without_timezone_dependence);
  RUN_TEST(latched_switch_boots_unknown_then_debounces);
  RUN_TEST(latched_switch_bounce_open_and_conflict_inhibit_reporting);
  RUN_TEST(momentary_buttons_retain_manual_choice_offline_but_not_after_restart);
  RUN_TEST(momentary_conflict_requires_unambiguous_selection);
  RUN_TEST(debounce_and_backoff_survive_millis_wrap);
  RUN_TEST(request_matches_exact_device_contract);
  RUN_TEST(request_refuses_missing_unknown_stale_invalid_fix);
  RUN_TEST(device_identity_and_token_are_strict);
  RUN_TEST(configuration_has_no_implicit_secrets_or_default_reporting);
  RUN_TEST(url_policy_rejects_cleartext_production_and_redirect_style_origins);
  RUN_TEST(response_requires_valid_device_provenance);
  RUN_TEST(errors_are_classified_for_retry_or_operator_action);
  RUN_TEST(retry_backoff_is_bounded_and_resets_on_success);
  RUN_TEST(rejected_or_revoked_credentials_halt_all_future_requests);
  RUN_TEST(restored_auth_lock_signal_blocks_reporter);
  RUN_TEST(no_gps_no_clock_unknown_switch_or_offline_never_sends);
  RUN_TEST(timeout_does_not_replay_or_retimestamp_old_gps);
  RUN_TEST(reconnect_uses_current_selection_and_new_fix_without_queue);
  return UNITY_END();
}
