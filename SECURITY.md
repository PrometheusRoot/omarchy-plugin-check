# Security policy

## Reporting a vulnerability

Report privately through GitHub's private vulnerability reporting:
**<https://github.com/PrometheusRoot/omarchy-plugin-check/security/advisories/new>**.

That is the only channel. There is no security e-mail address; please do not open a public issue,
pull request or discussion for anything that could put users at risk.

Include what is affected (component, version or commit), how to reproduce it, and the impact you
expect. A minimal proof of concept is welcome; see "Out of scope" for what not to send.

## In scope

- The checker plugin (`omarchy-plugin-check` CLI, bar shield, panel): the install gate, commit and
  tree pinning, identity binding to the listed repository, snapshot verification.
- The store app: bundle verification, install flow, anything that turns data into process arguments.
- The public website and its static API.
- The provider protocol, aggregator and collector (`spec/`, `aggregator/`, `collector/`): signature
  and Sigstore verification, merge rules, registry handling, a way to make a client trust data it
  should not.
- Published data: a snapshot, bundle, feed or registry that verifies but should not, or a published
  report that reveals what it is designed to hide (for example a reversible opaque identifier).
- A plugin we rate `safe` or `caution` that you can show is malicious: report it here *and* to the
  Omarchy marketplace maintainers, so it can be pulled for everyone.

## Out of scope

- The scanner's detection rules, rule identifiers, weights, prompts and thresholds. The scanner is
  private by design (anti-oracle policy, ADR-0011); we do not confirm or deny why a plugin did or did
  not trigger a finding, and we do not scan on demand.
- **Do not publish plugins built to test or evade the scanner to the Omarchy marketplace.** Real
  users install from it. If you believe you have an evasion, describe it privately in a report; do
  not send the test plugin to the marketplace, and do not ask us to review an unlisted one.
- Vulnerabilities in Omarchy, `omarchy-shell`, the marketplace or third-party tools: report them to
  their maintainers (we are happy to help coordinate if our clients are affected too).
- Volumetric denial of service, spam, social engineering, and findings that need a compromised
  machine or a compromised GitHub account to begin with.

## What to expect

This is a small, volunteer-run project; these are targets, not guarantees.

- Acknowledgement within 7 days, and a first assessment within 14 days.
- Fixes for critical issues as fast as we can, aiming for 30 days; we keep you posted in the advisory.
- Coordinated disclosure: we publish a GitHub security advisory once a fix is released (and request
  a CVE when it applies), crediting you unless you prefer otherwise.
- Only the latest release of each component is supported.
