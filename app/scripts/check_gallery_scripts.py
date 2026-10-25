#!/usr/bin/env python3
"""Compiles every gallery script and editor template in Polish and English with osacompile.

The scripts live in Sources/IntermezzoApp/ScriptGallery.swift; their comments come from
ScriptText (looked up per language in scripts/l10n). Also fails when the English text of a
comment still contains Polish letters.
"""
import glob
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLISH = re.compile("[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]")


def strings(lang: str) -> dict:
    merged = {}
    for path in glob.glob(os.path.join(ROOT, "scripts", "l10n", lang, "[a-z]*.py")):
        spec = importlib.util.spec_from_file_location("m", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        merged.update(mod.STRINGS)
    return merged


def main() -> int:
    text = open(os.path.join(ROOT, "Sources", "IntermezzoApp", "ScriptGallery.swift"), encoding="utf-8").read()
    names = dict(re.findall(r'static let (t\d+) = L\("([^"]+)"\)', text))
    bodies = re.findall(r'(?:source|body): """\n(.*?)"""', text, re.S)
    failures = 0
    for lang in ("pl", "en"):
        table = strings(lang)
        with tempfile.TemporaryDirectory() as tmp:
            for index, body in enumerate(bodies):
                code = textwrap.dedent(body)
                code = re.sub(r"\\\(ScriptText\.(t\d+)\)", lambda m: table.get(names[m[1]], names[m[1]]), code)
                if lang == "en":
                    for line in code.splitlines():
                        if line.lstrip().startswith("--") and POLISH.search(line):
                            print(f"[{lang}] Polish text in an English comment: {line.strip()}")
                            failures += 1
                src = os.path.join(tmp, f"s{index}.applescript")
                open(src, "w", encoding="utf-8").write(code)
                result = subprocess.run(["osacompile", "-o", os.path.join(tmp, f"s{index}.scpt"), src],
                                        capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"[{lang}] script #{index} does not compile: {result.stderr.strip()}")
                    failures += 1
        print(f"[{lang}] {len(bodies)} scripts checked")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
