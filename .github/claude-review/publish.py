"""Reconciles the Claude review with the pull request, and publishes the result.

Run by .github/workflows/claude-code-review.yml, taken from the base branch like the rules. The
review is blind: it returns every finding present at the head commit, knowing nothing of earlier
comments. This script alone compares that list with the threads this workflow already has:

- a finding that matches an open thread stays as it is, never posted twice;
- a finding that matches a thread this workflow resolved is back, so the thread is reopened;
- a finding that matches a thread a person resolved is left resolved: that judgement stands;
- a finding that matches nothing is posted, all new comments in one review;
- an open thread that no finding matches is resolved: its defect is gone.

A finding matches a thread on the same file, within 3 lines of the thread's line (or of the real
line a moved comment names), sharing a lens. Each thread and each finding matches at most once,
the nearest first. A finding on a line the diff does not carry moves to the nearest one it does.

The verdict follows the threads: changes are requested while any thread of this workflow is open,
and approved, after its earlier requests for changes are dismissed, when none is. An unchanged
request for changes is edited in place; an older verdict is dismissed and collapsed when a new
one is posted. Prints `open=<n>` to $GITHUB_OUTPUT for the step that holds the check red.
"""

import json
import os
import re
import subprocess
import sys

MARKER = "<!-- claude-review -->"
VERDICT_MARKER = "<!-- claude-review-verdict -->"
SUMMARY_MARKER = "<!-- claude-review-summary -->"
BOT = "github-actions[bot]"
BOT_GRAPHQL = "github-actions"
REQUIRED = "<sub>Required before merge: fix it, or reply with why it does not apply.</sub>"
NEAR = 3

REPO = os.environ["GITHUB_REPOSITORY"]
PR = os.environ["PR"]
HEAD = os.environ["HEAD_SHA"]
API = f"repos/{REPO}/pulls/{PR}"


def gh(*args, payload=None, check=True):
    """Calls `gh api`, sending `payload` as the JSON body, and returns the parsed answer."""
    cmd = ["gh", "api", *args]
    if payload is not None:
        cmd += ["--input", "-"]
    done = subprocess.run(
        cmd,
        input=None if payload is None else json.dumps(payload),
        capture_output=True,
        text=True,
    )
    if done.returncode != 0:
        if check:
            sys.exit(f"gh api {' '.join(args)} failed: {done.stderr.strip()}")
        return None
    out = done.stdout.strip()
    return json.loads(out) if out else None


def paged(path):
    """Every item of a paginated REST list."""
    pages = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", path], capture_output=True, text=True, check=True
    )
    return [item for page in json.loads(pages.stdout) for item in page]


