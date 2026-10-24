#include "intelligence/app_crash_explainer.hpp"
#include "intelligence/crash_explainer.hpp"
#include "intelligence/event_intelligence.hpp"
#include "intelligence/exception_catalog.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

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

bool Contains(const std::string& text, const std::string& part) {
  return text.find(part) != std::string::npos;
}

// Windows 11 layout, copied from a real Application Error 1000 event.
std::string NamedFaultXml(const std::string& module_name,
                          const std::string& module_path,
                          const std::string& code) {
  return "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"
         "<System><Provider Name='Application Error'/><EventID>1000</EventID>"
         "</System><EventData>"
         "<Data Name='AppName'>Pulse.exe</Data>"
         "<Data Name='AppVersion'>1.4.0.17</Data>"
         "<Data Name='AppTimeStamp'>6acfd82f</Data>"
         "<Data Name='ModuleName'>" + module_name + "</Data>"
         "<Data Name='ModuleVersion'>0.0.0.0</Data>"
         "<Data Name='ModuleTimeStamp'>6a62494e</Data>"
         "<Data Name='ExceptionCode'>" + code + "</Data>"
         "<Data Name='FaultingOffset'>000000000001d7b0</Data>"
         "<Data Name='ProcessId'>0x5490</Data>"
         "<Data Name='ProcessCreationTime'>0x1dd5dfd052374a4</Data>"
         "<Data Name='AppPath'>C:\\Program Files\\Pulse\\Pulse.exe</Data>"
         "<Data Name='ModulePath'>" + module_path + "</Data>"
         "<Data Name='IntegratorReportId'>38a77eed-0bd2-45ca-b1d6-a8d7b7b089e2</Data>"
         "<Data Name='PackageFullName'></Data>"
         "<Data Name='PackageRelativeAppId'></Data>"
         "</EventData></Event>";
}

// Older builds: the same values without names.
const char* kUnnamedFaultXml =
    "<Event><System><Provider Name='Application Error'/></System><EventData>"
    "<Data>Discord.exe</Data><Data>1.0.9170.0</Data><Data>66f1d2a0</Data>"
    "<Data>nvwgf2umx.dll</Data><Data>32.0.15.6094</Data><Data>66e0a1b2</Data>"
    "<Data>c0000005</Data><Data>0000000000a1b2c3</Data><Data>0x2f10</Data>"
    "<Data>0x1dd5dfd052374a4</Data>"
    "<Data>C:\\Users\\me\\AppData\\Local\\Discord\\app-1.0.9170\\Discord.exe</Data>"
    "<Data>C:\\Windows\\System32\\DriverStore\\FileRepository\\nv_dispi.inf_amd64_x\\nvwgf2umx.dll</Data>"
    "<Data>1b2c3d4e-0000-0000-0000-000000000000</Data><Data/><Data/>"
    "</EventData></Event>";

ipc::TimelineEvent Event(const std::string& provider, std::uint32_t id,
                         const std::string& xml) {
  ipc::TimelineEvent e;
  e.provider_name = provider;
  e.win_event_id = id;
  e.severity = ipc::Severity::Error;
  e.raw_xml = xml;
  return e;
}

void TestReadEventData() {
  const auto data = ReadEventData(
      "<EventData><Data Name='A'>1</Data><Data>x &amp; y</Data>"
      "<Data Name='Empty'/><DataItem>no</DataItem></EventData>");
  CHECK(data.size() == 3);
  CHECK(data[0].name == "A" && data[0].value == "1");
  CHECK(data[1].name.empty() && data[1].value == "x & y");
  CHECK(data[2].name == "Empty" && data[2].value.empty());

  // Named events never fall back to positions.
  CHECK(FindEventDataField(data, "A", 1) == std::string("1"));
  CHECK(!FindEventDataField(data, "Missing", 1).has_value());
  const auto unnamed = ReadEventData("<Data>a</Data><Data>b</Data>");
  CHECK(FindEventDataField(unnamed, "Second", 1) == std::string("b"));
  CHECK(!FindEventDataField(unnamed, "Third", 2).has_value());

  CHECK(ParseEventDataNumber("c0000005", 16) == 0xC0000005ull);
  CHECK(ParseEventDataNumber(" 0x9F ", 16) == 0x9Full);
  CHECK(!ParseEventDataNumber("abc", 10).has_value());
}

