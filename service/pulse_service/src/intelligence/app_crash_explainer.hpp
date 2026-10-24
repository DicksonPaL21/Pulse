#pragma once

#include "intelligence/event_intelligence.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace pulse {

/// Where the file an app crashed in comes from.
enum class FaultingModuleOrigin : std::uint8_t {
  /// No path to judge by (older event format) or no module at all.
  Unknown,
  /// The app's own program file or another file in its folder.
  App,
  /// A Microsoft file under the Windows folder.
  Windows,
  /// Part of a device driver (Windows\System32\DriverStore).
  Driver,
  /// A file from another program that was loaded into the app.
  Other,
};

/// The fields of an Application Error 1000 event that explain a crash.
struct ApplicationFault {
  std::string app_name;  // "Discord.exe"
  std::string app_version;
  std::string app_path;  // Empty on Windows builds that do not record it.
  std::string module_name;  // "nvwgf2umx.dll"; "unknown" when Windows could not tell.
  std::string module_version;
  std::string module_path;
  std::optional<std::uint32_t> exception_code;
};

/// The fields of an Application Hang 1002 event.
struct ApplicationHang {
  std::string app_name;
  std::string app_version;
  std::string app_path;
};

/// Reads an Application Error 1000 event; nullopt without an app name.
/// Windows 11 names the fields; older builds list them in the same order
/// without names (the order of the event's message template).
[[nodiscard]] std::optional<ApplicationFault> ParseApplicationFault(
    std::string_view event_xml);

/// Reads an Application Hang 1002 event; nullopt without an app name.
[[nodiscard]] std::optional<ApplicationHang> ParseApplicationHang(
    std::string_view event_xml);

/// Judges the faulting module by its path. `module_company` is the
/// CompanyName from the module's version resource, or empty when unknown;
/// a non-Microsoft file under the Windows folder counts as Other.
[[nodiscard]] FaultingModuleOrigin ClassifyFaultingModule(
    const ApplicationFault& fault, std::string_view module_company);

/// "Discord Crashed" with the exception and the faulting module in plain
/// language. `module_company` as for ClassifyFaultingModule.
[[nodiscard]] EventInsight ExplainApplicationFault(
    const ApplicationFault& fault, std::string_view module_company);

[[nodiscard]] EventInsight ExplainApplicationHang(const ApplicationHang& hang);

/// "Discord" for "Discord.exe"; "An app" when the name is empty.
[[nodiscard]] std::string AppDisplayName(std::string_view image_name);

/// True when Windows could not name the faulting module.
[[nodiscard]] bool IsUnknownModule(std::string_view module_name);

}  // namespace pulse
