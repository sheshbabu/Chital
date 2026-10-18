---
name: release
description: Bump Chital's version, commit it, archive and export the app to Downloads, and draft GitHub release notes. Use when the user runs /release or asks to cut a release.
argument-hint: "[version, defaults to the next minor version]"
---

# Release Chital

Run these steps in order and stop at the first failure.

## 1. Check the starting state
- `git status --short` must be empty and the branch must be `main`. If not, stop and tell the user, since the release commit should hold only the version bump.
- Read the current version: `grep -m1 MARKETING_VERSION Chital.xcodeproj/project.pbxproj`.
- The new version is the argument if one was given, otherwise the current one with the minor part bumped (1.8 becomes 1.9).
- The previous release is the latest tag: `git describe --tags --abbrev=0`.

## 2. Bump the version and commit
- `sed -i '' 's/MARKETING_VERSION = <old>;/MARKETING_VERSION = <new>;/' Chital.xcodeproj/project.pbxproj`, then check that both the Debug and Release lines changed. Leave `CURRENT_PROJECT_VERSION` alone.
- Commit only that file, with the bare version as the message, as in `402e442 1.7`: `git commit -m "<new>" Chital.xcodeproj/project.pbxproj`. No body.
- Don't tag or push. The user does that after checking the build.

## 3. Archive and export
This matches Xcode > Product > Archive > Distribute App > Custom > Copy App, which only copies the signed app out of the archive.
```
STAMP=$(date "+%Y-%m-%d %H-%M-%S")
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Chital $STAMP.xcarchive"
xcodebuild archive -scheme Chital -configuration Release -archivePath "$ARCHIVE" 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"
OUT="$HOME/Downloads/Chital $STAMP"
mkdir -p "$OUT" && ditto "$ARCHIVE/Products/Applications/Chital.app" "$OUT/Chital.app"
```
- The archive goes in Xcode's folder so it shows in the Organizer.
- Verify the export:
  - `defaults read "$OUT/Chital.app/Contents/Info" CFBundleShortVersionString` prints the new version.
  - `codesign --verify --deep --strict "$OUT/Chital.app"` passes.
  - `codesign -dvv "$OUT/Chital.app"` shows the Apple Development authority and `flags=0x10000(runtime)`.
  - `lipo -archs` on the binary lists `x86_64 arm64`.
  - `du -sh` shows the app size. The README promises under 5MB for the binary, so flag the binary going over that.

## 4. Draft the release notes
- Read what changed since the previous tag: `git log <previous tag>..HEAD` and `git diff <previous tag>..HEAD -- Chital/`. Read the diff, since commit subjects are short and miss things.
- Write the notes for users, not developers. One plain line per change, with no bullets, no trailing periods, no em dashes and no file or type names. Name shortcuts as in the menu (Cmd+Shift+E).
- Use this layout, and drop a section if it would be empty:
  ```
  ### Features

  <one line per new feature or visible improvement>

  ### Bugfixes

  <one line per fix>
  ```
- Performance gains go under Bugfixes with a measured number when `notes/perf-journal.md` has one, for example "Uses about 25% less CPU while streaming".
- Skip internal changes with no visible effect, such as refactors, docs and test scripts.
- Show the notes in chat so the user can paste them into the GitHub release. Don't write them to a file.

## 5. Report
Tell the user, briefly:
- The release commit's hash and message.
- The path of the exported app, its size and the signature check result.
- The release notes.
- The commands left for them: `git tag <new> && git push origin main <new>`, then create a GitHub release for the tag and attach the zipped app.
