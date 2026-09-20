#!/usr/bin/env python3
"""Validate the reviewed documentation inventory; this is not a semantic grader."""
import argparse
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import quote

SKILL = Path(__file__).resolve().parents[1]
GUIDES = {name: f"docs/liteflow-{name}-guide.md" for name in ("agent", "rule-db", "metrics")}
CORE = "docs/04.v2.16.X文档"


def headings(path):
    result, fence = [], None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            value = marker[1]
            if fence is None:
                fence = value
            elif value[0] == fence[0] and len(value) >= len(fence):
                fence = None
            continue
        if fence is None:
            match = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
            if match:
                result.append((len(match[1]), match[2], number))
    return result


def guide_units(path):
    heads = [h for h in headings(path) if h[0] in (2, 3)]
    units, parent = [], ""
    for index, (level, title, _) in enumerate(heads):
        if level == 2:
            parent = title
            if index + 1 < len(heads) and heads[index + 1][0] == 3:
                continue
        units.append(f"{parent} / {title}" if level == 3 else title)
    return units


def inventory(source, homepage):
    items = set()
    for group, document in GUIDES.items():
        for section in guide_units(source / document):
            items.add((group, document, section))
    core = homepage / CORE
    if not core.is_dir():
        raise ValueError(f"Core documentation directory missing: {core}")
    for file in core.rglob("*.md"):
        if any(p.startswith(("115.", "165.")) for p in file.relative_to(core).parts):
            continue  # These two topics are counted at guide-section granularity.
        items.add(("core", file.relative_to(homepage).as_posix(), ""))
    return items


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def anchor(title):
    return re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")


