#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
refscan-registry.py —— 从 npm 注册表推导 dsh 的 peer 补齐清单（权威方法）

=============================================================================
为什么需要这个脚本（上一版方法的根本缺陷）
=============================================================================
先前的方法（.patch-tools/refscan.mjs）扫描的是**已安装的 node_modules 树**，
找出「被 import 但解析不到」的包。这有个**循环依赖的致命缺陷**：

    没被装上的包，当然不会出现在安装树里；
    不在安装树里，就扫描不到；
    扫描不到，就报告「缺失 0 个」——即使它其实缺失。

实测事故：这个方法报告「缺失 0 个」，但 CI 的完整性断言在
`dsh-timeout` / `dsh-atomic-write` / `dsh-web-frontend` 上失败——
这三个包确实需要，只是从未被装上，因此从未被扫到。

=============================================================================
正确方法：遍历注册表依赖闭包，收集全部 peerDependencies
=============================================================================
dsh 的打包缺陷本质是：**子包把彼此声明为 peerDependencies，但主包 bundle
未把它们纳入 dependencies**。而 `--legacy-peer-deps` 会跳过所有 peer 解析。
于是这些 peer 既不在主包 dependencies 里，也不会被 npm 自动装上 → 运行期崩。

所以要补的集合 = **整个依赖闭包中所有 peerDependencies 的并集**，
再减去「已经在 dependencies 里会被自动装上的」。

