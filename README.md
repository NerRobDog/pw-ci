# pw-ci

Nightly CI builds of the Prime World battle client from the community sources
([Prime-World-Classic/prime-world-classic](https://github.com/Prime-World-Classic/prime-world-classic)),
under the Nival non-commercial license. Toolchain: VC9 (Windows SDK 7.0) to match
the precompiled vendor libraries (boost -vc90-, ACE).

Motivation: Release builds without debug assertions/traces for running the game
on macOS (CrossOver/Wine on Apple Silicon). See NerRobDog/Prime-World for code patches.

Licensing: two kinds of material, two sets of terms — the build system, stubs and
tooling are ours under MIT; the passages of Prime World sources quoted by the patch
steps, and the modifications made to them, are under Nival's non-commercial
LICENSING AGREEMENT (OFFER) of 5 May 2024. Non-commercial use only, and use ceases
within three calendar days of a revocation notice published by the licensor. The
game sources are not redistributed here; the build fetches them. See [LICENSE](LICENSE).
Nival is a registered trademark of NIVAL INTERNATIONAL LIMITED; this project is not
affiliated with or endorsed by Nival.

## Runtime notes (2026-09-05, first green build = run 55)

Two monolith-only startup issues, both handled in this repo, not in the game sources:

1. **Static-init order.** MSVC runs global constructors in link order; the alphabetical GLOB put
   `Client/`/`Core/` before `System/`, so `profiler3` (System/InlineProfiler3) was used before its
   constructor ran → `RtlpWaitForCriticalSection ... blocked by 0000` at startup.
   `cmake/pwci_extra.cmake` re-emits `ALL_SRCS` in the DLL dependency order from `PF.sln`.
2. **Launcher protocol.** The community `PW_Client/Game.cpp` comments out `local_game` and requires a
   `pwclassic://` protocol argument before `context->Start()`. The patch step restores the dev var and
   takes Nival's original path (`context->Start()` right away) when `local_game`/replay is set
   (marker `pwci-local`).

Artifacts: `PrimeWorld.exe` + `.pdb` + `.map` (`/Z7 /DEBUG /MAP`). Drop the exe next to the game's `Bin/`.
