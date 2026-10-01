# 0010. The marketplace is the only source of plugin identity

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

A second plugin list would drift and let us mislabel or rename plugins.

## Decision

**Plugin universe, ids, metadata, categories and repo URLs come only from the plugins.omarchy.org catalog and registry; unlisted repositories are never scanned.**

## Consequences

- `catalog.py` follows repositoryMigrations, retiredPluginIds and builtInSources.
- Each report records the catalog `generatedAt` it was resolved against.
