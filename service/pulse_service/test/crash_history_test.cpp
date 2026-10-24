#include "intelligence/crash_history.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

// CI builds Release, where assert() is compiled out; fail loudly instead.
#define CHECK(condition)                                                  \
  do {                                                                    \
    if (!(condition)) {                                                   \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: "       \
                << #condition << "\n";                                    \
      std::exit(1);                                                       \
    }                                                                     \
  } while (false)

namespace {

using namespace pulse;

constexpr std::int64_t kMinute = 60 * 1000;
constexpr std::int64_t kStart = 1760000000000;

ipc::TimelineEvent Event(const std::string& provider, std::uint32_t id,
                         const std::string& xml, std::int64_t unix_ms,
                         ipc::Severity severity = ipc::Severity::Error) {
  static std::uint64_t next_record_id = 1;
  ipc::TimelineEvent e;
  e.provider_name = provider;
  e.win_event_id = id;
  e.raw_xml = xml;
  e.timestamp_unix_ms = unix_ms;
  e.severity = severity;
  e.channel = id == 1000 || id == 1002 ? "Application" : "System";
  e.record_id = next_record_id++;
  return e;
}

std::string AppErrorXml(const std::string& app, const std::string& version,
                        const std::string& module, const std::string& module_path,
                        const std::string& code) {
  return "<EventData><Data Name='AppName'>" + app +
         "</Data><Data Name='AppVersion'>" + version +
         "</Data><Data Name='AppTimeStamp'>0</Data>"
         "<Data Name='ModuleName'>" + module +
         "</Data><Data Name='ModuleVersion'>1.0</Data>"
         "<Data Name='ModuleTimeStamp'>0</Data>"
         "<Data Name='ExceptionCode'>" + code +
         "</Data><Data Name='FaultingOffset'>0</Data>"
         "<Data Name='ProcessId'>0x1</Data><Data Name='ProcessCreationTime'>0x1</Data>"
         "<Data Name='AppPath'>C:\\Games\\" + app +
         "</Data><Data Name='ModulePath'>" + module_path + "</Data></EventData>";
}

std::string KernelPower41Xml(const std::string& bugcheck,
                             const std::string& power_button) {
  return "<EventData><Data Name='BugcheckCode'>" + bugcheck +
         "</Data><Data Name='SleepInProgress'>0</Data>"
         "<Data Name='PowerButtonTimestamp'>" + power_button +
         "</Data></EventData>";
}

const char* kBugcheck9fXml =
    "<EventData><Data Name='param1'>0x0000009f (0x0000000000000003, "
    "0xffffc00000000000, 0xfffff80000000000, 0xffffc00000000001)</Data>"
    "<Data Name='param2'>C:\\Windows\\Minidump\\102426-1-01.dmp</Data>"
    "<Data Name='param3'>abc</Data></EventData>";

const char* kDriverPath =
    "C:\\Windows\\System32\\DriverStore\\FileRepository\\nv.inf_amd64\\nvwgf2umx.dll";

void TestToCrashRecord() {
  const auto app = ToCrashRecord(Event(
      "Application Error", 1000,
      AppErrorXml("Game.exe", "2.1", "nvwgf2umx.dll", kDriverPath, "c0000005"),
      kStart));
  CHECK(app.has_value());
  CHECK(app->kind == ipc::CrashKind::AppCrash);
  CHECK(app->key == "app|game.exe|nvwgf2umx.dll|0xC0000005");
  CHECK(app->subject == "Game.exe");
  CHECK(app->version == "2.1");
  CHECK(app->code == 0xC0000005u);
  CHECK(app->channel == "Application");

  const auto hang = ToCrashRecord(Event(
      "Application Hang", 1002,
      "<EventData><Data Name='AppName'>Explorer.EXE</Data>"
      "<Data Name='AppVersion'>10.0</Data></EventData>",
      kStart));
  CHECK(hang && hang->kind == ipc::CrashKind::AppHang);
  CHECK(hang->key == "hang|explorer.exe");

  const auto bugcheck = ToCrashRecord(Event(
      "Microsoft-Windows-WER-SystemErrorReporting", 1001, kBugcheck9fXml, kStart));
  CHECK(bugcheck && bugcheck->kind == ipc::CrashKind::BlueScreen);
  CHECK(bugcheck->code == 0x9Fu);
  CHECK(bugcheck->subject == "DRIVER_POWER_STATE_FAILURE");
  CHECK(bugcheck->key == "bsod|0x0000009F");

  // Event 41 writes the stop code in decimal.
  const auto restart_bsod = ToCrashRecord(Event(
      "Microsoft-Windows-Kernel-Power", 41, KernelPower41Xml("159", "0"), kStart));
  CHECK(restart_bsod && restart_bsod->kind == ipc::CrashKind::BlueScreen);
  CHECK(restart_bsod->key == bugcheck->key);

  const auto forced = ToCrashRecord(Event("Microsoft-Windows-Kernel-Power", 41,
                                          KernelPower41Xml("0", "1"), kStart));
  CHECK(forced && forced->kind == ipc::CrashKind::UnexpectedRestart);
  CHECK(forced->key == "restart|power_button");
  CHECK(ToCrashRecord(Event("Microsoft-Windows-Kernel-Power", 41,
                            KernelPower41Xml("0", "0"), kStart))
            ->key == "restart|power_loss");
  CHECK(ToCrashRecord(Event("Microsoft-Windows-Kernel-Power", 41, "", kStart))
            ->key == "restart|unknown");

  const auto gpu = ToCrashRecord(Event(
      "Display", 4101, "<EventData><Data>nvlddmkm</Data><Data></Data></EventData>",
      kStart, ipc::Severity::Warning));
  CHECK(gpu && gpu->kind == ipc::CrashKind::GpuReset);
  CHECK(gpu->subject == "nvlddmkm");

  const auto service = ToCrashRecord(Event(
      "Service Control Manager", 7034,
      "<EventData><Data Name='param1'>SQL Server (SQLEXPRESS)</Data></EventData>",
      kStart));
  CHECK(service && service->kind == ipc::CrashKind::ServiceCrash);
  CHECK(service->key == "service|sql server (sqlexpress)");

  CHECK(ToCrashRecord(Event("Microsoft-Windows-WHEA-Logger", 18, "", kStart,
                            ipc::Severity::Critical))
            ->key == "whea|18");
  // A corrected hardware error is not a crash.
  CHECK(!ToCrashRecord(Event("Microsoft-Windows-WHEA-Logger", 19, "", kStart,
                             ipc::Severity::Warning)));
  CHECK(!ToCrashRecord(Event("Service Control Manager", 7036, "", kStart)));
  CHECK(!ToCrashRecord(Event("Application Error", 1000, "", kStart)));
}

void TestDropDuplicateBlueScreens() {
  std::vector<CrashRecord> records;
  // One blue screen written twice during the next boot...
  records.push_back(*ToCrashRecord(Event("Microsoft-Windows-Kernel-Power", 41,
                                         KernelPower41Xml("159", "0"), kStart)));
  records.push_back(*ToCrashRecord(Event("Microsoft-Windows-WER-SystemErrorReporting",
                                         1001, kBugcheck9fXml, kStart + kMinute)));
  // ...another with the same code a day later without a 1001 (dump off)...
  records.push_back(*ToCrashRecord(Event("Microsoft-Windows-Kernel-Power", 41,
                                         KernelPower41Xml("159", "0"),
                                         kStart + 24 * 60 * kMinute)));
  // ...and a different stop code right next to the first.
  records.push_back(*ToCrashRecord(Event("Microsoft-Windows-Kernel-Power", 41,
                                         KernelPower41Xml("307", "0"),
                                         kStart + 2 * kMinute)));
  DropDuplicateBlueScreens(&records);
  CHECK(records.size() == 3);
  CHECK(records[0].source == CrashEventType::Bugcheck);
  CHECK(records[1].timestamp_unix_ms == kStart + 24 * 60 * kMinute);
  CHECK(records[2].code == 307u);
}

void TestGroupCrashRecords() {
  std::vector<CrashRecord> records;
  // 12 crashes of one kind: 9 on version 2.1, then 3 on version 2.2.
  for (int i = 0; i < 12; ++i) {
    records.push_back(*ToCrashRecord(Event(
        "Application Error", 1000,
        AppErrorXml("Game.exe", i < 9 ? "2.1" : "2.2", "nvwgf2umx.dll",
                    kDriverPath, "c0000005"),
        kStart + i * kMinute)));
  }
  // A hang older than all of them, and a service crash newer.
  records.push_back(*ToCrashRecord(Event(
      "Application Hang", 1002,
      "<EventData><Data Name='AppName'>Tool.exe</Data></EventData>",
      kStart - 60 * kMinute)));
  records.push_back(*ToCrashRecord(Event(
      "Service Control Manager", 7031,
      "<EventData><Data Name='param1'>Spooler</Data></EventData>",
      kStart + 60 * kMinute)));

  const auto groups = GroupCrashRecords(records);
  CHECK(groups.size() == 3);
  CHECK(groups[0].kind == ipc::CrashKind::ServiceCrash);
  CHECK(groups[2].kind == ipc::CrashKind::AppHang);

  const ipc::CrashGroup& app = groups[1];
  CHECK(app.count == 12);
  CHECK(app.first_unix_ms == kStart);
  CHECK(app.last_unix_ms == kStart + 11 * kMinute);
  CHECK(app.occurrence_unix_ms.size() == 12);
  CHECK(app.occurrence_unix_ms.front() == kStart + 11 * kMinute);
  CHECK(app.recent.size() == kMaxRecentCrashesPerGroup);
  CHECK(app.recent.front().version == "2.2");
  CHECK(app.versions.size() == 2);
  CHECK(app.versions[0].version == "2.1" && app.versions[0].count == 9);
  CHECK(app.versions[1].version == "2.2" && app.versions[1].count == 3);
  CHECK(app.has_code && app.code == 0xC0000005u);
  CHECK(app.title.empty());  // Filled by ExplainCrashGroup.
}

void TestExplainCrashGroup() {
  const ipc::TimelineEvent newest = Event(
      "Application Error", 1000,
      AppErrorXml("Game.exe", "2.2", "nvwgf2umx.dll", kDriverPath, "c0000005"),
      kStart);
  std::vector<CrashRecord> records{*ToCrashRecord(newest)};
  auto groups = GroupCrashRecords(records);
  ExplainCrashGroup(newest, "NVIDIA Corporation", &groups[0]);
  CHECK(groups[0].title == "Game Crashed");
  CHECK(groups[0].module_origin == ipc::FaultingModuleOrigin::Driver);
  CHECK(groups[0].module_company == "NVIDIA Corporation");
  CHECK(groups[0].summary.find("NVIDIA Corporation") != std::string::npos);

  const ipc::TimelineEvent bsod = Event(
      "Microsoft-Windows-WER-SystemErrorReporting", 1001, kBugcheck9fXml, kStart);
  records = {*ToCrashRecord(bsod)};
  groups = GroupCrashRecords(records);
  ExplainCrashGroup(bsod, "", &groups[0]);
  CHECK(groups[0].title == "Windows Crashed With a Blue Screen");
  CHECK(groups[0].module_origin == ipc::FaultingModuleOrigin::Unknown);
  CHECK(!groups[0].recommendation.empty());
}

}  // namespace

int main() {
  TestToCrashRecord();
  TestDropDuplicateBlueScreens();
  TestGroupCrashRecords();
  TestExplainCrashGroup();
  std::cout << "crash_history_tests: all passed\n";
  return 0;
}
