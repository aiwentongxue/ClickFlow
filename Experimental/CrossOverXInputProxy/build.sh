#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out="$root/build"

build_architecture() {
  compiler=$1
  directory=$2
  mkdir -p "$directory"
  for name in xinput1_1 xinput1_2 xinput1_3 xinput1_4 xinput9_1_0; do
    "$compiler" -std=c11 -O2 -Wall -Wextra -Werror -shared \
      "$root/xinput_proxy.c" "$root/xinput_proxy.def" \
      -Wl,--enable-stdcall-fixup \
      -Wl,--out-implib,"$directory/lib${name}_proxy.a" \
      -o "$directory/$name.dll"
  done
  "$compiler" -std=c11 -O2 -Wall -Wextra -Werror \
    "$root/xinput_probe.c" "$directory/libxinput1_3_proxy.a" \
    -o "$directory/xinput_probe.exe"
  "$compiler" -std=c11 -O2 -Wall -Wextra -Werror -shared \
    "$root/xinput_fallback_fake.c" -Wl,--kill-at \
    -o "$directory/clickflow_xinput_fallback.dll"
  "$compiler" -std=c11 -O2 -Wall -Wextra -Werror \
    "$root/xinput_proxy_test.c" "$directory/libxinput1_3_proxy.a" \
    -o "$directory/xinput_proxy_test.exe"
}

build_architecture x86_64-w64-mingw32-gcc "$out/x64"
build_architecture i686-w64-mingw32-gcc "$out/x86"

echo "Built x64 and x86 XInput proxy variants under $out"
