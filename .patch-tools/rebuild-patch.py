# -*- coding: utf-8 -*-
"""
rebuild-patch.py — 把 brand-patch 从旧 dsh 基线重建到新基线。

背景
----
USB-Harness 的 brand-patch 早期抄了一段"整文件覆盖"的发行版产物当作补丁：
补丁文件 = 上游旧版文件 + 少量定制。这带来一个隐蔽且危险的问题 ——
每次升级 dsh，如果直接沿用旧补丁，就会把上游在新版里做的**全部修复一起回滚**
（静默地，因为文件照样能加载）。历史事故：升级 0.1.5 时 12 个文件里有 9 个
只含"纯品牌改名"，却覆盖掉了上游大量功能性修复。

本脚本的做法
------------
以"上游新基线"为底，把**意图化的定制清单**重新施加（re-apply）上去：
  - 品牌改名类：纯字符串替换，在新文件上重做
  - 逻辑定制类：带锚点的结构化替换（锚点在脚本里显式声明）
  - 无法自动施加的：报 OUTDATED 错误，要求人工迁移（防止静默丢失定制）

用法
----
  python .patch-tools/rebuild-patch.py --base 0.1.1-rc.2 --target 0.1.5-rc.2 --diff   # 只报告
  python .patch-tools/rebuild-patch.py --base 0.1.1-rc.2 --target 0.1.5-rc.2 --write  # 写入 brand-patch
"""
import argparse
import io
import os
import re
import sys
import difflib

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = os.path.join(ROOT, ".tmp-upstream")

# 文件名 -> 包名（brand-patch 内的布局：<包名>/<包内相对路径>）
PATCH_FILES = [
    "dsh/lib/bin.js",
    "dsh-app-boot/lib/index.js",
    "dsh-base/cordis.patch.yml",
    "dsh-client-connection/lib/client.js",
    "dsh-client-ui-brand-official/lib/client.js",
    "dsh-client-ui-conversation/lib/client.js",
    "dsh-client-ui-permission-presets/lib/client.js",
    "dsh-client-ui-renderer/lib/client.js",
    "dsh-client-ui-settings-models/lib/client.js",
    "dsh-llm-deepseek/lib/index.js",
    "dsh-skill-badge/lib/index.js",
    "dsh-system-prompt/lib/index.js",
    "dsh-web-app/lib/index.js",
    "dsh-web-app/lib/startup.js",
    "dsh-web-frontend/dist/favicon.svg",
    "dsh-web-frontend/dist/index.html",
    "dsh-web-frontend/dist/manifest.webmanifest",
]


def read(p):
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return None


def upstream(version, rel):
    parts = rel.split("/")
    pkg, inner = parts[0], "/".join(parts[1:])
    return os.path.join(TMP, "pkg", version, pkg, "package", *inner.split("/"))


def patch_path(rel):
    return os.path.join(ROOT, "brand-patch", "@deepseek-ai", *rel.split("/"))


# ---------------------------------------------------------------------------
# 定制清单：每条 = (rel, kind, payload)
#   kind = "sub"    : [(old, new), ...] 纯字符串替换（品牌改名）
#   kind = "anchor" : [(anchor_before, old_block, new_block), ...] 锚点定位后整体替换
#   kind = "manual" : 需人工迁移，脚本拒绝自动施加
# ---------------------------------------------------------------------------
BRAND_SWAPS = [
    ("DeepSeek Harness", "USB Harness"),
]


