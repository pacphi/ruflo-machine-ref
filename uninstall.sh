#!/usr/bin/env bash
#
# uninstall.sh — remove what install.sh placed on this machine.
#
# Removes:
#   every helper this repo ships in bin/ from ~/.local/bin/ (derived from bin/,
#     so it always matches what install.sh placed — no drift)
#   ~/.config/ruflo/claude-md-template.md
#   the BEGIN/END ruflo-reference block from ~/.claude/CLAUDE.md (content
#     outside the sentinels is preserved)
#   the source line from ~/.zshrc / ~/.bashrc (this also disables the sourced
#     shell functions: ruflo-resync, ruflo-setup-project, ruflo-setup-aqe, etc.)
#
# Leaves your ruflo installation, memory DBs, and project files untouched. Per-project
# data this kit may have created (.swarm/, .claude-flow/, .agentic-qe/) is intentionally
# NOT touched — remove that per-project with `ruflo cleanup --force` if you want it gone.
#
# With --this-project, ALSO reverts the kit's statusline patches in the current repo's
# .claude/helpers/statusline.cjs (the activation footer, the console.log wrap, and the
# version-probe injection) — restoring ruflo's own render. It does NOT delete the
# statusline or any ruflo/agentic-qe data; run it from the project root.
#
# Usage: ./uninstall.sh [--dry-run] [--this-project]

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DRY=0
THIS_PROJECT=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--dry-run) DRY=1 ;;
		--this-project) THIS_PROJECT=1 ;;
		-h|--help) sed -n '3,24p' "$0" | sed 's|^# \{0,1\}||'; exit 0 ;;
		*) echo "Unknown flag: $1 (try --help)" >&2; exit 2 ;;
	esac
	shift
done

if [ -t 1 ]; then C_OK=$'\033[32m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'; else C_OK=""; C_DIM=""; C_RESET=""; fi
ok()  { printf '%s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; }
run() { if [ "$DRY" -eq 1 ]; then printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"; else eval "$*"; fi; }

# 1. bin scripts — derived from this repo's bin/, so it always matches install.sh.
for src in "$HERE"/bin/*; do
	[ -f "$src" ] || continue
	f="$HOME/.local/bin/$(basename "$src")"
	[ -f "$f" ] && { run "rm -f '$f'"; ok "removed $f"; }
done

# 2. template
[ -f "$HOME/.config/ruflo/claude-md-template.md" ] && { run "rm -f '$HOME/.config/ruflo/claude-md-template.md'"; ok "removed template"; }

# 3. CLAUDE.md managed block
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [ -f "$CLAUDE_MD" ] && grep -q '<!-- BEGIN ruflo-reference -->' "$CLAUDE_MD"; then
	if [ "$DRY" -eq 1 ]; then
		printf '%s[dry-run]%s strip ruflo-reference block from %s\n' "$C_DIM" "$C_RESET" "$CLAUDE_MD"
	else
		cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%Y%m%d-%H%M%S)"
		new=$(mktemp)
		awk '/<!-- BEGIN ruflo-reference -->/{skip=1} /<!-- END ruflo-reference -->/{skip=0; next} !skip' "$CLAUDE_MD" > "$new"
		mv "$new" "$CLAUDE_MD"
		ok "stripped ruflo-reference block (backup saved; rest of file preserved)"
	fi
fi

# 4. rc source lines
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
	if [ -f "$RC" ] && grep -qF "shell/ruflo-functions.sh" "$RC" 2>/dev/null; then
		if [ "$DRY" -eq 1 ]; then
			printf '%s[dry-run]%s remove source line from %s\n' "$C_DIM" "$C_RESET" "$RC"
		else
			cp "$RC" "$RC.bak.$(date +%Y%m%d-%H%M%S)"
			grep -v "shell/ruflo-functions.sh" "$RC" | grep -v "^# ruflo machine reference helpers$" > "$RC.tmp" && mv "$RC.tmp" "$RC"
			ok "removed source line from $RC (backup saved)"
		fi
	fi
done

# 5. (--this-project) revert the kit's statusline patches in the current repo.
if [ "$THIS_PROJECT" -eq 1 ]; then
	echo ""
	echo "## --this-project: revert statusline patches in $(pwd -P)"
	SL=".claude/helpers/statusline.cjs"
	if [ ! -f "$SL" ]; then
		ok "no $SL here — nothing to revert"
	elif ! grep -qE "ruflo-seg:BEGIN|ruflo-machine-ref:" "$SL"; then
		ok "$SL has no ruflo-machine-ref patches — nothing to revert"
	elif [ "$DRY" -eq 1 ]; then
		printf '%s[dry-run]%s strip activation footer + version-probe injection + console.log wrap from %s\n' "$C_DIM" "$C_RESET" "$SL"
	else
		cp "$SL" "$SL.bak.$(date +%Y%m%d-%H%M%S)"
		SL="$SL" node -e '
const fs=require("fs"); const f=process.env.SL; let s=fs.readFileSync(f,"utf8");
// activation footer (new BEGIN/END block) + the console.log wrap
s=s.replace(/\/\* ruflo-seg:BEGIN \*\/[\s\S]*?\/\* ruflo-seg:END \*\/\n?/,"");
// legacy single-function activation marker + its function
s=s.replace(/\/\* ruflo-machine-ref: activation segments \*\/\s*\nfunction rufloActivationSegments\(cwd\)\{[\s\S]*?\n\}\n/,"");
s=s.replace(/ \+ rufloActivationSegments\(process\.cwd\(\)\)/g,"");
// version-probe injection inside the pkgPaths array (restore "const pkgPaths = [")
s=s.replace(/(const pkgPaths = \[) \/\* ruflo-machine-ref: global-install version probe \*\/ require\("path"\)\.join\([^\n]*?"package\.json"\),/,"$1");
fs.writeFileSync(f,s);
' && ok "reverted statusline patches in $SL (backup saved; ruflo render restored)"
		echo "   (the pinned version-string fallback is left as-is — harmless; original value unknown)"
		echo "   To remove ruflo/agentic-qe DATA in this repo: ruflo cleanup --force"
	fi
fi

echo ""
ok "Uninstalled. Your ruflo install, memory DBs, and projects are untouched."
