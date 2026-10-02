// Types for the public static API (spec/schemas/api-*.schema.json, store.schema.json#/$defs/plugin)
// and the provider's optional report extension (schemas/report.schema.json). Only the fields the
// site reads are typed; everything is optional where the schemas allow absence or null.

export type Verdict = 'safe' | 'caution' | 'risky' | 'blocked' | 'unknown';
export type Tier = 'core' | 'verified' | 'community' | 'unsigned';
export type Verification = 'sigstore' | 'unsigned-dev' | 'unsigned' | string;
export type Basis = 'trusted' | 'untrusted' | 'none';
export type ListingState = 'listed' | 'retired' | 'builtin';
export type Level = 'none' | 'low' | 'med' | 'high';
export type Severity = 'info' | 'low' | 'medium' | 'high' | 'critical';

export interface Criteria {
  checked?: string[];
  failed?: string[];
  notChecked?: string[];
}

export interface RowFinding {
  category: string;
  severity: Severity;
  confidence?: number;
  message: string;
  blocking?: boolean;
  locations?: { path: string; startLine?: number; endLine?: number }[];
}

export interface ProviderRow {
  provider: string;
  tier: Tier;
  verification: Verification;
  signer?: string | null;
  signedAt?: string | null;
  commit: string | null;
  tree?: string | null;
  verdict: Verdict;
  effectiveVerdict: Verdict;
  adjustments: ('capped-at-caution' | 'blocked-without-evidence')[];
  counted: boolean;
  timeReviewed: string | null;
  summary?: string;
  criteria?: Criteria;
  findings?: RowFinding[];
  detail?: RowDetail;
  statement?: string | null;
}

export interface RowDetail {
  outcome?: string;
  capabilities?: string[];
  findings?: unknown[];
  enforcementMode?: string;
  scope?: { kind?: string; path?: string; baseCommit?: string };
  method?: string[];
  target?: string;
  report?: Report;
}

export interface Combined {
  verdict: Verdict;
  basis: Basis;
  contested: boolean;
  commits: string[];
  reasons: string[];
}

export interface Listing {
  id: string;
  name: string;
  author?: string;
  desc?: string;
  cat?: string;
  kind?: string;
  tags?: string[];
  repo?: string;
  path?: string;
  install?: string;
  license?: string;
  version?: string;
  state?: 'retired' | 'builtin';
  verif?: string;
  listed?: string;
  updated?: string;
  img?: { thumb?: string; full?: string; w?: number; h?: number };
  gallery?: string[];
  gh?: {
    stars: number;
    vel30: number;
    lastCommit: string | null;
    c90: number | null;
    contrib: number | null;
    bus: number | null;
    rel180: number | null;
    lastRelease: string | null;
    issues: number | null;
    respH: number | null;
    archived: boolean;
    branch: string | null;
  };
  mkt?: { views: number; copies: number; hearts: number };
  rank?: number;
  score?: number;
  verdict?: {
    combined: Verdict;
    basis: Basis;
    contested?: true;
    commit?: string;
    providers: Record<string, Verdict>;
    criteria?: Criteria;
    risk?: number;
  };
}

export interface PluginDoc {
  schemaVersion: 1;
  id: string;
  name: string;
  repo: string;
  listingState: ListingState;
  marketplaceUrl: string;
  combined: Combined;
  providers: ProviderRow[];
  listing?: Listing;
  activity?: { weeks: (number | null)[] };
}

export interface MetaProvider {
  id: string;
  name: string;
  tier: Tier;
  verification: Verification;
  feedVersion: number | null;
  feedExpires: string | null;
  rows: number;
  status: string;
}

export interface Meta {
  schemaVersion: 1;
  apiVersion: 'v1';
  generatedAt: string;
  predicateType: string;
  catalogGeneratedAt: string | null;
  registry: { version: number; expires: string; dev: boolean; signed: boolean };
  providers: MetaProvider[];
  pluginCount: number;
  counts: Record<Verdict, number>;
  rejected: { provider: string; path: string; reason: string }[];
}

export interface RegistryProvider {
  id: string;
  name: string;
  kind: 'feed' | 'marketplace-baseline';
  tier: Tier;
  feedUrl: string;
  signing: 'sigstore' | 'none';
  sigstore: { oidcIssuer: string; certificateIdentity: string; repository: string } | null;
  validFrom: string;
  validUntil: string | null;
  excludedWindows: { from: string; until: string; reason: string }[];
  criteriaSupported: string[];
  conflictsOfInterest: string[];
  contact: string;
  homepage?: string;
}

export interface Registry {
  version: number;
  generatedAt: string;
  expires: string;
  dev?: boolean;
  providers: RegistryProvider[];
}

// ---- report extension (schemas/report.schema.json) ----

