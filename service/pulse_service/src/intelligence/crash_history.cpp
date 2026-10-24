#include "intelligence/crash_history.hpp"

#include "intelligence/app_crash_explainer.hpp"
#include "intelligence/bugcheck_catalog.hpp"
#include "intelligence/event_intelligence.hpp"
#include "intelligence/exception_catalog.hpp"

#include <algorithm>
#include <map>
#include <numeric>
#include <unordered_map>

namespace pulse {
namespace {

constexpr std::string_view kNoCode = "-";

std::string AsciiLower(std::string_view text) {
  std::string out(text);
  for (char& c : out) {
    if (c >= 'A' && c <= 'Z') {
      c = static_cast<char>(c - 'A' + 'a');
    }
  }
  return out;
}

std::string CodeKey(const std::optional<std::uint32_t>& code) {
  return code ? FormatExceptionCode(*code) : std::string(kNoCode);
}

/// "DPC_WATCHDOG_VIOLATION", or "0x00000133" for codes outside the catalog.
std::string StopCodeName(const std::optional<std::uint32_t>& code) {
  if (!code) {
    return "";
  }
  if (const BugcheckInfo* info = FindBugcheck(*code)) {
    return std::string(info->name);
  }
  return FormatBugcheckCode(*code);
}

void SetBlueScreen(const std::optional<std::uint32_t>& code,
                   CrashRecord* record) {
  record->kind = ipc::CrashKind::BlueScreen;
  record->code = code;
  record->subject = StopCodeName(code);
  record->key = "bsod|" + CodeKey(code);
}

ipc::FaultingModuleOrigin ToWire(FaultingModuleOrigin origin) {
  switch (origin) {
    case FaultingModuleOrigin::App:
      return ipc::FaultingModuleOrigin::App;
    case FaultingModuleOrigin::Windows:
      return ipc::FaultingModuleOrigin::Windows;
    case FaultingModuleOrigin::Driver:
      return ipc::FaultingModuleOrigin::Driver;
    case FaultingModuleOrigin::Other:
      return ipc::FaultingModuleOrigin::Other;
    case FaultingModuleOrigin::Unknown:
      break;
  }
  return ipc::FaultingModuleOrigin::Unknown;
}

}  // namespace

std::optional<CrashRecord> ToCrashRecord(const ipc::TimelineEvent& event) {
  CrashRecord record;
  record.source = ClassifyCrashEvent(event.provider_name, event.win_event_id);
  record.timestamp_unix_ms = event.timestamp_unix_ms;
  record.channel = event.channel;
  record.record_id = event.record_id;

  switch (record.source) {
    case CrashEventType::ApplicationError: {
      const auto fault = ParseApplicationFault(event.raw_xml);
      if (!fault) {
        return std::nullopt;
      }
      record.kind = ipc::CrashKind::AppCrash;
      record.subject = fault->app_name;
      record.version = fault->app_version;
      record.module_name = fault->module_name;
      record.module_path = fault->module_path;
      record.code = fault->exception_code;
      record.key = "app|" + AsciiLower(fault->app_name) + "|" +
                   AsciiLower(fault->module_name) + "|" +
                   CodeKey(fault->exception_code);
      return record;
    }
    case CrashEventType::ApplicationHang: {
      const auto hang = ParseApplicationHang(event.raw_xml);
      if (!hang) {
        return std::nullopt;
      }
      record.kind = ipc::CrashKind::AppHang;
      record.subject = hang->app_name;
      record.version = hang->app_version;
      record.key = "hang|" + AsciiLower(hang->app_name);
      return record;
    }
    case CrashEventType::Bugcheck:
      SetBlueScreen(ReadBugcheckStopCode(event), &record);
      return record;
    case CrashEventType::UnexpectedRestart: {
      const auto restart = ReadUnexpectedRestart(event.raw_xml);
      if (restart && restart->stop_code) {
        SetBlueScreen(restart->stop_code, &record);
        return record;
      }
      record.kind = ipc::CrashKind::UnexpectedRestart;
      record.key = !restart                    ? "restart|unknown"
                   : restart->power_button_held ? "restart|power_button"
                                                : "restart|power_loss";
      return record;
    }
    case CrashEventType::DisplayDriverReset: {
      // "Display driver %1 stopped responding and has successfully
      // recovered." The driver name is the only (unnamed) value.
      const auto data = ReadEventData(event.raw_xml);
      record.kind = ipc::CrashKind::GpuReset;
      record.subject = data.empty() ? std::string() : data.front().value;
      record.key = "gpu|" + AsciiLower(record.subject);
      return record;
    }
    case CrashEventType::ServiceCrash: {
      const auto data = ReadEventData(event.raw_xml);
      record.kind = ipc::CrashKind::ServiceCrash;
      record.subject = FindEventDataField(data, "param1", 0).value_or("");
      record.key = "service|" + AsciiLower(record.subject);
      return record;
    }
    case CrashEventType::HardwareError:
      // Corrected errors (Warning) are not crashes.
      if (event.severity != ipc::Severity::Error &&
          event.severity != ipc::Severity::Critical) {
        return std::nullopt;
      }
      record.kind = ipc::CrashKind::HardwareError;
      record.key = "whea|" + std::to_string(event.win_event_id);
      return record;
    case CrashEventType::None:
      break;
  }
  return std::nullopt;
}

void DropDuplicateBlueScreens(std::vector<CrashRecord>* records) {
  std::vector<const CrashRecord*> bugchecks;
  for (const auto& record : *records) {
    if (record.source == CrashEventType::Bugcheck) {
      bugchecks.push_back(&record);
    }
  }
  std::vector<bool> drop(records->size(), false);
  for (std::size_t i = 0; i < records->size(); ++i) {
    const CrashRecord& record = (*records)[i];
    if (record.source != CrashEventType::UnexpectedRestart ||
        record.kind != ipc::CrashKind::BlueScreen) {
      continue;
    }
    drop[i] = std::any_of(
        bugchecks.begin(), bugchecks.end(), [&](const CrashRecord* bugcheck) {
          const std::int64_t apart =
              bugcheck->timestamp_unix_ms - record.timestamp_unix_ms;
          return bugcheck->code == record.code &&
                 apart <= kSameBlueScreenWindowMs &&
                 apart >= -kSameBlueScreenWindowMs;
        });
  }
  std::vector<CrashRecord> kept;
  kept.reserve(records->size());
  for (std::size_t i = 0; i < records->size(); ++i) {
    if (!drop[i]) {
      kept.push_back(std::move((*records)[i]));
    }
  }
  *records = std::move(kept);
}

std::vector<ipc::CrashGroup> GroupCrashRecords(
    const std::vector<CrashRecord>& records) {
  // Newest first, so each group's first record is its newest.
  std::vector<std::size_t> order(records.size());
  std::iota(order.begin(), order.end(), std::size_t{0});
  std::stable_sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
    return records[a].timestamp_unix_ms > records[b].timestamp_unix_ms;
  });

  std::vector<ipc::CrashGroup> groups;
  std::vector<std::map<std::string, ipc::CrashVersion>> versions;
  std::unordered_map<std::string, std::size_t> group_index;
  for (const std::size_t i : order) {
    const CrashRecord& record = records[i];
    const auto [found, inserted] =
        group_index.try_emplace(record.key, groups.size());
    if (inserted) {
      ipc::CrashGroup group;
      group.kind = record.kind;
      group.key = record.key;
      group.subject = record.subject;
      group.module_name = record.module_name;
      group.module_path = record.module_path;
      group.has_code = record.code.has_value();
      group.code = record.code.value_or(0);
      group.first_unix_ms = record.timestamp_unix_ms;
      group.last_unix_ms = record.timestamp_unix_ms;
      groups.push_back(std::move(group));
      versions.emplace_back();
    }
    ipc::CrashGroup& group = groups[found->second];
    ++group.count;
    group.first_unix_ms = std::min(group.first_unix_ms, record.timestamp_unix_ms);
    group.last_unix_ms = std::max(group.last_unix_ms, record.timestamp_unix_ms);
    if (group.occurrence_unix_ms.size() < kMaxCrashTimestampsPerGroup) {
      group.occurrence_unix_ms.push_back(record.timestamp_unix_ms);
    }
    if (group.recent.size() < kMaxRecentCrashesPerGroup) {
      group.recent.push_back(ipc::CrashOccurrence{
          record.timestamp_unix_ms, record.channel, record.record_id,
          record.version});
    }
    if (!record.version.empty()) {
      ipc::CrashVersion& version = versions[found->second][record.version];
      version.version = record.version;
      ++version.count;
      version.last_unix_ms =
          std::max(version.last_unix_ms, record.timestamp_unix_ms);
    }
  }

  for (std::size_t i = 0; i < groups.size(); ++i) {
    for (auto& entry : versions[i]) {
      groups[i].versions.push_back(std::move(entry.second));
    }
    std::sort(groups[i].versions.begin(), groups[i].versions.end(),
              [](const ipc::CrashVersion& a, const ipc::CrashVersion& b) {
                if (a.count != b.count) {
                  return a.count > b.count;
                }
                return a.last_unix_ms > b.last_unix_ms;
              });
  }
  // Groups were created newest first; keep that order.
  if (groups.size() > kMaxCrashGroups) {
    groups.resize(kMaxCrashGroups);
  }
  return groups;
}

void ExplainCrashGroup(const ipc::TimelineEvent& newest,
                       std::string_view module_company,
                       ipc::CrashGroup* group) {
  EventInsight insight;
  const auto fault = group->kind == ipc::CrashKind::AppCrash
                         ? ParseApplicationFault(newest.raw_xml)
                         : std::nullopt;
  if (fault) {
    group->module_company = std::string(module_company);
    group->module_origin =
        ToWire(ClassifyFaultingModule(*fault, module_company));
    insight = ExplainApplicationFault(*fault, module_company);
  } else {
    insight = EventIntelligence().Analyze(newest);
  }
  group->title = std::move(insight.title);
  group->summary = std::move(insight.summary);
  group->recommendation = std::move(insight.recommendation);
}

}  // namespace pulse
