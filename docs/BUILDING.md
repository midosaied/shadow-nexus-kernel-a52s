# Building

All building is done by GitHub Actions: `.github/workflows/build.yml`.

## Run it

1. Fork this repository.
2. **Actions -> Build Shadow Nexus Kernel (a52sxq) -> Run workflow**.
3. Fill the inputs (defaults are the tested configuration):

| Input | Default | Meaning |
|---|---|---|
| `version` | `v1.0` | Version string used in file names |
| `kernel_repo` / `kernel_branch` | LineageOS-based sm7325 tree | Kernel source to build |
| `kernel_commit` | pinned full SHA `7a71935c...` | Pins the kernel source to the commit the tested build used, so a later upstream push cannot silently change your build. Empty = branch tip |
| `ksun_ref` | pinned commit `e5f5ec9...` | KernelSU-Next commit. setup.sh silently falls back to the default branch if the ref can't be checked out, so the workflow verifies the pin afterwards |
| `tweaks` | `true` | BBR + fq_codel default |
| `disable_userfaultfd` | `false` | Optional |
| `usb_extra` | `false` | Plain RNDIS + ECM |
| `wq_power_efficient` | `false` | **Experimental**, not in the tested build |
| `allow_abi_change` | `false` | Let the build pass even if the ABI guard fails (do not flash such a build blindly) |
| `publish_release` / `release_tag` | `false` | Publish a GitHub Release with the zips |

4. Download artifacts: the flashable kernel zip content, `ShadowNexus-Tuning-<ver>.zip`, `SHA256SUMS`, and `abi-files`.

## What the workflow does

self-tests -> dependencies -> clone kernel -> cache Proton clang -> apply patch -> add KernelSU-Next and verify pin -> configure -> build -> ABI guard -> package -> upload (-> release).

On a compile failure the log prints the first errors with context.

## Notes

- Not tested on GitHub's runners in this exact repository layout yet; expect to fix small things on the first run.
- The v1.0 workflow differs from the tested build only in the pinned KernelSU-Next ref and the optional inputs.
- Your kernel source repo must be one you are allowed to build; this repo never pushes to it.
