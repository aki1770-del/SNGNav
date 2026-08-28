#!/usr/bin/env python3
"""Check a draft of OUTBOUND text for claims that a five-second command would refute.

WHY THIS EXISTS
---------------
On 2026-08-27/28 every open upstream contribution we own was verified against the
projects' own sources for the first time. Eleven pull requests: PREMISE-FALSE 1,
PREMISE-PARTLY-TRUE 6, PREMISE-TRUE 4. NOT ONE WAS CLEAN.

Three of the findings are the same defect wearing different clothes, and all
three are the SENTENCE, not the code:

  ros2/rcl#1314  — our patch warns about a bare `LOCALHOST_ONLY` environment
      variable. Measured: the ROS 2 Iron Irwini release notes, 55,383 bytes
      fetched raw, contain only `ROS_LOCALHOST_ONLY`, twice. IT HAS NEVER
      EXISTED. The maintainer asked "when have we had this environment
      variable? that is not what i recall..." — 137 days ago, unanswered.

  ivi-homescreen-plugins#241 — body claims a null guard "before EVERY `*args`
      dereference across 6 plugins". Census: 35 sites, 18 guarded, camera 6 of
      23. And it carries `Fixes: #226`, which GitHub's own
      closingIssuesReferences confirms would AUTO-CLOSE the maintainer's
      security/high issue with 17 instances still live.

  ivi-homescreen-plugins#242 — body says "flatpak_shim.cc (two sites)". The file
      has 36-38. Off by ~18x. ⚑ That error UNDERSTATES our own work, so it
      deceives nobody in our favour. It is careless, not self-serving — and it
      is the same defect.

⚑ THE PATTERN: in all three the CODE WAS RIGHT AND THE CLAIM ABOUT IT WAS WRONG.
Reviews check diffs. Nothing checked the prose. A maintainer reads the prose
first, and it is the prose that spends their evening.

WHAT THIS CHECKS — four families, each drawn from a real instance above:

  COUNT       a bare number of things ("two sites", "18 call sites", "3 files")
  TOTALITY    every / all / each / none / always / never / only / entire
  IDENTIFIER  an ALL_CAPS_NAME, --flag, or `symbol` asserted to exist upstream
  AUTOCLOSE   Fixes/Closes/Resolves #N, which merges someone's issue shut

It does NOT judge whether a claim is true. It cannot. It requires that each one
carry EVIDENCE — a fenced block naming the command that was run and its output —
so the author has to have looked. That is the whole mechanism, and it is enough:
every one of the three defects above would have failed a person who was made to
paste the grep.

⚑ WHAT IT CANNOT DO, stated so nobody reads a pass as a blessing: it cannot tell
a true count from a false one, it cannot verify an identifier exists, and a
determined author can satisfy it with an irrelevant command. It raises the cost
of an unchecked sentence from zero. It does not make the sentence true.

USAGE   outbound_claim_check.py <draft.md> [--evidence <file>]
EXIT    0 every flagged claim has evidence · 1 unevidenced claims · 2 usage/read error
"""
import re, sys
from pathlib import Path

FAMILIES = [
    # ⚑ The `[:\-]?\s*` is not cosmetic. The first version required whitespace
    # DIRECTLY after the keyword, so it missed `Fixes: #226` — the real line in
    # ivi-homescreen-plugins#241, and the single most dangerous claim this tool
    # exists to catch, because merging it CLOSES a maintainer's security issue.
    # Caught by this file's own control on its first run. GitHub's linker accepts
    # the colon; a checker that does not is worse than none, because it certifies.
    ('AUTOCLOSE', re.compile(r'\b(?:fix(?:e[sd])?|close[sd]?|resolve[sd]?)\b[:\-]?\s*#\d+', re.I),
     'merging this CLOSES that issue — confirm it is fully fixed, not partly'),
    ('TOTALITY', re.compile(r'\b(?:every|all|each|none|always|never|only|entire)\b', re.I),
     'a totality claim — census the population before asserting it'),
    ('COUNT', re.compile(r'\b(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+'
                         r'(?:site|sites|call site|call sites|place|places|file|files|'
                         r'occurrence|occurrences|instance|instances|location|locations)\b', re.I),
     'a bare count — paste the command that produced it'),
    ('IDENTIFIER', re.compile(r'(?<![\w`])(?:[A-Z][A-Z0-9]{2,}(?:_[A-Z0-9]+)+|--[a-z][a-z0-9-]{2,})(?![\w`])'),
     'a named identifier asserted to exist upstream — grep their tree, not ours'),
]

EVID = re.compile(r'```[^\n]*\n(.*?)```', re.S)
CMDISH = re.compile(r'(?m)^\s*(?:\$|>|#)?\s*(?:git|grep|rg|gh|curl|sed|awk|python3?|dart|cargo|'
                    r'find|wc|md5sum|sha256sum|ls|cat|head|tail)\b')


def main():
    args = [a for a in sys.argv[1:]]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        return 2
    draft = Path(args[0])
    if not draft.is_file():
        print(f'  cannot read {draft}')
        return 2
    text = draft.read_text(encoding='utf-8', errors='replace')

    ev_text = text
    if '--evidence' in args:
        p = Path(args[args.index('--evidence') + 1])
        if not p.is_file():
            print(f'  cannot read evidence file {p}')
            return 2
        ev_text += '\n' + p.read_text(encoding='utf-8', errors='replace')

    # Evidence = fenced blocks that actually contain something command-shaped.
    blocks = [b for b in EVID.findall(ev_text) if CMDISH.search(b)]
    has_evidence = len(blocks) > 0

    # Strip fenced blocks before scanning prose: a count INSIDE the evidence is
    # the output, not a claim about it.
    prose = EVID.sub('\n', text)

    hits = []
    for line_no, line in enumerate(prose.split('\n'), 1):
        if line.lstrip().startswith('>'):
            continue                       # quoted maintainer text is theirs, not our claim
        for fam, rx, why in FAMILIES:
            for m in rx.finditer(line):
                hits.append((fam, line_no, m.group(0).strip(), line.strip()[:96], why))

    print(f'=== outbound claim check: {draft} ===')
    if not hits:
        print('  no COUNT / TOTALITY / IDENTIFIER / AUTOCLOSE claims found in prose.')
        print('  ⚑ that is not the same as "nothing to verify" — it means nothing MATCHED.')
        return 0

    by_fam = {}
    for fam, ln, tok, ctx, why in hits:
        by_fam.setdefault(fam, []).append((ln, tok, ctx, why))
    for fam in ('AUTOCLOSE', 'TOTALITY', 'COUNT', 'IDENTIFIER'):
        rows = by_fam.get(fam)
        if not rows:
            continue
        print(f'\n  {fam}  ({len(rows)})  — {rows[0][3]}')
        for ln, tok, ctx, _ in rows[:8]:
            print(f'    :{ln}  {tok!r}')
            print(f'          {ctx}')
        if len(rows) > 8:
            print(f'    … and {len(rows)-8} more')

    print(f'\n  evidence blocks containing a command: {len(blocks)}')
    if has_evidence:
        print('  PASS — claims are present and evidence is attached.')
        print('  ⚑ This tool did NOT verify the claims are TRUE. It cannot. It only')
        print('    confirms the author was made to paste what they ran.')
        return 0
    print('  FAIL — claims are asserted with NO command output anywhere in the draft.')
    print('  Every one of the three defects this exists to stop was exactly this:')
    print('  a confident sentence that a five-second grep would have refuted.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
