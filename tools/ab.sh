#!/bin/sh
# Paired A/B benchmark: build a base ref and the current tree, interleave the
# runs, and report medians and paired ratios. Alternating the order cancels
# clock drift; the ab lock is separate from the make lock so a build elsewhere
# does not wait on the whole matrix.
set -eu

usage() {
	cat <<'EOF'
usage: tools/ab.sh [options]

  --ref REF        base git ref (default origin/main)
  --scenario PATH  perf scenario; repeatable (default scenarios/perf.json)
  --size WxH       offscreen extent (default 2560x1440)
  --runs N         pairs per scenario (default 5)
  --prime SECONDS  time-based prime for every perf command (default 2.0)
  --out DIR        output directory (default runs/ab)
EOF
}

die() {
	keep_base=1
	printf 'tools/ab.sh: %s\n' "$*" >&2
	exit 1
}

die_usage() {
	printf 'tools/ab.sh: %s\n' "$1" >&2
	usage >&2
	exit 2
}

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

ref=origin/main
size=2560x1440
runs=5
prime=2.0
out=runs/ab
scenarios=

while [ $# -gt 0 ]; do
	case $1 in
	--ref)
		[ $# -ge 2 ] || die_usage "--ref needs a value"
		ref=$2
		shift 2
		;;
	--scenario)
		[ $# -ge 2 ] || die_usage "--scenario needs a path"
		if [ -z "$scenarios" ]; then
			scenarios=$2
		else
			scenarios="$scenarios
$2"
		fi
		shift 2
		;;
	--size)
		[ $# -ge 2 ] || die_usage "--size needs WIDTHxHEIGHT"
		size=$2
		shift 2
		;;
	--runs)
		[ $# -ge 2 ] || die_usage "--runs needs a count"
		runs=$2
		shift 2
		;;
	--prime)
		[ $# -ge 2 ] || die_usage "--prime needs seconds"
		prime=$2
		shift 2
		;;
	--out)
		[ $# -ge 2 ] || die_usage "--out needs a directory"
		out=$2
		shift 2
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

[ -n "$scenarios" ] || scenarios=scenarios/perf.json

printf '%s' "$runs" | grep -Eq '^[1-9][0-9]*$' || die_usage "--runs must be a positive integer"
printf '%s' "$prime" | grep -Eq '^[0-9]+([.][0-9]+)?$' || die_usage "--prime must be a non-negative number"
printf '%s' "$size" | grep -Eq '^[1-9][0-9]*x[1-9][0-9]*$' || die_usage "--size must be WIDTHxHEIGHT"
[ -n "$ref" ] || die_usage "--ref needs a value"
[ -n "$out" ] || die_usage "--out needs a directory"
command -v python3 >/dev/null 2>&1 || die "python3 is required for the reports"
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
case $out in
/) die "--out must not be /" ;;
esac
case "$root/" in
"$out"/*) die "--out must not be the repository or its parent: $out" ;;
esac
base_dir=$(abspath "$root/build/ab/base")

mkdir -p .make
exec 9>.make/harbagsa-ab.lock
if ! flock -n 9; then
	printf 'tools/ab.sh: waiting for another A/B run\n' >&2
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

ifs=$IFS
IFS='
'
set -- $scenarios
IFS=$ifs
for scenario in "$@"; do
	[ -f "$scenario" ] || die "scenario not found: $scenario"
done

command_line="tools/ab.sh --ref $ref --size $size --runs $runs --prime $prime --out $out_display"
for scenario in "$@"; do
	command_line="$command_line --scenario $scenario"
done

rm -rf "$out" || die "cannot clear $out"
mkdir -p "$out/logs" || die "cannot create $out"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/harbagsa-ab.XXXXXX") || die "cannot create a temporary directory"
keep_base=0
manifest=$tmp_dir/runs.tsv
: >"$manifest"

remove_base_worktree() {
	if git worktree list --porcelain 2>/dev/null | grep -Fqx "worktree $base_dir"; then
		git worktree remove --force "$base_dir" >/dev/null 2>&1 || true
	fi
	rm -rf "$base_dir" 2>/dev/null || true
	git worktree prune >/dev/null 2>&1 || true
}

cleanup() {
	status=$?
	rm -rf "$tmp_dir" || true
	if [ "$keep_base" -eq 0 ]; then
		remove_base_worktree
	elif [ -d "$base_dir" ]; then
		printf 'tools/ab.sh: kept the base worktree at %s\n' "$base_dir" >&2
	fi
	exit "$status"
}
trap cleanup EXIT

cat >"$tmp_dir/ab.py" <<'PY'
import datetime
import json
import math
import os
import statistics
import sys

METRICS = (
	("interval_p50", "frame interval p50", "ms", "interval"),
	("gpu_total", "GPU total", "ms", "GPU total"),
	("gpu_tlas", "GPU TLAS", "ms", "TLAS"),
	("gpu_depth", "GPU depth", "ms", "Depth"),
	("gpu_scene", "GPU scene", "ms", "Scene"),
	("gpu_taa", "GPU TAA", "ms", "TAA"),
	("gpu_overlay", "GPU overlay", "ms", "Overlay"),
)
SIDES = ("base", "optimized")


class Failure(Exception):
	pass


def cmd_patch(src, dst, prime_text):
	try:
		with open(src, encoding="utf-8") as handle:
			document = json.load(handle)
	except OSError as exc:
		print(f"ab: cannot read {src}: {exc}", file=sys.stderr)
		return 2
	except ValueError as exc:
		print(f"ab: invalid JSON in {src}: {exc}", file=sys.stderr)
		return 2
	try:
		prime = float(prime_text)
	except ValueError:
		print(f"ab: prime is not a number: {prime_text}", file=sys.stderr)
		return 2
	changed = False
	commands = document.get("commands") if isinstance(document, dict) else None
	if isinstance(commands, list):
		for command in commands:
			if isinstance(command, dict) and command.get("cmd") == "perf":
				command["prime"] = prime
				changed = True
	if not changed:
		return 3
	try:
		with open(dst, "w", encoding="utf-8") as handle:
			json.dump(document, handle, indent=2)
			handle.write("\n")
	except OSError as exc:
		print(f"ab: cannot write {dst}: {exc}", file=sys.stderr)
		return 2
	return 0


def load_json(path):
	try:
		with open(path, encoding="utf-8") as handle:
			return json.load(handle)
	except OSError as exc:
		raise Failure(f"cannot read {path}: {exc}") from exc
	except ValueError as exc:
		raise Failure(f"invalid JSON in {path}: {exc}") from exc


def finite(value):
	if isinstance(value, bool) or not isinstance(value, (int, float)):
		return None
	value = float(value)
	return value if math.isfinite(value) else None


def p50(value):
	if isinstance(value, dict):
		return finite(value.get("p50"))
	return finite(value)


def perf_of(report):
	perf = report.get("perf")
	if isinstance(perf, list):
		for entry in perf:
			if isinstance(entry, dict) and entry.get("name") == "perf":
				return entry
		for entry in perf:
			if isinstance(entry, dict):
				return entry
		return None
	if isinstance(perf, dict):
		return perf
	return None


def metrics_of(report, path):
	if not isinstance(report, dict):
		raise Failure(f"report is not an object: {path}")
	if report.get("ok") is False or report.get("exit_code", 0) != 0:
		raise Failure(f"run failed: {path}")
	perf = perf_of(report)
	if perf is None:
		raise Failure(f"no perf result: {path}")
	gpu = perf.get("gpu")
	if not isinstance(gpu, dict):
		gpu = {}
	metrics = {
		"interval_p50": p50(perf.get("interval")),
		"gpu_total": p50(gpu.get("total")),
		"gpu_tlas": p50(gpu.get("tlas")),
		"gpu_depth": p50(gpu.get("depth")),
		"gpu_scene": p50(gpu.get("scene")),
		"gpu_taa": p50(gpu.get("taa")),
		"gpu_overlay": p50(gpu.get("overlay")),
	}
	meta = {
		"name": perf.get("name") if isinstance(perf.get("name"), str) else None,
		"measured": perf.get("measured") if isinstance(perf.get("measured"), int) else None,
		"warmup": perf.get("warmup") if isinstance(perf.get("warmup"), int) else None,
		"prime_seconds": finite(perf.get("prime_seconds")),
	}
	return metrics, meta


def median(values):
	values = [value for value in values if value is not None]
	return statistics.median(values) if values else None


def ratio(numerator, denominator):
	if numerator is None or denominator is None or denominator == 0:
		return None
	return numerator / denominator


def read_manifest(path):
	runs = []
	try:
		with open(path, encoding="utf-8") as handle:
			for line in handle:
				line = line.rstrip("\n")
				if not line:
					continue
				parts = line.split("\t")
				if len(parts) != 6:
					raise Failure(f"bad manifest line: {line!r}")
				index, scenario, pair, side, prime_used, run_dir = parts
				if side not in SIDES:
					raise Failure(f"bad side in the manifest: {side}")
				runs.append({
					"scenario_index": int(index),
					"scenario": scenario,
					"pair": int(pair),
					"side": side,
					"prime_used": prime_used,
					"run_dir": run_dir,
				})
	except OSError as exc:
		raise Failure(f"cannot read the manifest: {exc}") from exc
	except ValueError as exc:
		raise Failure(f"bad manifest value: {exc}") from exc
	if not runs:
		raise Failure("the manifest holds no runs")
	return runs


def group_runs(runs):
	groups = {}
	order = []
	for run in runs:
		key = (run["scenario_index"], run["scenario"])
		if key not in groups:
			groups[key] = []
			order.append(key)
		groups[key].append(run)
	order.sort()
	return [{"scenario": key[1], "runs": groups[key]} for key in order]


def build_scenario(raw):
	pairs = {}
	for run in raw["runs"]:
		report_path = os.path.join(run["run_dir"], "report.json")
		report = load_json(report_path)
		metrics, perf = metrics_of(report, report_path)
		pair = pairs.setdefault(run["pair"], {"pair": run["pair"], "order": [], "runs": {}})
		if run["side"] in pair["runs"]:
			raise Failure(f"duplicate {run['side']} run for pair {run['pair']}")
		pair["order"].append(run["side"])
		pair["runs"][run["side"]] = {
			"run_dir": run["run_dir"],
			"prime_used": run["prime_used"],
			"metrics": metrics,
			"perf": perf,
		}
	ordered = []
	for index in sorted(pairs):
		pair = pairs[index]
		for side in SIDES:
			if side not in pair["runs"]:
				raise Failure(f"missing {side} run for pair {index} in {raw['scenario']}")
		pair["ratios"] = {
			key: ratio(pair["runs"]["optimized"]["metrics"][key], pair["runs"]["base"]["metrics"][key])
			for key, _, _, _ in METRICS
		}
		ordered.append(pair)
	medians = {
		side: {key: median([pair["runs"][side]["metrics"][key] for pair in ordered]) for key, _, _, _ in METRICS}
		for side in SIDES
	}
	paired = {key: median([pair["ratios"][key] for pair in ordered]) for key, _, _, _ in METRICS}
	of_medians = {
		key: ratio(medians["optimized"][key], medians["base"][key]) for key, _, _, _ in METRICS
	}
	return {
		"scenario": raw["scenario"],
		"base_prime_supported": all(
			pair["runs"]["base"]["prime_used"] == "patched" for pair in ordered
		),
		"pairs": ordered,
		"medians": medians,
		"paired_ratio": paired,
		"ratio_of_medians": of_medians,
	}


def fmt(value, digits=3):
	return "n/a" if value is None else f"{value:.{digits}f}"


def table_row(cells):
	return "| " + " | ".join(cells) + " |"


def render(data):
	base = data["base"]
	head = data["optimized"]
	lines = [
		"# Paired A/B benchmark",
		"",
		f"- base: `{base['ref']}` @ `{base['short']}`",
		f"- optimized: `HEAD` @ `{head['short']}`",
		f"- extent: `{data['size']}`",
		f"- pairs per scenario: {data['runs']}",
		f"- prime: `{data['prime_seconds']:g}` s",
	]
	if not data["base_prime_supported"]:
		lines.append(
			"- base prime: unsupported; the base ran the original scenario with its default priming only"
		)
	lines.extend([
		f"- command: `{data['command']}`",
		"",
		"Values are milliseconds. Each side's column is the median over the pairs; the ratio is the median of the per-pair ratios, optimized/base. `n/a` means the report did not carry the metric. An old report carries scalar GPU means; a new report carries p50.",
	])
	for scenario in data["scenarios"]:
		lines.extend(["", f"## `{scenario['scenario']}`", ""])
		lines.append(table_row([
			"metric",
			f"base @ {base['short']}",
			f"optimized @ {head['short']}",
			"optimized/base",
		]))
		lines.append(table_row(["---", "---:", "---:", "---:"]))
		for key, label, unit, _ in METRICS:
			lines.append(table_row([
				f"{label} ({unit})",
				fmt(scenario["medians"]["base"][key]),
				fmt(scenario["medians"]["optimized"][key]),
				fmt(scenario["paired_ratio"][key], 4),
			]))
		lines.extend([
			"",
			f"Medians over {len(scenario['pairs'])} pair(s).",
			"",
			"Per-pair ratios (optimized/base):",
			"",
		])
		lines.append(table_row(["pair", "order"] + [short for _, _, _, short in METRICS]))
		lines.append(table_row(["---", "---"] + ["---:"] * len(METRICS)))
		for pair in scenario["pairs"]:
			lines.append(table_row(
				[str(pair["pair"]), ",".join(pair["order"])]
				+ [fmt(pair["ratios"][key], 4) for key, _, _, _ in METRICS]
			))
		if not scenario["base_prime_supported"]:
			lines.extend([
				"",
				"The base rejected the prime field, so its runs used the original scenario. Base and optimized priming therefore differ.",
			])
	return "\n".join(lines) + "\n"


def cmd_summary(args):
	(
		manifest_path,
		out_dir,
		base_ref,
		base_commit,
		head_commit,
		size,
		runs,
		prime,
		command,
	) = args
	data = {
		"tool": "tools/ab.sh",
		"generated_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
		"command": command,
		"base": {"ref": base_ref, "commit": base_commit, "short": base_commit[:7]},
		"optimized": {"ref": "HEAD", "commit": head_commit, "short": head_commit[:7]},
		"size": size,
		"runs": int(runs),
		"prime_seconds": float(prime),
		"scenarios": [
			build_scenario(raw) for raw in group_runs(read_manifest(manifest_path))
		],
	}
	data["base_prime_supported"] = all(
		scenario["base_prime_supported"] for scenario in data["scenarios"]
	)
	data["metrics"] = [
		{"key": key, "label": label, "unit": unit} for key, label, unit, _ in METRICS
	]
	document = render(data)
	with open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8") as handle:
		handle.write(document)
	with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as handle:
		json.dump(data, handle, indent=2)
		handle.write("\n")
	sys.stdout.write(document)
	return 0


def main(argv):
	if len(argv) == 5 and argv[1] == "patch":
		return cmd_patch(argv[2], argv[3], argv[4])
	if len(argv) == 11 and argv[1] == "summary":
		return cmd_summary(argv[2:])
	print("ab.py: bad arguments", file=sys.stderr)
	return 2


if __name__ == "__main__":
	try:
		sys.exit(main(sys.argv))
	except Failure as exc:
		print(f"ab: {exc}", file=sys.stderr)
		sys.exit(1)
PY

remove_base_worktree
[ ! -e "$base_dir" ] || die "cannot remove $base_dir"
mkdir -p "$(dirname "$base_dir")"
printf 'tools/ab.sh: building base %s (%s) in %s\n' "$ref" "$ref_short" "${base_dir#"$root"/}"
git worktree add --detach "$base_dir" "$ref_commit" || die "cannot create the base worktree"
if ! (cd "$base_dir" && ./tools/make.sh build); then
	die "base build failed: $ref"
fi
[ -x "$base_dir/bin/harbagsa-agent" ] || die "the base build wrote no bin/harbagsa-agent"
base_bin=$tmp_dir/agent-base
cp "$base_dir/bin/harbagsa-agent" "$base_bin" || die "cannot copy the base binary"

printf 'tools/ab.sh: building the current tree (%s)\n' "$head_short"
tools/make.sh build || die "current build failed"
[ -x bin/harbagsa-agent ] || die "the current build wrote no bin/harbagsa-agent"
head_bin=$tmp_dir/agent-optimized
cp bin/harbagsa-agent "$head_bin" || die "cannot copy the current binary"

run_agent() {
	set +e
	"$1" run "$2" --size "$size" --out "$3" >"$4" 2>"$5"
	run_status=$?
	set -e
	return "$run_status"
}

report_failure() {
	keep_base=1
	printf 'tools/ab.sh: %s run failed with exit %s\n' "$1" "$2" >&2
	printf 'tools/ab.sh: logs: %s %s\n' "$3" "$4" >&2
	[ ! -f "$3" ] || tail -n 5 "$3" >&2 || true
	[ ! -f "$4" ] || tail -n 20 "$4" >&2 || true
}

scenario_index=0
for scenario in "$@"; do
	scenario_index=$((scenario_index + 1))
	stem=$(basename "$scenario")
	case $stem in
	*.json) stem=${stem%.json} ;;
	esac
	patched=$tmp_dir/scenario-$scenario_index-$stem.prime.json
	set +e
	python3 "$tmp_dir/ab.py" patch "$scenario" "$patched" "$prime"
	patch_status=$?
	set -e
	case $patch_status in
	0) ;;
	3) die "scenario has no perf command: $scenario" ;;
	*) die "cannot prepare the prime scenario: $scenario" ;;
	esac

	scenario_out=$out/scenario-$scenario_index-$stem
	mkdir -p "$scenario_out" || die "cannot create $scenario_out"
	base_prime=unknown
	pair=0
	while [ "$pair" -lt "$runs" ]; do
		if [ $((pair % 2)) -eq 0 ]; then
			order="base optimized"
		else
			order="optimized base"
		fi
		for side in $order; do
			case $side in
			base) bin=$base_bin ;;
			*) bin=$head_bin ;;
			esac
			run_dir=$scenario_out/pair-$pair/$side
			tag=scenario-$scenario_index-pair-$pair-$side
			run_scenario=$patched
			prime_used=patched
			if [ "$side" = base ] && [ "$base_prime" = no ]; then
				run_scenario=$scenario
				prime_used=original
			fi
			stdout_log=$out/logs/$tag.stdout.log
			stderr_log=$out/logs/$tag.stderr.log
			printf 'tools/ab.sh: pair %s/%s %s\n' "$((pair + 1))" "$runs" "$side" >&2
			if run_agent "$bin" "$run_scenario" "$run_dir" "$stdout_log" "$stderr_log"; then
				status=0
			else
				status=$?
			fi
			if [ "$status" -ne 0 ] && [ "$side" = base ] && [ "$prime_used" = patched ] && [ "$status" -eq 2 ]; then
				printf 'tools/ab.sh: base rejected --prime; retrying with %s\n' "$scenario" >&2
				run_scenario=$scenario
				prime_used=original
				stdout_log=$out/logs/$tag-fallback.stdout.log
				stderr_log=$out/logs/$tag-fallback.stderr.log
				if run_agent "$bin" "$run_scenario" "$run_dir" "$stdout_log" "$stderr_log"; then
					status=0
				else
					status=$?
				fi
			fi
			if [ "$status" -ne 0 ]; then
				report_failure "$side" "$status" "$stdout_log" "$stderr_log"
				exit 1
			fi
			if [ "$side" = base ]; then
				if [ "$prime_used" = original ]; then
					base_prime=no
				else
					base_prime=yes
				fi
			fi
			if [ ! -f "$run_dir/report.json" ]; then
				keep_base=1
				printf 'tools/ab.sh: missing report.json after a %s run: %s\n' "$side" "$run_dir" >&2
				exit 1
			fi
			printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
				"$scenario_index" "$scenario" "$pair" "$side" "$prime_used" "$run_dir" \
				>>"$manifest"
		done
		pair=$((pair + 1))
	done
done

python3 "$tmp_dir/ab.py" summary \
	"$manifest" "$out" "$ref" "$ref_commit" "$head_commit" \
	"$size" "$runs" "$prime" "$command_line" \
	|| die "cannot write the summary"

printf '\ntools/ab.sh: wrote %s and %s\n' "$out/summary.md" "$out/summary.json"
