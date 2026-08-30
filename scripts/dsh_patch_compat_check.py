#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dsh 品牌补丁兼容性校验

用途：升级 @deepseek-ai/dsh 版本前后，检查 brand-patch 里的文件是否仍适用。

做两件事：
  1) 基线判定 —— 对每个被补丁覆盖的文件，比较 patch 与 base/target 的差异行数，
     判断补丁实际是基于哪个版本改写的。
  2) 变更判定 —— 比较 base 与 target 的同名文件，判断升级是否会打回旧实现。

典型场景：
  - 升级前：--base 当前版本 --target 新版本
  - CI 断言：--expect-base 期望基线（通常等于 DSH_VERSION），不一致即失败

用法：
  python scripts/dsh_patch_compat_check.py --patch brand-patch/@deepseek-ai \
      --base 0.1.1-rc.1 --target 0.1.1-rc.2
  python scripts/dsh_patch_compat_check.py --patch brand-patch/@deepseek-ai \
      --base 0.1.1-rc.1 --target 0.1.1-rc.2 --expect-base 0.1.1-rc.2

退出码：
  0 = 全部通过；1 = 存在需确认项、阻断项或基线不符；2 = 参数/环境错误
"""

import argparse
import hashlib
import sys
import tarfile
import urllib.request
from pathlib import Path

REGISTRY = "https://registry.npmjs.org"


def tarball_url(pkg: str, ver: str) -> str:
    short = pkg.split("/")[-1]
    return f"{REGISTRY}/{pkg}/-/{short}-{ver}.tgz"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def cache_path(cache_dir: Path, pkg: str, ver: str) -> Path:
    short = pkg.split("/")[-1]
    return cache_dir / f"{short}-{ver}.tgz"


def fetch(pkg: str, ver: str, cache_dir: Path):
    """下载（或命中缓存）指定版本的 tarball，返回本地路径；失败返回 (None, 原因)。"""
    dest = cache_path(cache_dir, pkg, ver)
    if not dest.exists():
        url = tarball_url(pkg, ver)
        try:
            with urllib.request.urlopen(url, timeout=90) as r:
                dest.write_bytes(r.read())
        except Exception as exc:
            return None, f"{type(exc).__name__}: {exc}"
    return dest, None


def read_from_tar(tar_path: Path, file_rel: str):
    """从 npm tarball 中读取 package/<file_rel>；不存在返回 None。"""
    try:
        with tarfile.open(tar_path, "r:gz") as tf:
            handle = tf.extractfile(f"package/{file_rel}")
            return handle.read() if handle else None
    except (KeyError, tarfile.TarError):
        return None


def diff_lines(a: str, b: str) -> int:
    """两个文本之间的变更行数（统一 diff 的 +/- 行计数）。"""
    import difflib

    return sum(
        1
        for l in difflib.unified_diff(a.splitlines(), b.splitlines(), lineterm="", n=0)
        if l[:1] in "+-" and not l.startswith(("+++", "---"))
    )


def scan_patch(root: Path):
    """扫描补丁目录下所有文件，返回 [(包名, 包内相对路径, 本地路径)]。"""
    items = []
    for p in sorted(root.rglob("*")):
        if p.is_file():
            rel = p.relative_to(root)
            parts = rel.parts
            if len(parts) < 2:
                continue
            items.append((parts[0], "/".join(parts[1:]), p))
    return items


def main() -> int:
    # Windows 控制台默认 cp1252/gbk，输出中文会抛 UnicodeEncodeError，统一改为 UTF-8
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
        except (AttributeError, ValueError):
            pass

    ap = argparse.ArgumentParser(description="dsh 品牌补丁兼容性校验")
    ap.add_argument("--patch", required=True, help="brand-patch/@deepseek-ai 目录")
    ap.add_argument("--base", required=True, help="当前锁定的 dsh 版本，如 0.1.1-rc.1")
    ap.add_argument("--target", required=True, help="计划升级到的版本，如 0.1.1-rc.2")
    ap.add_argument("--scope", default="@deepseek-ai", help="npm scope")
    ap.add_argument("--expect-base", default=None,
                    help="期望的补丁基线版本；与实际基线不符则以退出码 1 失败")
    ap.add_argument("--cache", default=None, help="tarball 缓存目录")
    args = ap.parse_args()

    root = Path(args.patch)
    if not root.is_dir():
        print(f"[错误] 补丁目录不存在: {root}")
        return 2

    cache_dir = (
        Path(args.cache)
        if args.cache
        else Path(__file__).resolve().parent.parent / ".patch-check-cache"
    )
    cache_dir.mkdir(parents=True, exist_ok=True)

    items = scan_patch(root)
    print(f"补丁文件: {len(items)} 个，覆盖 {len({i[0] for i in items})} 个包")
    print(f"版本对比: {args.base} (base)  ->  {args.target} (target)")
    print("=" * 100)

    rows = []
    pkg_cache = {}
    for pkg, file_rel, local in items:
        full = pkg if "/" in pkg else f"{args.scope}/{pkg}"
        if pkg not in pkg_cache:
            b_tar, b_err = fetch(full, args.base, cache_dir)
            t_tar, t_err = fetch(full, args.target, cache_dir)
            pkg_cache[pkg] = (b_tar, b_err, t_tar, t_err)
        b_tar, b_err, t_tar, t_err = pkg_cache[pkg]

        if b_tar is None or t_tar is None:
            rows.append(("ERR  ", f"{pkg}/{file_rel}", "-", "-", "-", b_err or t_err or "tarball 不可用"))
            continue

        patch_bytes = local.read_bytes()
        base_bytes = read_from_tar(b_tar, file_rel)
        tgt_bytes = read_from_tar(t_tar, file_rel)

        if base_bytes is None:
            rows.append(("ERR  ", f"{pkg}/{file_rel}", "-", "-", "-", "base 版无此文件"))
            continue
        if tgt_bytes is None:
            rows.append(("BLOCK", f"{pkg}/{file_rel}", "-", "-", "-", "target 版无此文件，必须重做补丁"))
            continue

        patch_txt = patch_bytes.decode("utf-8", "replace")
        base_txt = base_bytes.decode("utf-8", "replace")
        tgt_txt = tgt_bytes.decode("utf-8", "replace")

        vs_base = diff_lines(base_txt, patch_txt)
        vs_target = diff_lines(tgt_txt, patch_txt)
        if args.base == args.target:
            # base 与 target 同一版本，无法区分差异，基线即该版本本身
            baseline = args.base
        else:
            baseline = (
                args.target if vs_target < vs_base
                else args.base if vs_base < vs_target
                else "identical"
            )

        if sha256(base_bytes) == sha256(tgt_bytes):
            status = "OK  "
            note = "新版未变动，补丁可直接沿用"
        else:
            status = "CHK "
            note = "新版该文件已变更，需确认补丁是否覆盖新修复"

        rows.append((status, f"{pkg}/{file_rel}", str(vs_base), str(vs_target), baseline, note))

    for status, name, vb, vt, baseline, note in rows:
        print(f"{status} | {name:<52} | vs_base={vb:<5} vs_target={vt:<5} | 基线={baseline:<12} | {note}")

    print("=" * 100)
    ok = sum(1 for r in rows if r[0] == "OK  ")
    chk = sum(1 for r in rows if r[0] == "CHK ")
    block = sum(1 for r in rows if r[0] == "BLOCK")
    err = sum(1 for r in rows if r[0] == "ERR ")

    baselines = {r[4] for r in rows if r[4] not in ("-",)}
    print(f"变更判定: 安全 {ok} / 需确认 {chk} / 阻断 {block} / 异常 {err}")
    print(f"补丁基线: {sorted(baselines) if baselines else '未知'}")

    failed = False
    if block or err:
        print("-> 存在阻断或异常，升级前必须处理。")
        failed = True
    if args.expect_base:
        wrong = [r[1] for r in rows if r[4] not in (args.expect_base, "-")]
        if wrong:
            print(f"-> 基线断言失败：期望 {args.expect_base}，以下文件不符：")
            for w in wrong[:20]:
                print(f"     {w}")
            failed = True
        else:
            print(f"-> 基线断言通过：全部文件基线为 {args.expect_base}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
