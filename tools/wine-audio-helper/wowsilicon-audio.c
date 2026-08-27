#define COBJMACROS
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <mmsystem.h>
#include <dsound.h>
#include <objbase.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <propsys.h>
#include <propvarutil.h>
#include <devpkey.h>
#include <stdio.h>
#include <wchar.h>

static const WCHAR driver_key[] = L"Software\\Wine\\Drivers\\winecoreaudio.drv";

static void print_utf8_field(const WCHAR *value)
{
    int length;
    char *utf8;
    WCHAR *copy;
    size_t i, count;

    if (!value) value = L"";
    count = wcslen(value);
    copy = HeapAlloc(GetProcessHeap(), 0, (count + 1) * sizeof(*copy));
    if (!copy) return;

    for (i = 0; i < count; ++i)
        copy[i] = value[i] == L'\t' || value[i] == L'\r' || value[i] == L'\n' ? L' ' : value[i];
    copy[count] = 0;

    length = WideCharToMultiByte(CP_UTF8, 0, copy, -1, NULL, 0, NULL, NULL);
    if (!length)
    {
        HeapFree(GetProcessHeap(), 0, copy);
        return;
    }

    utf8 = HeapAlloc(GetProcessHeap(), 0, length);
    if (utf8 && WideCharToMultiByte(CP_UTF8, 0, copy, -1, utf8, length, NULL, NULL))
        fwrite(utf8, 1, length - 1, stdout);

    HeapFree(GetProcessHeap(), 0, utf8);
    HeapFree(GetProcessHeap(), 0, copy);
}

static int list_devices(EDataFlow flow, char row_type)
{
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDeviceCollection *collection = NULL;
    UINT count = 0, i;
    HRESULT hr;
    int result = 1;

    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
            &IID_IMMDeviceEnumerator, (void **)&enumerator);
    if (FAILED(hr))
    {
        fprintf(stderr, "Could not create the Wine audio device enumerator (0x%08lx).\n", hr);
        goto done;
    }

    hr = IMMDeviceEnumerator_EnumAudioEndpoints(enumerator, flow,
            DEVICE_STATE_ACTIVE, &collection);
    if (FAILED(hr))
    {
        fprintf(stderr, "Could not enumerate Wine audio devices (0x%08lx).\n", hr);
        goto done;
    }

    hr = IMMDeviceCollection_GetCount(collection, &count);
    if (FAILED(hr)) goto done;

    for (i = 0; i < count; ++i)
    {
        IMMDevice *device = NULL;
        IPropertyStore *store = NULL;
        PROPVARIANT friendly_name;
        WCHAR *id = NULL;

        PropVariantInit(&friendly_name);
        if (FAILED(IMMDeviceCollection_Item(collection, i, &device))) continue;
        if (FAILED(IMMDevice_GetId(device, &id))) goto next;
        if (FAILED(IMMDevice_OpenPropertyStore(device, STGM_READ, &store))) goto next;
        IPropertyStore_GetValue(store, (const PROPERTYKEY *)&DEVPKEY_Device_FriendlyName,
                &friendly_name);

        if (row_type) fprintf(stdout, "%c\t", row_type);
        print_utf8_field(id);
        fputc('\t', stdout);
        print_utf8_field(friendly_name.vt == VT_LPWSTR ? friendly_name.pwszVal : id);
        fputc('\n', stdout);

next:
        PropVariantClear(&friendly_name);
        if (store) IPropertyStore_Release(store);
        CoTaskMemFree(id);
        IMMDevice_Release(device);
    }
    result = 0;

done:
    if (collection) IMMDeviceCollection_Release(collection);
    if (enumerator) IMMDeviceEnumerator_Release(enumerator);
    return result;
}

static int set_device(const WCHAR *value_name, const WCHAR *id)
{
    HKEY key;
    LONG status;

    status = RegCreateKeyExW(HKEY_CURRENT_USER, driver_key, 0, NULL, 0,
            KEY_SET_VALUE, NULL, &key, NULL);
    if (status != ERROR_SUCCESS)
    {
        fprintf(stderr, "Could not open Wine audio settings (%ld).\n", status);
        return 1;
    }

    if (id && *id)
        status = RegSetValueExW(key, value_name, 0, REG_SZ,
                (const BYTE *)id, (DWORD)((wcslen(id) + 1) * sizeof(*id)));
    else
    {
        status = RegDeleteValueW(key, value_name);
        if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
    }
    RegCloseKey(key);

    if (status != ERROR_SUCCESS)
    {
        fprintf(stderr, "Could not update Wine's default audio device (%ld).\n", status);
        return 1;
    }
    return 0;
}

