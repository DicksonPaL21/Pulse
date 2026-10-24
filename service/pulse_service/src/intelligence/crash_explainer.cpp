#include "intelligence/crash_explainer.hpp"

#include "intelligence/app_crash_explainer.hpp"
#include "intelligence/bugcheck_catalog.hpp"
#include "util/text_match.hpp"

#include <cctype>
#include <charconv>
#include <limits>

namespace pulse {
namespace {

constexpr std::string_view kKernelPowerProvider = "Kernel-Power";
constexpr std::uint32_t kUnexpectedRestartEventId = 41;
constexpr std::string_view kBugcheckProvider = "WER-SystemErrorReporting";
constexpr std::uint32_t kBugcheckEventId = 1001;
constexpr std::string_view kWheaProvider = "WHEA-Logger";
constexpr std::string_view kApplicationErrorProvider = "Application Error";
constexpr std::uint32_t kApplicationErrorEventId = 1000;
constexpr std::string_view kApplicationHangProvider = "Application Hang";
constexpr std::uint32_t kApplicationHangEventId = 1002;
constexpr std::string_view kServiceControlManagerProvider =
    "Service Control Manager";
// 7031: the service stopped and has a recovery action; 7034: it stopped and
// has none.
constexpr std::uint32_t kServiceCrashWithRecoveryEventId = 7031;
constexpr std::uint32_t kServiceCrashEventId = 7034;
constexpr std::string_view kDisplayProvider = "Display";
constexpr std::uint32_t kDisplayDriverResetEventId = 4101;

constexpr std::string_view kDumpExtension = ".dmp";

std::string DecodeXmlEntities(std::string_view text) {
  struct Entity {
    std::string_view encoded;
    char decoded;
  };
  constexpr Entity kEntities[] = {{"&amp;", '&'},  {"&lt;", '<'},
                                  {"&gt;", '>'},   {"&quot;", '"'},
                                  {"&apos;", '\''}};
  std::string out;
  out.reserve(text.size());
  for (std::size_t i = 0; i < text.size();) {
    bool replaced = false;
    if (text[i] == '&') {
      for (const auto& entity : kEntities) {
        if (text.substr(i, entity.encoded.size()) == entity.encoded) {
          out.push_back(entity.decoded);
          i += entity.encoded.size();
          replaced = true;
          break;
        }
      }
    }
    if (!replaced) {
      out.push_back(text[i]);
      ++i;
    }
  }
  return out;
}

/// "true"/"1" style flags; anything else (including absent) is false.
bool IsTruthy(const std::optional<std::string>& value) {
  if (!value) {
    return false;
  }
  if (ContainsIgnoreCase(*value, "true")) {
    return true;
  }
  const auto number = ParseEventDataNumber(*value, 10);
  return number.has_value() && *number != 0;
}

/// First "0x<hex> (" in text: the stop code in a bugcheck message, e.g.
/// "0x0000009f (0x0000000000000003, ...)". The pattern does not depend on the
/// Windows display language, unlike the surrounding sentence.
std::optional<std::uint32_t> FindStopCode(std::string_view text) {
  for (std::size_t at = text.find("0x"); at != std::string_view::npos;
       at = text.find("0x", at + 2)) {
    std::size_t end = at + 2;
    while (end < text.size() &&
           std::isxdigit(static_cast<unsigned char>(text[end]))) {
      ++end;
    }
    std::size_t paren = end;
    while (paren < text.size() && text[paren] == ' ') {
      ++paren;
    }
    if (end == at + 2 || paren >= text.size() || text[paren] != '(') {
      continue;
    }
    const auto value = ParseEventDataNumber(text.substr(at, end - at), 16);
    if (value && *value != 0 &&
        *value <= std::numeric_limits<std::uint32_t>::max()) {
      return static_cast<std::uint32_t>(*value);
    }
  }
  return std::nullopt;
}

/// First "X:\...\name.dmp" path in text.
std::optional<std::string> FindDumpPath(std::string_view text) {
  constexpr std::string_view kPathStops = "<>\"'\r\n|?*";
  for (std::size_t ext = 0; ext + kDumpExtension.size() <= text.size(); ++ext) {
    if (!ContainsIgnoreCase(text.substr(ext, kDumpExtension.size()),
                            kDumpExtension)) {
      continue;
    }
    std::size_t start = ext;
    while (start > 0 && kPathStops.find(text[start - 1]) == std::string_view::npos) {
      --start;
    }
    // Trim to the drive letter: "...was saved in: C:\Windows\MEMORY.DMP".
    const std::size_t drive = text.find(":\\", start);
    if (drive == std::string_view::npos || drive == 0 || drive - 1 < start ||
        drive > ext ||
        !std::isalpha(static_cast<unsigned char>(text[drive - 1]))) {
      continue;
    }
    const std::size_t path_start = drive - 1;
    return std::string(
        text.substr(path_start, ext + kDumpExtension.size() - path_start));
  }
  return std::nullopt;
}

/// "Stop code: NAME (0x0000000A). <why>" — the shared blue-screen sentence.
std::string DescribeStopCode(std::uint32_t code) {
  const BugcheckInfo* info = FindBugcheck(code);
  std::string text = "Stop code: ";
  if (info != nullptr) {
    text += std::string(info->name) + " (" + FormatBugcheckCode(code) + "). ";
    text += std::string(BugcheckCauseExplanation(info->cause));
  } else {
    text += FormatBugcheckCode(code) + ".";
  }
  return text;
}

std::string StopCodeRecommendation(std::uint32_t code) {
  const BugcheckInfo* info = FindBugcheck(code);
  if (info != nullptr) {
    return std::string(BugcheckCauseRecommendation(info->cause));
  }
  return "Look up this stop code in Microsoft's Bug Check Code Reference and "
         "check recently installed drivers or hardware.";
}

EventInsight BlueScreenInsight(std::string title, std::uint32_t code) {
  EventInsight out;
  out.title = std::move(title);
  out.summary = DescribeStopCode(code);
  out.recommendation = StopCodeRecommendation(code);
  out.action_required = !out.recommendation.empty();
  out.importance = Importance::Critical;
  out.category = InsightCategory::Crash;
  return out;
}

std::optional<EventInsight> ExplainUnexpectedRestart(
    const ipc::TimelineEvent& event) {
  const auto restart = ReadUnexpectedRestart(event.raw_xml);
  if (!restart) {
    return std::nullopt;  // No event data: keep the generic catalog wording.
  }

  EventInsight out;
  if (restart->stop_code) {
    out = BlueScreenInsight("Windows Restarted After a Blue Screen",
                            *restart->stop_code);
  } else if (restart->power_button_held) {
    out.title = "PC Was Forced Off With the Power Button";
    out.summary =
        "The power button was held down to turn the PC off, usually because "
        "it had stopped responding.";
    out.recommendation =
        "If Windows had frozen, look at the events just before this restart.";
    out.action_required = false;
    out.importance = Importance::High;
    out.category = InsightCategory::Power;
  } else {
    out.title = "PC Lost Power or Stopped Suddenly";
    out.summary =
        "The PC turned off without recording an error. This usually means a "
        "power cut, a drained battery, a faulty or underpowered power supply, "
        "overheating, or a complete freeze.";
    out.recommendation =
        "If it repeats, check the power supply and cables, temperatures and "
        "any overclocking. New hardware such as a CPU or graphics card may "
        "need a stronger power supply.";
    out.action_required = true;
    out.importance = Importance::Critical;
    out.category = InsightCategory::Power;
  }
  if (restart->during_sleep) {
    out.summary += " It happened while the PC was going to sleep or waking up.";
  }
  return out;
}

std::optional<EventInsight> ExplainBugcheck(const ipc::TimelineEvent& event) {
  const auto code = ReadBugcheckStopCode(event);
  if (!code) {
    return std::nullopt;
  }
  EventInsight out = BlueScreenInsight("Windows Crashed With a Blue Screen", *code);
  auto dump = FindDumpPath(event.raw_xml);
  if (!dump) {
    dump = FindDumpPath(event.message);
  }
  if (dump) {
    out.summary += " A crash dump was saved to " + DecodeXmlEntities(*dump) + ".";
  }
  return out;
}

std::optional<EventInsight> ExplainServiceCrash(
    const ipc::TimelineEvent& event) {
  const auto data = ReadEventData(event.raw_xml);
  // param1 is the service's display name, e.g. "Windows Update".
  const auto name = FindEventDataField(data, "param1", 0);
  if (!name || name->empty()) {
    return std::nullopt;
  }
  EventInsight out;
  out.title = ContainsIgnoreCase(*name, "service") ? *name + " Crashed"
                                                   : *name + " Service Crashed";
  out.summary = "The " + *name + " service stopped unexpectedly.";
  if (event.win_event_id == kServiceCrashWithRecoveryEventId) {
    out.summary +=
        " Windows will take the recovery action set for it, usually a "
        "restart.";
  }
  out.recommendation =
      "If it keeps happening, update or reinstall the program the service "
      "belongs to.";
  out.action_required = true;
  out.importance = Importance::High;
  out.category = InsightCategory::Service;
  return out;
}

std::optional<EventInsight> ExplainHardwareError(
    const ipc::TimelineEvent& event) {
  EventInsight out;
  out.category = InsightCategory::Device;
  switch (event.severity) {
    case ipc::Severity::Critical:
    case ipc::Severity::Error:
      out.title = "Hardware Reported a Fatal Error";
      out.summary =
          "A hardware component (processor, memory, a PCIe device or the "
          "motherboard) reported an error it could not fix. Windows usually "
          "stops with a blue screen when this happens.";
      out.recommendation =
          "Remove any overclock, check temperatures and the power supply, and "
          "run Windows Memory Diagnostic. The event details name the "
          "component that reported it.";
      out.action_required = true;
      out.importance = Importance::Critical;
      return out;
    case ipc::Severity::Warning:
      out.title = "Hardware Corrected an Error";
      out.summary =
          "A hardware component detected an error and fixed it on its own. "
          "One is harmless; many in a short time can point to failing "
          "hardware, an unstable overclock or a loose card.";
      out.recommendation =
          "Only worth checking if it keeps repeating. The event details name "
          "the component.";
      out.action_required = false;
      out.importance = Importance::Medium;
      return out;
    default:
      return std::nullopt;
  }
}

}  // namespace

std::optional<std::string> FindEventDataValue(std::string_view event_xml,
                                              std::string_view name) {
  // Windows renders <Data Name='X'>; accept double quotes as well.
  for (const char quote : {'\'', '"'}) {
    std::string attribute = "Name=";
    attribute += quote;
    attribute += name;
    attribute += quote;
    const std::size_t at = event_xml.find(attribute);
    if (at == std::string_view::npos) {
      continue;
    }
    const std::size_t tag_end = event_xml.find('>', at + attribute.size());
    if (tag_end == std::string_view::npos) {
      return std::nullopt;
    }
    if (event_xml[tag_end - 1] == '/') {
      return std::string();  // <Data Name='X'/>
    }
    const std::size_t close = event_xml.find("</Data>", tag_end);
    if (close == std::string_view::npos) {
      return std::nullopt;
    }
    return DecodeXmlEntities(
        event_xml.substr(tag_end + 1, close - tag_end - 1));
  }
  return std::nullopt;
}

std::vector<EventDataItem> ReadEventData(std::string_view event_xml) {
  constexpr std::string_view kOpen = "<Data";
  constexpr std::string_view kClose = "</Data>";
  std::vector<EventDataItem> items;
  for (std::size_t at = event_xml.find(kOpen); at != std::string_view::npos;
       at = event_xml.find(kOpen, at + kOpen.size())) {
    const std::size_t after = at + kOpen.size();
    if (after >= event_xml.size() ||
        (event_xml[after] != '>' && event_xml[after] != ' ' &&
         event_xml[after] != '/')) {
      continue;  // Another element, e.g. <DataItem>.
    }
    const std::size_t tag_end = event_xml.find('>', after);
    if (tag_end == std::string_view::npos) {
      break;
    }
    const std::string_view tag = event_xml.substr(after, tag_end - after);
    EventDataItem item;
    for (const char quote : {'\'', '"'}) {
      std::string attribute = "Name=";
      attribute += quote;
      const std::size_t name_at = tag.find(attribute);
      if (name_at == std::string_view::npos) {
        continue;
      }
      const std::size_t value_at = name_at + attribute.size();
      const std::size_t name_end = tag.find(quote, value_at);
      if (name_end != std::string_view::npos) {
        item.name = std::string(tag.substr(value_at, name_end - value_at));
      }
      break;
    }
    if (!tag.empty() && tag.back() == '/') {
      items.push_back(std::move(item));  // <Data Name='X'/>
      continue;
    }
    const std::size_t close = event_xml.find(kClose, tag_end);
    if (close == std::string_view::npos) {
      break;
    }
    item.value =
        DecodeXmlEntities(event_xml.substr(tag_end + 1, close - tag_end - 1));
    items.push_back(std::move(item));
    at = close;
  }
  return items;
}

std::optional<std::string> FindEventDataField(
    const std::vector<EventDataItem>& data, std::string_view name,
    std::size_t position) {
  bool any_named = false;
  for (const auto& item : data) {
    if (item.name == name) {
      return item.value;
    }
    any_named = any_named || !item.name.empty();
  }
  if (any_named || position >= data.size()) {
    return std::nullopt;
  }
  return data[position].value;
}

std::optional<std::uint64_t> ParseEventDataNumber(std::string_view text,
                                                  int base) {
  while (!text.empty() && std::isspace(static_cast<unsigned char>(text.front()))) {
    text.remove_prefix(1);
  }
  while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back()))) {
    text.remove_suffix(1);
  }
  if (base == 16 && text.size() > 2 && text[0] == '0' &&
      (text[1] == 'x' || text[1] == 'X')) {
    text.remove_prefix(2);
  }
  std::uint64_t value = 0;
  const auto* end = text.data() + text.size();
  const auto result = std::from_chars(text.data(), end, value, base);
  if (text.empty() || result.ec != std::errc() || result.ptr != end) {
    return std::nullopt;
  }
  return value;
}

