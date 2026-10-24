#pragma once

#include <string>

namespace pulse {

/// A string from a file's version resource, such as L"CompanyName" or
/// L"FileDescription", in the resource's first language. Empty when the file
/// cannot be read or has no such string (GetFileVersionInfoW / VerQueryValueW).
[[nodiscard]] std::string QueryFileVersionString(const std::wstring& path,
                                                 const wchar_t* key);

}  // namespace pulse
