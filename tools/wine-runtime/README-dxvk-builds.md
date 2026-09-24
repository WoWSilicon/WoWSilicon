# DXVK builds used by WoWSilicon

WoWSilicon bundles separate Direct3D 9 builds for the two Vulkan drivers:

- `Patching/d9vk/d3d9.dll` is the macOS D9VK 1.10.3 build for MoltenVK,
  with the hardware cursor scaling patch from `tairasu/d9vk` commit `7437b616`.
- `Patching/dxvk-kosmickrisp/d3d9.dll` is the stripped patched DXVK 3.1
  build for KosmicKrisp, with `dxvk-3.1-cursor-scale.patch` applied.

WoWSilicon installs the matching file as the game's `d3d9.dll` before launch.

The experimental DXVK 3.1 source tree lives at:

    /Users/marco/VSCode/dxvk-kosmickrisp-3.1

The KosmicKrisp compatibility patch is tracked as
`tools/wine-runtime/dxvk-3.1-kosmickrisp.patch`. The cursor patch applies on
top of it. Both DLLs read `d3d9.enlargeHardwareCursor` from `dxvk.conf`;
the launcher writes this setting for cursor sizes 2 and 4.

## Compact release packaging

From the DXVK 3.1 checkout, apply the cursor patch after the KosmicKrisp
compatibility patch, then build D3D9:

```sh
patch -p1 < ../WoWSilicon/tools/wine-runtime/dxvk-3.1-cursor-scale.patch
meson setup --cross-file build-win32.txt --buildtype release build.w32
ninja -C build.w32 src/d3d9/d3d9.dll
cp build.w32/src/d3d9/d3d9.dll \
  ../WoWSilicon/Sources/WoWSiliconSwift/Resources/Patching/dxvk-kosmickrisp/d3d9.dll
i686-w64-mingw32-strip --strip-all \
  ../WoWSilicon/Sources/WoWSiliconSwift/Resources/Patching/dxvk-kosmickrisp/d3d9.dll
make -C ../WoWSilicon bundle
```
