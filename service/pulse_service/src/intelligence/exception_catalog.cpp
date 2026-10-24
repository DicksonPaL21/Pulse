#include "intelligence/exception_catalog.hpp"

#include <cstdio>

namespace pulse {
namespace {

// Exception codes seen in Application Error 1000 events. Values and names come
// from ntstatus.h (Windows SDK), the debugger's Specific Exceptions table
// (learn.microsoft.com/windows-hardware/drivers/debugger/specific-exceptions),
// __fastfail (learn.microsoft.com/cpp/intrinsics/fastfail), the delay-load
// exceptions (learn.microsoft.com/cpp/build/reference/error-handling-and-notification)
// and the IIS crash guide for 0xE0434352. The cause is the usual culprit, not
// a diagnosis.
constexpr ExceptionInfo kExceptions[] = {
    {0x40000015, "STATUS_FATAL_APP_EXIT", "ending itself after a fatal error",
     ExceptionCause::ProgramError},
    {0x80000003, "STATUS_BREAKPOINT",
     "reaching a breakpoint, a deliberate stop that programs use when "
     "something goes wrong",
     ExceptionCause::ProgramError},
    {0xC0000005, "STATUS_ACCESS_VIOLATION", "a memory access error",
     ExceptionCause::Memory},
    {0xC0000006, "STATUS_IN_PAGE_ERROR",
     "a read error while loading part of the program",
     ExceptionCause::DiskRead},
    {0xC0000008, "STATUS_INVALID_HANDLE",
     "using a Windows handle that was no longer valid",
     ExceptionCause::ProgramError},
    {0xC0000017, "STATUS_NO_MEMORY", "running out of memory",
     ExceptionCause::Resources},
    {0xC000001D, "STATUS_ILLEGAL_INSTRUCTION",
     "an instruction the processor could not run", ExceptionCause::Processor},
    {0xC0000025, "STATUS_NONCONTINUABLE_EXCEPTION",
     "an error it could not continue from", ExceptionCause::ProgramError},
    {0xC000008E, "STATUS_FLOAT_DIVIDE_BY_ZERO", "a division by zero",
     ExceptionCause::ProgramError},
    {0xC0000094, "STATUS_INTEGER_DIVIDE_BY_ZERO", "a division by zero",
     ExceptionCause::ProgramError},
    {0xC0000096, "STATUS_PRIVILEGED_INSTRUCTION",
     "an instruction that only Windows itself may run",
     ExceptionCause::Processor},
    {0xC00000FD, "STATUS_STACK_OVERFLOW", "running out of stack memory",
     ExceptionCause::Resources},
    {0xC0000135, "STATUS_DLL_NOT_FOUND", "not finding a DLL file it needs",
     ExceptionCause::MissingFile},
    {0xC0000139, "STATUS_ENTRYPOINT_NOT_FOUND",
     "a DLL file that lacks a function it needs", ExceptionCause::MissingFile},
    {0xC0000142, "STATUS_DLL_INIT_FAILED", "a DLL file that failed to start",
     ExceptionCause::ProgramError},
    {0xC0000374, "STATUS_HEAP_CORRUPTION", "finding its memory damaged",
     ExceptionCause::Memory},
    // Also the code of every user-mode __fastfail since Windows 8.
    {0xC0000409, "STATUS_STACK_BUFFER_OVERRUN",
     "stopping itself on purpose after detecting a serious problem",
     ExceptionCause::ProgramError},
    {0xC0000417, "STATUS_INVALID_CRUNTIME_PARAMETER",
     "passing an invalid value to the C runtime library",
     ExceptionCause::ProgramError},
    {0xC000041D, "STATUS_FATAL_USER_CALLBACK_EXCEPTION",
     "an unhandled error in code that Windows called",
     ExceptionCause::ProgramError},
    {0xC0000420, "STATUS_ASSERTION_FAILURE", "a failed internal check",
     ExceptionCause::ProgramError},
    {0xC0000428, "STATUS_INVALID_IMAGE_HASH",
     "a file whose digital signature could not be verified",
     ExceptionCause::MissingFile},
    {0xC0000602, "STATUS_FAIL_FAST_EXCEPTION",
     "stopping itself on purpose after detecting a serious problem",
     ExceptionCause::ProgramError},
    // VcppException(ERROR_SEVERITY_ERROR, ERROR_MOD_NOT_FOUND / _PROC_NOT_FOUND).
    {0xC06D007E, "VcppException(ERROR_MOD_NOT_FOUND)",
     "not finding a DLL file it needs", ExceptionCause::MissingFile},
    {0xC06D007F, "VcppException(ERROR_PROC_NOT_FOUND)",
     "a DLL file that lacks a function it needs", ExceptionCause::MissingFile},
    {0xE0434352, "CLR exception",
     "an error in its own code that it did not handle (.NET exception)",
     ExceptionCause::ProgramError},
    {0xE0434F4D, "STATUS_CLR_EXCEPTION",
     "an error in its own code that it did not handle (.NET exception)",
     ExceptionCause::ProgramError},
    {0xE06D7363, "STATUS_CPP_EH_EXCEPTION",
     "an error in its own code that it did not handle (C++ exception)",
     ExceptionCause::ProgramError},
};

}  // namespace

const ExceptionInfo* FindException(std::uint32_t code) {
  for (const auto& info : kExceptions) {
    if (info.code == code) {
      return &info;
    }
  }
  return nullptr;
}

std::string_view ExceptionCauseRecommendation(ExceptionCause cause) {
  switch (cause) {
    case ExceptionCause::Memory:
      return "Update the app. If several different apps crash with memory "
             "errors, test the memory with Windows Memory Diagnostic and "
             "undo any overclock.";
    case ExceptionCause::ProgramError:
      return "Update the app. If it keeps happening, report it to the "
             "developer with the details of this event.";
    case ExceptionCause::MissingFile:
      return "Repair or reinstall the app so that its files are complete and "
             "belong to the same version.";
    case ExceptionCause::DiskRead:
      return "Check the health of the drive the app runs from, or the network "
             "or USB drive if it runs from one.";
    case ExceptionCause::Processor:
      return "Update the app, check that it supports this processor, and "
             "undo any CPU overclock.";
    case ExceptionCause::Resources:
      return "Update the app. If memory often runs low, close other programs "
             "or let Windows manage the page file size.";
  }
  return "";
}

std::string FormatExceptionCode(std::uint32_t code) {
  char buffer[16];
  std::snprintf(buffer, sizeof(buffer), "0x%08X", code);
  return buffer;
}

}  // namespace pulse
