# Physical iPhone deployment workflow

Use this workflow from the repository root. It targets the development build installed directly by Xcode tooling, not TestFlight or App Store distribution.

## Project facts

- Project: `ios/tennis-clips.xcodeproj`
- Scheme: `TennisClips`
- Product: `TennisClips.app`
- Bundle identifier: `dev.mmonteiro.tennisclips`
- Development team: `GX94N3438K`
- Expected phone: `iPhone de Matheus`, iPhone 16 Pro
- Minimum iOS version: 17.0

`ios/project.yml` is the source configuration for XcodeGen. Do not regenerate the Xcode project merely to deploy. Regenerate only when the project is missing or the current task intentionally changed the XcodeGen specification, because generation can modify tracked project files.

## 1. Establish the input and prerequisites

Inspect the repository without altering it:

```bash
git status --short --branch
xcodebuild -version
```

Build the current working tree exactly as it stands. Do not stash, reset, clean, commit, or pull unless the user separately asks for that operation.

The phone must be connected, unlocked, trusted, and have Developer Mode enabled. Discover it through both toolchains:

```bash
xcrun devicectl list devices
xcodebuild -project ios/tennis-clips.xcodeproj \
  -scheme TennisClips \
  -showdestinations
```

Record two values:

- `CORE_DEVICE_ID`: the connected CoreDevice identifier from `devicectl`, used by every `xcrun devicectl` command.
- `XCODE_DEVICE_ID`: the physical iOS destination ID from `xcodebuild`, used by `xcodebuild -destination`.

Confirm that both rows describe `iPhone de Matheus` and that `devicectl` reports `connected`. Do not select `My Mac`, `Any iOS Device`, or a simulator. Do not assume that a previously observed ID is still valid.

If the phone is absent, ask the user to connect and unlock it, accept **Confiar neste computador**, and enable **Developer Mode** if iOS requests it. After the user confirms a change, run discovery once more. Do not repeatedly poll an unchanged disconnected state.

## 2. Record the pre-deploy crash baseline

List existing Tennis Clips crash reports before installation:

```bash
xcrun devicectl device info files \
  --device "$CORE_DEVICE_ID" \
  --domain-type systemCrashLogs \
  --subdirectory . \
  --filter 'name BEGINSWITH "TennisClips"'
```

Note the newest filename and modification time. Old reports are not evidence that the new build crashed. A post-deploy report is new only if its filename or modification time is later than this baseline.

## 3. Run the relevant test gate

Reuse valid test evidence only when it was produced after the current code changes. Otherwise run the affected suites before installing. The normal gate for changes spanning the app and core is:

```bash
swift test --package-path ios/core
```

For app tests, choose an available iOS Simulator from `-showdestinations` and run:

```bash
mktemp -d /tmp/tennis-clips-simulator-tests.XXXXXX
```

Call that path `TEST_DERIVED_DATA`, then run:

```bash
xcodebuild test \
  -project ios/tennis-clips.xcodeproj \
  -scheme TennisClips \
  -destination 'id=<SIMULATOR_ID>' \
  -derivedDataPath "$TEST_DERIVED_DATA"
```

Do not install a failing build unless the user explicitly asks to bypass the failed gate after seeing the failure.

## 4. Create a fresh signed device build

Create a unique temporary derived-data directory and keep its absolute path:

```bash
mktemp -d /tmp/tennis-clips-device.XXXXXX
```

Call that path `DEPLOY_DERIVED_DATA`, then build for the discovered physical destination:

