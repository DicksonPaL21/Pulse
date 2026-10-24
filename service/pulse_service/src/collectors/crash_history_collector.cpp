#include "collectors/crash_history_collector.hpp"

#include "collectors/event_log_collector.hpp"
#include "intelligence/app_crash_explainer.hpp"
#include "intelligence/crash_history.hpp"
#include "ipc/event_mapper.hpp"
#include "logging/logger.hpp"
#include "windows/file_version_info.hpp"
#include "windows/wevt_helpers.hpp"

#include <algorithm>
#include <cctype>
#include <cwctype>
#include <chrono>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace pulse {
namespace {

constexpr std::int64_t kMillisecondsPerDay = 24LL * 60 * 60 * 1000;
constexpr DWORD kQueryBatchSize = 64;

/// Crash events of the System log in the last `window_ms`; timediff() counts
/// back from now. Provider names checked with Get-WinEvent -ListProvider.
std::wstring SystemLogQuery(std::int64_t window_ms) {
  return L"*[System[TimeCreated[timediff(@SystemTime) <= " +
         std::to_wstring(window_ms) +
         L"] and ("
         L"(Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=41) or "
         L"(Provider[@Name='Microsoft-Windows-WER-SystemErrorReporting'] and "
         L"EventID=1001) or "
         L"(Provider[@Name='Display'] and EventID=4101) or "
         L"(Provider[@Name='Service Control Manager'] and "
         L"(EventID=7031 or EventID=7034)) or "
         L"(Provider[@Name='Microsoft-Windows-WHEA-Logger'] and "
         L"(Level=1 or Level=2)))]]";
}

/// App crashes and hangs of the Application log in the last `window_ms`.
std::wstring ApplicationLogQuery(std::int64_t window_ms) {
  return L"*[System[TimeCreated[timediff(@SystemTime) <= " +
         std::to_wstring(window_ms) +
         L"] and ("
         L"(Provider[@Name='Application Error'] and EventID=1000) or "
         L"(Provider[@Name='Application Hang'] and EventID=1002))]]";
}

/// The fields grouping and explaining need; no message formatting.
ipc::TimelineEvent ToCrashEvent(const EventRecord& record) {
  ipc::TimelineEvent out;
  out.timestamp_unix_ms = record.timestamp_unix_ms.value_or(0);
  out.severity = ToIpcSeverity(record.level);
  out.channel = record.channel;
  out.provider_name = record.provider_name;
  out.win_event_id = record.event_id.value_or(0);
  out.record_id = record.record_id.value_or(0);
  out.raw_xml = record.raw_xml;
  return out;
}

/// Running totals of one Collect call.
struct CrashScan {
  std::vector<CrashRecord> records;
  /// Newest event of each group key, with its XML, to explain the group.
  std::unordered_map<std::string, ipc::TimelineEvent> newest_by_key;
  std::size_t scanned = 0;
  bool truncated = false;
};

/// Reads one log, newest first. False when the log cannot be queried.
bool ScanChannel(const std::wstring& channel, const std::wstring& query,
                 CrashScan* scan) {
  EVT_HANDLE raw = EvtQuery(nullptr, channel.c_str(), query.c_str(),
                            EvtQueryChannelPath | EvtQueryReverseDirection);
  if (raw == nullptr) {
    Logger::Instance().Warn(
        "CrashHistory", "EvtQuery failed for " + wevt::WideToUtf8(channel) +
                            ": " + wevt::FormatWin32Error(GetLastError()));
    return false;
  }
  wevt::EvtHandle query_handle{raw};
  DWORD error = ERROR_SUCCESS;
  wevt::EvtHandle context = wevt::CreateSystemRenderContext(&error);
  if (!context) {
    Logger::Instance().Warn("CrashHistory",
                            "EvtCreateRenderContext failed: " +
                                wevt::FormatWin32Error(error));
    return false;
  }

  const std::string channel_name = wevt::WideToUtf8(channel);
  std::size_t read = 0;
  while (!scan->truncated) {
    error = ERROR_SUCCESS;
    std::vector<wevt::EvtHandle> batch =
        wevt::NextEvents(query_handle.get(), kQueryBatchSize, &error);
    if (batch.empty()) {
      if (error != ERROR_SUCCESS && error != ERROR_NO_MORE_ITEMS) {
        Logger::Instance().Warn("CrashHistory",
                                "EvtNext ended early for " + channel_name +
                                    ": " + wevt::FormatWin32Error(error));
      }
      break;
    }
    for (wevt::EvtHandle& handle : batch) {
      if (read >= CrashHistoryCollector::kMaxEventsPerChannel) {
        scan->truncated = true;
        break;
      }
      ++read;
      auto parsed = EventLogCollector::ParseEvtHandle(
          handle.get(), context.get(), /*format_message=*/false);
      if (!parsed) {
        continue;
      }
      if (parsed->raw_xml.empty()) {
        parsed->raw_xml = wevt::RenderEventXml(handle.get());
      }
      if (parsed->channel.empty()) {
        parsed->channel = channel_name;
      }
      ipc::TimelineEvent event = ToCrashEvent(*parsed);
      auto record = ToCrashRecord(event);
      if (!record) {
        continue;
      }
      // Newest first, so the first event of a key is its newest.
      scan->newest_by_key.try_emplace(record->key, std::move(event));
      scan->records.push_back(std::move(*record));
    }
  }
  scan->scanned += read;
  return true;
}

/// "C:\..." on a fixed local drive. Version resources of other paths are not
/// read: a network path would make Pulse reach out over the network.
bool IsLocalFixedDrivePath(const std::wstring& path) {
  if (path.size() < 4 || !std::iswalpha(path[0]) || path[1] != L':' ||
      path[2] != L'\\') {
    return false;
  }
  const std::wstring root = path.substr(0, 3);
  return GetDriveTypeW(root.c_str()) == DRIVE_FIXED;
}

/// CompanyName of the module's version resource; empty when unknown.
std::string ModuleCompany(
    const std::string& module_path,
    std::unordered_map<std::string, std::string>* company_by_path) {
  if (IsUnknownModule(module_path)) {
    return {};
  }
  const auto [entry, inserted] = company_by_path->try_emplace(module_path);
  if (inserted) {
    const std::wstring wide = wevt::Utf8ToWide(module_path);
    if (IsLocalFixedDrivePath(wide)) {
      entry->second = QueryFileVersionString(wide, L"CompanyName");
    }
  }
  return entry->second;
}

std::int64_t NowUnixMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

}  // namespace

