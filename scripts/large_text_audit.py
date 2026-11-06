#!/usr/bin/env python3
"""Spec 1 W10a: the large-text audit.

Runs the given Flutter test paths with the phone's text size at SCALE on a
390 x 844 phone (test/flutter_test_config.dart's LARGE_TEXT_AUDIT hook) and
lists every layout overflow by the widget that overflowed (file:line), with
how many tests hit it and one of them. Games sites, surfaces outside the
audit (they keep 1.0) and test-only sites are listed apart (below).

  python3 scripts/large_text_audit.py --scale 2.0 test/features/opinions
  python3 scripts/large_text_audit.py --scale 1.3 --baseline 1.0 test/features/chat

With --baseline, sites that already overflow at the baseline size are
marked "(already at <baseline>)" and don't count. Exit status 1 when any
other site outside Games overflows, else 0. Test failures other than
overflows (goldens drawn at 1.0, finders) are expected and ignored.
"""
import argparse
import collections
import json
import re
import subprocess
import sys

SITE = re.compile(
    r'A RenderFlex overflowed by ([0-9.]+) pixels on the (\w+)\.'
    r'(?:.*\n){0,4}?.*The relevant error-causing widget was:\s*\n'
    # The widget's name and its file:// location come on one line or two
    # (the log wraps by line length, so it depends on the path's length).
    r'\s*(?:\S+\s+)?\S+:file://(\S+?:\d+)')

# An overflow a test swallowed with `expect(t.takeException(), isNull)`: it is
# reported as the expectation's "Actual:" with no widget location, so it is
# keyed by the test line that caught it.
SWALLOWED = re.compile(
    r'Actual: FlutterError:<A RenderFlex overflowed by ([0-9.]+) pixels.*?\n'
    r'(?:.*\n){0,6}?.*\(file://\S*/(test/\S+?:\d+):\d+\)')


def where(path):
    """lib/... or test/... in this repo; package:<name>/... for a package."""
    m = re.search(r'/pub\.dev/([^/]+)/(.*)$', path)
    if m:
        return f'package:{m.group(1)}/{m.group(2)}'
    m = re.search(r'/packages/(flutter\w*)/lib/(.*)$', path)
    if m:
        return f'package:{m.group(1)}/{m.group(2)}'
    m = re.search(r'/((?:lib|test)/.*)$', path)
    return m.group(1) if m else path


# Listed apart, never counted as a site to fix:
# - Games files are never edited (Spec 1 section 1.5); Games routes keep 1.0.
# - Surfaces outside the W10a audit keep 1.0 through TextScalePolicy (P-9).
# - A site that overflows only in its own test, never in the app.
NOT_AUDITED = {
    'lib/features/pulse/': 'not audited: keeps 1.0 (TextScalePolicy)',
}
TEST_ONLY = {
    'lib/features/relationships/presentation/widgets/relationship_lifecycle_card.dart:131':
        'test only: the card alone on a page that does not scroll; '
        'in the app it sits in scrolling lists',
    'swallowed@test/features/chat/linkified_message_text_test.dart:364':
        'test only: a 300-character link bubble alone on a page that '
        'does not scroll; in the app it sits in the scrolling thread',
    'test/features/relationships/relationship_lifecycle_card_test.dart:161':
        'test only: the card alone on a page that does not scroll, so '
        'its last button is out of reach; in the app it sits in '
        'scrolling lists',
    'swallowed@test/features/relationships/relationship_lifecycle_card_test.dart:358':
        'own phone: the test sets 320 x 568, outside the audit phones '
        '(390 and 360 wide); the device matrix decides',
}

PROGRESS = re.compile(r'^\d\d:\d\d \+\d+(?: ~\d+)?(?: -\d+)?: (.*)$')

# A tap (or drag) that missed its widget: flutter_test prints this warning
# and the test goes on without the tap, so its flow stops early and the
# states after it are never laid out at this size. Keyed by the test line
# that made it (the warning carries a stack). A miss that also happens at
# 1.0 on the audit phone (an overlay that takes the tap) is listed apart;
# any other fails the audit (W10 batch 4 review I-1).
MISSED = re.compile(r'A call to (\w+)\(\) with finder "(.*?)" derived an '
                    r'Offset \(.*?\) that would not hit test.*?'
                    r'To silence this warning', re.S)
FRAME = re.compile(r'file://\S*?/(test/\S+?\.dart:\d+):\d+')


