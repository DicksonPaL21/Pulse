#include "intelligence/app_crash_explainer.hpp"

#include "intelligence/crash_explainer.hpp"
#include "intelligence/exception_catalog.hpp"
#include "util/text_match.hpp"

#include <cctype>
#include <limits>

namespace pulse {
namespace {

// Application Error 1000 fields: Windows 11 names them; older builds list the
// same values without names, in this order (the event's message template).
constexpr std::size_t kFaultAppName = 0;
constexpr std::size_t kFaultAppVersion = 1;
constexpr std::size_t kFaultModuleName = 3;
constexpr std::size_t kFaultModuleVersion = 4;
constexpr std::size_t kFaultExceptionCode = 6;
constexpr std::size_t kFaultAppPath = 10;
constexpr std::size_t kFaultModulePath = 11;

// Application Hang 1002 fields, same rule.
constexpr std::size_t kHangAppName = 0;
constexpr std::size_t kHangAppVersion = 1;
constexpr std::size_t kHangAppPath = 5;

constexpr std::string_view kExecutableExtension = ".exe";
constexpr std::string_view kWindowsFolder = ":\\Windows\\";
constexpr std::string_view kDriverStoreFolder = ":\\Windows\\System32\\DriverStore\\";
constexpr std::string_view kMicrosoft = "Microsoft";

std::string Field(const std::vector<EventDataItem>& data,
                  std::string_view name, std::size_t position) {
  return FindEventDataField(data, name, position).value_or("");
}

bool EqualsIgnoreCase(std::string_view a, std::string_view b) {
  return a.size() == b.size() && ContainsIgnoreCase(a, b);
}

bool StartsWithIgnoreCase(std::string_view text, std::string_view prefix) {
  return text.size() >= prefix.size() &&
         EqualsIgnoreCase(text.substr(0, prefix.size()), prefix);
}

/// "C:\Windows\..." with any drive letter.
bool IsUnderDriveFolder(std::string_view path, std::string_view folder) {
  return path.size() > folder.size() &&
         std::isalpha(static_cast<unsigned char>(path[0])) &&
         StartsWithIgnoreCase(path.substr(1), folder);
}

/// "C:\Program Files\App\" for "C:\Program Files\App\app.exe"; empty without
/// a folder.
std::string_view FolderOf(std::string_view path) {
  const std::size_t slash = path.find_last_of('\\');
  return slash == std::string_view::npos ? std::string_view()
                                         : path.substr(0, slash + 1);
}

/// Completes "<App> closed unexpectedly after ...".
std::string ExceptionPhrase(const std::optional<std::uint32_t>& code) {
  if (!code) {
    return "an error";
  }
  if (const ExceptionInfo* info = FindException(*code)) {
    return std::string(info->meaning);
  }
  return "an error (code " + FormatExceptionCode(*code) + ")";
}

/// Second sentence: which file the error happened in and whose it is.
std::string ModuleSentence(const ApplicationFault& fault,
                           FaultingModuleOrigin origin,
                           std::string_view company) {
  if (IsUnknownModule(fault.module_name)) {
    return "Windows could not tell which file was running.";
  }
  const std::string& module = fault.module_name;
  switch (origin) {
    case FaultingModuleOrigin::App:
      if (EqualsIgnoreCase(module, fault.app_name)) {
        return "The error happened in the app's own program file.";
      }
      return "The error happened in " + module + ", one of the app's own files.";
    case FaultingModuleOrigin::Windows:
      return "The error surfaced in " + module +
             ", a Windows file. This usually means the app itself, or "
             "something running inside it, caused it.";
    case FaultingModuleOrigin::Driver:
      return "The error happened in " + module + ", part of a device driver" +
             (company.empty() ? std::string()
                              : " from " + std::string(company)) +
             ".";
    case FaultingModuleOrigin::Other:
      return "The error happened in " + module + ", a file from " +
             (company.empty() ? std::string("another program")
                              : std::string(company)) +
             " that was loaded into the app.";
    case FaultingModuleOrigin::Unknown:
      break;
  }
  return "The error happened in " + module + ".";
}

std::string Recommendation(const ApplicationFault& fault,
                           FaultingModuleOrigin origin) {
  switch (origin) {
    case FaultingModuleOrigin::Driver:
      return "Update or reinstall the driver from the device maker's "
             "website.";
    case FaultingModuleOrigin::Other:
      return "If " + fault.module_name +
             " shows up in repeated crashes, update or remove the program it "
             "belongs to.";
    default:
      break;
  }
  if (fault.exception_code) {
    if (const ExceptionInfo* info = FindException(*fault.exception_code)) {
      return std::string(ExceptionCauseRecommendation(info->cause));
    }
  }
  return std::string(
      ExceptionCauseRecommendation(ExceptionCause::ProgramError));
}

}  // namespace

std::optional<ApplicationFault> ParseApplicationFault(
    std::string_view event_xml) {
  const auto data = ReadEventData(event_xml);
  ApplicationFault fault;
  fault.app_name = Field(data, "AppName", kFaultAppName);
  if (fault.app_name.empty()) {
    return std::nullopt;
  }
  fault.app_version = Field(data, "AppVersion", kFaultAppVersion);
  fault.app_path = Field(data, "AppPath", kFaultAppPath);
  fault.module_name = Field(data, "ModuleName", kFaultModuleName);
  fault.module_version = Field(data, "ModuleVersion", kFaultModuleVersion);
  fault.module_path = Field(data, "ModulePath", kFaultModulePath);
  // Written as hex without "0x", e.g. "c0000005".
  const auto code = ParseEventDataNumber(
      Field(data, "ExceptionCode", kFaultExceptionCode), 16);
  if (code && *code <= std::numeric_limits<std::uint32_t>::max()) {
    fault.exception_code = static_cast<std::uint32_t>(*code);
  }
  return fault;
}

std::optional<ApplicationHang> ParseApplicationHang(
    std::string_view event_xml) {
  const auto data = ReadEventData(event_xml);
  ApplicationHang hang;
  hang.app_name = Field(data, "AppName", kHangAppName);
  if (hang.app_name.empty()) {
    return std::nullopt;
  }
  hang.app_version = Field(data, "AppVersion", kHangAppVersion);
  hang.app_path = Field(data, "ExeFileName", kHangAppPath);
  return hang;
}

FaultingModuleOrigin ClassifyFaultingModule(const ApplicationFault& fault,
                                            std::string_view module_company) {
  if (IsUnknownModule(fault.module_name) || fault.module_path.empty()) {
    if (!fault.module_name.empty() &&
        EqualsIgnoreCase(fault.module_name, fault.app_name)) {
      return FaultingModuleOrigin::App;
    }
    return FaultingModuleOrigin::Unknown;
  }
  const std::string_view module_path = fault.module_path;
  if (EqualsIgnoreCase(module_path, fault.app_path)) {
    return FaultingModuleOrigin::App;
  }
  // Checked before the app folder: for Windows' own apps (explorer.exe in
  // C:\Windows) every Windows file is also "in the app's folder".
  if (IsUnderDriveFolder(module_path, kDriverStoreFolder)) {
    return FaultingModuleOrigin::Driver;
  }
  if (IsUnderDriveFolder(module_path, kWindowsFolder)) {
    return module_company.empty() ||
                   ContainsIgnoreCase(module_company, kMicrosoft)
               ? FaultingModuleOrigin::Windows
               : FaultingModuleOrigin::Other;
  }
  const std::string_view app_folder = FolderOf(fault.app_path);
  if (app_folder.empty()) {
    return FaultingModuleOrigin::Unknown;
  }
  return StartsWithIgnoreCase(module_path, app_folder)
             ? FaultingModuleOrigin::App
             : FaultingModuleOrigin::Other;
}

EventInsight ExplainApplicationFault(const ApplicationFault& fault,
                                     std::string_view module_company) {
  const FaultingModuleOrigin origin =
      ClassifyFaultingModule(fault, module_company);
  const std::string app = AppDisplayName(fault.app_name);
  EventInsight out;
  out.title = app + " Crashed";
  out.summary = app + " closed unexpectedly after " +
                ExceptionPhrase(fault.exception_code) + ". " +
                ModuleSentence(fault, origin, module_company);
  out.recommendation = Recommendation(fault, origin);
  out.action_required = true;
  out.importance = Importance::High;
  out.category = InsightCategory::Crash;
  return out;
}

EventInsight ExplainApplicationHang(const ApplicationHang& hang) {
  const std::string app = AppDisplayName(hang.app_name);
  EventInsight out;
  out.title = app + " Stopped Responding";
  out.summary = app + " stopped responding and was closed.";
  out.recommendation =
      "If this repeats, update the app and check its add-ons or plugins.";
  out.action_required = false;
  out.importance = Importance::Medium;
  out.category = InsightCategory::Crash;
  return out;
}

std::string AppDisplayName(std::string_view image_name) {
  if (image_name.size() > kExecutableExtension.size() &&
      EqualsIgnoreCase(
          image_name.substr(image_name.size() - kExecutableExtension.size()),
          kExecutableExtension)) {
    image_name.remove_suffix(kExecutableExtension.size());
  }
  return image_name.empty() ? std::string("An app") : std::string(image_name);
}

bool IsUnknownModule(std::string_view module_name) {
  return module_name.empty() || EqualsIgnoreCase(module_name, "unknown");
}

}  // namespace pulse