void TestExceptionCatalog() {
  const ExceptionInfo* access = FindException(0xC0000005);
  CHECK(access != nullptr);
  CHECK(access->name == "STATUS_ACCESS_VIOLATION");
  CHECK(access->cause == ExceptionCause::Memory);
  CHECK(FindException(0xC0000409)->cause == ExceptionCause::ProgramError);
  CHECK(FindException(0xC06D007E)->cause == ExceptionCause::MissingFile);
  CHECK(FindException(0x12345678) == nullptr);
  CHECK(FormatExceptionCode(0xc0000005) == "0xC0000005");
}

void TestParseNamedFault() {
  const auto fault = ParseApplicationFault(
      NamedFaultXml("flutter_windows.dll",
                    "C:\\Program Files\\Pulse\\flutter_windows.dll", "c000041d"));
  CHECK(fault.has_value());
  CHECK(fault->app_name == "Pulse.exe");
  CHECK(fault->app_version == "1.4.0.17");
  CHECK(fault->module_name == "flutter_windows.dll");
  CHECK(fault->exception_code == 0xC000041Du);
  CHECK(fault->app_path == "C:\\Program Files\\Pulse\\Pulse.exe");
  CHECK(ClassifyFaultingModule(*fault, "") == FaultingModuleOrigin::App);

  const EventInsight insight = ExplainApplicationFault(*fault, "");
  CHECK(insight.title == "Pulse Crashed");
  CHECK(Contains(insight.summary, "code that Windows called"));
  CHECK(Contains(insight.summary, "flutter_windows.dll, one of the app's own files"));
  CHECK(insight.importance == Importance::High);
  CHECK(insight.category == InsightCategory::Crash);
}

void TestParseUnnamedFault() {
  const auto fault = ParseApplicationFault(kUnnamedFaultXml);
  CHECK(fault.has_value());
  CHECK(fault->app_name == "Discord.exe");
  CHECK(fault->module_name == "nvwgf2umx.dll");
  CHECK(fault->exception_code == 0xC0000005u);
  CHECK(ClassifyFaultingModule(*fault, "NVIDIA Corporation") ==
        FaultingModuleOrigin::Driver);

  const EventInsight insight =
      ExplainApplicationFault(*fault, "NVIDIA Corporation");
  CHECK(insight.title == "Discord Crashed");
  CHECK(Contains(insight.summary, "after a memory access error"));
  CHECK(Contains(insight.summary, "part of a device driver from NVIDIA Corporation"));
  CHECK(Contains(insight.recommendation, "driver"));

  CHECK(!ParseApplicationFault("<EventData><Data Name='AppVersion'>1</Data></EventData>")
             .has_value());
}

ApplicationFault Fault(const std::string& app_path,
                       const std::string& module_path) {
  ApplicationFault fault;
  fault.app_path = app_path;
  fault.app_name = app_path.substr(app_path.find_last_of('\\') + 1);
  fault.module_path = module_path;
  fault.module_name = module_path.substr(module_path.find_last_of('\\') + 1);
  return fault;
}

void TestClassifyFaultingModule() {
  const std::string app = "C:\\Program Files\\Game\\game.exe";
  CHECK(ClassifyFaultingModule(Fault(app, app), "") == FaultingModuleOrigin::App);
  CHECK(ClassifyFaultingModule(Fault(app, "c:\\program files\\game\\bin\\engine.dll"), "") ==
        FaultingModuleOrigin::App);
  CHECK(ClassifyFaultingModule(Fault(app, "C:\\Windows\\System32\\ntdll.dll"),
                               "Microsoft Corporation") ==
        FaultingModuleOrigin::Windows);
  CHECK(ClassifyFaultingModule(Fault(app, "D:\\WINDOWS\\SysWOW64\\KERNELBASE.dll"), "") ==
        FaultingModuleOrigin::Windows);
  // A third-party file someone copied into System32.
  CHECK(ClassifyFaultingModule(Fault(app, "C:\\Windows\\System32\\vendorhook.dll"),
                               "Contoso Ltd.") == FaultingModuleOrigin::Other);
  CHECK(ClassifyFaultingModule(Fault(app, "C:\\Program Files\\Overlay\\hook64.dll"), "") ==
        FaultingModuleOrigin::Other);
  // Windows' own apps live in the Windows folder; their DLLs are Windows files.
  CHECK(ClassifyFaultingModule(Fault("C:\\Windows\\explorer.exe",
                                     "C:\\Windows\\System32\\shell32.dll"),
                               "") == FaultingModuleOrigin::Windows);

  ApplicationFault unknown = Fault(app, app);
  unknown.module_name = "unknown";
  unknown.module_path = "unknown";
  CHECK(ClassifyFaultingModule(unknown, "") == FaultingModuleOrigin::Unknown);
  CHECK(Contains(ExplainApplicationFault(unknown, "").summary,
                 "could not tell which file"));

  ApplicationFault no_paths = Fault(app, app);
  no_paths.app_path.clear();
  no_paths.module_path.clear();
  no_paths.module_name = "engine.dll";
  CHECK(ClassifyFaultingModule(no_paths, "") == FaultingModuleOrigin::Unknown);
  CHECK(Contains(ExplainApplicationFault(no_paths, "").summary,
                 "The error happened in engine.dll."));
}

