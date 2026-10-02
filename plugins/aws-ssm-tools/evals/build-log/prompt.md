---
tags: [trigger]
runs: 3
max_turns: 6
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
---

Our EC2 Image Builder build for the core AMI failed about an hour ago in ap-south-1. The build instance is still running and is private (no SSH, port 22 closed). How do I find the error?