闭包遍历方式：
  从 @deepseek-ai/dsh@<ver> 出发，按 dependencies 递归展开（深度限制防爆炸），
  对途经的每个 @deepseek-ai/* 子包，读取其 peerDependencies，
  凡版本范围能匹配本次 dsh 版本的一律纳入。

用法：
  python .patch-tools/refscan-registry.py --dsh-version 0.1.5-rc.2
  python .patch-tools/refscan-registry.py --dsh-version 0.1.5-rc.2 --powershell
"""

import argparse
import json
import re
import sys
import urllib.request
import urllib.error
from collections import deque

REGISTRY = "https://registry.npmmirror.com"


def fetch_pkg(name, version, timeout=20, cache=None):
    """取某个包的某个版本的 package.json（走 npmmirror，失败回退官方源）。"""
    if cache is not None and (name, version) in cache:
        return cache[(name, version)]
    last_err = None
    for base in (REGISTRY, "https://registry.npmjs.org"):
        url = "%s/%s/%s" % (base, name, version)
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                data = json.loads(r.read())
            if cache is not None:
                cache[(name, version)] = data
            return data
        except Exception as e:  # noqa: BLE001
            last_err = e
            continue
    raise RuntimeError("拉取 %s@%s 失败: %s" % (name, version, last_err))


def norm_version(spec):
    """从 '^0.1.5-rc.2' / '0.1.5-rc.2' / '~0.1.5-rc.2' 里取出裸版本号。"""
    if not spec:
        return None
    m = re.search(r"(\d+\.\d+\.\d+(?:-[0-9A-Za-z.\-]+)?)", spec)
    return m.group(1) if m else None


def resolve_spec(name, spec, dsh_version, cache, sdk_base):
    """
    决定子包用哪个版本去查注册表：
    - 若 spec 指向 dsh 版本族（形如 ^0.1.5-rc.2 且与本次 dsh 同族），用 dsh_version
    - 否则取 spec 里的裸版本
    """
    v = norm_version(spec)
    if v is None:
        return None
    # dsh 自家子包统一锁到本次 dsh 版本
    if name.startswith("@deepseek-ai/dsh") and v.startswith(sdk_base):
        return dsh_version
    return v


def is_dsh_family(name, spec, sdk_base):
    """
    判断一个 peer 包是否「版本号跟随 dsh 发布」。

    关键：**不能只看包名前缀**。反例——
      @deepseek-ai/cordis-plugin-group 的版本号是 1.0.1 / 1.0.2，
      与 dsh 的 0.1.5-rc.2 毫无关系；若按前缀当成 dsh 家族去装
      @deepseek-ai/cordis-plugin-group@0.1.5-rc.2，npm 直接 ETARGET 报错。

    正确判据：看 peer 声明里的**版本范围是否落在本次 dsh 的版本族**
    （主版本号/次版本号前缀相同）。相同则为 dsh 家族，跟随 dsh 版本；
    否则是独立演进的第三方包，必须保留其自身版本范围。
    """
    v = norm_version(spec)
    if not v or not sdk_base:
        return False
    return v.startswith(sdk_base)


def collect_conflicts(dsh_version, max_nodes=400, verbose=True):
    """
    遍历依赖闭包，返回：
      peers  —— 闭包中所有 peerDependencies 的并集（包名 -> 引用它的子包集合）
      auto   —— 已在主包 dependencies 里、会被 npm 自动装上的包
      meta   —— 包名 -> {"version": 解析到的版本, "is_dsh": 是否 dsh 自家子包}
      scanned—— 实际扫描的子包数
    """
    cache = {}
    sdk_base = dsh_version.split("-")[0]          # 例如 0.1.5
    root = "@deepseek-ai/dsh"
    root_pkg = fetch_pkg(root, dsh_version, cache=cache)
    root_deps = dict(root_pkg.get("dependencies", {}))

    # 主包 dependencies 会由 npm 自动安装 → 算“已覆盖”
    auto = set(root_deps)

    seen = set()
    queue = deque()
    for n, s in root_deps.items():
        if n.startswith("@deepseek-ai/"):
            queue.append((n, s, 1))

    peers = {}          # peer 包名 -> 引用它的子包集合
    meta = {}           # 包名 -> {"version": ..., "is_dsh": bool}
    scanned = 0

    while queue and scanned < max_nodes:
        name, spec, depth = queue.popleft()
        key = (name, spec)
        if key in seen:
            continue
        seen.add(key)

        ver = resolve_spec(name, spec, dsh_version, cache, sdk_base)
        if ver is None:
            continue
        try:
            pkg = fetch_pkg(name, ver, cache=cache)
        except Exception as e:  # noqa: BLE001
            if verbose:
                print("  [warn] 跳过 %s@%s: %s" % (name, ver, e), file=sys.stderr)
            continue
        scanned += 1

        # 收集该子包的 peerDependencies
        for pn, pspec in (pkg.get("peerDependencies") or {}).items():
            if pn.startswith("@deepseek-ai/"):
                peers.setdefault(pn, set()).add(name.split("/")[-1])
                # 记录该 peer 声明里要求的版本范围，用于判定它是否「跟随 dsh 版本」
                if pn not in meta:
                    meta[pn] = {
                        "version": norm_version(pspec) or "",
                        "is_dsh": is_dsh_family(pn, pspec, sdk_base),
                    }

        # 继续沿 dependencies 下钻
        if depth < 4:
            for dn, dspec in (pkg.get("dependencies") or {}).items():
                if dn.startswith("@deepseek-ai/"):
                    queue.append((dn, dspec, depth + 1))

    return peers, auto, meta, scanned


# 额外的第三方补位包：主包依赖树里已存在或需要锁定，版本号独立于 dsh。
# react 必须锁 18.x：dsh-web-frontend 依赖 react@^18.2.0，用 latest 会拉到 19.x（跨大版本不兼容）。
EXTRA_THIRD_PARTY = [
    ("@cfworker/json-schema", "^4.1.1"),
    ("react", "^18.3.1"),
    ("react-dom", "^18.3.1"),
    ("bufferutil", "^4.0.1"),
    ("utf-8-validate", "^5.0.2"),
    ("@types/react", "^18.3.12"),
]


def classify(need, meta):
    """
    把待补包按「版本是否跟随 dsh」分成两组：
      dsh_family  —— 用 $peerVer / $DSH_VERSION 拼版本串
      third_party —— 保留各自独立的版本范围

    判据来自 meta[name]["is_dsh"]，即 peer 声明里的版本范围是否落在 dsh 版本族，
    **不是**看包名前缀（见 is_dsh_family 的说明）。
    """
    dsh_family, third_party = [], []
    for p in need:
        info = meta.get(p)
        if info and info.get("is_dsh"):
            dsh_family.append(p)
        else:
            ver = (info or {}).get("version") or ""
            third_party.append((p, "^" + ver if ver else "*"))
    return dsh_family, third_party


def _emit(need, meta, indent, sep, quote, dsh_tmpl, entries_per_line):
    dsh_family, third_party = classify(need, meta)
    lines = []
    for i in range(0, len(dsh_family), entries_per_line):
        chunk = dsh_family[i:i + entries_per_line]
        lines.append("%s%s" % (indent, sep.join(quote % (p, dsh_tmpl) for p in chunk)))
    third_party += EXTRA_THIRD_PARTY
    lines.append("%s# --- 主包依赖树里已存在，但版本号独立于 dsh 的第三方包 ---" % indent)
    for i in range(0, len(third_party), entries_per_line):
        chunk = third_party[i:i + entries_per_line]
        lines.append("%s%s" % (indent, sep.join("'%s@%s'" % (n, v) for n, v in chunk)))
    return "\n".join(lines)


def emit_powershell(need, meta, indent="        ", entries_per_line=2):
    """生成 setup-windows.ps1 的 $PeerFix 内容（不含 @( ) 外壳）。"""
    return _emit(need, meta, indent, ", ", '"%s@%s"', "$peerVer", entries_per_line)


def emit_shell(need, meta, indent="    ", entries_per_line=2):
    """生成 setup-unix.sh 的 PEERS 内容（不含 ( ) 外壳）。"""
    return _emit(need, meta, indent, " ", '"%s@%s"', "$DSH_VERSION", entries_per_line)


def main():
    ap = argparse.ArgumentParser(
        description="从 npm 注册表推导 dsh 的 peer 补齐清单（权威方法）")
    ap.add_argument("--dsh-version", required=True,
                    help="目标 dsh 版本，例如 0.1.5-rc.2")
    ap.add_argument("--emit-ps1", action="store_true",
                    help="仅输出 $PeerFix 片段（供脚本替换）")
    ap.add_argument("--emit-sh", action="store_true",
                    help="仅输出 PEERS 片段（供脚本替换）")
    ap.add_argument("--json", action="store_true",
                    help="仅输出 JSON（供其它工具消费）")
    ap.add_argument("--who", action="store_true",
                    help="额外打印每个 peer 的引用方（诊断用）")
    args = ap.parse_args()

    peers, auto, meta, scanned = collect_conflicts(args.dsh_version, verbose=not args.json)

    # 需要显式补的 = peer 集合 - 主包 dependencies 已覆盖的
    need = sorted(p for p in peers if p not in auto)
    covered = sorted(p for p in peers if p in auto)

    dsh_family, third_party = classify(need, meta)

    if args.json:
        print(json.dumps({
            "dsh_version": args.dsh_version,
            "need": need,
            "dsh_family": dsh_family,
            "third_party": [{"name": n, "range": v} for n, v in third_party],
            "covered": covered,
            "scanned_subpackages": scanned,
            "peer_count": len(peers),
            "auto_covered_count": len(covered),
        }, indent=2, ensure_ascii=False))
        return 0

    if args.emit_ps1:
        print(emit_powershell(need, meta))
        return 0

    if args.emit_sh:
        print(emit_shell(need, meta))
        return 0

    print("从注册表推导 peer 补齐清单（dsh %s）..." % args.dsh_version)
    print("扫描子包 %d 个；发现 peer 依赖 %d 个" % (scanned, len(peers)))
    print("主包 dependencies 自动覆盖 %d 个；必须显式补齐 %d 个（其中跟随 dsh 版本 %d 个、独立版本 %d 个）"
          % (len(covered), len(need), len(dsh_family), len(third_party)))
    print()

    if covered:
        print("=== 已由主包 dependencies 覆盖，无需显式补（%d）===" % len(covered))
        for p in covered:
            print("  %s" % p)
        print()

    print("=== 必须显式补齐（%d）===" % len(need))
    for p in need:
        tag = "dsh" if p in set(dsh_family) else "3rd"
        if args.who:
            print("  [%s] %-46s <- %s" % (tag, p, ", ".join(sorted(peers[p]))))
        else:
            print("  [%s] %s" % (tag, p))

    print()
    print("提示：--emit-ps1 / --emit-sh 可生成可直接替换进 setup 脚本的片段。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
