# Kuro's Wiki

A native macOS app that turns any folder of markdown files into a browsable, publishable wiki — maintained by your coding agent.

**[Download for macOS](https://github.com/sidharthmirch/kuros-wiki/releases/latest/download/KurosWiki-macOS.dmg)** (Apple Silicon + Intel, signed and notarized)

Based on [Andrej Karpathy's llm-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): instead of RAG, the LLM incrementally builds and maintains a persistent, interlinked wiki. You add sources; the agent reads them, writes summary pages, cross-references everything, and keeps it all consistent. The wiki compounds with every source you add.

## How it works

1. **Create a wiki** — Kuro's Wiki scaffolds the folder structure, build tools, and agent skills
2. **Open your agent** — use the built-in terminal or your own (Claude Code, Codex, Cursor)
3. **Add sources** — paste URLs, import from Readwise, or point at existing files
4. **Read and explore** — browse the compiled wiki with search, backlinks, and graph visualization

The agent does the grunt work: summarizing, cross-referencing, filing, and bookkeeping. You curate sources, ask questions, and think about what it all means.

## Building

Requires macOS 14+ and Swift 5.10+.

```
git clone https://github.com/sidharthmirch/kuros-wiki.git
cd kuros-wiki
swift build
.build/arm64-apple-macosx/debug/KurosWiki
```

## Architecture

- **SwiftUI** macOS app built with SwiftPM (no Xcode project)
- **JavaScriptCore** compiler turns markdown into styled HTML pages
- **SwiftTerm** embedded terminal for running coding agents
- **FSEvents** file watcher for live recompilation
- Wiki scaffold includes Claude Code skills for ingest, lint, and Readwise import

## Wiki structure

Each wiki folder is self-contained:

```
my-wiki/
  raw/            # immutable source documents
  wiki/           # agent-maintained markdown pages
    sources/      # one summary per ingested source
    home.md       # human entry point
    index.md      # agent catalog
    log.md        # chronological record
  site/           # build tools + compiled output
    build.js      # the wiki compiler
    style.css     # the wiki theme
    out/           # compiled HTML (gitignored)
  .kuros-wiki/    # app-owned workspace state
  .claude/        # agent skills and settings
  CLAUDE.md       # wiki schema
  llm-wiki.md     # Karpathy's pattern (reference)
```

See [`Sources/KurosWiki/Resources/scaffold/`](Sources/KurosWiki/Resources/scaffold/) for the full template — this is what gets copied when you create a new wiki, including the schema (`CLAUDE.md`), agent skills, and seed pages.

## Upstream tracking

This repo includes an upstream tracker that monitors:

- `TristanH/wikiwise` (`main`)
- `saivishnu2299/ambient-wikiwise` (`main`)

It generates change reports and suggested integration commands under `.upstream-tracker/reports/`, then updates a rolling automation PR.

Manual run:

```bash
python3 scripts/upstream_tracker.py run \
  --config .upstream-tracker/config.yml \
  --state .upstream-tracker/state.json \
  --out-dir .upstream-tracker/reports
```

See [`docs/upstream-tracking.md`](docs/upstream-tracking.md) for ownership rules, conflict behavior, and workflow details.

## License

GPLv3 — see [LICENSE](LICENSE)