def build_manifest(target):
    """返回 {rel: [(kind, payload), ...]} 形式的定制清单。"""
    m = {}

    # ---- dsh/lib/bin.js：只有一处品牌改名（其余为上游构建产物差异）----
    m["dsh/lib/bin.js"] = [
        ("sub", [("boot a DeepSeek Harness profile", "boot a USB Harness profile")]),
    ]

    # ---- dsh-app-boot/lib/index.js：FAT32/exFAT 无符号链接回退 + 品牌 ----
    m["dsh-app-boot/lib/index.js"] = [
        (
            "anchor",
            [
                # ① import 增加 cpSync
                (
                    'import { existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";',
                    'import { cpSync, existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";',
                ),
                # ② ensureSymlink 的文档
                (
                    "/** Ensure `link` is a symlink to `target`, replacing a wrong or dangling link; a real directory throws. */",
                    "/** Ensure `link` resolves to `target`: a symlink where the filesystem supports it, otherwise a real directory copy (FAT32/exFAT). */",
                ),
            ],
        ),
        # ③ 真实目录视为已就绪（幂等）—— 针对新版符号链接版本做迁移
        (
            "block_or_fail",
            (
                "symlink-exists-not-link",
                None,
            ),
        ),
        ("sub", [("The DeepSeek Harness implementation checkout", "The USB Harness implementation checkout")]),
    ]

    # ---- dsh-base/cordis.patch.yml：解绑官方 provider，改走自定义 OpenAI 兼容网关 ----
    m["dsh-base/cordis.patch.yml"] = [("yaml_usb_base", None)]

    # ---- 纯品牌改名 ----
    for rel in [
        "dsh-client-connection/lib/client.js",
        "dsh-llm-deepseek/lib/index.js",
        "dsh-system-prompt/lib/index.js",
        "dsh-web-app/lib/index.js",
        "dsh-client-ui-brand-official/lib/client.js",
    ]:
        m.setdefault(rel, []).append(("sub", BRAND_SWAPS))

    # ---- dsh-web-app/lib/startup.js：品牌改名 + 放行 --host 0.0.0.0 ----
    #      上游刻意禁止 0.0.0.0（"would expose remote code execution to the network"），
    #      但 USB-Harness 的核心场景就是 U 盘插在一台机器上、同局域网其他设备访问，
    #      因此必须移除该拦截。这是功能性定制，不是品牌改名，不能只按品牌处理。
    m["dsh-web-app/lib/startup.js"] = [
        ("sub", BRAND_SWAPS),
        ("allow_all_interfaces", None),
    ]

    # ---- dsh-llm-deepseek：provider 显示名改 USB Harness ----
    m["dsh-llm-deepseek/lib/index.js"] = [
        ("sub", [
            # 只改面向用户的 displayName / 展示 name，保留包名与 provider id（协议标识不能动）
            ('displayName: "DeepSeek"', 'displayName: "USB Harness"'),
        ]),
        ("llm_deepseek_name", None),
    ]

    # ---- dsh-client-ui-renderer：上游已把 DocumentTitle 移出本包（0.1.5 起）----
    #      定制点消失，补丁改为"仅承载品牌替换"；若上游重新引入则本项会报错提示人工处理。
    m["dsh-client-ui-renderer/lib/client.js"] = [("document_title_recheck", None)]

    # ---- dsh-client-ui-brand-official：自绘 USB 图标（去 FishLogo 依赖）----
    m["dsh-client-ui-brand-official/lib/client.js"].append(("usb_brand_icon", None))

    # ---- dsh-client-ui-conversation：抹掉 "预览版" 角标 ----
    m["dsh-client-ui-conversation/lib/client.js"] = [("hero_preview_badge", None)]

    # ---- dsh-client-ui-permission-presets：权限预设名本地化修复 ----
    m["dsh-client-ui-permission-presets/lib/client.js"] = [("permission_preset_i18n", None)]

    # ---- dsh-client-ui-settings-models：无内置 provider 时直接弹自定义网关表单 ----
    m["dsh-client-ui-settings-models/lib/client.js"] = [("onboarding_custom_provider", None)]

    # ---- dsh-skill-badge：品牌改名（含 "powered by dsh"）----
    m["dsh-skill-badge/lib/index.js"] = [
        ("sub", [
            ("powered by dsh", "powered by USB Harness"),
            ("produced with DeepSeek Harness", "produced with USB Harness"),
            ("asks for a dsh badge, powered-by-dsh attribution, or a reusable dsh badge",
             "asks for a USB Harness badge, powered-by-USB-Harness attribution, or a reusable USB Harness badge"),
            ("produced with USB Harness", "produced with USB Harness"),
        ]),
    ]

    # ---- web frontend：标题 / manifest / favicon / crypto.randomUUID 兜底 ----
    m["dsh-web-frontend/dist/index.html"] = [("web_index_html", None)]
    m["dsh-web-frontend/dist/manifest.webmanifest"] = [("web_manifest", None)]
    m["dsh-web-frontend/dist/favicon.svg"] = [("web_favicon", None)]

    return m


