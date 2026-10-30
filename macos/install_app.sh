#!/bin/bash
set -euo pipefail

APP_SUPPORT="${MULTISWITCHER_APP_SUPPORT:-$HOME/Library/Application Support/MultiSwitcher}"
INSTALL_BACKUPS="$APP_SUPPORT/InstallBackups"
DESTINATION="${MULTISWITCHER_DESTINATION:-/Applications/MultiSwitcher.app}"
APP_PARENT="$(/usr/bin/dirname "$DESTINATION")"

usage() {
  echo "Usage:"
  echo "  $0 install /path/to/MultiSwitcher.app"
  echo "  $0 restore BACKUP_NAME"
  exit 2
}

verify_app() {
  local app="$1"
  [[ -d "$app" ]] || { echo "App bundle not found: $app" >&2; return 1; }
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  local signature
  signature=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)
  if ! /usr/bin/grep -Fxq "Authority=MultiSwitcher Stable Code Signing" <<<"$signature"; then
    local expected_team actual_team
    expected_team=$(/usr/libexec/PlistBuddy -c 'Print :MSDeveloperTeamID' "$app/Contents/Info.plist" 2>/dev/null || true)
    actual_team=$(/usr/bin/awk -F= '/^TeamIdentifier=/ { print $2; exit }' <<<"$signature")
    [[ -n "$expected_team" && "$expected_team" == "$actual_team" ]] || {
      echo "App must use the configured MultiSwitcher Developer ID or the local stable signing identity." >&2
      return 1
    }
    /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
  fi
  local identifier
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
  [[ "$identifier" == "com.multiswitcher.app" ]] || {
    echo "Unexpected app identifier: $identifier" >&2
    return 1
  }
  /usr/bin/lipo -verify_arch arm64 "$app/Contents/MacOS/MultiSwitcher"
}

new_backup() {
  local stamp
  stamp=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
  local backup
  backup=$(/usr/bin/mktemp -d "$INSTALL_BACKUPS/$stamp.XXXXXX")
  /bin/mkdir -p "$backup/profile-state"
  /bin/chmod 700 "$INSTALL_BACKUPS" "$backup" "$backup/profile-state"
  if [[ -f "$APP_SUPPORT/profile.json" ]]; then
    /usr/bin/ditto "$APP_SUPPORT/profile.json" "$backup/profile-state/profile.json"
    : > "$backup/profile-present"
  fi
  if [[ -f "$APP_SUPPORT/profile.json.previous" ]]; then
    /usr/bin/ditto "$APP_SUPPORT/profile.json.previous" "$backup/profile-state/profile.json.previous"
  fi
  if [[ -d "$APP_SUPPORT/Backups" ]]; then
    /usr/bin/ditto "$APP_SUPPORT/Backups" "$backup/profile-state/Backups"
    : > "$backup/backups-present"
  fi
  if [[ -d "$DESTINATION" ]]; then
    # Keep rollback bundles recoverable without exposing every saved build as
    # a separate launchable app in Spotlight.
    /usr/bin/ditto "$DESTINATION" "$backup/MultiSwitcher.rollback"
    : > "$backup/app-present"
  else
    : > "$backup/app-absent"
  fi
  echo "$backup"
}

backup_app_path() {
  local backup="$1"
  if [[ -d "$backup/MultiSwitcher.rollback" ]]; then
    echo "$backup/MultiSwitcher.rollback"
  elif [[ -d "$backup/MultiSwitcher.app" ]]; then
    # Backward compatibility with backups created before rollback bundles
    # stopped using the .app extension.
    echo "$backup/MultiSwitcher.app"
  else
    return 1
  fi
}

install_app() {
  local source="$1"
  verify_app "$source"
  if /usr/bin/pgrep -x MultiSwitcher >/dev/null 2>&1; then
    echo "Quit MultiSwitcher before updating it." >&2
    return 1
  fi

  /bin/mkdir -p "$INSTALL_BACKUPS" "$APP_PARENT"
  local backup staging old
  backup=$(new_backup)
  local stamp
  stamp=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
  staging="$APP_PARENT/.MultiSwitcher-new-$stamp.app"
  old="$APP_PARENT/.MultiSwitcher-old-$stamp.app"
  /usr/bin/ditto "$source" "$staging"
  verify_app "$staging"

  local had_old=0
  local moved_old=0
  local installed=0
  rollback_install() {
    local status=$?
    if [[ "$installed" -eq 0 ]]; then
      /bin/rm -rf "$staging"
      if [[ "$moved_old" -eq 1 && -d "$old" ]]; then
        /bin/rm -rf "$DESTINATION"
        /bin/mv "$old" "$DESTINATION"
      elif [[ "$had_old" -eq 0 ]]; then
        /bin/rm -rf "$DESTINATION"
      fi
    fi
    return "$status"
  }
  trap rollback_install EXIT

  if [[ -d "$DESTINATION" ]]; then
    had_old=1
    /bin/mv "$DESTINATION" "$old"
    moved_old=1
  fi
  /bin/mv "$staging" "$DESTINATION"
  verify_app "$DESTINATION"
  installed=1
  trap - EXIT
  /bin/rm -rf "$old"
  echo "Installed: $DESTINATION"
  echo "Recovery backup: $backup"
}

