#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/game.exe-or-macOS-alias" >&2
  exit 64
fi

target=$1
if [ ! -e "$target" ]; then
  echo "Target does not exist: $target" >&2
  exit 66
fi

description=$(file -b "$target")
case "$description" in
  *"MacOS Alias file"*)
    if ! command -v swift >/dev/null 2>&1; then
      echo "Swift is required to resolve the macOS alias: $target" >&2
      exit 69
    fi
    resolved=$(swift -e '
      import Foundation
      let source = URL(fileURLWithPath: CommandLine.arguments[1])
      guard let target = try? URL(resolvingAliasFileAt: source) else { exit(1) }
      print(target.path)
    ' "$target")
    target=$resolved
    description=$(file -b "$target")
    ;;
esac

case "$description" in
  *"PE32+"*"x86-64"*) architecture=x64 ;;
  *"PE32"*"Intel 80386"*) architecture=x86 ;;
  *) architecture=unknown ;;
esac

directory=$(dirname "$target")

echo "Resolved target: $target"
echo "PE description: $description"
echo "Recommended proxy architecture: $architecture"

inspect_file() {
  file=$1
  [ -f "$file" ] || return 0
  echo "Inspecting: $file"
  if command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1; then
    x86_64-w64-mingw32-objdump -p "$file" 2>/dev/null |
      grep -Ei 'DLL Name: (xinput|dinput|gameinput|hid|SDL)' || true
  fi
  strings -a "$file" 2>/dev/null |
    grep -Eio 'xinput(1_[0-9]|9_1_0)?\.dll|XInputGetState|GameInput|RawInput|HidD_Get[A-Za-z]+' |
    sort -fu || true
}

inspect_file "$target"
inspect_file "$directory/UnityPlayer.dll"
inspect_file "$directory/GameAssembly.dll"

anti_cheat=$(find "$directory" -maxdepth 3 -type f \
  \( -iname '*EasyAntiCheat*' -o -iname '*BattlEye*' -o -iname '*NEP*.dll' \
     -o -iname '*mhyprot*' -o -iname '*HoYoKProtect*' -o -iname 'ACE-Base*.dll' \
     -o -iname 'AntiCheatExpert*.dll' \) \
  -print 2>/dev/null | head -20)

if [ -n "$anti_cheat" ]; then
  echo "Anti-cheat-sensitive components: YES"
  echo "$anti_cheat"
  echo "Result: inspection only; do not install a proxy DLL without an explicit risk decision."
else
  echo "Anti-cheat-sensitive components: none found by filename scan"
  echo "Result: choose only an XInput DLL name observed above, then test in a backup copy first."
fi