void TestOtherAndWindowsWording() {
  ApplicationFault fault =
      Fault("C:\\Program Files\\Game\\game.exe",
            "C:\\Program Files\\Overlay\\hook64.dll");
  fault.exception_code = 0xC0000409;
  EventInsight other = ExplainApplicationFault(fault, "Contoso Ltd.");
  CHECK(Contains(other.summary, "a file from Contoso Ltd. that was loaded"));
  CHECK(Contains(other.recommendation, "hook64.dll"));

  fault.module_path = "C:\\Windows\\System32\\ucrtbase.dll";
  fault.module_name = "ucrtbase.dll";
  EventInsight windows = ExplainApplicationFault(fault, "Microsoft Corporation");
  CHECK(Contains(windows.summary, "a Windows file"));
  CHECK(windows.recommendation ==
        ExceptionCauseRecommendation(ExceptionCause::ProgramError));

  fault.exception_code = 0xDEADBEEF;
  CHECK(Contains(ExplainApplicationFault(fault, "").summary,
                 "an error (code 0xDEADBEEF)"));
}

void TestApplicationHang() {
  const std::string xml =
      "<EventData><Data Name='AppName'>dllhost.exe</Data>"
      "<Data Name='AppVersion'>10.0.26100.9549</Data>"
      "<Data Name='ProcessId'>0x77b0</Data><Data Name='StartTime'>0x1</Data>"
      "<Data Name='TerminationTime'>4294967295</Data>"
      "<Data Name='ExeFileName'>C:\\Windows\\System32\\dllhost.exe</Data>"
      "</EventData>";
  const auto hang = ParseApplicationHang(xml);
  CHECK(hang.has_value());
  CHECK(hang->app_path == "C:\\Windows\\System32\\dllhost.exe");
  const EventInsight insight = ExplainApplicationHang(*hang);
  CHECK(insight.title == "dllhost Stopped Responding");
  CHECK(!insight.action_required);
}

void TestDispatch() {
  CHECK(IsCrashDiagnosticEvent("Application Error", 1000));
  CHECK(IsCrashDiagnosticEvent("Application Hang", 1002));
  CHECK(IsCrashDiagnosticEvent("Service Control Manager", 7031));
  CHECK(IsCrashDiagnosticEvent("Service Control Manager", 7034));
  CHECK(!IsCrashDiagnosticEvent("Application Error", 1001));
  CHECK(!IsCrashDiagnosticEvent("Service Control Manager", 7036));

  EventIntelligence engine;
  const auto crash = engine.Analyze(Event("Application Error", 1000, kUnnamedFaultXml));
  CHECK(crash.title == "Discord Crashed");

  // Without event data the catalog wording stays.
  const auto bare = engine.Analyze(Event("Application Error", 1000, ""));
  CHECK(bare.title == "Application Crashed");

  const std::string service_xml =
      "<EventData><Data Name='param1'>SQL Server (SQLEXPRESS)</Data>"
      "<Data Name='param2'>2</Data></EventData>";
  const auto service =
      engine.Analyze(Event("Service Control Manager", 7034, service_xml));
  CHECK(service.title == "SQL Server (SQLEXPRESS) Service Crashed");
  CHECK(service.category == InsightCategory::Service);
  CHECK(!Contains(service.summary, "recovery"));

  const auto recovered = engine.Analyze(Event(
      "Service Control Manager", 7031,
      "<EventData><Data Name='param1'>Print Spooler Service</Data></EventData>"));
  CHECK(recovered.title == "Print Spooler Service Crashed");
  CHECK(Contains(recovered.summary, "recovery action"));
}

}  // namespace

int main() {
  TestReadEventData();
  TestExceptionCatalog();
  TestParseNamedFault();
  TestParseUnnamedFault();
  TestClassifyFaultingModule();
  TestOtherAndWindowsWording();
  TestApplicationHang();
  TestDispatch();
  std::cout << "app_crash_explainer_tests: all passed\n";
  return 0;
}
