#define COBJMACROS
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <objbase.h>
#include <initguid.h>
#include <mmdeviceapi.h>
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

static int list_devices(void)
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

    hr = IMMDeviceEnumerator_EnumAudioEndpoints(enumerator, eRender,
            DEVICE_STATE_ACTIVE, &collection);
    if (FAILED(hr))
    {
        fprintf(stderr, "Could not enumerate Wine audio outputs (0x%08lx).\n", hr);
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

static int set_device(const WCHAR *id)
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
        status = RegSetValueExW(key, L"DefaultOutput", 0, REG_SZ,
                (const BYTE *)id, (DWORD)((wcslen(id) + 1) * sizeof(*id)));
    else
    {
        status = RegDeleteValueW(key, L"DefaultOutput");
        if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
    }
    RegCloseKey(key);

    if (status != ERROR_SUCCESS)
    {
        fprintf(stderr, "Could not update Wine's default audio output (%ld).\n", status);
        return 1;
    }
    return 0;
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
        result = list_devices();
    else if (argc == 3 && !wcscmp(argv[1], L"set"))
        result = set_device(argv[2]);
    else if (argc == 2 && !wcscmp(argv[1], L"clear"))
        result = set_device(NULL);
    else
    {
        fprintf(stderr, "Usage: wowsilicon-audio.exe list | set <endpoint-id> | clear\n");
        result = 2;
    }

    CoUninitialize();
    return result;
}
