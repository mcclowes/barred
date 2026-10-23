# Publishing Barred via Homebrew

Users install with:

```bash
brew install --cask mcclowes/barred/barred
```

The fully qualified command grants trust to this cask, as described in [Homebrew's tap trust guidance](https://docs.brew.sh/Tap-Trust#installing-from-a-tap). The current v1.1.4 download requires an Apple silicon Mac and macOS 14 (Sonoma) or later.

## Existing tap

The public tap is [mcclowes/homebrew-barred](https://github.com/mcclowes/homebrew-barred). The [release workflow](../.github/workflows/release.yml) writes `Casks/barred.rb` there using the release version, ZIP checksum, and executable architectures. The root repository's `Casks/barred.rb` is an old placeholder with no usable checksum; use the generated cask in the tap.

## Release credentials

Configure these Actions secrets in the `mcclowes/barred` repository:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing the Developer ID Application certificate and its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that `.p12` file |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for that account |
| `APPLE_TEAM_ID` | Developer team ID used for signing and notarization |
| `RELEASE_TOKEN` | GitHub token able to read and update `Casks/barred.rb` in `mcclowes/homebrew-barred` |

Certificate import, signing, notarization, and the tap update run unconditionally. Missing credentials fail those steps; this workflow has no unsigned-release fallback. GitHub Release creation uses the workflow's built-in token with `contents: write`; the separate `RELEASE_TOKEN` is used for the tap.

For certificate creation, follow [Apple's Developer ID certificate guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), then export the certificate and private key as a password-protected `.p12` in Keychain Access. Encode that file locally for `DEVELOPER_ID_CERTIFICATE_BASE64`:

```bash
base64 -i Certificates.p12 | pbcopy
```

## Prepare a version

From a clean checkout with the intended release changes committed, use the existing version helper:

```bash
make bump TYPE=patch
```

Use `minor` or `major` as appropriate. The [helper](../Scripts/bump-version.sh) updates `MARKETING_VERSION` in `project.yml`, creates a version commit, and creates an annotated `vX.Y.Z` tag. It doesn't update `CURRENT_PROJECT_VERSION`; update that build number before the bump when needed. Without `PUSH=--push`, the helper leaves the commit and tag local and prints the exact push commands.

The helper accepts only `major`, `minor`, or `patch`, followed by an optional `--push`. Unsupported or empty arguments and extra operands return usage on stderr with exit status 2 before reading or changing project metadata.

Review the version commit and tag, then push the release commit and that specific tag when ready. The tag must match the app's `MARKETING_VERSION`: the workflow derives the cask version from the tag and the app version from `project.yml`. Pushing any `v*` tag starts the release workflow. `make bump TYPE=patch PUSH=--push` also pushes immediately, so use the local-only form when reviewing first.

## What the workflow publishes

The workflow runs on macOS 26 with Xcode 26 and:

1. Generates the Xcode project and runs the hosted app tests.
2. Imports the signing certificate and builds a signed Release app.
3. Submits the app for notarization, staples the ticket, and recreates `Barred.zip`.
4. Reads the ZIP checksum and executable architectures, then publishes a GitHub Release with the ZIP.
5. Writes the generated cask to the existing Homebrew tap with the version, checksum, macOS requirement, and supported architectures.
6. Attempts to delete the temporary signing keychain even if an earlier step fails.

## Verify delivery

Check the Actions result, the GitHub Release's `Barred.zip`, and the tap's generated cask. The cask's version, URL, SHA-256, and architecture requirements must match the published artifact.

The app release is published before the tap update. If that last update fails, the ZIP may already be public while Homebrew still points to the previous release. Check both before calling delivery complete.

Local `make app` packaging has its own credential handling and optional notarization; it isn't the tagged release workflow. See the [command catalog](../.clip/commands.md) for command effects and isolated helper checks.
