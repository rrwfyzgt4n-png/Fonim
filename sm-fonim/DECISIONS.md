# Fonim Decisions

## 2026-09-02 — Canonical StringMaster control is project-local

Mutable StringMaster control for Fonim lives only under `sm-fonim/` in this repository. GitHub is authoritative for mutable project state. Machine-local StringMaster bindings and Remote host projections are transport/runtime state, not canonical project truth.


## 2026-09-07 — Project-local Remote cutover canary

Fonim is used as a read-only infrastructure canary for the accepted StringMaster project-local Remote path.

The canary must not alter or accept Fonim product behavior. It uses exact accepted product base `62de6488c7c7ddd3ae1d942eb9b9802b5a0056b6`, produces no source writes, runs no tests, and exists only to prove project-local draft routing, explicit phone authorization, host provenance admission, conductor execution, and canonical REPORT/RECEIPT publication.

Request `TR-fonim-2026-09-07-001` is the sole preauthorized identity for this canary. It may be submitted at most once.
