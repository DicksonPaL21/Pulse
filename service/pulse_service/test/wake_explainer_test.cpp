#include "intelligence/event_intelligence.hpp"
#include "intelligence/wake_explainer.hpp"

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

/// U+2026, spelled as UTF-8 bytes (the build has no /utf-8 flag).
constexpr const char* kEllipsis = "\xE2\x80\xA6";

bool Contains(const std::string& text, const std::string& part) {
  return text.find(part) != std::string::npos;
}

/// Power-Troubleshooter event 1 shaped like the manifest (version 3), with
/// the wake fields set; "" leaves a field out, as older versions do.
std::string WakeXml(const std::string& source, const std::string& timer_owner,
                    const std::string& timer_context) {
  std::string xml =
      "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"
      "<System><Provider Name='Microsoft-Windows-Power-Troubleshooter'/>"
      "<EventID>1</EventID></System><EventData>"
      "<Data Name='SleepTime'>2026-10-17T21:00:00.0000000Z</Data>"
      "<Data Name='WakeTime'>2026-10-17T21:30:00.0000000Z</Data>"
      "<Data Name='WakeSourceType'>0</Data>"
      "<Data Name='WakeSourceTextLength'>" +
      std::to_string(source.size()) + "</Data>";
  xml += source.empty() ? "<Data Name='WakeSourceText'/>"
                        : "<Data Name='WakeSourceText'>" + source + "</Data>";
  if (!timer_owner.empty()) {
    xml += "<Data Name='WakeTimerOwner'>" + timer_owner + "</Data>";
  }
  if (!timer_context.empty()) {
    xml += "<Data Name='WakeTimerContext'>" + timer_context + "</Data>";
  }
  return xml + "</EventData></Event>";
}

ipc::TimelineEvent WakeEvent(const std::string& xml) {
  ipc::TimelineEvent e;
  e.provider_name = "Microsoft-Windows-Power-Troubleshooter";
  e.win_event_id = 1;
  e.severity = ipc::Severity::Info;
  e.raw_xml = xml;
  return e;
}

void TestDeviceWake() {
  const auto insight =
      ExplainWakeEvent(WakeEvent(WakeXml("Intel(R) Ethernet Connection I219-V", "", "")));
  CHECK(insight.has_value());
  CHECK(insight->title == "PC Woke Up: Intel(R) Ethernet Connection I219-V");
  CHECK(Contains(insight->summary, "Intel(R) Ethernet Connection I219-V."));
  CHECK(Contains(insight->recommendation, "Allow this device to wake"));
  CHECK(insight->category == InsightCategory::Power);
  CHECK(insight->importance == Importance::Low);
  CHECK(!insight->action_required);
}

void TestTimerWake() {
  const auto insight = ExplainWakeEvent(WakeEvent(WakeXml(
      "", "\\Device\\HarddiskVolume3\\Windows\\System32\\svchost.exe",
      "Windows will execute 'NT TASK\\Microsoft\\Windows\\UpdateOrchestrator"
      "\\Reboot' scheduled task that requested waking the computer.")));
  CHECK(insight.has_value());
  CHECK(insight->title == "PC Woke Up for a Scheduled Task");
  CHECK(Contains(insight->summary, "UpdateOrchestrator"));
  CHECK(Contains(insight->summary, "Requested by: \\Device\\"));
  CHECK(Contains(insight->recommendation, "Allow wake timers"));
}

void TestTimerWinsOverSourceText() {
  // A timer wake can also carry source text; the timer is the clearer cause.
  const auto insight = ExplainWakeEvent(
      WakeEvent(WakeXml("Timer", "svchost.exe", "Maintenance task.")));
  CHECK(insight.has_value());
  CHECK(insight->title == "PC Woke Up for a Scheduled Task");
}

void TestLongSourceIsShortenedOnlyInTitle() {
  const std::string source =
      "Realtek PCIe GbE Family Controller with a very long vendor description";
  const auto insight = ExplainWakeEvent(WakeEvent(WakeXml(source, "", "")));
  CHECK(insight.has_value());
  CHECK(insight->title.size() < std::string("PC Woke Up: ").size() + source.size());
  CHECK(Contains(insight->title, kEllipsis));
  CHECK(Contains(insight->summary, source));
}

void TestXmlEntitiesAreDecoded() {
  const auto insight =
      ExplainWakeEvent(WakeEvent(WakeXml("Mouse &amp; Keyboard Hub", "", "")));
  CHECK(insight.has_value());
  CHECK(insight->title == "PC Woke Up: Mouse & Keyboard Hub");
}

void TestNothingRecordedKeepsCatalog() {
  CHECK(!ExplainWakeEvent(WakeEvent(WakeXml("", "", ""))).has_value());
  CHECK(!ExplainWakeEvent(WakeEvent(WakeXml("   ", "", ""))).has_value());
  CHECK(!ExplainWakeEvent(WakeEvent("")).has_value());

  // The engine then falls back to the generic catalog title.
  EventIntelligence engine;
  const auto generic = engine.Analyze(WakeEvent(""));
  CHECK(generic.title == "Windows Woke From Sleep");
}

void TestEngineUsesWakeSource() {
  EventIntelligence engine;
  const auto insight =
      engine.Analyze(WakeEvent(WakeXml("USB Composite Device", "", "")));
  CHECK(insight.title == "PC Woke Up: USB Composite Device");
}

void TestOnlyPowerTroubleshooterEvent1() {
  CHECK(IsWakeDiagnosticEvent("Microsoft-Windows-Power-Troubleshooter", 1));
  CHECK(!IsWakeDiagnosticEvent("Microsoft-Windows-Power-Troubleshooter", 2));
  CHECK(!IsWakeDiagnosticEvent("Microsoft-Windows-Kernel-Power", 1));

  auto other = WakeEvent(WakeXml("USB Composite Device", "", ""));
  other.provider_name = "Microsoft-Windows-Kernel-General";
  CHECK(!ExplainWakeEvent(other).has_value());
}

}  // namespace

int main() {
  TestDeviceWake();
  TestTimerWake();
  TestTimerWinsOverSourceText();
  TestLongSourceIsShortenedOnlyInTitle();
  TestXmlEntitiesAreDecoded();
  TestNothingRecordedKeepsCatalog();
  TestEngineUsesWakeSource();
  TestOnlyPowerTroubleshooterEvent1();
  std::cout << "wake_explainer_tests passed\n";
  return 0;
}
