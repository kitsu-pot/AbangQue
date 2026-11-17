#pragma once
#include "Model.h"
#include <cstddef>

namespace abangque {
class GpsReader {
 public:
  virtual ~GpsReader() = default;
  virtual void feed(char byte, uint32_t nowMs) = 0;
  virtual Fix latest() const = 0;
  virtual void invalidate() = 0;
};

// Only checksum-verified RMC supplies a coherent position + UTC date/time.
// GGA-only / binary modules need a separate adapter after identification.
class NmeaGpsReader final : public GpsReader {
 public:
  void feed(char byte, uint32_t nowMs) override;
  Fix latest() const override { return fix_; }
  void invalidate() override { fix_.valid = false; length_ = 0; }
 private:
  void parse(uint32_t nowMs);
  char line_[160]{};
  size_t length_ = 0;
  int64_t newestTimestamp_ = 0;
  Fix fix_;
};
}
