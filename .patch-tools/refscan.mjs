// =============================================================================
// refscan.mjs — 重定 dsh 的 peer 依赖补齐清单
// =============================================================================
// 用途：升级 dsh 版本后，确定 scripts/setup-windows.ps1 的 $PeerFix 与
//       scripts/setup-unix.sh 的 PEERS 里应该写哪些包。
//
// 为什么不能靠「跑一次 dsh 看缺哪个包」：
//   绝大多数 @deepseek-ai/* 子模块是懒加载的，只有走到对应功能才会 import。
//   实测：单次启动只报出 1 个缺失包，静态扫描报出 26 个 —— 漏报的 25 个
//   会在用户用到对应功能时才炸。
//
// 正确做法：对安装树里全部 .js/.mjs/.cjs 提取 @deepseek-ai/* 的 import 说明符，
//           逐个尝试解析，凡解析不到的即为必须补齐的缺失项。
//
// 用法：
//   node .patch-tools/refscan.mjs "<包根>/.cache/app/node_modules"
//   node .patch-tools/refscan.mjs "D:/SimpleProject/outputs/USB-Harness/.cache/app/node_modules"
//
// 退出码：0 = 缺失 0 个（清单完整）；1 = 存在缺失项（需补进 $PeerFix / PEERS）
//
// 注意：路径用 Windows 形式（D:/...）—— node.exe 是原生 Windows 程序，
//       不接受 Git Bash 的 POSIX 形式（/d/...），会静默失败。
// =============================================================================

import { createRequire } from 'node:module'
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const MODS = process.argv[2]
if (!MODS) {
  console.error('用法: node refscan.mjs "<node_modules 绝对路径（Windows 形式）>"')
  process.exit(2)
}

// 匹配 from '...' / import('...') / require('...') 三种形式，取包名前两级
const SPEC = /(?:from\s*|import\s*\(\s*|require\s*\(\s*)["'](@deepseek-ai\/[^"'/]+)(?:\/[^"']*)?["']/g

function walk(dir, out = []) {
  let entries
  try {
    entries = readdirSync(dir, { withFileTypes: true })
  } catch {
    return out
  }
  for (const e of entries) {
    const p = join(dir, e.name)
    if (e.isDirectory()) walk(p, out)
    else if (/\.(js|mjs|cjs)$/.test(e.name)) out.push(p)
  }
  return out
}

const root = join(MODS, '@deepseek-ai')
const files = walk(root)
if (files.length === 0) {
  console.error(`未在 ${root} 下找到任何 .js/.mjs/.cjs 文件——路径是否正确？`)
  process.exit(2)
}

// spec -> 首次出现它的文件（用于 createRequire 的解析基准）
const seen = new Map()
for (const f of files) {
  const text = readFileSync(f, 'utf8')
  for (const m of text.matchAll(SPEC)) {
    if (!seen.has(m[1])) seen.set(m[1], f)
  }
}

const missing = []
for (const [spec, from] of seen) {
  const req = createRequire(from)
  try {
    req.resolve(spec + '/package.json')
  } catch {
    missing.push(spec)
  }
}

console.log(`扫描文件 ${files.length} 个`)
console.log(`@deepseek-ai/* 说明符 ${seen.size} 个；缺失 ${missing.length} 个`)

if (missing.length === 0) {
  console.log('=> 清单完整，无需补齐')
  process.exit(0)
}

console.log('\n以下包解析不到，需补进 $PeerFix / PEERS（版本串用锁定的 dsh 版本）：')
for (const s of missing.sort()) console.log('  ' + s)

const dshVersion = process.argv[3]
if (dshVersion) {
  console.log(`\n可直接粘贴（\$DshVersion = ${dshVersion}）：`)
  for (const s of missing.sort()) console.log(`        "${s}@$peerVer",`)
}

process.exit(1)
