# Publishing Barman via Homebrew

Users install with:

```bash
brew tap mcclowes/barman
brew install --cask barman
```

## Setup

### 1. Create the tap repo

```bash
gh repo create mcclowes/homebrew-barman --public --clone
cp Casks/barman.rb homebrew-barman/Casks/barman.rb
cd homebrew-barman && git add . && git commit -m "Add barman cask" && git push
```

### 2. Add GitHub secrets

Add these to the `barman` repo (Settings > Secrets and variables > Actions):

| Secret | Description |
|---|---|
| `CERTIFICATE_P12` | Base64-encoded `.p12` of your Developer ID Application cert (`base64 -i cert.p12 \| pbcopy`) |
| `CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `DEVELOPER_ID_APPLICATION` | Full identity string, e.g. `Developer ID Application: Max Clowes (ABCDE12345)` |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_ID_PASSWORD` | App-specific password — generate at [appleid.apple.com](https://appleid.apple.com) > Sign-In and Security > App-Specific Passwords |
| `APPLE_TEAM_ID` | Your 10-character team ID (visible in Apple Developer portal) |
| `HOMEBREW_TAP_TOKEN` | A GitHub personal access token with push access to `mcclowes/homebrew-barman` |

All signing/notarization secrets are optional. Without them, the release still works but produces an unsigned build (users must run `xattr -cr /Applications/Barman.app` after install).

### 3. Create a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

The GitHub Actions workflow (`.github/workflows/release.yml`) will automatically:

1. Build the app on a macOS runner
2. Sign and notarize (if secrets are configured)
3. Create a GitHub Release with `Barman.zip`
4. Update the cask SHA and version in `homebrew-barman` (if `HOMEBREW_TAP_TOKEN` is set)

## Getting a Developer ID certificate

1. Enrol in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/yr)
2. In Xcode: Settings > Accounts > Manage Certificates > + > Developer ID Application
3. Export the certificate as `.p12` from Keychain Access
4. Base64-encode it: `base64 -i Certificates.p12 | pbcopy`

## Updating

Just push a new tag. The workflow handles everything:

```bash
git tag v0.2.0
git push origin v0.2.0
```
