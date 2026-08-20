---
name: deploy-to-iphone
description: Build, sign, install, launch, and validate Tennis Clips on Matheus's connected physical iPhone. Use when asked to deploy or reinstall this repository's iOS app on the phone, especially to test a device-only fix. Do not use for simulator-only runs, TestFlight, or App Store distribution.
metadata:
  short-description: Deploy Tennis Clips to the physical iPhone
---

# Deploy Tennis Clips to iPhone

Deploy the current working tree to Matheus's physical iPhone and leave evidence that the installed app launches without a new crash.

Before acting, read [references/workflow.md](references/workflow.md) completely and follow its discovery, build, installation, and validation gates.

## Boundaries

- Treat installation and launch as mutations that require the user's request. Invoking this skill does not authorize code changes, uninstalling the app, deleting app data, changing bundle identifiers or signing teams, committing, or pushing.
- Preserve the working tree and existing device data. A dirty tree may be the intended build input; never clean or reset it.
- Discover device identifiers on every run. The Xcode destination ID and the CoreDevice ID are different identifiers for the same phone and are not interchangeable.
- Install over the existing app. Do not uninstall first unless the user explicitly accepts losing local sessions and generated videos.
- A successful build, install, and launch does not prove the requested feature works. Ask the user to exercise the device-only behavior, then check for a new crash report.
- Stop on a failed test, build, signature, or install and report the exact evidence. Retry only after a concrete state change such as unlocking the phone, trusting the Mac, enabling Developer Mode, or fixing signing; do not loop on an unchanged failure.
