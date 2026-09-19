#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define VGP_MAGIC 0x31504756u
#define VGP_VERSION 1u
#define VGP_DEFAULT_PATH L"Z:\\private\\tmp\\ClickFlow.xinput"
#define VGP_STALE_FILE_100NS (3ULL * 10000000ULL)
#define VGP_FALLBACK_ENV L"CLICKFLOW_XINPUT_FALLBACK_DLL"

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

typedef char vgp_shared_state_must_be_32_bytes[(sizeof(VGP_SHARED_STATE) == 32) ? 1 : -1];

static volatile LONG input_enabled = 1;
static volatile LONG get_state_calls = 0;
static DWORD last_trace_tick = 0;
static HMODULE proxy_module = NULL;
static INIT_ONCE fallback_once = INIT_ONCE_STATIC_INIT;

typedef DWORD (WINAPI *XInputGetStateProc)(DWORD, XINPUT_STATE *);
typedef void (WINAPI *XInputEnableProc)(BOOL);
typedef DWORD (WINAPI *XInputSetStateProc)(DWORD, XINPUT_VIBRATION *);
typedef DWORD (WINAPI *XInputGetCapabilitiesProc)(DWORD, DWORD, XINPUT_CAPABILITIES *);
typedef DWORD (WINAPI *XInputGetBatteryInformationProc)(
    DWORD, BYTE, XINPUT_BATTERY_INFORMATION *);
typedef DWORD (WINAPI *XInputGetDSoundAudioDeviceGuidsProc)(DWORD, GUID *, GUID *);
typedef DWORD (WINAPI *XInputGetAudioDeviceIdsProc)(
    DWORD, LPWSTR, UINT *, LPWSTR, UINT *);
typedef DWORD (WINAPI *XInputGetKeystrokeProc)(DWORD, DWORD, PXINPUT_KEYSTROKE);

typedef struct XINPUT_FALLBACK {
    HMODULE module;
    XInputGetStateProc get_state;
    XInputGetStateProc get_state_ex;
    XInputEnableProc enable;
    XInputSetStateProc set_state;
    XInputGetCapabilitiesProc get_capabilities;
    XInputGetBatteryInformationProc get_battery_information;
    XInputGetDSoundAudioDeviceGuidsProc get_dsound_audio_device_guids;
    XInputGetAudioDeviceIdsProc get_audio_device_ids;
    XInputGetKeystrokeProc get_keystroke;
} XINPUT_FALLBACK;

static XINPUT_FALLBACK fallback = {0};

static void store_proc_address(void *destination, FARPROC proc)
{
    memcpy(destination, &proc, sizeof(proc));
}

static BOOL CALLBACK initialize_fallback(PINIT_ONCE once, PVOID parameter, PVOID *context)
{
    (void)once;
    (void)parameter;
    (void)context;

    WCHAR path[32768];
    DWORD length = GetEnvironmentVariableW(VGP_FALLBACK_ENV, path, 32768);
    if (length == 0) {
        WCHAR proxy_path[32768];
        DWORD proxy_length = GetModuleFileNameW(proxy_module, proxy_path, 32768);
        const WCHAR *name = proxy_path;
        if (proxy_length > 0 && proxy_length < 32768) {
            for (const WCHAR *cursor = proxy_path; *cursor; ++cursor) {
                if (*cursor == L'\\' || *cursor == L'/') name = cursor + 1;
            }
        }
        lstrcpyW(
            path,
            lstrcmpiW(name, L"xinput1_4.dll") == 0
                ? L"C:\\windows\\system32\\xinput1_3.dll"
                : L"C:\\windows\\system32\\xinput1_4.dll"
        );
    } else if (length >= 32768) {
        return TRUE;
    }

    HMODULE module = LoadLibraryW(path);
    if (!module || module == proxy_module ||
        GetProcAddress(module, "ClickFlowXInputProxyMarker") != NULL) {
        if (module && module != proxy_module) FreeLibrary(module);
        return TRUE;
    }

    fallback.module = module;
    store_proc_address(&fallback.get_state, GetProcAddress(module, "XInputGetState"));
    store_proc_address(&fallback.get_state_ex, GetProcAddress(module, (LPCSTR)100));
    store_proc_address(&fallback.enable, GetProcAddress(module, "XInputEnable"));
    store_proc_address(&fallback.set_state, GetProcAddress(module, "XInputSetState"));
    store_proc_address(
        &fallback.get_capabilities, GetProcAddress(module, "XInputGetCapabilities"));
    store_proc_address(
        &fallback.get_battery_information,
        GetProcAddress(module, "XInputGetBatteryInformation"));
    store_proc_address(
        &fallback.get_dsound_audio_device_guids,
        GetProcAddress(module, "XInputGetDSoundAudioDeviceGuids"));
    store_proc_address(
        &fallback.get_audio_device_ids,
        GetProcAddress(module, "XInputGetAudioDeviceIds"));
    store_proc_address(
        &fallback.get_keystroke, GetProcAddress(module, "XInputGetKeystroke"));
    return TRUE;
}

