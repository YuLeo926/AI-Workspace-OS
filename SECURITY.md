# Security and Privacy

AI Workspace OS is a template and cooperative governance protocol. It should not contain private operational data.

## Security Boundary

`workspace-policy.json`, the delegation ledger, native agent instructions, and the authorization checker help cooperating humans and agents follow declared boundaries. They do not:

- authenticate that a caller really holds a claimed role;
- intercept or prevent filesystem writes;
- sandbox agents, scripts, editors, or other processes;
- make JSONL logs or Git history tamper-proof;
- replace operating-system permissions, secret management, review, or backups.

A result of `allow` means the declared request matches the workspace protocol. It is not proof of identity or a security capability token.

## Do Not Commit Private Data

Do not commit:

- real accounts or account identifiers;
- real orders or SKUs;
- real customers or client details;
- payment, backend, or platform state;
- screenshots or platform exports;
- tokens, API keys, cookies, credentials, or secrets;
- private handoffs;
- real `_ops_log/agent_action_log.jsonl` records;
- real `_ops_log/delegations.jsonl` records;
- private browser or automation details;
- internal task or conversation identifiers;
- absolute paths from private machines or workspaces.

Use fictional examples, generic roles and paths, fixed example timestamps, and synthetic logs.

## If Private Data Is Added

1. Stop using the affected branch for public release.
2. Remove the private content from the working tree.
3. If it was committed, rewrite repository history before publishing.
4. Rotate any exposed credentials, tokens, or session material.
5. Check generated files, fixtures, logs, screenshots, and copied workspaces for the same exposure.
6. Add a safer template, test, or rule so the leak is less likely to recur.

## Reporting Security Issues

Once GitHub private vulnerability reporting is enabled, use it for suspected vulnerabilities or exposed private data.

Do not open a public issue for a suspected vulnerability or exposure. Never include secrets, real customer data, account identifiers, screenshots, private handoffs, real action logs, or real delegation events in a report.
