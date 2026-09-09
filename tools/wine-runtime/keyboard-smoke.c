/* Build: i686-w64-mingw32-gcc keyboard-smoke.c -o keyboard-smoke.exe -luser32
 * Run with WOWSILICON_STABLE_ANSI_HKL=1 and a non-English LANG.
 * Checks the real driver; switching layouts in WoW still needs a game check.
 */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HKL layouts[256], current = GetKeyboardLayout(0);
    int count = GetKeyboardLayoutList(256, layouts), failed = 0;
    char enabled[8];
    BOOL stable = GetEnvironmentVariableA("WOWSILICON_STABLE_ANSI_HKL", enabled,
                                        sizeof(enabled)) == 1 && enabled[0] == '1';

    printf("current=%p layouts=%d stable=%d\n", current, count, stable);
    if (count <= 0) return 1;
    for (int i = 0; i < count; i++)
    {
        printf("layout[%d]=%p\n", i, layouts[i]);
        if (stable && LOWORD(layouts[i]) != LOWORD(current)) failed = 1;
    }
    for (UINT key = 'A'; key <= 'Z'; key++)
    {
        WCHAR name[8];
        UINT scan = MapVirtualKeyW(key, MAPVK_VK_TO_VSC);
        if (MapVirtualKeyW(key, MAPVK_VK_TO_CHAR) != key ||
            GetKeyNameTextW(scan << 16, name, 8) != 1 || name[0] != key)
        {
            printf("bad mapping/name: %c\n", key);
            failed = 1;
        }
    }
    puts(failed ? "FAIL" : "PASS");
    return failed;
}
