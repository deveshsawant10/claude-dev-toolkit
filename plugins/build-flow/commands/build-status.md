---
description: Show epic/story/task progress for this repo's /build-plan issues and which tasks can start now
argument-hint: [--repo OWNER/NAME] [--milestone NAME]
---

Run `build-status $ARGUMENTS` (on PATH once build-flow is installed;
equivalently `${CLAUDE_PLUGIN_ROOT}/bin/build-status`) and show the output to
the user verbatim.

This command is read-only. Do not create, edit, or close issues as a
follow-up unless the user asks. If it exits 3, relay its message (gh missing
or not authenticated) and stop.