# ---------------------------------------------------------------------------
# 各"结构化定制"的具体施加逻辑
# ---------------------------------------------------------------------------
def apply_base_yaml(text, log):
    """dsh-base/cordis.patch.yml —— 4 处定制。"""
    out = text

    # ① agent-default-model: 不再默认指向官方 provider
    old = "    - id: agent-default-model\n      name: '@deepseek-ai/dsh-agent-default-model'\n      config:\n        provider: deepseek-official\n"
    new = (
        "    # USB Harness: 默认不指向任何内置 provider（占位值），用户首次在模型页配置\n"
        "    # 自定义 OpenAI 兼容网关并在模型选择器里选定真实模型后，会覆盖此默认。\n"
        "    - id: agent-default-model\n      name: '@deepseek-ai/dsh-agent-default-model'\n      config:\n        provider: pi-ai\n"
    )
    if old in out:
        out = out.replace(old, new, 1)
        log("① agent-default-model provider -> pi-ai")
    elif "provider: pi-ai" in out:
        log("① agent-default-model 已是 pi-ai（跳过）")
    else:
        log("① !! 未命中 agent-default-model 锚点")

    # ② model: deepseek-* -> default（占位）
    m = re.search(r"(    - id: agent-default-model\n.*?\n      config:\n        provider: pi-ai\n        model: )(\S+)", out, re.S)
    if m and m.group(2).startswith("deepseek"):
        out = out[:m.start(2)] + "default" + out[m.end(2):]
        log("② agent-default-model model -> default")
    else:
        log("② agent-default-model model 已是占位（跳过）")

    # ③ web.searchProvider 解绑
    old = "        searchProvider: deepseek-official\n"
    new = "        searchProvider: ''\n"
    if old in out:
        out = out.replace(old, new, 1)
        log("③ web.searchProvider -> ''")
    else:
        log("③ web.searchProvider 已解绑（跳过）")

    # ④ 官方 DeepSeek 相关行禁用
    for row_id in ["web-search-deepseek", "llm-deepseek"]:
        anchor = "    - id: %s\n" % row_id
        idx = out.find(anchor)
        if idx < 0:
            log("④ !! 未找到 %s 行" % row_id)
            continue
        # 在该行的 name 之后插入 disabled: true（若尚未存在）
        tail = out[idx:idx + 600]
        if re.search(r"\n      disabled: true\n", tail[:tail.find("\n    - id: ", 5) if tail.find("\n    - id: ", 5) > 0 else len(tail)]):
            log("④ %s 已 disabled（跳过）" % row_id)
            continue
        nl = out.index("\n", out.index("name:", idx))
        comment = ""
        if row_id == "llm-deepseek":
            comment = (
                "    # USB Harness: 禁用官方 DeepSeek 适配器，模型配置仅保留自定义 OpenAI 兼容网关。\n"
            )
            # 注释插到该行之前
            line_start = out.rfind("\n", 0, idx) + 1
            out = out[:line_start] + comment + out[line_start:]
            nl = out.index("\n", out.index("name:", idx + len(comment)))
        out = out[:nl] + "\n      disabled: true" + out[nl:]
        log("④ %s -> disabled: true" % row_id)

    return out


def apply_app_boot(text, log):
    """dsh-app-boot：FAT32/exFAT 无符号链接 → 目录复制回退。

    上游 0.1.5 把 ensureSymlink 重构成了 "module proxy 记录" 机制：
    非符号链接的目录只有在带 dsh.moduleFallback.targets 记录时才会被接管，
    否则报错。FAT32/exFAT 场景下无符号链接可用，必须保留复制回退，
    同时让"无记录的普通目录"也能被幂等接受。
    """
    out = text

    # ① import 增加 cpSync（锚点用正则，上游会调整 import 名单）
    if re.search(r'import \{[^}]*\bcpSync\b[^}]*\} from "node:fs";', out):
        log("① import 已含 cpSync（跳过）")
    else:
        m = re.search(r'import \{([^}]*)\} from "node:fs";', out)
        if m:
            names = [n.strip() for n in m.group(1).split(",") if n.strip()]
            names.append("cpSync")
            names = sorted(set(names))
            out = out[:m.start(0)] + "import { " + ", ".join(names) + ' } from "node:fs";' + out[m.end(0):]
            log("① import 增加 cpSync")
        else:
            log("① !! import 锚点未命中")

    # ② symlinkSync 失败 → 目录复制回退（锚点兼容 readlinkSync / symlinkPointsTo 两种写法）
    m = re.search(
        r"if \(error\.code !== \"EEXIST\" \|\| !lstatSync\(link\)\.isSymbolicLink\(\) \|\| "
        r"(?:readlinkSync\(link\) !== target|!symlinkPointsTo\(link, target\))\) throw error;",
        out,
    )
    if m:
        out = out[:m.start(0)] + (
            "if (error.code !== \"EEXIST\" || !lstatSync(link).isSymbolicLink() || "
            "(typeof symlinkPointsTo === \"function\" ? !symlinkPointsTo(link, target) : readlinkSync(link) !== target)) {\n"
            "\t\t\t// 回退:文件系统不支持符号链接(如 FAT32/exFAT)时,复制真实目录代替链接\n"
            "\t\t\ttry {\n"
            "\t\t\t\tcpSync(target, link, { recursive: true, force: true, dereference: true, errorOnExist: false });\n"
            "\t\t\t} catch (copyError) {\n"
            "\t\t\t\tthrow new Error(`dsh: cannot symlink ${target} -> ${link} (${error.code}); directory copy fallback also failed (${copyError.code}): ${copyError.message}`);\n"
            "\t\t\t}\n"
            "\t\t}"
        ) + out[m.end(0):]
        log("② symlinkSync 失败 → cpSync 目录复制回退")
    else:
        log("② symlinkSync 失败分支已是复制回退或锚点变化")

    # ③ 非符号链接的普通目录 → 视为已就绪（幂等），不抛错
    #   上游原文（单行）：
    #     if ((stat.isDirectory() ? readModuleProxyRecord(link) : void 0)?.dsh?.moduleFallback?.targets === void 0) throw new Error(`...`);
    STMT = (
        "if ((stat.isDirectory() ? readModuleProxyRecord(link) : void 0)"
        "?.dsh?.moduleFallback?.targets === void 0) throw new Error("
        "`dsh: ${link} exists and is not a symlink or dsh-managed module proxy; "
        "remove it so dsh can manage the installation fallback`);"
    )
    if STMT in out:
        out = out.replace(
            STMT,
            "// USB Harness: 无符号链接支持的文件系统（FAT32/exFAT）下，上一轮复制回退留下的\n"
            "\t\t\t// 真实目录视为已就绪（幂等），不抛错；非目录（普通文件）仍保持上游的 fail-loud。\n"
            "\t\t\tif ((stat.isDirectory() ? readModuleProxyRecord(link) : void 0)?.dsh?.moduleFallback?.targets === void 0) {\n"
            "\t\t\t\tif (!stat.isDirectory()) throw new Error(`dsh: ${link} exists and is not a symlink or dsh-managed module proxy; remove it so dsh can manage the installation fallback`);\n"
            "\t\t\t\treturn;\n"
            "\t\t\t}",
            1,
        )
        log("③ 普通真实目录 → 视为已就绪（幂等）")
    elif "USB Harness: 无符号链接支持的文件系统" in out:
        log("③ 普通真实目录幂等分支已存在（跳过）")
    else:
        log("③ !! 普通真实目录锚点未命中")
    return out


