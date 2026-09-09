# Legacy WoW keyboard input

The bundled macOS Wine driver has two independent compatibility changes:

- `MapVirtualKeyEx(..., MAPVK_VK_TO_CHAR)` and `GetKeyNameText` return Latin
  uppercase A–Z for those virtual keys, as required by the Windows API.
  Character translation still follows the active macOS layout.
- An optional stable HKL avoids changing the ANSI charset expected by legacy
  WoW while switching keyboard layouts.

## Scope and configuration

Direct game launches and third-party launcher starts for WoW profiles default
`WOWSILICON_STABLE_ANSI_HKL` to `1` when the profile has no explicit value.
This default covers Vanilla, TBC, and WotLK; only WotLK 3.3.5a has been manually
verified. Generic game profiles, installers, and registry helpers do not receive
an automatic setting.

The driver enables the workaround only for the exact value `1`, without a
language whitelist. It preserves the current HKL language when enumerating
layouts and handling source changes; enumerated layout identifiers stay distinct.
When disabled, HKL handling follows the official input-source-language patch.
IME composition and non-Russian game input have not been manually verified.

To disable the HKL workaround, add this line to the profile's environment
variables:

```text
WOWSILICON_STABLE_ANSI_HKL=0
```

An explicit value overrides the launcher default. Empty values and values other
than `1` also disable the workaround. The A–Z compatibility changes stay active.

The workaround does not select an ANSI code page. For Russian input, the tested
profile uses `LANG=ru_RU.UTF-8` and `LC_ALL=ru_RU.UTF-8`; fixing HKL alone cannot
make a CP1252 process represent Cyrillic characters.

## Validation and packaging

On WotLK 3.3.5a, manual comparison found:

- official r15: chat survives RU/EN switches, but WASD fails on RU, both when
  starting with ABC and when starting with Russian;
- A–Z changes alone: WASD works on both layouts, but Russian chat becomes garbled;
- A–Z plus the stable HKL: both chat and WASD work in the tested RU/EN scenario;
  login-screen layout switching also passes on the installed build.

The published r15 runtime archive does not contain these local source patches.
Before releasing this change, rebuild and package Wine, then regenerate the
runtime artifact lock. Restoring the existing r15 archive is insufficient.

`tools/wine-runtime/keyboard-smoke.c` checks A–Z mappings and consistent HKL
language IDs through the actual Wine driver. Build it with the command in its
header and run it with a non-English locale and the workaround enabled.
Also check repeated layout switches on the login screen and in game: this smoke
test cannot detect every game-specific hang.
