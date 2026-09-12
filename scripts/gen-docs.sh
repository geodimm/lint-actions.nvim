#!/usr/bin/env bash
# Regenerate the Vim help files from the Markdown sources.
#
# Usage: scripts/gen-docs.sh <destination>
#
# Writes a complete doc/ directory into <destination>. `just docs` passes the
# repository root; `just docs-check` passes a temporary directory and diffs the
# result against the committed one.
#
# The Nix development shell provides panvimdoc and its pinned Pandoc dependency.

set -euo pipefail

# <project name>|<Markdown source>|<description in the help file's title line>
DOCUMENTS=(
  "lint-actions|README.md|Native LSP actions for structured fixes"
  "lint-actions-golangci|docs/golangci.md|golangci-lint actions through nvim-lint"
  "lint-actions-markdownlint|docs/markdownlint.md|markdownlint actions through nvim-lint"
  "lint-actions-shellcheck|docs/shellcheck.md|shellcheck actions through nvim-lint"
  "lint-actions-sarif|docs/sarif.md|reusable SARIF fix adapter"
)

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [ $# -ne 1 ]; then
  echo >&2 "usage: $0 <destination>"
  exit 2
fi
dest="$1"

mkdir -p "$dest/doc"
cd "$dest"

for document in "${DOCUMENTS[@]}"; do
  IFS='|' read -r project source description <<<"$document"
  # panvimdoc writes doc/<project>.txt relative to the working directory and
  # reports failures on stdout, so keep its output for the error path.
  # GITHUB_ACTIONS=true makes it look for its Lua filters in /scripts, which
  # only exists inside its own Docker action; unset it so it finds its own.
  # --demojify is deliberately absent. Its filter also swallows a colon that
  # follows inline code, turning "the kind `source.fixAll.shellcheck`: applies"
  # into one word. The Markdown sources carry no emoji, so it buys nothing.
  if ! out="$(GITHUB_ACTIONS=false panvimdoc \
    --project-name "$project" \
    --input-file "$root/$source" \
    --description "$description" \
    --shift-heading-level-by -1 \
    --toc true \
    --dedup-subheadings true \
    --doc-mapping true \
    --doc-mapping-project-name false 2>&1)"; then
    printf '%s\n' "$out" >&2
    exit 1
  fi
  # panvimdoc pads the blank lines inside code blocks; .editorconfig trims
  # trailing whitespace everywhere. sed -i is not portable, hence the copy.
  tmp="$(mktemp)"
  sed -e 's/[[:space:]]*$//' "doc/$project.txt" >"$tmp"
  mv "$tmp" "doc/$project.txt"
done

# doc/tags is committed: Neovim does not build it for plugins dropped into
# pack/*/start, and :help then fails with E149. Output is byte-identical across
# Neovim versions and locales, so it diffs cleanly. This also catches duplicate
# tags, which panvimdoc emits without complaining and plugin managers swallow
# behind a pcall. Neovim reports E154 on stderr but still exits 0, hence the
# stderr test.
if ! err="$(NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -c 'helptags doc' -c 'quitall' 2>&1)" || [ -n "$err" ]; then
  printf '%s\n' "$err" >&2
  echo >&2 "helptags rejected the generated vimdoc."
  exit 1
fi

# panvimdoc right-aligns a heading's tag at column 78 by padding, and silently
# emits no padding at all when the heading and its tag do not both fit. The tag
# then abuts the heading text, :helptags skips it, and every reference to it
# dangles. Report the cause rather than the symptom: shorten the heading.
glued="$(grep -nE '[^[:space:]][*|][A-Za-z0-9_.()-]+[*|]$' doc/*.txt || true)"
if [ -n "$glued" ]; then
  printf '%s\n' "$glued" >&2
  echo >&2 "A heading and its tag do not fit in 78 columns. Shorten the heading."
  exit 1
fi

# panvimdoc builds |cross-references| from a link's TEXT, ignoring its target,
# so [the providers below](#providers) emits a reference to
# |lint-actions-the-providers-below|, which no tag matches and :help cannot
# follow. The same applies to a `:h some-tag` that names a tag we do not build.
# Every project reference must resolve to a tag just built.
dangling=""
for ref in $(grep -hoE '\|lint[-_]actions[A-Za-z0-9_.()-]*\|' doc/*.txt | tr -d '|' | sort -u); do
  cut -f1 doc/tags | grep -qxF "$ref" || dangling="$dangling $ref"
done
if [ -n "$dangling" ]; then
  for ref in $dangling; do
    echo >&2 "Dangling help reference: |$ref|"
  done
  echo >&2 "A link's text must match the heading it points at, and a ':h' must name a real tag."
  exit 1
fi
