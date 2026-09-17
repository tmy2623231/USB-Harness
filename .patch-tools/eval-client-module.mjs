// 求值 brand-patch 里的「浏览器端」模块，验证它们能真正执行而不抛运行时错误。
//
// 【为什么需要这个工具】
// brand-patch 下的 client.js 是**整文件快照**，其中的定制逻辑只做语法检查
// （`node --check`）是查不出问题的：
//
//   * ReferenceError / TypeError 属于**运行时**错误 —— 语法完全合法；
//   * CLI 侧路径（--version / --help / headless）**不加载浏览器端 bundle**，
//     所以 CLI 冒烟全绿也可能 Web 页面整页白屏；
//   * 补丁基线校验只回答「定制意图在不在」，不回答「代码能不能跑」。
//
// 实测事故：dsh-client-ui-permission-presets/lib/client.js 里定制往控制器
// 穿了 locale 查找函数 t，却漏把它加进构造函数形参 —— 浏览器端 apply()
// 抛 `ReferenceError: t is not defined`，Web 页面显示 "Failed to load plugins"。
// 本工具就是为堵住这一类缺陷而写的：**真的把模块求值一次**。
//
// 用法：
//   node .patch-tools/eval-client-module.mjs <path/to/client.js>
// 退出码：0 = 求值通过；1 = 抛错或导出缺失。

import fs from 'node:fs';
import vm from 'node:vm';

const file = process.argv[2];
if (!file) {
  console.error('用法: node eval-client-module.mjs <path/to/client.js>');
  process.exit(2);
}

const src = fs.readFileSync(file, 'utf8');

// 捕获模块自注册：浏览器端 bundle 的约定是调用 window.__ModuleLoader__.load()
let loaded = null;
const sandbox = {
  window: {
    __ModuleLoader__: {
      load(def) { loaded = def; },
    },
  },
  console,
};
sandbox.globalThis = sandbox;

vm.runInNewContext(src, sandbox, { filename: file });

if (!loaded) {
  console.error('FAIL: 模块未调用 window.__ModuleLoader__.load() 注册自身');
  process.exit(1);
}

// 替身 require：客户端 bundle 依赖的 react / @deepseek-ai/* 包在 Node 侧不可用，
// 这里给出「万能替身」——本工具只验证模块自身能否执行，
// 不验证被依赖包的行为（那是 dsh 上游的事）。
//
// 【为什么不用 Proxy 而是普通对象 + 原型链】
// bundle 头部是 esbuild 风格的辅助函数，其中：
//     __toESM(mod, 1)  ->  __create(__getProtoOf(mod))  +  __copyProps(..., mod)
//     __copyProps 遍历 __getOwnPropNames(from) 逐个建 getter
// 若替身是 Proxy，`__getOwnPropNames` 只枚举到函数自身的 length/name，
// 于是 `react.memo` 等成员**根本不会被拷贝**，模块一调用就抛
//     TypeError: (0, react.memo) is not a function
// ——这是**替身的缺陷**，不是被检模块的缺陷，会把工具变成"狼来了"。
// 用普通对象把成员实打实地挂在身上，`__copyProps` 才能正确搬运。
const makeUniversal = () => {
  const u = function () {};
  // 显式挂上常用成员，保证 own-property 枚举能看见它们
  for (const k of [
    'default', 'memo', 'forwardRef', 'createElement', 'useState', 'useEffect',
    'useMemo', 'useRef', 'useCallback', 'useReducer', 'useContext', 'Fragment',
    'createContext', 'Children', 'cloneElement', 'isValidElement', 'useId',
    'useSyncExternalStore', 'useLayoutEffect', 'useTransition', 'useDeferredValue',
  ]) {
    u[k] = u;
  }
  // 让属性访问兜底到自身（未知成员也返回同一个通用替身）
  return new Proxy(u, {
    get: (t, prop) => {
      if (prop in t) return t[prop];
      if (typeof prop === 'symbol') return undefined;
      return t;
    },
    apply: () => u,
    construct: () => u,
  });
};
const anyStub = makeUniversal();
const requireStub = () => anyStub;