CrashEventType ClassifyCrashEvent(std::string_view provider_name,
                                  std::uint32_t win_event_id) {
  const auto is = [&](std::string_view provider, std::uint32_t id) {
    return win_event_id == id && ContainsIgnoreCase(provider_name, provider);
  };
  if (is(kKernelPowerProvider, kUnexpectedRestartEventId)) {
    return CrashEventType::UnexpectedRestart;
  }
  if (is(kBugcheckProvider, kBugcheckEventId)) {
    return CrashEventType::Bugcheck;
  }
  if (is(kApplicationErrorProvider, kApplicationErrorEventId)) {
    return CrashEventType::ApplicationError;
  }
  if (is(kApplicationHangProvider, kApplicationHangEventId)) {
    return CrashEventType::ApplicationHang;
  }
  if (is(kServiceControlManagerProvider, kServiceCrashWithRecoveryEventId) ||
      is(kServiceControlManagerProvider, kServiceCrashEventId)) {
    return CrashEventType::ServiceCrash;
  }
  if (is(kDisplayProvider, kDisplayDriverResetEventId)) {
    return CrashEventType::DisplayDriverReset;
  }
  if (ContainsIgnoreCase(provider_name, kWheaProvider)) {
    return CrashEventType::HardwareError;
  }
  return CrashEventType::None;
}

