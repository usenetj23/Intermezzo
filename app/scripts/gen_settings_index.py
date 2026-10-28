#!/usr/bin/env python3
"""Settings search index and jump anchors.

Reads the Settings sources, finds the labelled controls (Toggle, Picker, Stepper, Button, Section) and the
explanatory notes (Text(...).settingsNote()), gives each one a `.settingsAnchor("<pane>-<slug>")` in the
source (rows that already carry an anchor keep it) and writes Settings/SettingsIndex.generated.swift, which
the sidebar search reads. Run it again after adding or renaming settings; it is idempotent.

    python3 scripts/gen_settings_index.py          # patch the sources and write the index
    python3 scripts/gen_settings_index.py --check  # fail when the sources or the index are out of date
"""
import re, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "Sources/IntermezzoApp/Settings"
OUT = SETTINGS / "SettingsIndex.generated.swift"

# file -> (pane case, expert only)
FILES = {
    "GeneralPane": ("general", False), "FocusRolesView": ("general", False), "AutomationSection": ("general", False),
    "StatusPane": ("status", False),
    "WorkLogPane": ("workLog", False), "WorkCalendar": ("workLog", False),
    "BreaksPane": ("breaks", False), "BreakPresetSection": ("breaks", False), "BreakStyleSection": ("breaks", False),
    "RemindersSection": ("breaks", True), "RelaxationAudioSection": ("breaks", False),
    "FocusPane": ("focus", False), "SeamBreaksSection": ("focus", True), "RhythmExperimentSection": ("focus", False),
    "SessionAwareSection": ("focus", True), "FocusShortcutsSection": ("focus", True),
    "PomodoroPlanSection": ("focus", False), "PomodoroProjectsSection": ("focus", True),
    "ProjectSensorsSection": ("focus", True),
    "AppearancePane": ("appearance", False), "LanguageSection": ("appearance", False),
    "BreakLookSections": ("appearance", False),
    "LightPane": ("light", False), "LightMonitorsSection": ("light", False),
    "StatisticsPane": ("statistics", False),
    "RulesPane": ("rules", True), "FlashPane": ("flash", True), "AwakePane": ("awake", False),
    "ClockOutPane": ("clockOut", False), "MessagesPane": ("messages", False), "ExercisesPane": ("exercises", False),
    "ScriptGalleryPane": ("gallery", True), "SyncPane": ("sync", False), "AdvancedPane": ("advanced", True),
    "AIPane": ("ai", True), "AboutPane": ("about", False),
}
PANE_PREFIX = {"workLog": "worklog", "clockOut": "clockout"}
CALL = re.compile(r'\b(Toggle|Picker|Stepper|Button|Section|Text)\(\s*"')


def code_mask(s):
    """True for characters that are code (not inside a string or a comment)."""
    n = len(s)
    mask = [True] * n
    i = 0

    def string(i):
        # i at the opening quote; returns the index after the closing quote, marking it as non-code
        j = i + 1
        while j < n:
            c = s[j]
            if c == "\\":
                if s[j + 1:j + 2] == "(":
                    depth, j = 1, j + 2
                    while j < n and depth:
                        if s[j] == '"':
                            j = string(j)
                            continue
                        depth += (s[j] == "(") - (s[j] == ")")
                        j += 1
                    continue
                j += 2
                continue
            if c == '"':
                return j + 1
            j += 1
        return n

    while i < n:
        c = s[i]
        if c == "/" and s[i + 1:i + 2] == "/":
            j = s.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                mask[k] = False
            i = j
        elif c == "/" and s[i + 1:i + 2] == "*":
            j = s.find("*/", i)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                mask[k] = False
            i = j
        elif c == '"':
            j = string(i)
            for k in range(i, j):
                mask[k] = False
            i = j
        else:
            i += 1
    return mask


def match(s, mask, i, open_c, close_c):
    """Index after the bracket that closes the one at i."""
    depth = 0
    for j in range(i, len(s)):
        if not mask[j] and s[j] != open_c:
            continue
        if mask[j]:
            if s[j] == open_c:
                depth += 1
            elif s[j] == close_c:
                depth -= 1
                if depth == 0:
                    return j + 1
    return None


def skip_ws(s, j):
    while j < len(s) and s[j] in " \t\r\n":
        j += 1
    return j


def call_end(s, mask, open_paren, trailing=True):
    e = match(s, mask, open_paren, "(", ")")
    if e is None:
        return None
    while trailing:
        k = skip_ws(s, e)
        if k < len(s) and s[k] == "{" and mask[k]:
            e2 = match(s, mask, k, "{", "}")
            if e2 is None:
                break
            e = e2
        else:
            break
    return e


def slug(text):
    t = unicodedata.normalize("NFKD", text.replace("ł", "l").replace("Ł", "L"))
    t = "".join(c for c in t if not unicodedata.combining(c)).lower()
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    return t[:36].rstrip("-") or "row"


