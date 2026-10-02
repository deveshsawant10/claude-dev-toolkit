---
type: llm
weight: 1
---

PASS if the plan uses the plugin commands: ssm-ls (or equivalent) to find the build instance and ssm-logs on /var/lib/amazon/toe/TOE_*/console.log with a grep for errors. FAIL if it recommends opening port 22, a bastion host, or printing secrets with --no-redact.