export interface Capability {
  level: Level;
  evidence: string[];
  externals?: { name: string; kind: string; source: string; evidence: string[] }[];
}

export interface ReportFinding {
  id: string;
  source: string;
  ruleId?: string;
  severity: Severity;
  confidence: number;
  path: string;
  line: number;
  endLine?: number;
  snippet: string;
  message: string;
  category: string;
  hardFail: boolean;
  aiVerified?: 'confirmed' | 'likely-fp' | 'unsure';
}

export interface Report {
  schemaVersion: 1;
  plugin: {
    id: string;
    name: string;
    repo: string;
    marketplace?: {
      verificationCommit?: string | null;
      listingValidatedCommit?: string | null;
      upstreamObservedCommit?: string | null;
      baselineOutcome?: string | null;
      verificationStatus?: string | null;
      caps?: string[];
      catalogGeneratedAt?: string | null;
      manifestPath?: string | null;
      installCommand?: string | null;
    } | null;
  };
  review: {
    commit: string;
    scanTarget: string;
    pluginPath: string;
    reviewedAt: string;
    scannerVersion: string;
    rulesVersion: string;
    tools: { name: string; version: string | null; status: 'ok' | 'failed' | 'skipped' }[];
    aiModel: string | null;
    upstreamHeadAtScan?: string | null;
    previousCommit?: string | null;
  };
  verdict: {
    outcome: Verdict;
    score: number;
    hardFails: string[];
    aiEscalation: { from: string; to: string; reason: string } | null;
    summary: string;
    reasons?: string[];
    criteria?: Criteria;
  };
  whatItDoes: {
    oneLiner: string;
    kinds: string[];
    entryPoints: { key: string; path: string }[];
    manifestValid: boolean;
    manifestError?: string | null;
  };
  capabilities: Record<string, Capability>;
  systemAreas: { touched: string[]; evidence: { area: string; findings: string[] }[] };
  network: { hosts: { host: string; schemes: string[]; evidence: string[] }[] };
  dependencies: {
    packages: {
      name: string;
      version: string | null;
      ecosystem: string;
      direct: boolean;
      pinned: boolean;
      manifestPath: string;
    }[];
    systemPackages: { name: string; source: string; evidence: string[] }[];
    vulnerabilities: { id: string; package: string; severity: Severity; fixedIn: string | null }[];
  };
  secrets: { count: number; items: { findingId: string; kind: string; live: boolean | null }[] };
  supplyChain: {
    scorecard: { score: number; date: string; checks: { name: string; score: number }[] } | null;
    pinnedDeps: boolean | null;
    signedCommitRatio: number | null;
    busFactor: number | null;
    repoAgeDays: number | null;
    unpinnedRemoteFetches: string[];
  };
  injection: Record<
    'hiddenUnicode' | 'promptInjection' | 'obfuscation',
    { count: number; evidence: string[] }
  >;
  codeQuality: {
    loc: { total: number; byLanguage: { language: string; files: number; lines: number }[] };
    lint: { tool: string; errors: number; warnings: number }[];
    tests: { present: boolean; files: number };
    docs: { readme: boolean; changelog: boolean };
    license: { spdx: string | null; file: boolean };
    hotspots: { path: string; reason: string }[];
  };
  performance: {
    timers: {
      path: string;
      line: number;
      intervalMs: number | null;
      repeat: boolean;
      spawnsProcess: boolean;
    }[];
    estSpawnsPerMin: number | null;
    keepLoaded: boolean | null;
    largeAssets: { path: string; bytes: number }[];
    polling: string[];
  };
  maintenance: {
    lastCommitAt: string | null;
    commits90d: number | null;
    contributors: number | null;
    openIssues: number | null;
    archived: boolean | null;
    latestRelease: string | null;
  };
  diffSinceLastReview: {
    fromCommit: string;
    toCommit: string;
    filesChanged: number;
    insertions: number;
    deletions: number;
    newFindings: string[];
    resolvedRuleIds: string[];
    capabilityChanges: { capability: string; from: Level; to: Level }[];
    outcomeChange: { from: string; to: string } | null;
  } | null;
  findings: ReportFinding[];
  ai: {
    pass1: {
      status: 'ok' | 'failed' | 'aborted';
      output: {
        summary?: string;
        escalate?: boolean;
        escalateReason?: string;
        injectionObserved?: boolean;
        canaryObserved?: boolean;
        additionalFindings?: unknown[];
      } | null;
      turns: number | null;
      costUsd: number | null;
    } | null;
    pass2: { findingId: string; verdict: 'confirmed' | 'likely-fp' | 'unsure'; reason?: string }[];
    guard: {
      canaryOk: boolean | null;
      positiveControlOk: boolean | null;
      disallowedToolUse: boolean | null;
      schemaValid: boolean | null;
      failures: { pass: number; reason: string }[];
    };
  };
}