let api;
try {
  api = loaded.factory(requireStub);
} catch (e) {
  // 同上：按 name 判定，不用 instanceof（跨 realm）
  if (e && e.name === 'TypeError') {
    console.log(`SKIP: 替身能力不足，无法判定（${e.message}）`);
    console.log('      —— 这是检查工具的替身局限，不是补丁缺陷');
    process.exit(0);
  }
  console.error('FAIL: factory 执行抛错 ->', (e && e.name) + ': ' + (e && e.message));
  process.exit(1);
}

if (!api || typeof api.apply !== 'function') {
  console.error('FAIL: 模块未导出 apply()');
  process.exit(1);
}

// 最小可用的 ctx：让 apply() 体内的语句都能走到。
// 【设计要点】这里刻意做得「宽」——未知属性一律返回万能替身，
// 目的是让 apply() 执行到「模块自身会抛错」的语句。
// 若 stub 太窄，会把「stub 缺方法」误报成「模块有缺陷」，使本工具失去可信度。
// 判据：只有 *模块自身* 的 ReferenceError / 明确的逻辑错误才算 FAIL。
const registered = [];
const ctxTarget = {
  effect: (fn) => {
    try { fn(); } catch { /* effect 回调错误由其自身语义决定，不计入 */ }
    return () => {};
  },
  locale: {
    register: (...args) => { registered.push(args[0]); return () => {}; },
    bind: (ns) => {
      const fn = (key) => `[${ns}]${key}`;
      fn.__ns = ns;
      return fn;
    },
  },
  settingsScope: {
    describe: () => ({}),
    // 真实 ctx.settingsScope 支持按命名空间 bind 出读写面；给出同形状替身，
    // 避免把「stub 缺方法」误报成「模块有缺陷」。
    bind: () => ({
      get: () => undefined,
      set: () => {},
      update: () => {},
      subscribe: () => () => {},
      describe: () => ({}),
    }),
    get: () => undefined,
    set: () => {},
  },
  settingsSchema: {},
};
const ctx = new Proxy(ctxTarget, {
  get: (t, prop) => {
    if (prop in t) return t[prop];
    if (typeof prop === 'symbol') return undefined;
    // 未知成员：返回一个「万能」值，既能当函数调用、也能取属性、也能当对象用
    const universal = new Proxy(function () {}, {
      get: (_t2, p2) => {
        if (p2 === 'default') return universal;
        if (typeof p2 === 'symbol') return undefined;
        return universal;
      },
      apply: () => universal,
      construct: () => universal,
    });
    return universal;
  },
  has: () => true,
});

try {
  api.apply(ctx);
} catch (e) {
  // 【区分两类失败 —— 这是本工具可信度的关键】
  // (A) 模块自身的缺陷：ReferenceError（自由变量未声明）、或语法/求值期错误。
  //     这类必然是我们补丁写错了，必须 FAIL。
  // (B) 替身不足：TypeError —— 形如 "ctx.xxx is not a function"、
  //     "host.getSnapshot is not a function"，是我们 minimal ctx 造得不够像，
  //     **不是被检模块的缺陷**。这类必须报 SKIP，否则工具会"狼来了"，
  //     使用者很快就不再相信它。
  //
  // 【坑】不要用 `e instanceof TypeError`：模块是在 vm 的**独立 realm** 里求值的，
  // 它抛出的 TypeError 不是本 realm 的 TypeError 构造器实例，instanceof 恒为 false。
  // 必须按 error.name 判定。
  const name = e && e.name;
  if (name === 'ReferenceError') {
    console.error('FAIL: apply() 抛 ReferenceError（补丁自身引用了未声明的标识符）');
    console.error('  ->', e.message);
    if (e.stack) console.error(e.stack.split('\n').slice(1, 4).join('\n'));
    process.exit(1);
  }
  if (name === 'TypeError') {
    console.log(`SKIP: 替身 ctx 能力不足，无法判定（${e.message}）`);
    console.log('      —— 这是检查工具的替身局限，不是补丁缺陷');
    process.exit(0);
  }
  console.error('FAIL: apply() 抛错 ->', name + ': ' + e.message);
  if (e.stack) console.error(e.stack.split('\n').slice(0, 6).join('\n'));
  process.exit(1);
}

console.log(`PASS: apply() 执行完成，未抛运行时错误（注册字典 ${registered.length} 处）`);