def apply_brand_icon(text, log):
    """dsh-client-ui-brand-official：自绘 USB 图标，去掉 FishLogo 依赖。"""
    out = text
    # 删除 primitives 依赖（仅当不再被引用时）
    m = re.search(r"\t\tlet _deepseek_ai_dsh_client_ui_primitives = require\(\"@deepseek-ai/dsh-client-ui-primitives\"\);\n", out)
    if m:
        probe = out.replace(m.group(0), "")
        if "_deepseek_ai_dsh_client_ui_primitives" not in probe:
            out = probe
            log("① 移除 FishLogo/BrandWordmark 依赖")

    USB_SVG = """		function OfficialBrandMark({ size = 24, className }) {
			return (0, react_jsx_runtime.jsx)("svg", {
				width: size,
				height: size,
				viewBox: "0 0 24 24",
				fill: "none",
				className,
				"aria-label": "USB Harness",
				children: [
					(0, react_jsx_runtime.jsx)("circle", { cx: 12, cy: 5, r: 2.3, fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" }),
					(0, react_jsx_runtime.jsx)("line", { x1: 12, y1: 7.3, x2: 12, y2: 9.5, stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" }),
					(0, react_jsx_runtime.jsx)("rect", { x: 8.6, y: 9.5, width: 6.8, height: 3.1, rx: 1.1, fill: "currentColor", stroke: "none" }),
					(0, react_jsx_runtime.jsx)("path", { d: "M10 12.6 L10 15.2 L12 18.6 L14 15.2 L14 12.6", fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round", strokeLinejoin: "round" })
				]
			});
		}"""
    # 用正则替换整个 OfficialBrandMark 函数体
    m = re.search(r"\t\tfunction OfficialBrandMark\(\{[\s\S]*?\n\t\t\}", out)
    if m and "circle\", { cx: 12" not in m.group(0):
        out = out[:m.start(0)] + USB_SVG + out[m.end(0):]
        log("② OfficialBrandMark -> 自绘 USB 图标")
    else:
        log("② OfficialBrandMark 已是 USB 图标（跳过）")

    USB_NAME = """		function OfficialBrandName() {
			return (0, react_jsx_runtime.jsx)("span", {
				children: "USB Harness",
				style: { fontWeight: 600, letterSpacing: "0.02em" }
			});
		}"""
    m = re.search(r"\t\tfunction OfficialBrandName\(\) \{[\s\S]*?\n\t\t\}", out)
    if m and '"USB Harness"' not in m.group(0):
        out = out[:m.start(0)] + USB_NAME + out[m.end(0):]
        log("③ OfficialBrandName -> 纯文本 USB Harness")
    else:
        log("③ OfficialBrandName 已是 USB Harness（跳过）")

    # 清理：primitives 若已无人引用，删除其 require 行（避免 unused require 告警）
    if "_deepseek_ai_dsh_client_ui_primitives" in out:
        probe = re.sub(r"\t*let _deepseek_ai_dsh_client_ui_primitives = require\(\"@deepseek-ai/dsh-client-ui-primitives\"\);\n", "", out)
        if "_deepseek_ai_dsh_client_ui_primitives" not in probe:
            out = probe
            log("④ 清理无用的 primitives 引用")
    return out


