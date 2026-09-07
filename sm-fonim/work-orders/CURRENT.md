---
schema: stringmaster/v1
work_order_id: WO-2026-09-07-001
work_order_kind: single
execution_mode: read-only
project_id: fonim
state_revision: 5
executor: codex
recommended_model: gpt-5.6-terra
reasoning_effort: medium
spending_class: S1
status: READY
base_head: 62de6488c7c7ddd3ae1d942eb9b9802b5a0056b6
write_roots: []
maximum_full_test_runs: 0
maximum_evidence_runs: 0
progress_narration: prohibited
architecture_changes: prohibited
created_at: "2026-09-07T16:37:30-04:00"
---

# Objective

Run one clean read-only Fonim turn solely as the external-project canary for the accepted project-local StringMaster Remote cutover.

# Required behavior

- use exact accepted Fonim source `62de6488c7c7ddd3ae1d942eb9b9802b5a0056b6`;
- make no source, test, resource, control, configuration, credential, or external-service mutation;
- run no tests, builds, profilers, devices, network product operations, or evidence commands;
- do not create a branch or commit;
- return a concise successful completion after confirming the prepared repository is the expected Fonim project and remains clean.

The expected source disposition is `clean-no-change`.

# Purpose

A successful canonical TURN/RUN/REPORT/RECEIPT proves the new project-local draft -> private transport -> repository-provenance admission -> ordinary StringMaster conductor path for an external project.

It does not constitute Fonim product acceptance or product evidence.
