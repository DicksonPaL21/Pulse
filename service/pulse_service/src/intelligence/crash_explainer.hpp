#pragma once

#include "intelligence/event_intelligence.hpp"
#include "pulse_wire.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace pulse {

/// Explains crashes in plain language, using the event's own data:
///
///  - Kernel-Power 41: BugcheckCode / PowerButtonTimestamp / SleepInProgress
///    tell a blue screen, a forced power-off and a power loss apart
///    (learn.microsoft.com/troubleshoot/windows-client/performance/event-id-41-restart).
///  - WER-SystemErrorReporting 1001 ("BugCheck"): the stop code and dump path.
///  - WHEA-Logger: fatal (Error / Critical level) vs corrected (Warning).
///  - Application Error 1000 / Application Hang 1002: the app, the exception
///    and the file it crashed in (see app_crash_explainer).
///  - Service Control Manager 7031 / 7034: the service that stopped.
///
/// Needs TimelineEvent::raw_xml for all but WHEA; the collector renders it
/// for every event where IsCrashDiagnosticEvent() is true. Returns nullopt
/// when the event data is missing, so the generic catalog rule still applies.
[[nodiscard]] std::optional<EventInsight> ExplainCrashEvent(
    const ipc::TimelineEvent& event);

/// True for events whose explanation needs their EventData (raw XML).
[[nodiscard]] bool IsCrashDiagnosticEvent(std::string_view provider_name,
                                          std::uint32_t win_event_id);

/// The crash events Pulse explains and collects, by provider and event ID.
enum class CrashEventType : std::uint8_t {
  None,
  UnexpectedRestart,   // Kernel-Power 41
  Bugcheck,            // WER-SystemErrorReporting 1001
  HardwareError,       // WHEA-Logger, any event ID
  ApplicationError,    // Application Error 1000
  ApplicationHang,     // Application Hang 1002
  ServiceCrash,        // Service Control Manager 7031 / 7034
  DisplayDriverReset,  // Display 4101
};

[[nodiscard]] CrashEventType ClassifyCrashEvent(std::string_view provider_name,
                                                std::uint32_t win_event_id);

/// What a Kernel-Power 41 event says about the restart.
struct UnexpectedRestart {
  /// Set when Windows stopped with a blue screen.
  std::optional<std::uint32_t> stop_code;
  bool power_button_held = false;
  bool during_sleep = false;
};

/// nullopt when the event has no data (no BugcheckCode field).
[[nodiscard]] std::optional<UnexpectedRestart> ReadUnexpectedRestart(
    std::string_view event_xml);

/// Stop code of a BugCheck 1001 event, from its data or else its message.
[[nodiscard]] std::optional<std::uint32_t> ReadBugcheckStopCode(
    const ipc::TimelineEvent& event);

/// Value of <Data Name='name'> in event XML; nullopt when absent.
[[nodiscard]] std::optional<std::string> FindEventDataValue(
    std::string_view event_xml, std::string_view name);

/// One <Data> element of an event's EventData.
struct EventDataItem {
  std::string name;  // Empty for unnamed data.
  std::string value;
};

/// Every <Data> element of the event XML in document order, entities decoded.
[[nodiscard]] std::vector<EventDataItem> ReadEventData(
    std::string_view event_xml);

/// The field called `name`; when the event has no field names at all (older
/// Windows builds of classic providers), the field at `position` instead.
[[nodiscard]] std::optional<std::string> FindEventDataField(
    const std::vector<EventDataItem>& data, std::string_view name,
    std::size_t position);

/// Unsigned number in `base`, ignoring surrounding spaces and a "0x" prefix
/// for base 16; nullopt when the text is not a number.
[[nodiscard]] std::optional<std::uint64_t> ParseEventDataNumber(
    std::string_view text, int base);

}  // namespace pulse