def graphql(query, **variables):
    args = ["graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        args += ["-F", f"{key}={value}"]
    return gh(*args)["data"]


def diff_lines(path):
    """The head-side lines a review comment may sit on, per file: added and context lines."""
    lines, current, right = {}, None, 0
    for raw in open(path, encoding="utf-8", errors="replace"):
        if raw.startswith("+++ "):
            name = raw[4:].rstrip("\n")
            current = None if name == "/dev/null" else name.removeprefix("b/")
            if current:
                lines.setdefault(current, set())
        elif raw.startswith("@@"):
            match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", raw)
            right = int(match.group(1)) if match else 0
        elif current and raw.startswith(("+", " ")) and not raw.startswith("+++"):
            lines[current].add(right)
            right += 1
    return lines


def anchor(path, line, valid):
    """Moves a comment onto a line the diff carries, saying where it really belongs."""
    if line in valid.get(path, ()):
        return path, line, ""
    note = f"On `{path}:{line}`:\n\n"
    if valid.get(path):
        return path, min(valid[path], key=lambda candidate: abs(candidate - line)), note
    for other in sorted(valid):
        if valid[other]:
            return other, min(valid[other]), note
    return None, None, note


def lenses(text):
    """The lenses a finding or a comment names: `issue (blocking, security, boundaries)`."""
    match = re.search(r"issue \(blocking,\s*([^)]*)\)", text)
    names = match.group(1) if match else text
    return {name.strip().lower() for name in names.split(",") if name.strip()}


THREADS = """
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { id isResolved resolvedBy { login } path line originalLine
        comments(first: 1) { nodes { id databaseId author { login } body } } } } } }
}"""


def own_threads():
    """This workflow's review threads: their root comment is the bot's and carries the marker."""
    owner, name = REPO.split("/")
    threads, cursor = [], None
    while True:
        extra = {"endCursor": cursor} if cursor else {}
        page = graphql(THREADS, owner=owner, name=name, number=PR, **extra)
        block = page["repository"]["pullRequest"]["reviewThreads"]
        for thread in block["nodes"]:
            roots = thread["comments"]["nodes"]
            if roots and roots[0]["author"]["login"] == BOT_GRAPHQL and MARKER in roots[0]["body"]:
                thread["root"] = roots[0]
                thread["lenses"] = lenses(roots[0]["body"])
                line = thread["line"] or thread["originalLine"] or 0
                thread["places"] = {(thread["path"], line)}
                real = re.match(r"On `?([^`\s]+?):(\d+)`?:", roots[0]["body"])
                if real:
                    thread["places"].add((real.group(1), int(real.group(2))))
                threads.append(thread)
        if not block["pageInfo"]["hasNextPage"]:
            return threads
        cursor = block["pageInfo"]["endCursor"]


def distance(thread, finding):
    """How far a finding is from a thread, or None when they are not the same finding."""
    if not (thread["lenses"] & finding["lenses"]):
        return None
    gaps = [abs(at - finding["line"]) for where, at in thread["places"] if where == finding["path"]]
    gap = min(gaps, default=None)
    return gap if gap is not None and gap <= NEAR else None


def resolve(thread):
    graphql("mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id } } }",
            id=thread["id"])


def reopen(thread):
    graphql("mutation($id: ID!) { unresolveReviewThread(input: {threadId: $id}) { thread { id } } }",
            id=thread["id"])


def main():
    result = json.loads(os.environ["RESULT"])
    valid = diff_lines(os.environ["DIFF"])
    threads = own_threads()

    # The review's list, with exact repeats removed.
    findings, seen = [], set()
    for item in result.get("findings", []):
        key = (item["path"], item["line"], item["body"])
        if key in seen:
            continue
        seen.add(key)
        findings.append({**item, "lenses": lenses(item.get("lens", "")) or lenses(item["body"])})

    # Match each finding to at most one thread, and each thread to at most one finding.
    pairs = sorted(
        (gap, index, thread["id"])
        for index, finding in enumerate(findings)
        for thread in threads
        if (gap := distance(thread, finding)) is not None
    )
    matched_finding, matched_thread = {}, {}
    for gap, index, thread_id in pairs:
        if index not in matched_finding and thread_id not in matched_thread:
            matched_finding[index] = thread_id
            matched_thread[thread_id] = index

    # Threads: keep, reopen, leave, or resolve.
    for thread in threads:
        where = f"{thread['path']}:{thread['line'] or thread['originalLine']}"
        if thread["id"] in matched_thread:
            if not thread["isResolved"]:
                print(f"kept {where}: still present")
            elif (thread["resolvedBy"] or {}).get("login") == BOT_GRAPHQL:
                reopen(thread)
                thread["isResolved"] = False
                print(f"reopened {where}: the defect is back")
            else:
                who = (thread["resolvedBy"] or {}).get("login", "someone")
                print(f"left {where}: resolved by {who}")
        elif not thread["isResolved"]:
            resolve(thread)
            thread["isResolved"] = True
            print(f"resolved {where}: no longer found")

    # New findings: posted, all in one review.
    comments = []
    for index, finding in enumerate(findings):
        if index in matched_finding:
            continue
        path, line, note = anchor(finding["path"], finding["line"], valid)
        if path is None:
            print(f"skipped {finding['path']}:{finding['line']}: the diff carries no line to comment on")
            continue
        comments.append({
            "path": path, "line": line, "side": "RIGHT",
            "body": f"{note}{finding['body']}\n\n{REQUIRED}\n{MARKER}",
        })
        print(f"new {finding['path']}:{finding['line']}")

    # The verdict follows the threads: every open one, old or new, is a required finding.
    open_count = len([thread for thread in threads if not thread["isResolved"]]) + len(comments)
    if open_count:
        event = "REQUEST_CHANGES"
        body = (f"❌ **Changes requested** — {open_count} open finding(s).\n\n"
                "Every finding is required: each one blocks the merge until it is fixed, or someone "
                "with write access replies with why it does not apply and resolves its thread. "
                f"Resolve every thread before merging.\n{VERDICT_MARKER}")
    else:
        event = "APPROVE"
        body = ("✅ **Approved** — no open findings.\n\n"
                "Every finding was required, and every one is resolved. This approval does not "
                f"count toward the merge: a code owner still has to approve.\n{VERDICT_MARKER}")

    verdicts = [
        review for review in paged(f"{API}/reviews")
        if review["user"]["login"] == BOT and VERDICT_MARKER in (review["body"] or "")
        and review["state"] != "DISMISSED"
    ]
    latest = verdicts[-1] if verdicts else None

    if not comments and latest and event == "REQUEST_CHANGES" and latest["state"] == "CHANGES_REQUESTED":
        gh(f"{API}/reviews/{latest['id']}", "-X", "PUT", payload={"body": body})
        print(f"updated verdict {latest['id']} in place: {open_count} open")
        posted = latest
    elif not comments and latest and event == "APPROVE" and latest["state"] in ("APPROVED", "COMMENTED") \
            and latest["body"].startswith("✅"):
        print(f"verdict {latest['id']} already approves")
        posted = latest
    else:
        payload = {"commit_id": HEAD, "event": event, "body": body, "comments": comments}
        posted = gh(f"{API}/reviews", "-X", "POST", payload=payload, check=False)
        if posted is None:
            print(f"GitHub refused {event}; posting the same review as a comment-review")
            posted = gh(f"{API}/reviews", "-X", "POST", payload={**payload, "event": "COMMENT"})
        print(f"posted review {posted['id']} ({posted['state']}) with {len(comments)} comment(s)")

    # One live verdict: every older one is dismissed where it requests changes, and collapsed.
    for review in verdicts:
        if review["id"] == posted["id"]:
            continue
        if review["state"] == "CHANGES_REQUESTED":
            gh(f"{API}/reviews/{review['id']}/dismissals", "-X", "PUT",
               payload={"event": "DISMISS", "message": f"Superseded by the review at {HEAD[:7]}."})
        graphql("mutation($id: ID!) { minimizeComment(input: {subjectId: $id, "
                "classifier: OUTDATED}) { clientMutationId } }", id=review["node_id"])
        print(f"superseded verdict {review['id']}")

    # This workflow never leaves a conversation comment.
    for comment in paged(f"repos/{REPO}/issues/{PR}/comments"):
        if comment["user"]["login"] == BOT and SUMMARY_MARKER in (comment["body"] or ""):
            gh(f"repos/{REPO}/issues/comments/{comment['id']}", "-X", "DELETE")
            print(f"deleted summary comment {comment['id']}")

    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
        out.write(f"open={open_count}\n")
    print(f"open findings: {open_count}")


if __name__ == "__main__":
    main()