def apply_hero_preview(text, log):
    """dsh-client-ui-conversation：抹掉 "Preview / 预览版" 角标。"""
    out = text
    n = 0
    for old, new in [('"hero.preview": "预览版"', '"hero.preview": ""'),
                     ('"hero.preview": "Preview"', '"hero.preview": ""')]:
        if old in out:
            out = out.replace(old, new)
            n += 1
    if n:
        log("① hero.preview 文案置空 ×%d" % n)
    else:
        log("① hero.preview 已置空（跳过）")

    # 移除渲染 previewBadge 的那个 span（若仍存在）
    m = re.search(
        r"\n\t*\(0, react_jsx_runtime\.jsx\)\(\"span\", \{\n\t*className: HeroShell_module_css_default\.previewBadge,\n\t*children: t\(\"hero\.preview\"\)\n\t*\}\),?",
        out,
    )
    if m:
        out = out[:m.start(0)] + out[m.end(0):]
        log("② 移除 previewBadge 渲染节点")
    else:
        log("② previewBadge 节点已移除（跳过）")
    return out


def apply_permission_i18n(text, log):
    """dsh-client-ui-permission-presets：预设名走 i18n（修上游硬编码英文）。"""
    out = text

    old_fn = """		function displayPermissionPreset(value, name) {
			return value === "danger-full-access" ? "Full access" : displayPresetName(name);
		}"""
    new_fn = """		function displayPermissionPreset(value, name, t) {
			if (value === "danger-full-access" || name === "danger-full-access") return t("preset.fullAccess");
			if (value === "read-only" || name === "read-only" || value === "danger-read-only") return t("preset.readOnly");
			if (value === "workspace-write" || name === "workspace-write" || value === "danger-workspace-write") return t("preset.workspaceWrite");
			return displayPresetName(name);
		}"""
    if old_fn in out:
        out = out.replace(old_fn, new_fn, 1)
        log("① displayPermissionPreset 接入 i18n")
    elif "preset.fullAccess" in out:
        log("① displayPermissionPreset 已接入 i18n（跳过）")
    else:
        log("① !! displayPermissionPreset 锚点未命中")

    # 词典补齐：仅在没有该 key 时插入（上游可能已自带，重复 key 会让后者覆盖前者）
    def ensure_key(text, anchor, lines, label):
        if '"_presetprobe"' in text:
            return text
        # 逐个 key 检查，缺哪个补哪个
        missing = [ln for ln in lines if ln.split(":")[0].strip() not in text]
        if not missing:
            log("%s 已齐备（跳过）" % label)
            return text
        if anchor in text:
            text = text.replace(anchor, anchor + "\n" + "\n".join(missing), 1)
            log("%s 补齐 %d 项" % (label, len(missing)))
        else:
            log("%s !! 锚点未命中" % label)
        return text

    out = ensure_key(out, '			"unavailable": "不可用",',
                     ['			"preset.readOnly": "只读",',
                      '			"preset.workspaceWrite": "工作区可写",',
                      '			"preset.fullAccess": "完全访问",'], "② zh 词典")
    out = ensure_key(out, '			"unavailable": "Unavailable",',
                     ['			"preset.readOnly": "Read Only",',
                      '			"preset.workspaceWrite": "Workspace Write",',
                      '			"preset.fullAccess": "Full access",'], "③ en 词典")

    # 调用点补 t 参数
    pairs = [
        ("function permissionDefaultOf(view, schema) {", "function permissionDefaultOf(view, schema, t) {"),
        ("displayPermissionPreset(choice.value, described)", "displayPermissionPreset(choice.value, described, t)"),
        ("displayPermissionPreset(choice.value, choice.value)", "displayPermissionPreset(choice.value, choice.value, t)"),
        ("constructor(describeFace, api, schema) {", "constructor(describeFace, api, schema, t) {"),
        ("const resolved = permissionDefaultOf(view, this.schema);", "const resolved = permissionDefaultOf(view, this.schema, this.t);"),
        ("label: displayPermissionPreset(option.value, option.name),", "label: displayPermissionPreset(option.value, option.name, t),"),
    ]
    n = 0
    for old, new in pairs:
        if old in out and new not in out:
            out = out.replace(old, new)
            n += 1
    log("④ 调用点补 t 参数 ×%d" % n)

    # controller 保存 t
    if "this.t = t;" not in out:
        anchor = "\t\t\t\tthis.schema = schema;"
        if anchor in out:
            out = out.replace(anchor, anchor + "\n\t\t\t\tthis.t = t;", 1)
            log("⑤ controller 保存 t")
    # 构造处传 t
    if 'ctx.locale.bind("settings.permission")' not in out:
        anchor = "const controller = new PermissionPresetSettingsController(ctx.settingsScope.describe(), connection.api, ctx.settingsSchema);"
        if anchor in out:
            out = out.replace(
                anchor,
                'const permissionT = ctx.locale.bind("settings.permission");\n'
                "			const controller = new PermissionPresetSettingsController(ctx.settingsScope.describe(), connection.api, ctx.settingsSchema, permissionT);",
                1,
            )
            log("⑥ 构造处注入 locale 绑定")
    return out