def report(data):
    groups = defaultdict(Counter)
    for row in data["units"]:
        groups[row["group"]][row["status"]] += 1
    total = len(data["units"])
    covered = sum(c["covered"] for c in groups.values())
    lines = ["# LiteFlow 2.16.2 技能覆盖报告", "",
             f"核验日期：{data['reviewed_at']}。知识基线：LiteFlow 2.16.2／AgentScope 2.0.3。",
             f"源码提交：`{data['source_commit']}`；官网提交：`{data['homepage_commit']}`。以工作区实际文件为准，包含尚未提交的官网文档；文件 SHA-256 记录在 [coverage-map.json](coverage-map.json)。", "",
             f"**已覆盖 {covered}／{total} 个功能单元，覆盖率 {covered / total:.2%}，目标至少 90%。**", "",
             "## 口径", "",
             "核心范围为官网 2.16.X 的每个 Markdown 页面；Rule-DB、Metrics 页面与源码 guide 重复，仅按 guide 计算。Agent、Rule-DB、Metrics 三份 guide 按三级标题划分；没有三级标题的二级章节独立计数。四级及更深内容归入所属单元，代码块中的注释不算标题。旧版文档、英文重复页面、宣传／更新日志不计入。", "",
             "covered 表示 reference 含本单元的主要用法、配置或 API 以及关键边界，并列出对应源码证据；partial 表示已提供部分说明但不足以代替该章节，按零分计；missing 也按零分计。每个单元等权，各分组也必须达到 90%。", "",
             "这是人工复核的文档功能覆盖率，不是 Java 行覆盖率、所有公开 API 的覆盖率或实测问答准确率。脚本校验分母完整性、文件指纹、reference 标题、源码证据与统计，不自动判断语义正确；只有读过正文才能更新 covered 状态。", "",
             "| 范围 | 已覆盖 | 部分 | 未覆盖 | 覆盖率 |", "|---|---:|---:|---:|---:|"]
    for group, counts in sorted(groups.items()):
        count = sum(counts.values())
        lines.append(f"| {group} | {counts['covered']}/{count} | {counts['partial']} | {counts['missing']} | {counts['covered']/count:.2%} |")
    lines += ["", "## 未计入覆盖的部分", ""]
    for row in data["units"]:
        if row["status"] != "covered":
            label = row["section"] or Path(row["document"]).name
            lines.append(f"- {row['group']}／{label}：{row['note']}")
    lines += ["", "## 复查", "", "```bash",
              "python3 skills/how2useliteflow/scripts/audit-coverage.py \\",
              "  --source /path/to/LiteFlow-Jdk17 \\",
              "  --homepage /path/to/liteflow-homepage", "```", "",
              "新增／删除章节、证据文件或已核验文档发生变化会使校验失败，须先重新审阅清单；脚本不会自动把新增内容标为已覆盖。核验通过后用 `--write-report` 更新本报告。Skill 结构另用 skill-creator 的 quick_validate.py 校验。", "",
              "## 本次验证", ""]
    lines.extend(f"- {item}" for item in data.get("validation", []))
    lines += ["", "## 逐项映射", "", "源码文件路径和 SHA-256 见 coverage-map.json 的 evidence 字段；以下链接直达技能正文。", ""]
    for group in sorted(groups):
        lines += [f"### {group}", "", "| 文档功能单元 | 状态 | 技能位置 |", "|---|---|---|"]
        for row in data["units"]:
            if row["group"] != group:
                continue
            label = row["section"] or str(Path(row["document"]).relative_to(CORE))
            label = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", label)
            links = "、".join(f"[{target['file']}：{target['heading']}]({quote(target['file'])}#{quote(anchor(target['heading']))})" for target in row["references"])
            lines.append(f"| {label.replace('|', '／')} | {row['status']} | {links} |")
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--homepage", required=True, type=Path)
    parser.add_argument("--write-report", action="store_true")
    args = parser.parse_args()
    data = json.loads((SKILL / "references/coverage-map.json").read_text(encoding="utf-8"))
    errors, keys, groups = [], [], defaultdict(Counter)
    roots = {"source": args.source, "homepage": args.homepage, "skill": SKILL}
    for row in data["units"]:
        keys.append((row["group"], row["document"], row["section"]))
        if row["status"] not in ("covered", "partial", "missing"):
            errors.append(f"Invalid status: {keys[-1]}")
        groups[row["group"]][row["status"]] += 1
        if row["status"] == "covered" and (not row["references"] or not row["evidence"]):
            errors.append(f"Missing coverage evidence: {keys[-1]}")
        if row["status"] != "covered" and not row.get("note"):
            errors.append(f"Missing gap explanation: {keys[-1]}")
        for ref in row["references"]:
            file = SKILL / "references" / ref["file"]
            if not file.is_file() or ref["heading"] not in [h[1] for h in headings(file)]:
                errors.append(f"Broken reference: {ref}")
        for evidence in row["evidence"]:
            if "source:" + evidence not in data["snapshots"]:
                errors.append(f"Untracked source evidence: {evidence}")
    if len(keys) != len(set(keys)):
        errors.append("Duplicate inventory rows")
    expected = inventory(args.source, args.homepage)
    for key in sorted(expected - set(keys)):
        errors.append(f"Unreviewed document unit: {key}")
    for key in sorted(set(keys) - expected):
        errors.append(f"Document unit removed: {key}")
    required_documents = {("homepage:" if g == "core" else "source:") + doc for g, doc, _ in expected}
    for key in required_documents - data["snapshots"].keys():
        errors.append(f"Untracked document: {key}")
    for key, sha in data["snapshots"].items():
        root, rel = key.split(":", 1)
        file = roots[root] / rel
        if not file.is_file() or digest(file) != sha:
            errors.append(f"Changed/missing reviewed file: {key}")
    for group, counts in groups.items():
        ratio = counts["covered"] / sum(counts.values())
        print(f"{group}: {counts['covered']}/{sum(counts.values())} = {ratio:.2%}")
        if ratio < 0.9:
            errors.append(f"Below 90%: {group}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    count = sum(row["status"] == "covered" for row in data["units"])
    print(f"TOTAL: {count}/{len(keys)} = {count/len(keys):.2%}; inventory, references and source snapshots verified")
    if args.write_report:
        (SKILL / "references/coverage.md").write_text(report(data), encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"Coverage audit failed: {error}", file=sys.stderr)
        sys.exit(1)
