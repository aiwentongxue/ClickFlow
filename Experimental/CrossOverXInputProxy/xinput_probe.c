#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>
#include <stdio.h>

int main(void)
{
    HMODULE module = GetModuleHandleW(L"xinput1_3.dll");
    if (!module) {
        printf("FAIL GetModuleHandle error=%lu\n", GetLastError());
        return 2;
    }
    WCHAR path[MAX_PATH];
    GetModuleFileNameW(module, path, MAX_PATH);
    wprintf(L"Loaded: %ls\n", path);
    for (int i = 0; i < 30; ++i) {
        XINPUT_STATE state;
        DWORD result = XInputGetState(0, &state);
        if (result == ERROR_SUCCESS) {
            printf("OK packet=%lu buttons=0x%04X LT=%u RT=%u LS=(%d,%d) RS=(%d,%d)\n",
                   state.dwPacketNumber, state.Gamepad.wButtons,
                   state.Gamepad.bLeftTrigger, state.Gamepad.bRightTrigger,
                   state.Gamepad.sThumbLX, state.Gamepad.sThumbLY,
                   state.Gamepad.sThumbRX, state.Gamepad.sThumbRY);
        } else {
            printf("DISCONNECTED error=%lu\n", result);
        }
        Sleep(100);
    }
    return 0;
}
