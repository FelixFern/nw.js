# `num-wasm` — NumPy-like Library in Zig → WASM

## Architecture

```
num-wasm/
├── build.zig                  # Zig build config (wasm32-freestanding target)
├── src/
│   ├── ndarray.zig            # Core NDArray struct + memory layout
│   ├── dtype.zig              # Data types (f32, f64, i32, i64, u8)
│   ├── strides.zig            # Stride computation, contiguity checks
│   ├── creation.zig           # zeros, ones, empty, full, arange, linspace
│   ├── indexing.zig           # getItem, setItem, slice (views)
│   ├── shape.zig              # reshape, transpose, flatten, squeeze
│   ├── broadcast.zig          # Broadcasting rules engine
│   ├── elementwise.zig        # +, -, *, /, sqrt, abs, pow, exp, log
│   ├── reduction.zig          # sum, mean, max, min, argmax, argmin (axis-aware)
│   ├── linalg.zig             # dot, matmul, transpose
│   ├── wasm_api.zig           # WASM exports (thin wrapper over core)
│   └── root.zig               # Module root
├── web/
│   ├── numwasm.js             # JS glue: typed API over raw WASM pointers
│   └── index.html             # Demo/test page
└── tests/
    └── ndarray_test.zig       # Native tests (run with `zig test`)
```

**Design principle**: All core logic lives in platform-agnostic `.zig` files. `wasm_api.zig` is a thin layer that translates pointer+length ↔ slices using `std.heap.wasm_allocator`. This means you can test everything natively with `zig test` before touching the browser.

---

## Phase 1 — Toolchain Setup & Hello WASM

**Goal**: Prove Zig → WASM → JS works end-to-end.

- [x] **1.1** `zig init` the project, configure `build.zig` with `wasm32-freestanding` target, `.entry = .disabled`, `.rdynamic = true`, optimize for `.ReleaseFast`
- [x] **1.2** Write a single `export fn add(a: i32, b: i32) i32` in `wasm_api.zig`
- [x] **1.3** Write `web/test.js` (Node.js) that loads the `.wasm` via `WebAssembly.instantiate`, tests `add()`, `wasm_alloc/free`, and `sum_f64`
- [x] **1.4** Export `wasm_alloc(len) → [*]u8` and `wasm_free(ptr, len)` using `std.heap.wasm_allocator` — this is the memory bridge for everything later
- [x] **1.5** Test passing a `Float64Array` from JS into WASM: allocate buffer in WASM, copy JS data into it via `Float64Array` view of `memory.buffer`, call a Zig `sum_f64(ptr, len) → f64`, verify result via `node web/test.js`

**Key constraints**:

- `export fn` can only accept/return: `i32`, `i64`, `f32`, `f64`, pointers
- No slices, structs, or arrays across the boundary — always pointer + length
- `std.heap.wasm_allocator` is the only allocator that works in `wasm32-freestanding`
- No `std.debug.print` in WASM — import `consoleLog(ptr, len)` from JS environment if you need logging

---

## Phase 2 — NDArray Core Data Structure

**Goal**: Build the struct everything else depends on.

- [ ] **2.1** Define `DType` enum (`f32`, `f64`, `i32`, `i64`, `u8`) with a `sizeOf() → usize` method
- [ ] **2.2** Define `NDArray` struct: `data: [*]u8`, `shape: []usize`, `strides: []usize`, `ndim: usize`, `dtype: DType`, `flags: Flags`, `base: ?*NDArray`
- [ ] **2.3** Implement `computeStrides(shape, dtype_size) → []usize` — C-contiguous (row-major). For shape `(3, 4)` with `f64`: strides = `[32, 8]`. Formula: `strides[i] = product(shape[i+1..]) * dtype_size`
- [ ] **2.4** Implement `getItem(indices) → value` and `setItem(indices, value)` using stride-based offset: `offset = Σ(index[i] * stride[i])`
- [ ] **2.5** Implement `init(allocator, shape, dtype) → NDArray` and `deinit(allocator)` — allocate data + shape + strides. `deinit` only frees data if `base == null` (owns data)
- [ ] **2.6** Write native tests for all of the above

**The one thing to internalize**: `offset = indices[0]*strides[0] + indices[1]*strides[1] + ...` — this single formula is what makes reshape, transpose, and slicing nearly free later.

---

## Phase 3 — Array Creation Functions

**Goal**: Equivalent of `np.zeros()`, `np.ones()`, `np.arange()`, etc.

