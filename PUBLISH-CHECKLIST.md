# Before This Goes Public — Review Checklist

*(This file itself is not meant to be published — delete it, or leave it out of the repo, once reviewed.)*

Scanned the drafted repo for IPs, MAC addresses, the Dell service tag, SSH host aliases, the real hostname pattern, and the account username/email — none found. That said, this was written fresh from the source material rather than copy-pasted, so a manual read-through before publishing is still worth doing. Specific things to decide:

1. **LICENSE** — defaulted to MIT with a `[YOUR NAME OR HANDLE]` placeholder. Fill in whatever public name/handle should appear, or swap the license entirely if a different one is preferred (this stack — GPL-licensed KDE components referenced, MIT-licensed reference project) doesn't obligate any particular choice for original writing/scripts).

2. **Virtual display name** — the scripts use a placeholder `myserver-vm` instead of the real hostname-based name. Genericized deliberately, on the theory that a repo meant for other people to adapt is more useful with an obviously-placeholder value than with a real (if not especially sensitive) hostname. Worth confirming this reads right — if there's a preference for keeping the original naming pattern instead, that's a one-line change per script.

3. **GitHub username / repo owner** — nothing in the drafted content assumes or reveals a specific GitHub account. Whatever account actually publishes this is a separate decision (see the note at the end of this checklist on getting it onto GitHub).

4. **The Reddit thread text** — `docs/02-xorg-dead-end.md` quotes the actual forum post verbatim, since it was already posted publicly. If the goal is for people to be able to search and land on this repo from that thread, the two should stay consistent (e.g. the forum post could eventually be edited to link back here).

5. **A read-through for tone** — this was assembled from several separate working documents and chat threads; a pass to make sure it reads as one consistent voice, rather than stitched-together notes, is worth doing before publishing even though the technical content has been checked.

## Getting it onto GitHub

This session can prepare every file (already done, in this folder) but doesn't have a connection to a GitHub account to actually create/push a public repo. Once the checklist above is settled, either:

- Create a new repo on GitHub, then `git init`, `git add .`, `git commit`, and push this folder to it, or
- Ask for help with the exact `git`/`gh` commands to run once a repo name and visibility (public) are decided.