```bash
xcodebuild \
  -project ios/tennis-clips.xcodeproj \
  -scheme TennisClips \
  -configuration Debug \
  -destination "id=$XCODE_DEVICE_ID" \
  -derivedDataPath "$DEPLOY_DERIVED_DATA" \
  DEVELOPMENT_TEAM=GX94N3438K \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

Do not treat early package-resolution or compilation output as success. Wait for exit code 0 and `** BUILD SUCCEEDED **`.

The expected artifact is:

```text
$DEPLOY_DERIVED_DATA/Build/Products/Debug-iphoneos/TennisClips.app
```

Before installation, validate the artifact:

```bash
test -d "$DEPLOY_DERIVED_DATA/Build/Products/Debug-iphoneos/TennisClips.app"
plutil -extract CFBundleIdentifier raw \
  "$DEPLOY_DERIVED_DATA/Build/Products/Debug-iphoneos/TennisClips.app/Info.plist"
codesign --verify --deep --strict --verbose=2 \
  "$DEPLOY_DERIVED_DATA/Build/Products/Debug-iphoneos/TennisClips.app"
codesign -d --verbose=4 \
  "$DEPLOY_DERIVED_DATA/Build/Products/Debug-iphoneos/TennisClips.app"
```

The bundle identifier must be `dev.mmonteiro.tennisclips`, the signature must be valid, and the team must be `GX94N3438K`. If signing fails, do not change the bundle identifier, team, entitlements, or project configuration as a deployment workaround. Report the signing error and ask the user to resolve the Apple account, certificate, or provisioning state in Xcode.

## 5. Install without deleting device data

Install the built bundle over the current app:

```bash
xcrun devicectl device install app \
  --device "$CORE_DEVICE_ID" \
  "$DEPLOY_DERIVED_DATA/Build/Products/Debug-iphoneos/TennisClips.app"
```

Require exit code 0 and verify that the output reports:

```text
bundleID: dev.mmonteiro.tennisclips
```

This preserves the app's data container, including existing sessions and generated videos. Never uninstall as a routine recovery step.

## 6. Launch and verify basic health

Launch the new build in the foreground, terminating only an existing process instance:

```bash
xcrun devicectl device process launch \
  --device "$CORE_DEVICE_ID" \
  --terminate-existing \
  dev.mmonteiro.tennisclips
```

After a short settling period, verify that the main process is still present:

```bash
xcrun devicectl device info processes \
  --device "$CORE_DEVICE_ID" \
  --filter 'executable.path CONTAINS "TennisClips"'
```

The main `TennisClips.app/TennisClips` process is the required evidence. The Live Activity extension may also appear, but it does not substitute for the main process.

Repeat the crash-report listing from step 2. There must be no report newer than the recorded baseline. Report separately:

- signed build succeeded;
- installation succeeded;
- main process remained active;
- no new crash report appeared during launch.

## 7. Validate the requested behavior on the phone

Physical-device-only flows need human interaction. Tell the user exactly which behavior is ready to test and leave the app open. Do not claim the feature passed merely because the app launched.

After the user reproduces the flow, check the process list and crash reports again. If the behavior succeeds and no new report exists, state that device validation passed. If the app exits or a new report appears, collect the newest report:

```bash
xcrun devicectl device copy from \
  --device "$CORE_DEVICE_ID" \
  --domain-type systemCrashLogs \
  --source '<NEW_CRASH_REPORT>.ips' \
  --destination '/tmp/<NEW_CRASH_REPORT>.ips'
```

Inspect and symbolicate that report against the exact build before proposing a fix. Do not attribute an old report to the current build.

For a reproducible crash with no `.ips` yet, relaunch with an attached console and ask the user to repeat the action while the command is running:

```bash
xcrun devicectl device process launch \
  --device "$CORE_DEVICE_ID" \
  --terminate-existing \
  --console \
  dev.mmonteiro.tennisclips
```

The console command waits until the app exits. Keep the user updated during a long capture and stop after one useful reproduction instead of repeatedly crashing the app.

## Handoff checklist

At the end, give a concise, evidence-based handoff containing:

- which working-tree revision or uncommitted changes were built;
- physical device name and model;
- test results used as the gate;
- build, signing, installation, and launch outcomes;
- whether the app data was preserved;
- whether a new crash report appeared;
- the exact manual behavior still awaiting the user's test, if any;
- confirmation that no commit or push was performed unless separately requested.