ROOT_CAP = []  # --root-cap: the harness's root clamp, set in main()


def run(scale, paths):
    out = subprocess.run(
        ['flutter', 'test', '--no-pub', '--reporter', 'expanded',
         f'--dart-define=LARGE_TEXT_AUDIT={scale}', *ROOT_CAP, *paths],
        capture_output=True, text=True, errors='replace')
    text = (out.stdout + out.stderr).replace('\r', '\n')
    sites = collections.defaultdict(list)
    missed = collections.defaultdict(list)
    test = ''
    ran = False
    for block in re.split(r'\n(?=\d\d:\d\d \+\d+)', text):
        m = PROGRESS.match(block.split('\n', 1)[0])
        if m:
            test = m.group(1)
            ran = ran or not test.startswith('loading ')
        for s in SITE.finditer(block):
            sites[where(s.group(3))].append((float(s.group(1)), test))
        for s in SWALLOWED.finditer(block):
            sites[f'swallowed@{s.group(2)}'].append((float(s.group(1)), test))
        for s in MISSED.finditer(block):
            frames = [f for f in FRAME.findall(s.group(0))
                      if not f.startswith('test/helpers/')]
            finder = re.sub(r'^Found \d+ widgets? with ', '',
                            s.group(2).split('\n')[0]).rstrip(': [')[:70]
            missed[frames[0] if frames else test].append(
                f'{s.group(1)} {finder}')
    # No test ran (a path that does not exist, an unsplit shell variable):
    # never report that as "0 sites".
    missing = re.search(r'Failed to load "[^"]*": Does not exist', text)
    if not ran or missing or 'No tests ran' in text:
        sys.stderr.write(text[-2000:] + '\n')
        print(f'SCALE {scale}: no tests ran (check the paths)')
        sys.exit(2)
    return sites, missed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scale', required=True)
    ap.add_argument('--baseline')
    ap.add_argument('--json', help='also write every site and the tests '
                    'that hit it to this file')
    ap.add_argument('--root-cap', help='the root clamp flow screens run '
                    'under (default: the audit size). 1.0 is what ships '
                    'until text_scale_v2 is on: only AllowLargeText '
                    'screens grow')
    ap.add_argument('paths', nargs='+')
    a = ap.parse_args()
    if a.root_cap:
        ROOT_CAP.append(f'--dart-define=LARGE_TEXT_AUDIT_ROOT_CAP={a.root_cap}')
    sites, missed = run(a.scale, a.paths)
    before = run(a.baseline, a.paths)[0] if a.baseline else {}
    if a.json:
        with open(a.json, 'w') as f:
            json.dump({k: [t for _, t in v] for k, v in sites.items()}, f,
                      indent=1, sort_keys=True)
    failing = 0
    for site in sorted(sites):
        hits = sites[site]
        worst = max(px for px, _ in hits)
        note = ''
        not_audited = [v for k, v in NOT_AUDITED.items() if site.startswith(k)]
        if site.startswith('lib/features/games/'):
            note = ' (Games: never edited)'
        elif not_audited:
            note = f' ({not_audited[0]})'
        elif site in TEST_ONLY:
            note = f' ({TEST_ONLY[site]})'
        elif site in before:
            note = f' (already at {a.baseline})'
        else:
            failing += 1
        example = re.sub(r'^.*?(?=test/)', '', hits[0][1])[:160]
        print(f'{len(hits):4d} {site} up to {worst:.0f}px{note}')
        print(f'       e.g. {example}')
    # Misses that also happen at 1.0: rerun only the files they are in.
    at_one = {}
    if missed and float(a.scale) != 1.0:
        files = sorted({m.rsplit(':', 1)[0] for m in missed
                        if m.startswith('test/')})
        if files:
            at_one = run('1.0', files)[1]
    misses = 0
    for m in sorted(missed):
        note = (f' ({TEST_ONLY[m]})' if m in TEST_ONLY
                else ' (already at 1.0)' if m in at_one else '')
        misses += 0 if note else len(missed[m])
        print(f'{len(missed[m]):4d} missed tap(s): {m} {missed[m][0]}{note}')
    cap = f' (root clamp {a.root_cap})' if a.root_cap else ''
    print(f'SCALE {a.scale}{cap}: {failing} site(s) to fix, '
          f'{len(sites) - failing} listed apart'
          + (f', {misses} missed tap(s)' if misses else ''))
    sys.exit(1 if failing or misses else 0)


if __name__ == '__main__':
    main()
