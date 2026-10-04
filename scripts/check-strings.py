#!/usr/bin/env python3
"""Every L("…") key in the app must have a Russian translation, and no translation may be orphaned.
English needs no file: the key is the English text. usage: scripts/check-strings.py [--keys]"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
literal = r'"((?:[^"\\]|\\.)*)"'
used = set()
for source in (root / 'Sources/MGF').glob('*.swift'):
    used |= set(re.findall(r'\bL\(' + literal, source.read_text()))
strings = (root / 'Sources/MGF/Resources/ru.lproj/Localizable.strings')
translated = dict(re.findall(r'^' + literal + r'\s*=\s*' + literal + r';', strings.read_text() if strings.exists() else '', re.M))

if '--keys' in sys.argv:
    print('\n'.join(sorted(used)))
    sys.exit(0)
missing, orphaned = sorted(used - translated.keys()), sorted(translated.keys() - used)
# a translation must keep the placeholders of its key, in order
broken = sorted(k for k in used & translated.keys() if re.findall(r'%[@d]|%\d*\.?\d*[dfg]', k) != re.findall(r'%[@d]|%\d*\.?\d*[dfg]', translated[k]))
for title, keys in (('missing in ru', missing), ('not used by the app', orphaned), ('placeholders differ', broken)):
    for key in keys: print(f'{title}: {key}')
print(f'{len(used)} keys, {len(translated)} translated')
sys.exit(1 if missing or orphaned or broken else 0)
