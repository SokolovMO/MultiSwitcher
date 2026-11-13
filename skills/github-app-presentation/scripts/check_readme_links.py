#!/usr/bin/env python3
"""Check local Markdown/HTML links and anchors without network requests."""
from __future__ import annotations
import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

class Markup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links: list[str] = []
        self.ids: set[str] = set()
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ('id', 'name'):
            if key in attrs:
                self.ids.add(attrs[key])
        for key in ('href', 'src'):
            if attrs.get(key):
                self.links.append(attrs[key])
        if tag == 'source' and attrs.get('srcset'):
            self.links.extend(x.strip().split()[0] for x in attrs['srcset'].split(','))

def content(path: Path):
    # Fenced code examples are not rendered links or heading anchors.
    lines, fence = [], None
    for line in path.read_text(encoding='utf-8').splitlines():
        marker = re.match(r'^\s*(`{3,}|~{3,})', line)
        if marker:
            kind = marker[1][0]
            if fence is None:
                fence = kind
            elif fence == kind:
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return '\n'.join(lines)

def anchors(text: str, markup: Markup):
    result, seen = set(markup.ids), {}
    for heading in re.findall(r'^#{1,6}\s+(.+?)\s*#*\s*$', text, flags=re.M):
        label = re.sub(r'<[^>]+>', '', heading).strip().lower()
        label = re.sub(r'[^\w\- ]', '', label, flags=re.U).replace(' ', '-')
        count = seen.get(label, 0)
        seen[label] = count + 1
        result.add(label if count == 0 else f'{label}-{count}')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('files', nargs='+', help='Markdown paths relative to root')
    args = parser.parse_args()
    root, errors, checked = args.root.resolve(), [], 0
    for name in args.files:
        source = root / name
        if not source.is_file():
            errors.append(f'{name}: source file missing')
            continue
        text = content(source)
        markup = Markup(); markup.feed(text)
        links = markup.links + re.findall(r'!?\[[^\]]*\]\(<?([^\s)>]+)>?(?:\s+"[^"]*")?\)', text)
        for href in links:
            parts = urlsplit(href)
            if parts.scheme or parts.netloc or href.startswith('//'):
                continue
            checked += 1
            target = (source.parent / unquote(parts.path)).resolve() if parts.path else source
            if not target.exists():
                errors.append(f'{name}: missing {href}')
                continue
            if parts.fragment and target.suffix.lower() in ('.md', '.markdown', '.html'):
                target_text = content(target)
                target_markup = Markup(); target_markup.feed(target_text)
                fragment = unquote(parts.fragment)
                if fragment not in anchors(target_text, target_markup):
                    errors.append(f'{name}: missing anchor {href}')
    for error in errors:
        print(error, file=sys.stderr)
    print(f'Checked {checked} local references in {len(args.files)} files; {len(errors)} errors.')
    return bool(errors)

if __name__ == '__main__':
    raise SystemExit(main())
