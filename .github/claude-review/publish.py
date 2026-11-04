"""Publishes the Claude review from its structured output.

Run by .github/workflows/claude-code-review.yml, taken from the base branch like the rules.
Every write to the pull request happens here, so each run leaves the same shape behind:

- at most one new review per run, holding every new inline comment and the verdict;
- no finding posted twice: an open thread from this workflow within 3 lines is the same one;
- a finding on a line the diff does not carry moves to the nearest line it does;
- only this workflow's own comments and threads are replied to, resolved or reopened;
- one live verdict: an unchanged request for changes is edited in place, and every older
  verdict is dismissed and collapsed when a new one is posted;
- the verdict follows the threads, not the model: changes are requested while any thread
  from this workflow is unresolved.

Prints `open=<n>` to $GITHUB_OUTPUT for the step that holds the check red.
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


THREADS = """
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { id isResolved path line originalLine
        comments(first: 1) { nodes { id databaseId author { login } body } } } } } }
}"""


def locations(thread):
    """Where a thread's finding sits: the line it is on, and the real one a moved comment names."""
    line = thread["line"] or thread["originalLine"] or 0
    places = {(thread["path"], line)}
    real = re.match(r"On `(.+):(\d+)`:", thread["root"]["body"])
    if real:
        places.add((real.group(1), int(real.group(2))))
    return places


def same_finding(thread, path, line):
    return any(where == path and abs(at - line) <= NEAR for where, at in locations(thread))


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
            if roots and roots[0]["author"]["login"] == "github-actions" and MARKER in roots[0]["body"]:
                thread["root"] = roots[0]
                threads.append(thread)
        if not block["pageInfo"]["hasNextPage"]:
            return threads
        cursor = block["pageInfo"]["endCursor"]


def main():
    result = json.loads(os.environ["RESULT"])
    valid = diff_lines(os.environ["DIFF"])
    threads = own_threads()
    by_thread = {thread["id"]: thread for thread in threads}
    by_comment = {thread["root"]["databaseId"]: thread for thread in threads}

    # Replies, resolutions and reopenings first, on this workflow's own threads only.
    for reply in result.get("replies", []):
        if reply["comment_id"] not in by_comment:
            print(f"skipped reply to {reply['comment_id']}: not this workflow's thread")
            continue
        gh(f"{API}/comments/{reply['comment_id']}/replies", "-X", "POST",
           payload={"body": f"{reply['body']}\n{MARKER}"})
        print(f"replied to {reply['comment_id']}")
    for item in result.get("resolve", []):
        thread = by_thread.get(item["thread_id"])
        if not thread:
            print(f"skipped resolving {item['thread_id']}: not this workflow's thread")
            continue
        if not thread["isResolved"]:
            graphql("mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) "
                    "{ thread { id } } }", id=thread["id"])
            thread["isResolved"] = True
        graphql("mutation($id: ID!) { minimizeComment(input: {subjectId: $id, "
                "classifier: RESOLVED}) { clientMutationId } }", id=thread["root"]["id"])
        print(f"resolved and hid {thread['id']}")
    for item in result.get("reopen", []):
        thread = by_thread.get(item["thread_id"])
        if not thread or not thread["isResolved"]:
            print(f"skipped reopening {item['thread_id']}")
            continue
        graphql("mutation($id: ID!) { unresolveReviewThread(input: {threadId: $id}) "
                "{ thread { id } } }", id=thread["id"])
        thread["isResolved"] = False
        print(f"reopened {thread['id']}")

    # New comments: drop any an open thread of this workflow already makes, then anchor.
    open_threads = [thread for thread in threads if not thread["isResolved"]]
    comments = []
    for item in result.get("comments", []):
        path, line, note = anchor(item["path"], item["line"], valid)
        if path is None:
            print(f"skipped {item['path']}:{item['line']}: the diff carries no line to comment on")
            continue
        # The same finding as an open thread, by where the model puts it or where it lands.
        same = [
            thread for thread in open_threads
            if same_finding(thread, item["path"], item["line"]) or (not note and same_finding(thread, path, line))
        ]
        # ...or as a comment this run already queued.
        if same or any(queued["at"] == (item["path"], item["line"]) for queued in comments):
            print(f"skipped {item['path']}:{item['line']}: already open")
            continue
        comments.append({
            "at": (item["path"], item["line"]),
            "path": path, "line": line, "side": "RIGHT",
            "body": f"{note}{item['body']}\n\n{REQUIRED}\n{MARKER}",
        })

    # The verdict follows the threads: every open one, old or new, is a required finding.
    open_count = len([thread for thread in threads if not thread["isResolved"]]) + len(comments)
    if open_count:
        event = "REQUEST_CHANGES"
        body = (f"❌ **Changes requested** — {open_count} open finding(s).\n\n"
                "Every finding is required: each one blocks the merge until it is fixed, or a "
                "reply disputes it and the review accepts the reply. Resolve every thread before "
                f"merging.\n{VERDICT_MARKER}")
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
        queued = [{key: value for key, value in comment.items() if key != "at"} for comment in comments]
        payload = {"commit_id": HEAD, "event": event, "body": body, "comments": queued}
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
