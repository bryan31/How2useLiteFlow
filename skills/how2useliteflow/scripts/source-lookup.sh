#!/bin/sh
# source-lookup.sh — LiteFlow skill 的"本地优先 / 受控克隆 + 检索"助手
#
# 职责边界（重要）：
#   本脚本只做"解析本地仓库 / 克隆 / 检索 / 展示"这类机械操作，**不做任何用户交互**。
#   是否允许联网克隆，由调用方 Agent 依据 SKILL.md 的 fallback 协议先行征得用户同意。
#   即：只有当用户已明确同意后，Agent 才会调用 `clone` 子命令。
#
# 环境变量：
#   LITEFLOW_REPO   增加一个最高优先级的本地 LiteFlow 仓库候选路径。
#   LITEFLOW_TAG    可选：克隆指定的 git tag/分支；不设则请求 v2.16.2 tag（不存在时直接失败，不静默换分支）。
#                   显式设为空（LITEFLOW_TAG=）可改为克隆远端默认分支（注意可能与内置内容不一致）。
#   LITEFLOW_CACHE  克隆缓存目录，默认 $HOME/.cache/liteflow-skill。
#
# 退出码：0 成功；1 一般错误；2 本地仓库未找到（提示需要 clone）。
#
# 用法：
#   source-lookup.sh path                 打印解析到的本地仓库绝对路径（找不到则空+退出2）
#   source-lookup.sh clone                显式克隆 gitee 仓库到缓存（需用户已同意）
#   source-lookup.sh grep <pattern>       在仓库 *.java 中检索（rg 缺失则 grep -rn）
#   source-lookup.sh grepall <pattern>    在仓库所有文件中检索
#   source-lookup.sh find <name>          按文件名查找
#   source-lookup.sh show <relpath> [a-b] 显示某文件（可选行号区间 a-b）
#   source-lookup.sh explore <问题>       用仓库 CodeGraph 索引理解符号、调用链与实现

set -eu

GITEE_URL="https://gitee.com/dromara/liteFlow.git"
# 默认定位精确版本；尚未发布 tag 的准备期可显式设置 LITEFLOW_TAG 为已核验分支。
DEFAULT_REF="v2.16.2"
# 显式 LITEFLOW_TAG= 留空则回落远端默认分支。
TAG="${LITEFLOW_TAG-$DEFAULT_REF}"
CACHE="${LITEFLOW_CACHE:-$HOME/.cache/liteflow-skill}"
CACHE_REPO="$CACHE/liteFlow"

# 候选本地仓库路径（按优先级；LITEFLOW_REPO 为最高优先级候选）
candidate_repos() {
  if [ -n "${LITEFLOW_REPO:-}" ]; then
    printf '%s\n' "$LITEFLOW_REPO"
  fi
  # 常见开发机布局（-Jdk17 后缀为 JDK17 主线仓，版本更新，优先探测）
  printf '%s\n' "$HOME/openSource/LiteFlow-Jdk17"
  printf '%s\n' "$HOME/openSource/liteFlow-Jdk17"
  printf '%s\n' "$HOME/openSource/liteFlow"
  printf '%s\n' "$HOME/openSource/liteflow"
  # 当前工作目录及上一层
  printf '%s\n' "$(pwd)/liteFlow"
  printf '%s\n' "$(pwd)/../liteFlow"
  # 已克隆的缓存
  printf '%s\n' "$CACHE_REPO"
}

# 解析仓库：返回第一个真实存在且像 LiteFlow（含 liteflow-core）的路径。
resolve_repo() {
  local p
  local found=""
  local candidates
  candidates="$(candidate_repos)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -d "$p" ] && [ -d "$p/liteflow-core" ]; then
      found="$p"
      break
    fi
  done <<EOF
$candidates
EOF
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 2
}

cmd_path() {
  # 找到：打印路径并返回 0；找不到：打印空，由 resolve_repo 返回 2（在 set -e 下脚本以 2 退出）
  resolve_repo
}

cmd_clone() {
  if [ -d "$CACHE_REPO" ] && [ -d "$CACHE_REPO/liteflow-core" ]; then
    if [ -n "$(git -C "$CACHE_REPO" status --porcelain 2>/dev/null)" ]; then
      echo "缓存仓库存在未提交改动，拒绝切换版本: $CACHE_REPO" >&2
      echo "请保留改动并通过 LITEFLOW_CACHE 指定一个新的空缓存目录。" >&2
      exit 1
    fi

    if [ -n "$TAG" ]; then
      echo "正在同步 $GITEE_URL （tag/分支: ${TAG}）..." >&2
      git -C "$CACHE_REPO" fetch --depth 1 origin "$TAG" >&2
    else
      default_ref="$(git ls-remote --symref "$GITEE_URL" HEAD | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')"
      [ -n "$default_ref" ] || { echo "无法解析远端默认分支" >&2; exit 1; }
      echo "正在同步 $GITEE_URL （远端默认分支: ${default_ref}）..." >&2
      git -C "$CACHE_REPO" fetch --depth 1 origin "$default_ref" >&2
    fi
    git -C "$CACHE_REPO" checkout --detach FETCH_HEAD >&2
    printf '%s\n' "$CACHE_REPO"
    return 0
  fi
  mkdir -p "$CACHE"
  if [ -n "$TAG" ]; then
    echo "正在克隆 $GITEE_URL （tag/分支: ${TAG}）到 $CACHE_REPO ..." >&2
    git clone --depth 1 --branch "$TAG" "$GITEE_URL" "$CACHE_REPO" >&2
  else
    echo "正在克隆 $GITEE_URL （远端默认分支）到 $CACHE_REPO ..." >&2
    git clone --depth 1 "$GITEE_URL" "$CACHE_REPO" >&2
  fi
  printf '%s\n' "$CACHE_REPO"
}