- [ ] **3.1** `empty(shape, dtype)` — allocate without initializing (fastest)
- [ ] **3.2** `zeros(shape, dtype)` — `empty()` + `@memset(data, 0, total_bytes)`
- [ ] **3.3** `ones(shape, dtype)` / `full(shape, value, dtype)` — fill with value
- [ ] **3.4** `arange(start, stop, step)` — compute length as `ceil((stop - start) / step)`, create 1D array, fill with sequence
- [ ] **3.5** `linspace(start, stop, count)` — create 1D array, fill with `start + i * (stop - start) / (count - 1)`
- [ ] **3.6** `fromSlice(data, shape, dtype)` — wrap existing data pointer as NDArray (no copy, caller owns memory)
- [ ] **3.7** Export creation functions via `wasm_api.zig`, test from JS

**Simplification**: Hardcode `f64` for now. Add dtype generics via Zig `comptime` once the API surface is stable.

---

## Phase 4 — Shape Manipulation (Zero-Copy)

**Goal**: `reshape`, `transpose`, `flatten` — all return views (same data, different metadata).

- [ ] **4.1** `isContiguous(self) → bool` — check if strides match what `computeStrides` would produce for the current shape
- [ ] **4.2** `reshape(self, new_shape) → NDArray` — verify `product(new_shape) == product(old_shape)`. If contiguous: return view with new shape/strides, `base = self`. If not contiguous: allocate + copy first
- [ ] **4.3** `transpose(self) → NDArray` — reverse both `shape` and `strides` arrays. Return view. No data movement
- [ ] **4.4** `transposeAxes(self, axes) → NDArray` — generalized transpose, reorder shape/strides by `axes` permutation
- [ ] **4.5** `flatten(self) → NDArray` — equivalent to `reshape(&[_]usize{total_elements})`
- [ ] **4.6** `squeeze(self) → NDArray` — remove all dimensions of size 1
- [ ] **4.7** Tests: reshape `(2,6)` → `(3,4)`, verify data unchanged. Transpose `(3,4)` → verify shape `(4,3)` and strides swapped. Modify transposed view → verify original changed

---

## Phase 5 — Broadcasting Engine 🔑 *Hardest phase*

**Goal**: Enable operations between arrays of different shapes.

- [ ] **5.1** Implement `broadcastShapes(shape_a, shape_b) → result_shape` — align from right, dimensions must be equal or one must be 1, missing dims = 1, result = max of pair, error if incompatible
- [ ] **5.2** Implement `broadcastStrides(original_strides, original_shape, target_shape) → new_strides` — where original dim was 1 and target is >1: set stride to **0** (element repeats virtually without copying)
- [ ] **5.3** Implement `BroadcastIterator` struct — iterates two arrays simultaneously with broadcast-aware index computation, `next() → (?*f64, ?*f64)`
- [ ] **5.4** Tests:
  - `(3, 4) + (4,)` → `(3, 4)` — row broadcast
  - `(3, 1) + (1, 4)` → `(3, 4)` — both broadcast
  - `(5, 1, 3) + (1, 4, 1)` → `(5, 4, 3)` — 3D broadcast
  - scalar + `(3, 4)` → `(3, 4)` — scalar broadcast
  - `(3, 4) + (3, 5)` → error — incompatible

**The stride=0 trick**: When dimension is broadcast from 1→N, stride is 0. Iterator advances index but pointer stays — same element read N times. No data duplication.

---

## Phase 6 — Element-wise Operations

**Goal**: `add(a, b)`, `sqrt(a)`, etc. — all using the broadcasting engine.

- [ ] **6.1** Implement generic `binaryOp(a, b, comptime op) → NDArray` — broadcast shapes, allocate output, iterate with `BroadcastIterator`, apply `op`
- [ ] **6.2** Wire up: `add`, `subtract`, `multiply`, `divide`, `power`
- [ ] **6.3** Implement generic `unaryOp(a, comptime op) → NDArray` — allocate output with same shape, iterate, apply
- [ ] **6.4** Wire up: `negate`, `abs`, `sqrt`, `exp`, `log`, `sin`, `cos` — use `@sqrt`, `@exp`, `@log` builtins and `std.math`
- [ ] **6.5** Comparison ops: `equal`, `greaterThan`, `lessThan` — binaryOp but output dtype is `u8` (0 or 1)
- [ ] **6.6** Scalar shortcuts: `addScalar`, `mulScalar` — avoid broadcast overhead for most common case
- [ ] **6.7** Export key ops via WASM, verify from JS

---

## Phase 7 — Reduction Operations

**Goal**: `sum()`, `mean()`, `max()`, `min()` — with optional axis parameter.

