#pragma once

#include "intelligence/crash_explainer.hpp"
#include "pulse_wire.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace pulse {

/// Most groups one CrashHistory reply carries (newest first).
inline constexpr std::size_t kMaxCrashGroups = 150;
/// Most timestamps per group, for the daily chart.
inline constexpr std::size_t kMaxCrashTimestampsPerGroup = 1000;
/// Most events per group the details list can open.
inline constexpr std::size_t kMaxRecentCrashesPerGroup = 10;
/// A Kernel-Power 41 and a BugCheck 1001 with the same stop code this close
/// together describe one blue screen (both are written during the next boot).
inline constexpr std::int64_t kSameBlueScreenWindowMs = 10 * 60 * 1000;

/// A crash event reduced to what groups it.
struct CrashRecord {
  ipc::CrashKind kind = ipc::CrashKind::Unspecified;
  /// Same key = same group: app + module + exception code, stop code, etc.
  std::string key;
  /// App image, service, display driver or stop code name.
  std::string subject;
  /// App version (app crashes and hangs).
  std::string version;
  std::string module_name;
  std::string module_path;
  std::optional<std::uint32_t> code;
  std::int64_t timestamp_unix_ms = 0;
  std::string channel;
  std::uint64_t record_id = 0;
  /// The event it came from; a blue screen can come from two.
  CrashEventType source = CrashEventType::None;
};

/// Reads a crash event (needs raw_xml); nullopt for events that are not
/// crashes, such as a corrected hardware error, or that lack the data to
/// group them.
[[nodiscard]] std::optional<CrashRecord> ToCrashRecord(
    const ipc::TimelineEvent& event);

/// Drops each Kernel-Power 41 that has a BugCheck 1001 with the same stop
/// code within kSameBlueScreenWindowMs: both describe one blue screen.
void DropDuplicateBlueScreens(std::vector<CrashRecord>* records);

/// Groups records by key. Groups are ordered by their newest event and
/// capped at kMaxCrashGroups; explanation fields stay empty (see
/// ExplainCrashGroup).
[[nodiscard]] std::vector<ipc::CrashGroup> GroupCrashRecords(
    const std::vector<CrashRecord>& records);

/// Fills title, summary and recommendation from the group's newest event and,
/// for app crashes, the faulting module's origin. `module_company` is the
/// CompanyName of the module's version resource, or empty when unknown.
void ExplainCrashGroup(const ipc::TimelineEvent& newest,
                       std::string_view module_company,
                       ipc::CrashGroup* group);

}  // namespace pulse
