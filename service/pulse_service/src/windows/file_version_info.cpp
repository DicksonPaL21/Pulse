#include "windows/file_version_info.hpp"

#include "windows/wevt_helpers.hpp"

#include <cstdint>
#include <cwchar>
#include <vector>

#include <winver.h>

namespace pulse {

std::string QueryFileVersionString(const std::wstring& path,
                                   const wchar_t* key) {
  DWORD unused = 0;
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &unused);
  if (size == 0) {
    return {};
  }
  std::vector<std::uint8_t> data(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    return {};
  }

  struct LanguageAndCodePage {
    WORD language;
    WORD code_page;
  };
  LanguageAndCodePage* translation = nullptr;
  UINT translation_size = 0;
  if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<LPVOID*>(&translation),
                      &translation_size) ||
      translation == nullptr ||
      translation_size < sizeof(LanguageAndCodePage)) {
    return {};
  }
  wchar_t sub_block[96];
  swprintf_s(sub_block, L"\\StringFileInfo\\%04x%04x\\%s",
             translation[0].language, translation[0].code_page, key);
  wchar_t* value = nullptr;
  UINT value_size = 0;
  if (!VerQueryValueW(data.data(), sub_block, reinterpret_cast<LPVOID*>(&value),
                      &value_size) ||
      value == nullptr || value_size <= 1) {
    return {};
  }
  std::string text = wevt::WideToUtf8(value);
  const auto first = text.find_first_not_of(" \t");
  const auto last = text.find_last_not_of(" \t");
  return first == std::string::npos ? std::string()
                                    : text.substr(first, last - first + 1);
}

}  // namespace pulse