restore_backup() {
  local requested="$1"
  local backup
  if [[ "$requested" = /* ]]; then
    backup="$requested"
  else
    backup="$INSTALL_BACKUPS/$requested"
  fi
  [[ -d "$backup" ]] || { echo "Backup not found: $requested" >&2; return 1; }
  local saved_app=""
  if [[ -f "$backup/app-present" ]]; then
    saved_app=$(backup_app_path "$backup") || { echo "Backup is incomplete: app bundle is missing." >&2; return 1; }
    verify_app "$saved_app"
  elif [[ ! -f "$backup/app-absent" ]]; then
    echo "This backup does not record the previous app state." >&2
    return 1
  fi
  if /usr/bin/pgrep -x MultiSwitcher >/dev/null 2>&1; then
    echo "Quit MultiSwitcher before restoring it." >&2
    return 1
  fi

  /bin/mkdir -p "$INSTALL_BACKUPS" "$APP_PARENT"
  local rollback staging old
  rollback=$(new_backup)
  local stamp
  stamp=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
  staging="$APP_PARENT/.MultiSwitcher-restore-$stamp.app"
  old="$APP_PARENT/.MultiSwitcher-current-$stamp.app"
  if [[ -f "$backup/app-present" ]]; then
    /usr/bin/ditto "$saved_app" "$staging"
    verify_app "$staging"
  fi

  local had_old=0
  local moved_old=0
  local restored=0
  rollback_restore() {
    local status=$?
    if [[ "$restored" -eq 0 ]]; then
      /bin/rm -rf "$staging"
      if [[ "$moved_old" -eq 1 && -d "$old" ]]; then
        /bin/rm -rf "$DESTINATION"
        /bin/mv "$old" "$DESTINATION"
      elif [[ "$had_old" -eq 0 ]]; then
        /bin/rm -rf "$DESTINATION"
      fi
      if [[ -f "$rollback/profile-present" ]]; then
        /usr/bin/ditto "$rollback/profile-state/profile.json" "$APP_SUPPORT/profile.json"
      else
        /bin/rm -f "$APP_SUPPORT/profile.json"
      fi
      if [[ -f "$rollback/profile-state/profile.json.previous" ]]; then
        /usr/bin/ditto "$rollback/profile-state/profile.json.previous" "$APP_SUPPORT/profile.json.previous"
      else
        /bin/rm -f "$APP_SUPPORT/profile.json.previous"
      fi
      /bin/rm -rf "$APP_SUPPORT/Backups"
      if [[ -f "$rollback/backups-present" ]]; then
        /usr/bin/ditto "$rollback/profile-state/Backups" "$APP_SUPPORT/Backups"
      fi
    fi
    return "$status"
  }
  trap rollback_restore EXIT

  if [[ -d "$DESTINATION" ]]; then
    had_old=1
    /bin/mv "$DESTINATION" "$old"
    moved_old=1
  fi
  if [[ -f "$backup/app-present" ]]; then
    /bin/mv "$staging" "$DESTINATION"
    verify_app "$DESTINATION"
  fi

  /bin/mkdir -p "$APP_SUPPORT"
  if [[ -f "$backup/profile-present" ]]; then
    /usr/bin/ditto "$backup/profile-state/profile.json" "$APP_SUPPORT/profile.json"
    if [[ -f "$backup/profile-state/profile.json.previous" ]]; then
      /usr/bin/ditto "$backup/profile-state/profile.json.previous" "$APP_SUPPORT/profile.json.previous"
    else
      /bin/rm -f "$APP_SUPPORT/profile.json.previous"
    fi
  else
    /bin/rm -f "$APP_SUPPORT/profile.json" "$APP_SUPPORT/profile.json.previous"
  fi
  /bin/rm -rf "$APP_SUPPORT/Backups"
  if [[ -f "$backup/backups-present" ]]; then
    /usr/bin/ditto "$backup/profile-state/Backups" "$APP_SUPPORT/Backups"
  fi
  restored=1
  trap - EXIT
  /bin/rm -rf "$old"
  echo "Restored app and profile from: $backup"
  echo "Rollback copy of the replaced state: $rollback"
}

[[ "$#" -ge 1 ]] || usage
case "$1" in
  install)
    [[ "$#" -eq 2 ]] || usage
    install_app "$2"
    ;;
  restore)
    [[ "$#" -eq 2 ]] || usage
    restore_backup "$2"
    ;;
  *)
    usage
    ;;
esac
