# pw-ci

Nightly CI builds of the Prime World battle client from the community sources
([Prime-World-Classic/prime-world-classic](https://github.com/Prime-World-Classic/prime-world-classic)),
under the Nival non-commercial license. Toolchain: VC9 (Windows SDK 7.0) to match
the precompiled vendor libraries (boost -vc90-, ACE).

Motivation: Release builds without debug assertions/traces for running the game
on macOS (CrossOver/Wine on Apple Silicon). See NerRobDog/Prime-World for code patches.
