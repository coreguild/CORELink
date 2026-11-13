#!/usr/bin/env python3
"""Measure the reviewer against real history.

Each case in cases/<name>/ is a diff.patch plus case.json: {"kind": "bug"|"clean", "title", "expect", "why"}.
Bug cases are the reverse of a merged fix, addon files only: a PR that would put the bug back. Clean cases are
a merged fix as it was, harness included. The reviewer (claude -p, headless) gets the gameplay checklist and the
diff and must end with a VERDICT line. A bug case scores a hit when the verdict is "needs changes" and the review
mentions the bug (the expect regex); a clean case when the verdict is "approve".

    tests/review-evals/run.py [--model <id>] [--strict] [case ...]

Costs plan usage, one review per case; not part of tests/run.sh. --strict exits 1 on any miss. Raw reviews land
in tests/review-evals/out/ (ignored by git) so a miss can be read. A MISS means the checklist needs a line; an
ERROR (the CLI failed or ran out of turns) means the run, not the reviewer, needs looking at.
"""
import json, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CASES = os.path.join(ROOT, "tests", "review-evals", "cases")
OUT = os.path.join(ROOT, "tests", "review-evals", "out")

PROMPT = """You are reviewing a pull request for CORELink, a World of Warcraft addon, before merge.
Walk the checklist below against the diff. The diff is against an older snapshot of the repository, so judge it
on its own terms; you may read files in the working tree for context, but the diff is the change under review.
Report in the checklist's format: one bullet per finding with file and line, then a final line that is exactly
`VERDICT: approve` or `VERDICT: needs changes`.

<checklist>
{checklist}
</checklist>

<pull_request title="{title}">
{diff}
</pull_request>
"""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def review(name, model):
    case = json.loads(read(os.path.join(CASES, name, "case.json")))
    prompt = PROMPT.format(checklist=read(os.path.join(ROOT, "agents", "review-checklist.md")),
                           title=case["title"], diff=read(os.path.join(CASES, name, "diff.patch")))
    cmd = ["claude", "-p", "--output-format", "json", "--max-turns", "20"]
    if model:
        cmd += ["--model", model]
    run = subprocess.run(cmd + [prompt], cwd=ROOT, capture_output=True, text=True)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as f:
        f.write(run.stdout)
    try:
        data = json.loads(run.stdout)
    except ValueError:
        return case, "", 0.0, "error: " + (run.stderr.strip().splitlines() or ["no JSON from claude"])[-1][:60]
    text, cost = str(data.get("result") or ""), float(data.get("total_cost_usd") or 0)
    error = ""
    if data.get("is_error") or data.get("subtype") not in (None, "success"):
        error = "error: " + str(data.get("subtype") or "is_error")   # a budget or CLI problem, not a reviewer miss
    return case, text, cost, error


def grade(case, text, error):
    if error:
        return "none", False, "ERROR"
    verdicts = re.findall(r"VERDICT:\s*(approve|needs changes)", text, re.I)
    verdict = verdicts[-1].lower() if verdicts else "none"
    if case["kind"] == "bug":
        hit = verdict == "needs changes" and bool(re.search(case["expect"], text, re.I))
    else:
        hit = verdict == "approve"
    return verdict, hit, "HIT " if hit else "MISS"


def main(argv):
    model, strict, names = "", False, []
    while argv:
        a = argv.pop(0)
        if a == "--model":
            if not argv:
                print("usage: tests/review-evals/run.py [--model <id>] [--strict] [case ...]"); return 2
            model = argv.pop(0)
        elif a == "--strict":
            strict = True
        else:
            names.append(a)
    names = names or sorted(n for n in os.listdir(CASES) if os.path.isfile(os.path.join(CASES, n, "case.json")))
    missing = [n for n in names if not os.path.isfile(os.path.join(CASES, n, "case.json"))]
    if missing:
        print("review-evals: no such case: " + ", ".join(missing)); return 2
    if not shutil.which("claude"):
        print("review-evals: the claude CLI is not on PATH")
        return 2
    hits, errors, total_cost = 0, 0, 0.0
    print(f"{'case':24} {'kind':6} {'verdict':14} result  cost")
    for name in names:
        case, text, cost, error = review(name, model)
        verdict, hit, result = grade(case, text, error)
        hits, errors, total_cost = hits + hit, errors + bool(error), total_cost + cost
        print(f"{name:24} {case['kind']:6} {verdict:14} {result}    ${cost:.2f}  {error}")
    print(f"review-evals: {hits}/{len(names)} hits, {errors} errors, ${total_cost:.2f}" + (f" on {model}" if model else ""))
    return 1 if strict and hits < len(names) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