static int print_details(void)
{
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDevice *device = NULL;
    IPropertyStore *store = NULL;
    IAudioClient *client = NULL;
    PROPVARIANT friendly_name;
    WAVEFORMATEX *format = NULL;
    HRESULT hr;
    int result = 1;

    PropVariantInit(&friendly_name);
    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
            &IID_IMMDeviceEnumerator, (void **)&enumerator);
    if (FAILED(hr)) goto done;
    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(enumerator, eRender, eMultimedia, &device);
    if (FAILED(hr)) goto done;
    hr = IMMDevice_OpenPropertyStore(device, STGM_READ, &store);
    if (FAILED(hr)) goto done;
    IPropertyStore_GetValue(store, (const PROPERTYKEY *)&DEVPKEY_Device_FriendlyName,
            &friendly_name);
    hr = IMMDevice_Activate(device, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client);
    if (FAILED(hr)) goto done;
    hr = IAudioClient_GetMixFormat(client, &format);
    if (FAILED(hr)) goto done;

    fputs("D\t", stdout);
    print_utf8_field(friendly_name.vt == VT_LPWSTR ? friendly_name.pwszVal : L"");
    fprintf(stdout, "\t%u\t%lu\t%u\n", format->nChannels,
            format->nSamplesPerSec, format->wBitsPerSample);
    result = 0;

done:
    CoTaskMemFree(format);
    PropVariantClear(&friendly_name);
    if (client) IAudioClient_Release(client);
    if (store) IPropertyStore_Release(store);
    if (device) IMMDevice_Release(device);
    if (enumerator) IMMDeviceEnumerator_Release(enumerator);
    return result;
}

static int test_output(void)
{
    IDirectSound8 *sound = NULL;
    IDirectSoundBuffer *buffer = NULL;
    WAVEFORMATEX format = {0};
    DSBUFFERDESC desc = {0};
    void *part1 = NULL, *part2 = NULL;
    DWORD size1 = 0, size2 = 0, frame, frames;
    short *samples;
    HRESULT hr;
    int result = 1;

    hr = DirectSoundCreate8(NULL, &sound, NULL);
    if (FAILED(hr)) goto done;
    hr = IDirectSound8_SetCooperativeLevel(sound, GetDesktopWindow(), DSSCL_NORMAL);
    if (FAILED(hr)) goto done;

    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 2;
    format.nSamplesPerSec = 44100;
    format.wBitsPerSample = 16;
    format.nBlockAlign = 4;
    format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
    frames = format.nSamplesPerSec;

    desc.dwSize = sizeof(desc);
    desc.dwFlags = DSBCAPS_GLOBALFOCUS;
    desc.dwBufferBytes = frames * format.nBlockAlign;
    desc.lpwfxFormat = &format;
    hr = IDirectSound8_CreateSoundBuffer(sound, &desc, &buffer, NULL);
    if (FAILED(hr)) goto done;
    hr = IDirectSoundBuffer_Lock(buffer, 0, desc.dwBufferBytes,
            &part1, &size1, &part2, &size2, 0);
    if (FAILED(hr) || part2) goto done;

    samples = part1;
    for (frame = 0; frame < frames; ++frame)
    {
        short tone = ((frame * 660 / format.nSamplesPerSec) & 1) ? 3500 : -3500;
        samples[frame * 2] = frame < frames * 2 / 5 ? tone : 0;
        samples[frame * 2 + 1] = frame > frames * 3 / 5 ? tone : 0;
    }
    IDirectSoundBuffer_Unlock(buffer, part1, size1, part2, size2);
    part1 = NULL;
    hr = IDirectSoundBuffer_Play(buffer, 0, 0, 0);
    if (FAILED(hr)) goto done;
    Sleep(1100);
    result = 0;

done:
    if (part1) IDirectSoundBuffer_Unlock(buffer, part1, size1, part2, size2);
    if (buffer) IDirectSoundBuffer_Release(buffer);
    if (sound) IDirectSound8_Release(sound);
    return result;
}

int wmain(int argc, WCHAR **argv)
{
    HRESULT hr;
    int result;

    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(hr))
    {
        fprintf(stderr, "Could not initialize COM (0x%08lx).\n", hr);
        return 1;
    }

    if (argc == 2 && !wcscmp(argv[1], L"list"))
        result = list_devices(eRender, 0);
    else if (argc == 2 && !wcscmp(argv[1], L"snapshot"))
        result = list_devices(eRender, 'O') || list_devices(eCapture, 'I') || print_details();
    else if (argc == 3 && !wcscmp(argv[1], L"set"))
        result = set_device(L"DefaultOutput", argv[2]);
    else if (argc == 2 && !wcscmp(argv[1], L"clear"))
        result = set_device(L"DefaultOutput", NULL);
    else if (argc == 3 && !wcscmp(argv[1], L"set-input"))
        result = set_device(L"DefaultInput", argv[2]);
    else if (argc == 2 && !wcscmp(argv[1], L"clear-input"))
        result = set_device(L"DefaultInput", NULL);
    else if (argc == 2 && !wcscmp(argv[1], L"test"))
        result = test_output();
    else
    {
        fprintf(stderr, "Usage: wowsilicon-audio.exe snapshot | list | set <id> | clear | set-input <id> | clear-input | test\n");
        result = 2;
    }

    CoUninitialize();
    return result;
}
