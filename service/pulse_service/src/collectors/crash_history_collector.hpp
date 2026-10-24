#pragma once

#include "pulse_wire.hpp"

#include <cstddef>
#include <cstdint>

namespace pulse {

/// Reads the crash events of the last days from the System and Application
/// logs (ADR-007: Event Log only) and groups them for the Crashes page
/// (doc 43). Read-only; safe to call from any thread.
class CrashHistoryCollector {
 public:
  static constexpr std::uint32_t kDefaultDays = 30;
  static constexpr std::uint32_t kMaxDays = 90;
  /// Events read per log at most, newest first; the reply says when older
  /// events were left out.
  static constexpr std::size_t kMaxEventsPerChannel = 5000;

  /// `days` 0 means kDefaultDays; more than kMaxDays is clamped.
  [[nodiscard]] ipc::CrashHistory Collect(std::uint32_t days) const;
};

}  // namespace pulse