def apply_onboarding(text, log):
    """dsh-client-ui-settings-models：无内置 provider 时直接弹自定义网关表单 + 文案改写。"""
    out = text

    # ① complete() 触发条件去掉 adapter-absent
    old = 'if (readiness.kind === "adapter-absent" || readiness.kind === "provider-ready" || readiness.kind === "unavailable") complete();'
    new = 'if (readiness.kind === "provider-ready" || readiness.kind === "unavailable") complete();'
    if old in out:
        out = out.replace(old, new, 1)
        log("① complete() 条件去掉 adapter-absent")
    else:
        log("① complete() 条件已调整（跳过）")

    # ② adapter-absent → 直接渲染自定义 provider 表单
    if "CustomProviderCard, {\n\t\t\t\t\t\t\ttaken," not in out and "USB Harness: 无内置 deepseek-official 提供方" not in out:
        anchor = "\t\t\t(0, react.useEffect)(() => {\n\t\t\t\t" + new + "\n\t\t\t}, [complete, readiness.kind]);"
        if anchor in out:
            block = anchor + """
			// USB Harness: 无内置 deepseek-official 提供方（adapter-absent）→ 直接弹出「自定义 OpenAI 兼容网关」表单
			if (readiness.kind === "adapter-absent") {
				const taken = state.rows.map((row) => row.entry.provider);
				const protocols = protocolChoices(state.namespaces.get("llm-pi-ai"), schema);
				const revision = state.namespaces.get("llm-pi-ai")?.revision ?? 0;
				const finishCustom = (changed) => {
					if (!changed) {
						complete();
						return;
					}
					controller.load();
				};
				return (0, react_jsx_runtime.jsxs)(OnboardingModal, {
					title: t("onboardingTitle"),
					children: [(0, react_jsx_runtime.jsx)("p", {
						className: DeepSeekOnboardingDialog_module_css_default.description,
						children: t("onboardingDescription")
					}), (0, react_jsx_runtime.jsx)("div", {
						className: DeepSeekOnboardingDialog_module_css_default.editor,
						children: (0, react_jsx_runtime.jsx)(CustomProviderCard, {
							taken,
							protocols,
							revision,
							api,
							t,
							readOnly: !state.writable,
							onClose: finishCustom
						})
					})]
				});
			}"""
            out = out.replace(anchor, block, 1)
            log("② adapter-absent 分支已插入")
        else:
            log("② !! use() 锚点未命中")
    else:
        log("② adapter-absent 分支已存在（跳过）")

    # ③ switch 中删除 case "adapter-absent"
    old = '\t\t\t\tcase "adapter-absent":\n'
    if old in out:
        out = out.replace(old, "", 1)
        log("③ switch 中移除 case adapter-absent")
    else:
        log("③ switch 已无 adapter-absent（跳过）")

    # ④ 文案（内测声明 → 欢迎；onboarding 描述 → 自定义网关）
    swaps = [
        ("welcomeTitle: \"Internal Testing Notice\"", "welcomeTitle: \"Welcome\""),
        ("welcomeTitle: \"内测声明\"", "welcomeTitle: \"欢迎使用\""),
        ("onboardingTitle: \"Add an API key to get started\"", "onboardingTitle: \"Connect an OpenAI-compatible endpoint\""),
        ("onboardingDescription: \"Configure the official DeepSeek provider to start building.\"",
         "onboardingDescription: \"Connect a custom OpenAI-compatible endpoint to start building.\""),
        ("onboardingTitle: \"添加一个 API Key 开始使用\"", "onboardingTitle: \"连接一个 OpenAI 兼容网关\""),
        ("onboardingDescription: \"配置 DeepSeek 官方模型，即可开始使用。\"",
         "onboardingDescription: \"连接自定义 OpenAI 兼容网关，即可开始使用。\""),
    ]
    n = 0
    for old_s, new_s in swaps:
        if old_s in out:
            out = out.replace(old_s, new_s)
            n += 1

    # welcomeBody：中英各一段，统一换成简洁的 USB Harness 描述
    ZH_BODY = "USB Harness 是一款基于插件的 AI 智能体框架，支持自定义 OpenAI 兼容网关。欢迎提出反馈建议，帮助我们持续改进。"
    EN_BODY = ("USB Harness is a plugin-based AI agent framework with custom OpenAI-compatible "
               "endpoint support. We welcome your feedback to help us keep improving.")
    for label, body in (("zh", ZH_BODY), ("en", EN_BODY)):
        pat = re.compile(r'(welcomeBody: )"((?:[^"\\]|\\.)*)"')
        target = None
        for m in pat.finditer(out):
            seg = m.group(2)
            if label == "zh" and ("内测" in seg or "Harness 目前的 0.1" in seg):
                target = m
                break
            if label == "en" and "DeepSeek Harness" in seg and "remains in testing" in seg:
                target = m
                break
        if target:
            out = out[:target.start(2)] + body + out[target.end(2):]
            n += 1

    log("④ 文案改写 ×%d" % n)
    return out


