#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace pulse {

/// What an application exception code usually points at.
enum class ExceptionCause : std::uint8_t {
  /// Bad memory access or a damaged heap.
  Memory,
  /// The program detected a problem itself and stopped (fail fast, abort,
  /// assertion, unhandled C++ or .NET exception).
  ProgramError,
  /// A DLL the program needs is missing or the wrong version.
  MissingFile,
  /// Part of the program could not be read from disk or the network.
  DiskRead,
  /// The processor refused an instruction.
  Processor,
  /// Out of memory or out of stack.
  Resources,
};

/// An exception code Pulse can name and explain.
struct ExceptionInfo {
  std::uint32_t code = 0;
  /// Symbolic name from ntstatus.h, or the name Microsoft documents the code
  /// under when it has no symbol.
  std::string_view name;
  /// Plain-language phrase that completes "closed after ...".
  std::string_view meaning;
  ExceptionCause cause = ExceptionCause::ProgramError;
};

/// Common exception codes from Application Error 1000 events, or nullptr when
/// the code is not in the catalog.
[[nodiscard]] const ExceptionInfo* FindException(std::uint32_t code);

/// What the user can check next for a cause.
[[nodiscard]] std::string_view ExceptionCauseRecommendation(
    ExceptionCause cause);

/// "0xC0000005" — the eight-digit form Windows shows exception codes in.
[[nodiscard]] std::string FormatExceptionCode(std::uint32_t code);

}  // namespace pulse