def process(name, pane, expert, used, entries):
    path = SETTINGS / f"{name}.swift"
    if not path.exists():
        return None
    s = path.read_text()
    mask = code_mask(s)
    # closures of ForEach: rows repeat there, so they get no anchor
    skip = []
    for m in re.finditer(r"\bForEach\(", s):
        if not mask[m.start()]:
            continue
        e = call_end(s, mask, m.end() - 1)
        if e:
            skip.append((m.start(), e))
    inserts = []   # (position, text)
    found = []     # (pos, kind, key, anchor, end)
    for m in CALL.finditer(s):
        if not mask[m.start()]:
            continue
        kind = m.group(1)
        q = m.end() - 1
        # literal without interpolation
        j, key = q + 1, []
        ok = True
        while j < len(s) and s[j] != '"':
            if s[j] == "\\":
                if s[j + 1] == "(":
                    ok = False
                    break
                key.append(s[j:j + 2])
                j += 2
                continue
            key.append(s[j])
            j += 1
        if not ok or not key:
            continue
        raw = "".join(key)
        text = raw
        if "\\" in raw:
            text = raw.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
        if len(text.strip()) < 2 or any(a <= m.start() < b for a, b in skip):
            continue
        open_paren = m.end() - 1 - (m.end() - 1 - s.rfind("(", 0, m.end()))
        open_paren = s.rfind("(", m.start(), m.end())
        e = call_end(s, mask, open_paren, trailing=kind != "Text" and kind != "Section")
        if e is None:
            continue
        args = s[open_paren:match(s, mask, open_paren, "(", ")") or e]
        if kind == "Button" and "role:" in args:
            continue
        if kind == "Text":
            nm = re.compile(r"\s*\.settingsNote\(\s*\)").match(s, e)
            if not nm or len(text) < 25:
                continue
            e = nm.end()
        elif kind == "Section":
            sec_end = call_end(s, mask, open_paren, trailing=True)
            found.append((m.start(), "Section", text, None, sec_end))
            continue
        am = re.compile(r'\s*\.settingsAnchor\("([^"]+)"\)').match(s, e)
        if am:
            anchor = am.group(1)
        else:
            base = f"{PANE_PREFIX.get(pane, pane)}-{slug(text)}"
            anchor, n = base, 2
            while anchor in used:
                anchor, n = f"{base}-{n}", n + 1
            inserts.append((e, f'.settingsAnchor("{anchor}")'))
        used.add(anchor)
        found.append((m.start(), kind, text, anchor, e))
    # a section points at the first row inside it
    for pos, kind, text, anchor, end in list(found):
        if kind == "Section":
            inner = [f for f in found if f[1] != "Section" and pos < f[0] < (end or pos)]
            if inner:
                found[found.index((pos, kind, text, anchor, end))] = (pos, kind, text, inner[0][3], end)
    for pos, kind, text, anchor, end in found:
        if anchor:
            entries.append((pane, text, anchor, expert))
    new = s
    for pos, text in sorted(inserts, reverse=True):
        new = new[:pos] + text + new[pos:]
    return path, s, new


def swift_str(t):
    return '"' + t.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    check = "--check" in sys.argv
    used, entries, changes = set(), [], []
    # anchors that already exist anywhere stay reserved
    for f in SETTINGS.glob("*.swift"):
        used.update(re.findall(r'\.settingsAnchor\("([^"]+)"\)', f.read_text()))
    reserved = set(used)
    for name, (pane, expert) in FILES.items():
        r = process(name, pane, expert, used, entries)
        if r:
            changes.append(r)
    expert_files = {n for n, (_, e) in FILES.items() if e}
    lines = ["// Generated by scripts/gen_settings_index.py — do not edit.",
             "// Every labelled setting and note in the Settings sources, for the sidebar search.", "",
             "extension SettingsSearch {",
             "    static let generated: [SettingsSearchEntry] = ["]
    seen = set()
    for pane, text, anchor, expert in entries:
        if (pane, text) in seen:
            continue
        seen.add((pane, text))
        lines.append(f"        .init(.{pane}, {swift_str(text)}, anchor: {swift_str(anchor)}{', expert: true' if expert else ''}),")
    lines += ["    ]", "}", ""]
    out = "\n".join(lines)
    stale = [str(p.name) for p, old, new in changes if old != new]
    if OUT.exists() is False or OUT.read_text() != out:
        stale.append(OUT.name)
    if check:
        if stale:
            print("out of date:", ", ".join(stale))
            sys.exit(1)
        print("settings index is current:", len(seen), "entries")
        return
    for p, old, new in changes:
        if old != new:
            p.write_text(new)
    OUT.write_text(out)
    print(f"{len(seen)} entries, {len([1 for _, o, n in changes if o != n])} source files patched")


main()