HTML_SNIPPET = """    <script>
      // USB Harness: 兼容非安全上下文（如通过局域网 IP 访问）下 crypto.randomUUID 不可用。
      // 用始终可用的 getRandomValues 实现 RFC4122 v4 兜底，避免 "crypto.randomUUID is not a function"。
      if (typeof crypto !== "undefined" && typeof crypto.randomUUID !== "function") {
        try {
          crypto.randomUUID = function () {
            return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
              var r = crypto.getRandomValues(new Uint8Array(1))[0] & 15;
              var v = c === "x" ? r : (r & 0x3) | 0x8;
              return v.toString(16);
            });
          };
        } catch (e) { /* 极旧浏览器忽略 */ }
      }
    </script>
"""


def apply_web_index(text, log):
    """dsh-web-frontend/dist/index.html：标题 + crypto.randomUUID 兜底 + 相对路径修正。"""
    out = text
    if "<title>DeepSeek Harness</title>" in out:
        out = out.replace("<title>DeepSeek Harness</title>", "<title>USB Harness</title>", 1)
        log("① <title> -> USB Harness")
    else:
        log("① <title> 已是 USB Harness（跳过）")

    if "crypto.randomUUID is not a function" not in out:
        anchor = '    <link rel="icon" type="image/svg+xml" href="./favicon.svg" />\n'
        if anchor in out:
            out = out.replace(anchor, anchor + HTML_SNIPPET, 1)
            log("② crypto.randomUUID 兜底脚本已注入")
        else:
            m = re.search(r'(    <link rel="icon"[^>]*>\n)', out)
            if m:
                out = out[:m.end(1)] + HTML_SNIPPET + out[m.end(1):]
                log("② crypto.randomUUID 兜底脚本已注入（宽松锚点）")
            else:
                log("② !! 找不到 icon 锚点")
    else:
        log("② crypto.randomUUID 兜底已存在（跳过）")

    # 资源引用改绝对路径（USB-Harness 经 /assets 提供，相对路径在 /session/xxx 下会 404）
    n = 0
    for a, b in [('href="./manifest.webmanifest"', 'href="/manifest.webmanifest"'),
                 ('href="./favicon.svg"', 'href="/favicon.svg"'),
                 ('src="./assets/', 'src="/assets/'),
                 ('href="./assets/', 'href="/assets/')]:
        if a in out:
            out = out.replace(a, b)
            n += 1
    log("③ 静态资源绝对路径 ×%d" % n)
    return out