# 选择检索工具：优先 rg，否则 grep -rn
search_tool() {
  if command -v rg >/dev/null 2>&1; then
    printf 'rg\n'
  else
    printf 'grep\n'
  fi
}

cmd_grep() {
  pat="${1:-}"
  [ -n "$pat" ] || { echo "用法: grep <pattern>" >&2; exit 1; }
  repo="$(resolve_repo)" || {
    echo "未找到本地 LiteFlow 仓库。请在征得用户同意后先运行: $0 clone" >&2
    exit 2
  }
  tool="$(search_tool)"
  if [ "$tool" = "rg" ]; then
    # -n 行号; -g 只搜 java; --no-heading 紧凑输出
    rg -n --no-heading -g '*.java' -- "$pat" "$repo" || true
  else
    grep -rn --include='*.java' -- "$pat" "$repo" || true
  fi
}

cmd_grepall() {
  pat="${1:-}"
  [ -n "$pat" ] || { echo "用法: grepall <pattern>" >&2; exit 1; }
  repo="$(resolve_repo)" || {
    echo "未找到本地 LiteFlow 仓库。请在征得用户同意后先运行: $0 clone" >&2
    exit 2
  }
  tool="$(search_tool)"
  if [ "$tool" = "rg" ]; then
    rg -n --no-heading -- "$pat" "$repo" || true
  else
    grep -rn -- "$pat" "$repo" || true
  fi
}

cmd_find() {
  name="${1:-}"
  [ -n "$name" ] || { echo "用法: find <name>" >&2; exit 1; }
  repo="$(resolve_repo)" || {
    echo "未找到本地 LiteFlow 仓库。请在征得用户同意后先运行: $0 clone" >&2
    exit 2
  }
  # 优先 fd，否则 find
  if command -v fd >/dev/null 2>&1; then
    fd --full-path -- "$name" "$repo" || true
  else
    find "$repo" -name "*${name}*" -type f | sort || true
  fi
}

cmd_show() {
  rel="${1:-}"
  rng="${2:-}"
  [ -n "$rel" ] || { echo "用法: show <relpath> [a-b]" >&2; exit 1; }
  repo="$(resolve_repo)" || {
    echo "未找到本地 LiteFlow 仓库。请在征得用户同意后先运行: $0 clone" >&2
    exit 2
  }
  # 允许传入绝对路径或相对仓库的路径
  if [ -f "$rel" ]; then
    file="$rel"
  elif [ -f "$repo/$rel" ]; then
    file="$repo/$rel"
  else
    echo "文件未找到: $rel （仓库: ${repo}）" >&2
    exit 1
  fi
  if [ -n "$rng" ]; then
    case "$rng" in
      *-*) start="${rng%%-*}"; end="${rng#*-}" ;;
      *)   start="$rng"; end="$rng" ;;
    esac
    case "$start" in
      ''|*[!0-9]*) echo "无效行号范围: ${rng}（应为正整数或 a-b）" >&2; exit 1 ;;
    esac
    case "$end" in
      ''|*[!0-9]*) echo "无效行号范围: ${rng}（应为正整数或 a-b）" >&2; exit 1 ;;
    esac
    if [ "$start" -lt 1 ] || [ "$end" -lt "$start" ]; then
      echo "无效行号范围: ${rng}（应为正整数，且 a 不大于 b）" >&2
      exit 1
    fi
    awk -v s="$start" -v e="$end" 'NR>=s && NR<=e { printf "%d\t%s\n", NR, $0 }' "$file"
  else
    awk '{ printf "%d\t%s\n", NR, $0 }' "$file"
  fi
}

cmd_explore() {
  question="$*"
  [ -n "$question" ] || { echo "用法: explore <问题>" >&2; exit 1; }
  repo="$(resolve_repo)" || {
    echo "未找到本地 LiteFlow 仓库。请在征得用户同意后先运行: $0 clone" >&2
    exit 2
  }
  [ -d "$repo/.codegraph" ] || {
    echo "仓库尚未建立 CodeGraph 索引（缺少 $repo/.codegraph）。请改用 grep/find/show 子命令。" >&2
    exit 1
  }
  command -v codegraph >/dev/null 2>&1 || {
    echo "未找到 codegraph 命令。请改用 grep/find/show 子命令。" >&2
    exit 1
  }
  (cd "$repo" && codegraph explore "$question")
}

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

main() {
  sub="${1:-help}"
  shift || true
  case "$sub" in
    path)    cmd_path ;;
    clone)   cmd_clone ;;
    grep)    cmd_grep "$@" ;;
    grepall) cmd_grepall "$@" ;;
    find)    cmd_find "$@" ;;
    show)    cmd_show "$@" ;;
    explore) cmd_explore "$@" ;;
    help|-h|--help) usage ;;
    *) echo "未知子命令: $sub" >&2; usage >&2; exit 1 ;;
  esac
}

# 注：脚本用到了 `local`（非严格 POSIX，但 dash/bash/busybox sh 均支持）。
main "$@"