std::optional<UnexpectedRestart> ReadUnexpectedRestart(
    std::string_view event_xml) {
  const auto bugcheck_value = FindEventDataValue(event_xml, "BugcheckCode");
  if (!bugcheck_value) {
    return std::nullopt;
  }
  UnexpectedRestart out;
  // Event 41 stores the stop code in decimal (159 = 0x9F).
  const auto bugcheck = ParseEventDataNumber(*bugcheck_value, 10).value_or(0);
  if (bugcheck != 0 && bugcheck <= std::numeric_limits<std::uint32_t>::max()) {
    out.stop_code = static_cast<std::uint32_t>(bugcheck);
  }
  out.power_button_held =
      IsTruthy(FindEventDataValue(event_xml, "PowerButtonTimestamp")) ||
      IsTruthy(FindEventDataValue(event_xml, "LongPowerButtonPressDetected"));
  out.during_sleep = IsTruthy(FindEventDataValue(event_xml, "SleepInProgress"));
  return out;
}

std::optional<std::uint32_t> ReadBugcheckStopCode(
    const ipc::TimelineEvent& event) {
  auto code = FindStopCode(event.raw_xml);
  if (!code) {
    code = FindStopCode(event.message);
  }
  return code;
}

bool IsCrashDiagnosticEvent(std::string_view provider_name,
                            std::uint32_t win_event_id) {
  switch (ClassifyCrashEvent(provider_name, win_event_id)) {
    case CrashEventType::UnexpectedRestart:
    case CrashEventType::Bugcheck:
    case CrashEventType::ApplicationError:
    case CrashEventType::ApplicationHang:
    case CrashEventType::ServiceCrash:
      return true;
    case CrashEventType::None:
    case CrashEventType::HardwareError:
    case CrashEventType::DisplayDriverReset:
      return false;
  }
  return false;
}

std::optional<EventInsight> ExplainCrashEvent(const ipc::TimelineEvent& event) {
  switch (ClassifyCrashEvent(event.provider_name, event.win_event_id)) {
    case CrashEventType::UnexpectedRestart:
      return ExplainUnexpectedRestart(event);
    case CrashEventType::Bugcheck:
      return ExplainBugcheck(event);
    case CrashEventType::ApplicationError: {
      const auto fault = ParseApplicationFault(event.raw_xml);
      if (!fault) {
        return std::nullopt;
      }
      return ExplainApplicationFault(*fault, /*module_company=*/"");
    }
    case CrashEventType::ApplicationHang: {
      const auto hang = ParseApplicationHang(event.raw_xml);
      if (!hang) {
        return std::nullopt;
      }
      return ExplainApplicationHang(*hang);
    }
    case CrashEventType::ServiceCrash:
      return ExplainServiceCrash(event);
    case CrashEventType::HardwareError:
      return ExplainHardwareError(event);
    case CrashEventType::DisplayDriverReset:
    case CrashEventType::None:
      break;
  }
  return std::nullopt;
}

}  // namespace pulse
