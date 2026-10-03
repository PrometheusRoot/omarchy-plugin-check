# Schema changelog

Every change to `schemas/*.schema.json` or `spec/schemas/*.schema.json` gets an entry here (enforced by `just docs`).
The private scanner vendors `schemas/` at a pinned commit of this repository.
v1 is unpublished; breaking changes stay in v1 until the first public release.

## Unreleased (v1)

- Provider protocol v1 (`spec/schemas/`, ADR-0026/0027/0028): `statement`, `predicate`,
  `feed-index`, `providers`, `store`, `api-{meta,index,plugin,by-repo}`, `common`. `report.schema.json`
  is now the optional `predicate.report` extension; rule ids in it are opaque per rules version.

- `spec/schemas/store` rows: `verdict.tree` (the reviewed tree of `verdict.commit`, from the trusted
  statements' `subject.digest.gitTree`) and `formerRepos[]` (previous repository URLs from the
  registry's migrations); `api-plugin` `combined.tree` (ADR-0034). Both optional, additive.

- `report.capabilities.externalCode` (required): `{level, evidence, externals[{name, kind, source, evidence}]}`
  — binaries / system packages / registry packages the plugin depends on but does not ship (ADR-0019).
- `report.verdict.reasons` (required): every condition that shaped the outcome.
- `report.verdict.criteria` (required): `{checked, failed, notChecked}` over the provider-protocol
  criteria vocabulary (`$defs/criterion`).
- `findings.category`: new value `external-code`.
- `report.diffSinceLastReview.capabilityChanges[].capability`: may be `externalCode`.
- `report.ai.guard.failures` (required): `[{pass: 1|2, reason}]`, reason one of `guard`, `auth`,
  `timeout`, `budget`, `max-turns`, `schema`, `error`; `[]` when every pass that ran succeeded (ADR-0022).

## 2026-09-30 (v1, P0)

- Initial schemas: report, findings, ai-review, ai-verify (the provider-internal layout schemas
  live with the private scanner).
