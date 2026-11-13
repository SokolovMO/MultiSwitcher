# Multi apps for Homebrew

Official third-party tap for MultiSwitcher and MultiShift. Homebrew 7+ and Apple Silicon.
MultiSwitcher requires macOS 15+; MultiShift requires macOS 14+.

## Install

```sh
brew tap SokolovMO/apps
HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew install --cask SokolovMO/apps/multiswitcher
HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew install --cask SokolovMO/apps/multishift
```

The apps are not Apple-notarized. `HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1` explicitly asks the cask to verify the code
signature and remove quarantine only from the installed app. Without this opt-in,
normal Homebrew quarantine behavior remains. Homebrew 7 removed the old
`--no-quarantine` option. Use it only if you trust this
publisher. This consent applies to both apps if named in the same command.
It does not disable Gatekeeper for other apps. Homebrew verifies each
ZIP against the SHA256 pinned in this Git repository; these checks do not provide
Apple notarization or an independent security audit.

If the app is already in Applications, do not use `--force` or delete its data.
Homebrew can adopt a byte-identical copy:

```sh
HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew install --cask --adopt SokolovMO/apps/multiswitcher
HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew install --cask --adopt SokolovMO/apps/multishift
```

If the installed copy differs, finish its work and use the application's updater
first, then retry adoption when the tap and app versions match.

## Updates

For the native update window, choose **Check for Updates** inside either app.
Sparkle verifies Ed25519 signatures and asks for confirmation before installing.
Keep the same update channel and signing keys across releases.

Homebrew can also update either app. First finish conversions and quit the app;
this path replaces the bundle without the app's native progress window.

```sh
brew update
HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew upgrade --cask SokolovMO/apps/multiswitcher SokolovMO/apps/multishift
```

Both casks declare `auto_updates true`: a blanket `brew upgrade` normally skips
them, so Homebrew and Sparkle do not independently replace a running app.
Explicitly naming the casks includes them. Versions include the build number, so
releases with the same marketing version still compare correctly.

`brew uninstall --cask …` removes the app; preferences, dictionaries and operation
history are preserved. No `zap` cleanup is defined.

## Publish a release

After publishing and checking the application's immutable release ZIP:

```sh
python3 scripts/update_casks.py
python3 -m unittest discover -s tests
brew style --cask Casks/*.rb
git diff -- Casks
git add Casks
git commit -m "chore: update app casks"
git push
```

The refresh command validates both public manifests, downloads both pinned ZIPs,
checks size and SHA256, then writes the casks. A failure leaves existing casks
unchanged. `python3 scripts/update_casks.py --check` verifies freshness without
editing. Refresh the tap after every public build; publishing an app alone does
not change the cask. Never reuse an archive URL for different bytes.