def apply_allow_all_interfaces(text, log):
    """移除上游对 --host 0.0.0.0 的安全拦截。

    上游理由：绑定全网卡会把远程代码执行暴露到网络上，故刻意禁止。
    USB-Harness 的理由：本项目的核心使用场景就是 U 盘插在一台机器、同网段其他设备
    用局域网 IP 访问，因此必须放行。该拦截是一行 program.error 语句，逐字匹配删除；
    若上游改了措辞或换了实现方式，这里必须报错而不是静默放过。
    """
    STMT = ('\t\tif (options.host === "0.0.0.0") program.error("error: --host 0.0.0.0 '
            'is intentionally not supported yet for safety: it would expose remote code '
            'execution to the network; use 127.0.0.1 instead");\n')
    if STMT in text:
        text = text.replace(STMT, "\t\t// USB Harness: 放行 0.0.0.0 —— 本项目按 U 盘 / 局域网 \n"
                                  "\t\t// 共享场景设计，需允许同网段设备访问（上游默认禁止）。\n", 1)
        log("已移除 --host 0.0.0.0 拦截（USB Harness 必需）")
        return text

    # 已经处理过（幂等）
    if "USB Harness: 放行 0.0.0.0" in text:
        log("0.0.0.0 拦截已移除（跳过）")
        return text

    # 逐字未命中 —— 上游可能改了措辞/重构。必须失败，不能静默放过。
    if "0.0.0.0" in text:
        m = re.search(r'[^\n]*0\.0\.0\.0[^\n]*', text)
        log("!! !! 拦截语句未逐字命中，但文件里仍有 0.0.0.0 相关代码，需人工核对：")
        log("       %s" % (m.group(0).strip()[:160] if m else ""))
        raise RuntimeError("allow_all_interfaces: %s 的 0.0.0.0 拦截未能移除" % "startup.js")
    log("上游已不再拦截 0.0.0.0（定制点自动失效，无需改动）")
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--diff", action="store_true")
    args = ap.parse_args()

    manifest = build_manifest(args.target)
    problems = []

    for rel in PATCH_FILES:
        src = upstream(args.target, rel)
        if not os.path.exists(src):
            print("!! 上游缺文件: %s (%s)" % (rel, args.target))
            problems.append(rel)
            continue
        out = read(src)
        log = lambda m, rel=rel: print("   [%s] %s" % (rel.split("/")[0], m))

        for kind, payload in manifest.get(rel, []):
            if kind == "sub":
                for old, new in payload:
                    if old in out:
                        out = out.replace(old, new)
                continue
            if kind == "anchor":
                for old, new in payload:
                    if old in out:
                        out = out.replace(old, new, 1)
                continue
            if kind in ("yaml_usb_base",):
                print("\n== %s ==" % rel); out = apply_base_yaml(out, log); continue
            if kind == "llm_deepseek_name":
                print("\n== %s ==" % rel)
                # provider 面向用户的 name（保留 provider id / 包名不动）
                n = 0
                out2 = re.sub(r'(\n\t*name: )"DeepSeek"(\n)', r'\1"USB Harness"\2', out, count=1)
                if out2 != out:
                    out = out2; n += 1
                if 'displayName: "USB Harness"' in out or n:
                    log("provider name / displayName -> USB Harness")
                else:
                    log("!! provider 显示名锚点未命中（需人工确认）")
                continue
            if kind == "document_title_recheck":
                print("\n== %s ==" % rel)
                if "DocumentTitle" in out or "document.title" in out:
                    log("!! 上游重新在本包引入标题逻辑 —— 需人工迁移 USB Harness 定制")
                    problems.append(rel + " (DocumentTitle 回归，需人工迁移)")
                else:
                    log("上游已移出标题逻辑（0.1.5 起由 dsh-web-app/前端承担）；本包仅承载品牌替换")
                continue
            if kind == "block_or_fail":
                print("\n== %s ==" % rel); out = apply_app_boot(out, log); continue
            if kind == "usb_brand_icon":
                print("\n== %s ==" % rel); out = apply_brand_icon(out, log); continue
            if kind == "hero_preview_badge":
                print("\n== %s ==" % rel); out = apply_hero_preview(out, log); continue
            if kind == "permission_preset_i18n":
                print("\n== %s ==" % rel); out = apply_permission_i18n(out, log); continue
            if kind == "onboarding_custom_provider":
                print("\n== %s ==" % rel); out = apply_onboarding(out, log); continue
            if kind == "allow_all_interfaces":
                print("\n== %s ==" % rel); out = apply_allow_all_interfaces(out, log); continue
            if kind == "web_index_html":
                print("\n== %s ==" % rel); out = apply_web_index(out, log); continue
            if kind == "web_manifest":
                print("\n== %s ==" % rel)
                out = out.replace('"name": "DeepSeek Harness"', '"name": "USB Harness"')
                out = out.replace('"short_name": "DSH"', '"short_name": "USB-H"')
                log("name/short_name -> USB Harness / USB-H")
                continue
            if kind == "web_favicon":
                print("\n== %s ==" % rel)
                # favicon 是自绘的 USB 图标，与上游无文本关系，直接沿用现值（不随上游变动）
                log("favicon 为 USB 自绘图标，保持现值（不受上游基线影响）")
                continue

        if args.write:
            dst = patch_path(rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8", newline="\n") as f:
                f.write(out)
            print("   写入 %s" % os.path.relpath(dst, ROOT))
        if args.diff:
            old = read(patch_path(rel))
            if old is not None and old != out:
                print("\n---- %s ----" % rel)
                d = list(difflib.unified_diff(old.splitlines(), out.splitlines(),
                                              fromfile="patch(old)", tofile="patch(new)", n=1, lineterm=""))
                print("\n".join(x[:200] for x in d[:80]))

    if problems:
        print("\n!! 有 %d 个文件无法处理: %s" % (len(problems), problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