ipc::CrashHistory CrashHistoryCollector::Collect(std::uint32_t days) const {
  const auto started = std::chrono::steady_clock::now();
  ipc::CrashHistory out;
  out.days = days == 0 ? kDefaultDays : std::min(days, kMaxDays);
  const std::int64_t window_ms =
      static_cast<std::int64_t>(out.days) * kMillisecondsPerDay;

  CrashScan scan;
  const std::pair<std::wstring, std::wstring> logs[] = {
      {L"System", SystemLogQuery(window_ms)},
      {L"Application", ApplicationLogQuery(window_ms)},
  };
  for (const auto& [channel, query] : logs) {
    if (!ScanChannel(channel, query, &scan)) {
      out.unreadable_channels.push_back(wevt::WideToUtf8(channel));
    }
  }

  DropDuplicateBlueScreens(&scan.records);
  out.groups = GroupCrashRecords(scan.records);
  std::unordered_map<std::string, std::string> company_by_path;
  for (ipc::CrashGroup& group : out.groups) {
    const auto newest = scan.newest_by_key.find(group.key);
    if (newest == scan.newest_by_key.end()) {
      continue;
    }
    const std::string company =
        group.kind == ipc::CrashKind::AppCrash
            ? ModuleCompany(group.module_path, &company_by_path)
            : std::string();
    ExplainCrashGroup(newest->second, company, &group);
  }

  out.scanned_events = static_cast<std::uint32_t>(scan.scanned);
  out.truncated = scan.truncated;
  out.collected_unix_ms = NowUnixMs();
  const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::steady_clock::now() - started)
                              .count();
  Logger::Instance().Info(
      "CrashHistory",
      "days=" + std::to_string(out.days) +
          " scanned=" + std::to_string(out.scanned_events) +
          " crashes=" + std::to_string(scan.records.size()) +
          " groups=" + std::to_string(out.groups.size()) +
          " truncated=" + (out.truncated ? "true" : "false") +
          " ms=" + std::to_string(elapsed_ms));
  return out;
}

}  // namespace pulse