static XINPUT_FALLBACK *get_fallback(void)
{
    InitOnceExecuteOnce(&fallback_once, initialize_fallback, NULL, NULL);
    return fallback.module ? &fallback : NULL;
}

static void trace_get_state(
    DWORD user_index, DWORD result, const VGP_SHARED_STATE *state, const char *source)
{
    WCHAR path[32768];
    DWORD length = GetEnvironmentVariableW(L"CLICKFLOW_XINPUT_TRACE_FILE", path, 32768);
    if (length == 0 || length >= 32768) return;

    LONG calls = InterlockedIncrement(&get_state_calls);
    DWORD now = GetTickCount();
    if (last_trace_tick != 0 && now - last_trace_tick < 1000) return;
    last_trace_tick = now;

    HANDLE file = CreateFileW(path, FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;

    char line[256];
    int count = snprintf(
        line, sizeof(line),
        "pid=%lu calls=%ld user=%lu source=%s result=%lu sequence=%lu connected=%lu "
        "buttons=0x%04X LT=%u RT=%u LS=(%d,%d) RS=(%d,%d)\r\n",
        GetCurrentProcessId(), calls, user_index, source, result,
        (unsigned long)(state ? state->sequence : 0),
        (unsigned long)(state ? state->connected : 0),
        state ? state->buttons : 0,
        state ? state->left_trigger : 0,
        state ? state->right_trigger : 0,
        state ? state->left_x : 0,
        state ? state->left_y : 0,
        state ? state->right_x : 0,
        state ? state->right_y : 0
    );
    if (count > 0) {
        DWORD written = 0;
        WriteFile(file, line, (DWORD)count, &written, NULL);
    }
    CloseHandle(file);
}

static DWORD read_shared_state(VGP_SHARED_STATE *state)
{
    WCHAR path[32768];
    DWORD length = GetEnvironmentVariableW(L"VGAMEPAD_STATE_FILE", path, 32768);
    if (length == 0) {
        lstrcpyW(path, VGP_DEFAULT_PATH);
    } else if (length >= 32768) {
        return ERROR_BAD_PATHNAME;
    }

    HANDLE file = CreateFileW(path, GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return ERROR_DEVICE_NOT_CONNECTED;

    DWORD bytes_read = 0;
    BOOL ok = ReadFile(file, state, sizeof(*state), &bytes_read, NULL);
    FILETIME last_write;
    BOOL has_write_time = GetFileTime(file, NULL, NULL, &last_write);
    CloseHandle(file);
    if (!ok || bytes_read != sizeof(*state)) return ERROR_DEVICE_NOT_CONNECTED;
    if (has_write_time) {
        FILETIME now;
        ULARGE_INTEGER last_value;
        ULARGE_INTEGER now_value;
        GetSystemTimeAsFileTime(&now);
        last_value.LowPart = last_write.dwLowDateTime;
        last_value.HighPart = last_write.dwHighDateTime;
        now_value.LowPart = now.dwLowDateTime;
        now_value.HighPart = now.dwHighDateTime;
        if (now_value.QuadPart > last_value.QuadPart + VGP_STALE_FILE_100NS)
            return ERROR_DEVICE_NOT_CONNECTED;
    }
    if (state->magic != VGP_MAGIC || state->version != VGP_VERSION ||
        state->size != sizeof(*state) || !state->connected) {
        return ERROR_DEVICE_NOT_CONNECTED;
    }
    return ERROR_SUCCESS;
}

static DWORD get_state(DWORD user_index, XINPUT_STATE *output, BOOL include_guide)
{
    if (!output) return ERROR_BAD_ARGUMENTS;
    ZeroMemory(output, sizeof(*output));

    VGP_SHARED_STATE input = {0};
    DWORD error = read_shared_state(&input);
    if (error != ERROR_SUCCESS) {
        XINPUT_FALLBACK *native = get_fallback();
        XInputGetStateProc proc = include_guide && native && native->get_state_ex
            ? native->get_state_ex
            : (native ? native->get_state : NULL);
        DWORD result = proc ? proc(user_index, output) : ERROR_DEVICE_NOT_CONNECTED;
        trace_get_state(user_index, result, NULL, "fallback");
        return result;
    }
    if (user_index != 0) {
        trace_get_state(user_index, ERROR_DEVICE_NOT_CONNECTED, &input, "clickflow");
        return ERROR_DEVICE_NOT_CONNECTED;
    }

    output->dwPacketNumber = input.sequence;
    if (InterlockedCompareExchange(&input_enabled, 1, 1)) {
        output->Gamepad.wButtons = input.buttons;
        if (!include_guide) output->Gamepad.wButtons &= (WORD)~0x0400u;
        output->Gamepad.bLeftTrigger = input.left_trigger;
        output->Gamepad.bRightTrigger = input.right_trigger;
        output->Gamepad.sThumbLX = input.left_x;
        output->Gamepad.sThumbLY = input.left_y;
        output->Gamepad.sThumbRX = input.right_x;
        output->Gamepad.sThumbRY = input.right_y;
    }
    trace_get_state(user_index, ERROR_SUCCESS, &input, "clickflow");
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI ClickFlowXInputProxyMarker(void)
{
    return VGP_MAGIC;
}

__declspec(dllexport) DWORD WINAPI XInputGetState(DWORD user_index, XINPUT_STATE *state)
{
    return get_state(user_index, state, FALSE);
}

__declspec(dllexport) DWORD WINAPI XInputGetStateEx(DWORD user_index, XINPUT_STATE *state)
{
    return get_state(user_index, state, TRUE);
}

__declspec(dllexport) void WINAPI XInputEnable(BOOL enable)
{
    InterlockedExchange(&input_enabled, enable ? 1 : 0);
    XINPUT_FALLBACK *native = get_fallback();
    if (native && native->enable) native->enable(enable);
}

__declspec(dllexport) DWORD WINAPI XInputSetState(DWORD user_index, XINPUT_VIBRATION *vibration)
{
    VGP_SHARED_STATE input;
    if (read_shared_state(&input) == ERROR_SUCCESS) {
        if (user_index != 0) return ERROR_DEVICE_NOT_CONNECTED;
        XINPUT_FALLBACK *native = get_fallback();
        if (native && native->set_state) native->set_state(user_index, vibration);
        return ERROR_SUCCESS;
    }
    XINPUT_FALLBACK *native = get_fallback();
    return native && native->set_state
        ? native->set_state(user_index, vibration)
        : ERROR_DEVICE_NOT_CONNECTED;
}

__declspec(dllexport) DWORD WINAPI XInputGetCapabilities(
    DWORD user_index, DWORD flags, XINPUT_CAPABILITIES *capabilities)
{
    if (!capabilities) return ERROR_BAD_ARGUMENTS;
    VGP_SHARED_STATE input;
    if (read_shared_state(&input) != ERROR_SUCCESS) {
        XINPUT_FALLBACK *native = get_fallback();
        return native && native->get_capabilities
            ? native->get_capabilities(user_index, flags, capabilities)
            : ERROR_DEVICE_NOT_CONNECTED;
    }
    if (user_index != 0) return ERROR_DEVICE_NOT_CONNECTED;
    ZeroMemory(capabilities, sizeof(*capabilities));
    capabilities->Type = XINPUT_DEVTYPE_GAMEPAD;
    capabilities->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
    capabilities->Gamepad.wButtons = 0xF3FFu;
    capabilities->Gamepad.bLeftTrigger = 0xFFu;
    capabilities->Gamepad.bRightTrigger = 0xFFu;
    capabilities->Gamepad.sThumbLX = 0x7FFF;
    capabilities->Gamepad.sThumbLY = 0x7FFF;
    capabilities->Gamepad.sThumbRX = 0x7FFF;
    capabilities->Gamepad.sThumbRY = 0x7FFF;
    capabilities->Vibration.wLeftMotorSpeed = 0xFFFFu;
    capabilities->Vibration.wRightMotorSpeed = 0xFFFFu;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetBatteryInformation(
    DWORD user_index, BYTE device_type, XINPUT_BATTERY_INFORMATION *battery)
{
    if (!battery) return ERROR_BAD_ARGUMENTS;
    VGP_SHARED_STATE input;
    if (read_shared_state(&input) != ERROR_SUCCESS) {
        XINPUT_FALLBACK *native = get_fallback();
        return native && native->get_battery_information
            ? native->get_battery_information(user_index, device_type, battery)
            : ERROR_DEVICE_NOT_CONNECTED;
    }
    if (user_index != 0) return ERROR_DEVICE_NOT_CONNECTED;
    battery->BatteryType = BATTERY_TYPE_WIRED;
    battery->BatteryLevel = BATTERY_LEVEL_FULL;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetDSoundAudioDeviceGuids(
    DWORD user_index, GUID *render_guid, GUID *capture_guid)
{
    VGP_SHARED_STATE input;
    if (read_shared_state(&input) != ERROR_SUCCESS) {
        XINPUT_FALLBACK *native = get_fallback();
        return native && native->get_dsound_audio_device_guids
            ? native->get_dsound_audio_device_guids(user_index, render_guid, capture_guid)
            : ERROR_DEVICE_NOT_CONNECTED;
    }
    if (user_index != 0) return ERROR_DEVICE_NOT_CONNECTED;
    if (render_guid) ZeroMemory(render_guid, sizeof(*render_guid));
    if (capture_guid) ZeroMemory(capture_guid, sizeof(*capture_guid));
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI XInputGetAudioDeviceIds(
    DWORD user_index, LPWSTR render_id, UINT *render_count,
    LPWSTR capture_id, UINT *capture_count)
{
    VGP_SHARED_STATE input;
    if (read_shared_state(&input) != ERROR_SUCCESS) {
        XINPUT_FALLBACK *native = get_fallback();
        return native && native->get_audio_device_ids
            ? native->get_audio_device_ids(
                user_index, render_id, render_count, capture_id, capture_count)
            : ERROR_DEVICE_NOT_CONNECTED;
    }
    if (user_index != 0) return ERROR_DEVICE_NOT_CONNECTED;
    if (render_count) *render_count = 0;
    if (capture_count) *capture_count = 0;
    if (render_id) *render_id = L'\0';
    if (capture_id) *capture_id = L'\0';
    return ERROR_NOT_SUPPORTED;
}

__declspec(dllexport) DWORD WINAPI XInputGetKeystroke(
    DWORD user_index, DWORD reserved, PXINPUT_KEYSTROKE keystroke)
{
    (void)reserved;
    if (!keystroke) return ERROR_BAD_ARGUMENTS;
    VGP_SHARED_STATE input;
    if (read_shared_state(&input) != ERROR_SUCCESS) {
        XINPUT_FALLBACK *native = get_fallback();
        return native && native->get_keystroke
            ? native->get_keystroke(user_index, reserved, keystroke)
            : ERROR_DEVICE_NOT_CONNECTED;
    }
    if (user_index != XUSER_INDEX_ANY && user_index != 0)
        return ERROR_DEVICE_NOT_CONNECTED;
    ZeroMemory(keystroke, sizeof(*keystroke));
    return ERROR_EMPTY;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        proxy_module = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