- [ ] **7.1** Full reduction (no axis): iterate all elements, accumulate → return scalar
- [ ] **7.2** Axis reduction: output shape = input shape with reduced axis removed. e.g. `(3, 4, 5)` sum over `axis=1` → `(3, 5)`. For each output position, loop over reduced axis
- [ ] **7.3** Implement generic `reduce(arr, comptime op, comptime identity, axis) → NDArray` — `op` = accumulation fn, `identity` = starting value (0 for sum, -inf for max)
- [ ] **7.4** Wire up: `sum(axis)`, `mean(axis)` (= sum / count), `max(axis)`, `min(axis)`, `prod(axis)`
- [ ] **7.5** `argmax(axis)`, `argmin(axis)` — same pattern but track index of best value
- [ ] **7.6** Tests: `(3, 4)` sum axis 0 → `(4,)`, sum axis 1 → `(3,)`, no axis → scalar

---

## Phase 8 — Slicing & Indexing

**Goal**: Extract sub-arrays. Basic slicing = views (zero-copy), advanced indexing = copies.

- [ ] **8.1** Basic slice `slice(self, dim, start, stop, step) → NDArray` (view): adjust data pointer by `start * stride[dim]`, new shape = `ceil((stop-start)/step)`, new stride = `stride[dim] * step`, set `base = self`
- [ ] **8.2** Multi-dim slicing: chain single-dim slices. `arr[1:3, 0:2]` = `arr.slice(0, 1, 3, 1).slice(1, 0, 2, 1)`
- [ ] **8.3** Integer index `index(self, dim, i) → NDArray` — select one position along a dim, reduce ndim by 1
- [ ] **8.4** Boolean masking `where(self, mask) → NDArray` — count true values, allocate, copy matching. **Always a copy**
- [ ] **8.5** Fancy indexing `take(self, dim, indices) → NDArray` — gather at arbitrary positions. **Always a copy**
- [ ] **8.6** Negative indexing: treat negatives as `shape[dim] + index`
- [ ] **8.7** Tests: slice `(4, 5)`, modify view, verify original changed. Boolean mask 1D array, verify copy semantics

---

## Phase 9 — Linear Algebra Basics

**Goal**: Dot product, matrix multiply.

- [ ] **9.1** `dot(a, b) → f64` — 1D only, `Σ(a[i] * b[i])`, validate both 1D and same length
- [ ] **9.2** `matmul(a, b) → NDArray` — 2D, `(m,k) × (k,n) → (m,n)`, naive triple loop first
- [ ] **9.3** Optimize matmul with loop tiling — cache-friendly blocks (e.g. 32×32). 3-5x speedup over naive
- [ ] **9.4** `outer(a, b) → NDArray` — outer product, `result[i,j] = a[i] * b[j]`
- [ ] **9.5** (Future) WASM SIMD via `@Vector(4, f64)` — 4x throughput for f64 ops

---

## Phase 10 — JS Glue Library

**Goal**: Clean JS API that hides pointer/memory management.

- [ ] **10.1** `NumWasm` class — async `init()` loads WASM, stores exports
- [ ] **10.2** `NdArray` JS class — holds pointer + shape + dtype. Methods: `.toArray()`, `.toTypedArray()`, `.free()`, `.shape`/`.dtype`/`.ndim` getters
- [ ] **10.3** `nw.array(jsData)` — detect shape from nesting, flatten, copy into WASM, return `NdArray`
- [ ] **10.4** Method wrappers: `nw.add(a, b)`, `nw.sum(a, {axis: 0})`, `nw.reshape(a, [3, 4])`, etc.
- [ ] **10.5** `FinalizationRegistry` — auto-cleanup with console warning if user forgets `.free()`
- [ ] **10.6** Error handling — check null pointers from WASM (allocation failures), throw typed JS errors

**Target API**:

```javascript
const nw = await NumWasm.init();

const a = nw.array([[1, 2, 3], [4, 5, 6]]);
const b = nw.ones([2, 3]);
const c = nw.add(a, b);
const s = nw.sum(c, { axis: 0 });

console.log(s.toArray()); // [6, 8, 10]

a.free(); b.free(); c.free(); s.free();
```

---

## Tips

1. **Test natively first** — `zig test` is instant. Don't debug in the browser until you must.
2. **Start with `f64` only** — Add dtype generics later. Get the algorithms right first.
3. **Print from WASM** — Import a `consoleLog(ptr, len)` from JS env for debugging.
4. **C-contiguous only at first** — Fortran order adds complexity, defer it.
5. **Read NumPy source** — [`numpy/_core/src/multiarray/`](https://github.com/numpy/numpy/tree/main/numpy/_core/src/multiarray) is surprisingly readable C.
