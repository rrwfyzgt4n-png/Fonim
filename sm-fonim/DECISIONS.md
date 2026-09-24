# Fonim Decisions

## 2026-09-02 — Canonical StringMaster control is project-local

Mutable StringMaster control for Fonim lives only under `sm-fonim/` in this repository. GitHub is authoritative for mutable project state. Machine-local StringMaster bindings and Remote host projections are transport/runtime state, not canonical project truth.


## 2026-09-07 — Project-local Remote cutover canary

Fonim is used as a read-only infrastructure canary for the accepted StringMaster project-local Remote path.

The canary must not alter or accept Fonim product behavior. It uses exact accepted product base `62de6488c7c7ddd3ae1d942eb9b9802b5a0056b6`, produces no source writes, runs no tests, and exists only to prove project-local draft routing, explicit phone authorization, host provenance admission, conductor execution, and canonical REPORT/RECEIPT publication.

Request `TR-fonim-2026-09-07-001` is the sole preauthorized identity for this canary. It may be submitted at most once.


## 2026-09-07 — Project-local Remote cutover canary completed cleanly

Request `TR-fonim-2026-09-07-001` was human-authorized exactly once through the accepted project-local StringMaster Remote Shortcut.

Canonical GitHub evidence independently proves:

- `TURN-2026-09-07-001` / `RUN-2026-09-07-001`;
- result `COMPLETED`;
- exact accepted source `62de6488c7c7ddd3ae1d942eb9b9802b5a0056b6` prepared and observed;
- no branch;
- zero changed paths;
- `clean-no-change`;
- executor return code 0;
- no transport failure.

This accepts the infrastructure canary result only. Fonim product source and product acceptance remain unchanged.

The consumed project-local preauthorization draft is removed from the active draft directory after acceptance. Its request identity remains permanently spent; draft deletion never authorizes reuse.


## 2026-09-24 — StringMaster v1.6 Remote canary completed cleanly

Request `TR-fonim-2026-09-24-001` was human-authorized exactly once through the installed StringMaster Remote Shortcut as the final external-project canary for the deployed StringMaster v1.6 runtime.

Canonical GitHub evidence independently proves:

- `TURN-2026-09-24-001` / `RUN-2026-09-24-001`;
- result `COMPLETED`;
- execution mode `evidence`;
- conductor-only execution with executor, model, and reasoning effort all null;
- exact accepted Fonim source `62de6488c7c7ddd3ae1d942eb9b9802b5a0056b6` prepared and observed;
- evidence classification `PASSED` with return code 0;
- evidence output `V1_6_REMOTE_CANARY_PASS`;
- no branch, no changed paths, and `clean-no-change`;
- no transport failure.

This accepts the canary as StringMaster infrastructure evidence only. Fonim product source and product acceptance remain unchanged.

The consumed project-local draft is retired. Request identity `TR-fonim-2026-09-24-001` remains permanently spent and must never be replayed or reused.
