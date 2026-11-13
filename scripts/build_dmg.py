"""Create and verify a native Finder drag-to-Applications installer."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def create(app, output, tool=None):
    app, output = Path(app).resolve(), Path(output).resolve()
    if app.name not in {'MultiShift.app', 'MultiSwitcher.app'} or not app.is_dir():
        raise ValueError('expected a MultiShift or MultiSwitcher app bundle')
    if output.exists():
        raise ValueError('refusing to overwrite a disk image')
    tool = Path(tool or ROOT / '.build/release-tools/bin/dmgbuild').resolve()
    if not tool.is_file():
        raise ValueError('Run bash scripts/prepare_dmg.sh first')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    with tempfile.TemporaryDirectory(prefix='multi-dmg-') as temporary:
        temporary = Path(temporary)
        renderer, background = temporary / 'render', temporary / 'background.tiff'
        env = dict(os.environ, DEVELOPER_DIR=os.environ.get('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer'))
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(temporary / 'cache'),
                        str(ROOT / 'scripts/dmg_background.swift'), '-o', str(renderer)], env=env, check=True)
        subprocess.run([str(renderer), app.stem, str(background)], check=True)
        settings = dict(format='UDZO', filesystem='HFS+', files=[str(app)],
                        symlinks={'Программы': '/Applications'}, background=str(background),
                        window_rect=((200, 150), (700, 520)), default_view='icon-view',
                        show_status_bar=False, show_toolbar=False, show_pathbar=False,
                        show_sidebar=False, show_tab_view=False, icon_size=120, text_size=16,
                        label_pos='bottom', arrange_by=None, scroll_position=(0, 0),
                        icon_locations={app.name: (180, 205), 'Программы': (520, 205)})
        icon_name = info.get('CFBundleIconFile', '')
        if icon_name:
            icon = app / 'Contents/Resources' / (icon_name if icon_name.endswith('.icns') else icon_name + '.icns')
            if icon.is_file():
                settings['icon'] = str(icon)
        config = temporary / 'settings.py'
        config.write_text('\n'.join(name + ' = ' + repr(value) for name, value in settings.items()) + '\n')
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(tool), '-s', str(config), f'{app.stem} {info["CFBundleShortVersionString"]}', str(output)], check=True)
    subprocess.run(['hdiutil', 'verify', str(output)], check=True)
    # Verify the actual mounted installer, including copied bundle and real shortcut.
    with tempfile.TemporaryDirectory(prefix='multi-dmg-check-') as mount:
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, str(output)], check=True)
        try:
            root = Path(mount)
            if not (root / '.DS_Store').is_file() or os.readlink(root / 'Программы') != '/Applications':
                raise ValueError('missing Finder layout or Applications shortcut')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(root / app.name)], check=True)
            subprocess.run([str(root / app.name / 'Contents/MacOS' / app.stem), '--selftest'], check=True)
        finally:
            subprocess.run(['hdiutil', 'detach', mount], check=True)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--tool', type=Path)
    args = parser.parse_args()
    print(create(args.app, args.output, args.tool))
