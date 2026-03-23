# num-wasm

A NumPy-like array library written in Zig, compiled to WebAssembly for JavaScript/TypeScript.

Built as a learning project — beginner-friendly approach with simple flat arrays, `f64` only, no strides.

## Project Structure

```
num-wasm/
├── build.zig               # Zig build config (native + WASM targets)
├── package.json
├── tsconfig.json
├── PLAN.md                 # Full development roadmap
├── src/
│   ├── core/
│   │   ├── ndarray.zig     # NDArray struct (init, deinit, getItem, setItem, flatIndex)
│   │   └── creation.zig    # zeros, ones, full, arange, linspace
│   ├── wasm_api.zig        # WASM exports (thin wrapper)
│   ├── root.zig            # Module re-exports
│   ├── main.zig            # CLI playground
│   └── nw.ts               # TypeScript NumWasm wrapper class
├── tests/
│   └── test.ts             # TypeScript tests
└── zig-out/
    └── bin/
        └── num-wasm.wasm   # Built WASM binary
```

## Prerequisites

- Zig 0.15.2+
- Node.js 22+

## Quick Start

```bash
npm install

zig build test          # run native Zig tests (17 tests)
zig build wasm          # build WASM binary to zig-out/bin/
npx tsx tests/test.ts   # run TypeScript tests (8 tests)
npm test                # same as above
```

## Usage

```typescript
import { NumWasm } from "./src/nw";

const nw = await NumWasm.init();

const a = nw.zeros([2, 3]);     // { data: [0,0,0,0,0,0], shape: [2,3] }
const b = nw.ones([2, 3]);      // { data: [1,1,1,1,1,1], shape: [2,3] }
const c = nw.full([2, 2], 7.5); // { data: [7.5,7.5,7.5,7.5], shape: [2,2] }
const d = nw.arange(0, 5, 1);   // { data: [0,1,2,3,4], shape: [5] }
const e = nw.linspace(0, 1, 5); // { data: [0,0.25,0.5,0.75,1], shape: [5] }
```

## Design Choices

- **f64 only** — no dtype enum, no generic type dispatch
- **Flat `[]f64` storage** — no pointer casting, no strides
- **Copy-based operations** — no views, no ownership tracking
- **Row-major (C-contiguous)** — no Fortran order

These simplifications keep the codebase approachable. They can be upgraded later when performance matters.

## Roadmap

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Toolchain setup, hello WASM | Done |
| 2 | NDArray core data structure | Done |
| 3 | Array creation functions | Done |
| 4 | Shape manipulation (reshape, transpose, flatten) | Upcoming |
| 5 | Broadcasting | Upcoming |
| 6 | Element-wise operations (add, multiply, sqrt, etc.) | Upcoming |
| 7 | Reduction operations (sum, mean, max, min) | Upcoming |
| 8 | Slicing and indexing | Upcoming |
| 9 | Linear algebra (dot, matmul) | Upcoming |
| 10 | JS glue library (clean API) | Upcoming |

See [PLAN.md](./PLAN.md) for detailed implementation plans.
