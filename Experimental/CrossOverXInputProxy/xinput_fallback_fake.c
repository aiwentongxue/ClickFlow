#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>

#define FAKE_PACKET 0xFA11BACCu

__declspec(dllexport) DWORD WINAPI XInputGetState(DWORD user_index, XINPUT_STATE *state)
{
    if (!state) return ERROR_BAD_ARGUMENTS;
    ZeroMemory(state, sizeof(*state));
    if (user_index > 1) return ERROR_DEVICE_NOT_CONNECTED;
    state->dwPacketNumber = FAKE_PACKET + user_index;
    state->Gamepad.wButtons = XINPUT_GAMEPAD_A | XINPUT_GAMEPAD_Y;
    state->Gamepad.bLeftTrigger = 17;
    state->Gamepad.bRightTrigger = 231;
    state->Gamepad.sThumbLX = -12345;
    state->Gamepad.sThumbLY = 23456;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetStateEx(DWORD user_index, XINPUT_STATE *state)
{
    return XInputGetState(user_index, state);
}

__declspec(dllexport) void WINAPI XInputEnable(BOOL enable)
{
    (void)enable;
}

__declspec(dllexport) DWORD WINAPI XInputSetState(
    DWORD user_index, XINPUT_VIBRATION *vibration)
{
    (void)vibration;
    return user_index <= 1 ? ERROR_SUCCESS : ERROR_DEVICE_NOT_CONNECTED;
}

__declspec(dllexport) DWORD WINAPI XInputGetCapabilities(
    DWORD user_index, DWORD flags, XINPUT_CAPABILITIES *capabilities)
{
    (void)flags;
    if (!capabilities) return ERROR_BAD_ARGUMENTS;
    if (user_index > 1) return ERROR_DEVICE_NOT_CONNECTED;
    ZeroMemory(capabilities, sizeof(*capabilities));
    capabilities->Type = XINPUT_DEVTYPE_GAMEPAD;
    capabilities->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
    capabilities->Gamepad.wButtons = XINPUT_GAMEPAD_A | XINPUT_GAMEPAD_Y;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetBatteryInformation(
    DWORD user_index, BYTE device_type, XINPUT_BATTERY_INFORMATION *battery)
{
    (void)device_type;
    if (!battery) return ERROR_BAD_ARGUMENTS;
    if (user_index > 1) return ERROR_DEVICE_NOT_CONNECTED;
    battery->BatteryType = BATTERY_TYPE_WIRED;
    battery->BatteryLevel = BATTERY_LEVEL_FULL;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetKeystroke(
    DWORD user_index, DWORD reserved, PXINPUT_KEYSTROKE keystroke)
{
    (void)reserved;
    if (!keystroke) return ERROR_BAD_ARGUMENTS;
    if (user_index != XUSER_INDEX_ANY && user_index > 1)
        return ERROR_DEVICE_NOT_CONNECTED;
    ZeroMemory(keystroke, sizeof(*keystroke));
    return ERROR_EMPTY;
}
