#!/bin/sh
# Visual A/B: build a base ref and the current tree, run one scenario on both,
# and write the labeled compare panel with the delta column.
set -eu

usage() {
	cat <<'EOF'
usage: tools/visual-ab.sh --scenario PATH [options]

  --ref REF        base git ref (default origin/main)
  --scenario PATH  scenario to run on both builds (required)
  --size WxH       capture extent; omit to use the scenario or 1280x720
  --out DIR        output directory (default runs/visual-ab)
  --keep           keep the base worktree under build/visual-ab/base
EOF
}

die() {
	keep_base=1
	printf 'tools/visual-ab.sh: %s\n' "$*" >&2
	exit 1
}

die_usage() {
	printf 'tools/visual-ab.sh: %s\n' "$1" >&2
	usage >&2
	exit 2
}

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

ref=origin/main
scenario=
size=
out=runs/visual-ab
keep_base=0

while [ $# -gt 0 ]; do
	case $1 in
	--ref)
		[ $# -ge 2 ] || die_usage "--ref needs a value"
		ref=$2
		shift 2
		;;
	--scenario)
		[ $# -ge 2 ] || die_usage "--scenario needs a path"
		scenario=$2
		shift 2
		;;
	--size)
		[ $# -ge 2 ] || die_usage "--size needs WIDTHxHEIGHT"
		size=$2
		shift 2
		;;
	--out)
		[ $# -ge 2 ] || die_usage "--out needs a directory"
		out=$2
		shift 2
		;;
	--keep)
		keep_base=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die_usage "unknown argument: $1"
		;;
	esac
done

[ -n "$scenario" ] || die_usage "--scenario is required"
[ -f "$scenario" ] || die "scenario not found: $scenario"
if [ -n "$size" ]; then
	printf '%s' "$size" | grep -Eq '^[1-9][0-9]*x[1-9][0-9]*$' || die_usage "--size must be WIDTHxHEIGHT"
fi

command -v flock >/dev/null 2>&1 || die "flock is required to serialize runs"

abspath() {
	if command -v realpath >/dev/null 2>&1; then
		realpath -m "$1"
	else
		case $1 in
		/*) printf '%s\n' "$1" ;;
		*) printf '%s\n' "$root/$1" ;;
		esac
	fi
}

out_display=$out
out=$(abspath "$out")
[ "$out" = "/" ] && die "--out must not be /"
[ "$out" = "$root" ] && die "--out must not be the repository: $out"
case "$root/" in
"$out"/*) die "--out must not be the repository or its parent: $out" ;;
esac
scenario_abs=$(abspath "$scenario")
base_dir=$(abspath "$root/build/visual-ab/base")

mkdir -p .make
exec 9>.make/harbagsa-visual-ab.lock
if ! flock -n 9; then
	printf 'tools/visual-ab.sh: waiting for another visual A/B run\n' >&2
	flock 9
fi

if ! ref_commit=$(git rev-parse --verify --quiet "$ref^{commit}"); then
	die "cannot resolve --ref $ref"
fi
if ! head_commit=$(git rev-parse --verify --quiet 'HEAD^{commit}'); then
	die "cannot resolve HEAD"
fi
ref_short=$(git rev-parse --short "$ref_commit")
head_short=$(git rev-parse --short "$head_commit")

remove_base_worktree() {
	if git worktree list --porcelain 2>/dev/null | grep -Fqx "worktree $base_dir"; then
		git worktree remove --force "$base_dir" >/dev/null 2>&1 || true
	fi
	rm -rf "$base_dir" 2>/dev/null || true
	git worktree prune >/dev/null 2>&1 || true
}

cleanup() {
	status=$?
	if [ "$keep_base" -eq 0 ]; then
		remove_base_worktree
	elif [ -d "$base_dir" ]; then
		printf 'tools/visual-ab.sh: kept the base worktree at %s\n' "$base_dir" >&2
	fi
	exit "$status"
}
trap cleanup EXIT

rm -rf "$out" || die "cannot clear $out"
mkdir -p "$out" || die "cannot create $out"

printf 'tools/visual-ab.sh: base %s (%s)\n' "$ref" "$ref_short"
git worktree add --detach "$base_dir" "$ref_commit" || die "cannot create the base worktree"
if ! (cd "$base_dir" && ./tools/make.sh agent); then
	die "base build failed: $ref"
fi
printf 'tools/visual-ab.sh: current tree (%s)\n' "$head_short"
tools/make.sh agent || die "current build failed"

run_side() {
	side=$1
	binary=$2
	run_dir=$3
	if [ -n "$size" ]; then
		"$binary" run "$scenario_abs" --size "$size" --out "$run_dir"
	else
		"$binary" run "$scenario_abs" --out "$run_dir"
	fi
}

base_status=0
head_status=0
printf 'tools/visual-ab.sh: base run\n'
set +e
run_side base "$base_dir/bin/harbagsa-agent" "$out/base"
base_status=$?
set -e
printf 'tools/visual-ab.sh: current run\n'
set +e
run_side head "$root/bin/harbagsa-agent" "$out/head"
head_status=$?
set -e

if [ ! -f "$out/base/report.json" ] || [ ! -f "$out/head/report.json" ]; then
	printf 'tools/visual-ab.sh: a side wrote no report.json; base %s, current %s\n' "$base_status" "$head_status" >&2
	exit 1
fi

printf 'tools/visual-ab.sh: compare\n'
"$root/bin/harbagsa-agent" compare "$out/base" "$out/head" --out "$out/compare" --delta

printf 'visual A/B: base %s @ %s, current %s @ %s\n' "$ref" "$ref_short" HEAD "$head_short"
printf 'base report: %s/base/report.json\n' "$out"
printf 'current report: %s/head/report.json\n' "$out"
printf 'panel: %s/compare/compare.png\n' "$out"
printf 'base exit: %s, current exit: %s\n' "$base_status" "$head_status"

if [ "$base_status" -ne 0 ] || [ "$head_status" -ne 0 ]; then
	exit 1
fi
