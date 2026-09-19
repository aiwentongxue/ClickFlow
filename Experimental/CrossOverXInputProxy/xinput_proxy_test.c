#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>
#include <stdint.h>
#include <stdio.h>

#define FAKE_PACKET 0xFA11BACCu
#define TEST_STATE_PATH L"Z:\\private\\tmp\\ClickFlow-xinput-proxy-test.state"

#pragma pack(push, 1)
typedef struct VGP_SHARED_STATE {
    uint32_t magic;
    uint16_t version;
    uint16_t size;
    uint32_t sequence;
    uint32_t connected;
    uint16_t buttons;
    uint8_t left_trigger;
    uint8_t right_trigger;
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
    uint32_t reserved;
} VGP_SHARED_STATE;
#pragma pack(pop)

static int failures = 0;

static void check(BOOL condition, const char *message)
{
    if (condition) {
        printf("PASS %s\n", message);
    } else {
        printf("FAIL %s\n", message);
        ++failures;
    }
}

static BOOL write_state(void)
{
    VGP_SHARED_STATE state = {
        0x31504756u, 1u, sizeof(VGP_SHARED_STATE), 42u, 1u,
        XINPUT_GAMEPAD_B | XINPUT_GAMEPAD_X, 64u, 192u,
        -32768, 32767, -2222, 3333, 0u
    };
    HANDLE file = CreateFileW(TEST_STATE_PATH, GENERIC_WRITE,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return FALSE;
    DWORD written = 0;
    BOOL ok = WriteFile(file, &state, sizeof(state), &written, NULL);
    CloseHandle(file);
    return ok && written == sizeof(state);
}

static BOOL age_state_file(void)
{
    HANDLE file = CreateFileW(TEST_STATE_PATH, FILE_WRITE_ATTRIBUTES,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return FALSE;
    FILETIME now;
    ULARGE_INTEGER value;
    GetSystemTimeAsFileTime(&now);
    value.LowPart = now.dwLowDateTime;
    value.HighPart = now.dwHighDateTime;
    value.QuadPart -= 4ULL * 10000000ULL;
    FILETIME old_time = {value.LowPart, value.HighPart};
    BOOL ok = SetFileTime(file, NULL, NULL, &old_time);
    CloseHandle(file);
    return ok;
}

int main(void)
{
    SetEnvironmentVariableW(L"VGAMEPAD_STATE_FILE", TEST_STATE_PATH);
    SetEnvironmentVariableW(
        L"CLICKFLOW_XINPUT_FALLBACK_DLL", L"clickflow_xinput_fallback.dll");
    DeleteFileW(TEST_STATE_PATH);

    XINPUT_STATE state;
    DWORD result = XInputGetState(0, &state);
    check(result == ERROR_SUCCESS && state.dwPacketNumber == FAKE_PACKET,
          "missing ClickFlow state uses native fallback");
    ZeroMemory(&state, sizeof(state));
    result = XInputGetState(1, &state);
    check(result == ERROR_SUCCESS && state.dwPacketNumber == FAKE_PACKET + 1u,
          "native fallback keeps additional physical user indices");

    check(write_state(), "writes fresh ClickFlow state fixture");
    ZeroMemory(&state, sizeof(state));
    result = XInputGetState(0, &state);
    check(result == ERROR_SUCCESS && state.dwPacketNumber == 42u &&
              state.Gamepad.wButtons == (XINPUT_GAMEPAD_B | XINPUT_GAMEPAD_X) &&
              state.Gamepad.bLeftTrigger == 64u && state.Gamepad.bRightTrigger == 192u,
          "fresh ClickFlow state takes ownership");

    ZeroMemory(&state, sizeof(state));
    result = XInputGetState(1, &state);
    check(result == ERROR_DEVICE_NOT_CONNECTED,
          "ClickFlow ownership exposes only synthetic user zero");

    check(age_state_file(), "ages ClickFlow state beyond heartbeat timeout");
    ZeroMemory(&state, sizeof(state));
    result = XInputGetState(0, &state);
    check(result == ERROR_SUCCESS && state.dwPacketNumber == FAKE_PACKET,
          "stale ClickFlow state returns to native fallback");

    XINPUT_CAPABILITIES capabilities;
    ZeroMemory(&capabilities, sizeof(capabilities));
    result = XInputGetCapabilities(0, 0, &capabilities);
    check(result == ERROR_SUCCESS && capabilities.Gamepad.wButtons ==
              (XINPUT_GAMEPAD_A | XINPUT_GAMEPAD_Y),
          "capability query follows native fallback");

    DeleteFileW(TEST_STATE_PATH);
    printf("%s: %d failure(s)\n", failures == 0 ? "PASS" : "FAIL", failures);
    return failures == 0 ? 0 : 1;
}
