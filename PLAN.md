    

# `num-wasm` — NumPy-like Library in Zig → WASM

## Architecture

```
num-wasm/
├── build.zig                  # Zig build config (wasm32-freestanding target)
├── src/
│   ├── ndarray.zig            # Core NDArray struct, get/set, creation, shape ops
│   ├── ops.zig                # Element-wise and reduction operations
│   ├── linalg.zig             # dot, matmul
│   ├── wasm_api.zig           # WASM exports (thin wrapper over core)
│   └── root.zig               # Module root, re-exports ndarray
├── web/
│   ├── numwasm.js             # JS glue: typed API over raw WASM pointers
│   └── test.js                # Node.js test runner
└── tests/                     # (future) additional test files
```

**Design principle**: Keep it simple. One data type (`f64`), flat array storage, no strides. All core logic lives in platform-agnostic `.zig` files. `wasm_api.zig` is a thin wrapper for WASM exports. Test natively with `zig build test`, test WASM with `node web/test.js`.

**Simplification choices** (can be upgraded later):

- `f64` only — no DType enum, no generic type dispatch
- Flat `[]f64` — no `[*]u8` pointer casting, no strides
- Always copy — no views, no ownership tracking. Simpler memory model.
- Row-major (C-contiguous) only — no Fortran order

---

## Phase 1 — Toolchain Setup & Hello WASM ✅

**Goal**: Prove Zig → WASM → JS works end-to-end.

- [X] **1.1** `zig init` the project, configure `build.zig` with `wasm32-freestanding` target, `.entry = .disabled`, `.rdynamic = true`, optimize for `.ReleaseFast`
- [X] **1.2** Write a single `export fn add(a: i32, b: i32) i32` in `wasm_api.zig`
- [X] **1.3** Write `web/test.js` (Node.js) that loads the `.wasm` via `WebAssembly.instantiate`, tests `add()`, `wasm_alloc/free`, and `sum_f64`
- [X] **1.4** Export `wasm_alloc(len) → [*]u8` and `wasm_free(ptr, len)` using `std.heap.wasm_allocator` — this is the memory bridge for everything later
- [X] **1.5** Test passing a `Float64Array` from JS into WASM: allocate buffer in WASM, copy JS data into it via `Float64Array` view of `memory.buffer`, call a Zig `sum_f64(ptr, len) → f64`, verify result via `node web/test.js`

---

## Phase 2 — NDArray Core Data Structure

**Goal**: Build the struct everything else depends on. Simple flat `[]f64` storage.

- [X] **2.1** Define `NDArray` struct in `src/ndarray.zig`: `data: []f64`, `shape: []usize`, `ndim: usize`, `allocator: Allocator`
- [X] **2.2** Implement `init(allocator, shape) → NDArray` — compute total elements from shape, allocate `[]f64` of that size, duplicate the shape slice (caller may pass stack memory)
- [X] **2.3** Implement `deinit(self)` — free `data`, then free `shape`
- [X] **2.4** Implement `flatIndex(self, indices) → usize` — convert N-dimensional indices to flat index. For shape `(3, 4)`: `flatIndex([1, 2])` = `1*4 + 2` = `6`. Formula: walk right-to-left, multiply by cumulative product of dimensions
- [X] **2.5** Implement `getItem(self, indices) → f64` — calls `flatIndex`, returns `self.data[flat]`
- [X] **2.6** Implement `setItem(self, indices, value)` — calls `flatIndex`, writes `self.data[flat] = value`
- [X] **2.7** Update `src/root.zig` to re-export: `pub const NDArray = @import("ndarray.zig").NDArray;`
- [ ] **2.8** Write tests: create `(3, 4)` array, set/get values, verify `flatIndex` math, verify memory cleanup with `std.testing.allocator`

**Index math** (no strides needed):

```
flatIndex([i, j])    for shape (R, C)       = i*C + j
flatIndex([i, j, k]) for shape (A, B, C)    = i*B*C + j*C + k
```

General formula: `flat = Σ(indices[d] * product(shape[d+1..]))`

---

## Phase 3 — Array Creation Functions

**Goal**: Equivalent of `np.zeros()`, `np.ones()`, `np.arange()`, etc.

- [ ] **3.1** `zeros(allocator, shape) → NDArray` — init + fill data with `0.0` using `@memset`
- [ ] **3.2** `ones(allocator, shape) → NDArray` — init + fill data with `1.0`
- [ ] **3.3** `full(allocator, shape, value) → NDArray` — init + fill data with arbitrary value
- [ ] **3.4** `arange(allocator, start, stop, step) → NDArray` — compute count = `@intFromFloat(@ceil((stop - start) / step))`, create 1D array `shape = [count]`, fill with `start, start+step, start+2*step, ...`
- [ ] **3.5** `linspace(allocator, start, stop, count) → NDArray` — 1D array of `count` evenly spaced values from `start` to `stop` inclusive
- [ ] **3.6** `fromSlice(allocator, data, shape) → NDArray` — copy a `[]const f64` into a new NDArray with given shape. Validate `data.len == product(shape)`
- [ ] **3.7** Export creation functions via `wasm_api.zig`, test from Node.js

---

## Phase 4 — Shape Manipulation

**Goal**: `reshape`, `transpose`, `flatten`. All return new arrays (copies).

- [ ] **4.1** `reshape(self, allocator, new_shape) → NDArray` — validate `product(new_shape) == product(old_shape)`, create new NDArray, copy data (`@memcpy`), assign new shape
- [ ] **4.2** `transpose(self, allocator) → NDArray` — 2D only. Create new `(cols, rows)` array, copy `result[j][i] = self[i][j]`
- [ ] **4.3** `flatten(self, allocator) → NDArray` — reshape to `[total_elements]`
- [ ] **4.4** `squeeze(self, allocator) → NDArray` — remove dimensions of size 1 from shape, copy data
- [ ] **4.5** Tests: reshape `(2, 6)` → `(3, 4)`, verify values preserved. Transpose `(3, 4)` → verify `(4, 3)` with correct element positions

---

## Phase 5 — Broadcasting

**Goal**: Enable operations between arrays of different shapes.

- [ ] **5.1** Implement `broadcastShapes(allocator, shape_a, shape_b) → []usize` — align from right, each pair must be equal or one must be 1, result = max of pair, error if incompatible
- [ ] **5.2** Implement `broadcastIndex(indices, original_shape, broadcast_shape) → []usize` — for each dimension, if `original_shape[d] == 1`, use index `0` regardless of the broadcast index (the element repeats)
- [ ] **5.3** Tests:
  - `(3, 4) + (4,)` → `(3, 4)`
  - `(3, 1) + (1, 4)` → `(3, 4)`
  - scalar + `(3, 4)` → `(3, 4)`
  - `(3, 4) + (3, 5)` → error

**How broadcasting works without strides**: Instead of the stride=0 trick, use index remapping. When iterating the output shape, map each output index back to each input's index — if an input dim is 1, always use 0 for that dimension.

---

## Phase 6 — Element-wise Operations

**Goal**: `add(a, b)`, `sqrt(a)`, etc. — using broadcasting.

- [ ] **6.1** Implement `binaryOp(allocator, a, b, comptime op_fn) → NDArray` — broadcast shapes, allocate output, iterate all indices in output, use `broadcastIndex` to get values from a and b, apply op
- [ ] **6.2** Wire up: `add`, `subtract`, `multiply`, `divide`
- [ ] **6.3** Implement `unaryOp(allocator, a, comptime op_fn) → NDArray` — allocate output with same shape, apply op to each element
- [ ] **6.4** Wire up: `negate`, `abs`, `sqrt`, `exp`, `log` — use `@sqrt`, `@exp`, `@log` builtins and `std.math`
- [ ] **6.5** Scalar-array ops: `addScalar`, `mulScalar` — simpler fast path, no broadcasting needed
- [ ] **6.6** Export key ops via WASM, test from Node.js

---

## Phase 7 — Reduction Operations

**Goal**: `sum()`, `mean()`, `max()`, `min()` — with optional axis.

- [ ] **7.1** Full reduction (no axis): iterate `self.data`, accumulate → return `f64`
- [ ] **7.2** Axis reduction: compute output shape (input shape with axis removed). Iterate output indices, for each one loop over the reduced dimension, accumulate
- [ ] **7.3** Implement generic `reduce(allocator, arr, comptime op, comptime identity, axis)` — shared iteration logic
- [ ] **7.4** Wire up: `sum`, `mean` (sum / count), `max`, `min`, `prod`
- [ ] **7.5** `argmax`, `argmin` — return index of best value
- [ ] **7.6** Tests: `(3, 4)` sum axis 0 → `(4,)`, sum axis 1 → `(3,)`, no axis → scalar

---

## Phase 8 — Slicing & Indexing

**Goal**: Extract sub-arrays. All operations return copies (no views in simplified approach).

- [ ] **8.1** `slice(self, allocator, dim, start, stop, step) → NDArray` — compute output shape, iterate and copy matching elements
- [ ] **8.2** Multi-dim slicing: chain single-dim slices
- [ ] **8.3** `indexAxis(self, allocator, dim, i) → NDArray` — select one position along dim, reduce ndim by 1
- [ ] **8.4** Boolean masking `where(self, allocator, mask) → NDArray` — copy elements where mask is non-zero
- [ ] **8.5** Negative indexing: `shape[dim] + index` for negative values
- [ ] **8.6** Tests: slice `(4, 5)` array, verify correct elements. Negative index. Boolean mask

---

## Phase 9 — Linear Algebra Basics

**Goal**: Dot product, matrix multiply.

- [ ] **9.1** `dot(a, b) → f64` — 1D only, `Σ(a.data[i] * b.data[i])`
- [ ] **9.2** `matmul(allocator, a, b) → NDArray` — 2D, `(m,k) × (k,n) → (m,n)`, naive triple loop
- [ ] **9.3** `outer(allocator, a, b) → NDArray` — `result[i*n + j] = a[i] * b[j]`
- [ ] **9.4** Tests: dot product, 2×3 times 3×2 matmul, outer product

---

## Phase 10 — JS Glue Library

**Goal**: Clean JS API that hides pointer/memory management.

- [ ] **10.1** `NumWasm` class — async `init()` loads WASM, stores exports
- [ ] **10.2** `NdArray` JS class — holds pointer + shape. Methods: `.toArray()`, `.toTypedArray()`, `.free()`
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

1. **Test natively first** — `zig build test` is instant. Don't debug in the browser until you must.
2. **`std.testing.allocator` detects memory leaks** — if your `deinit` misses a free, the test fails. This is your safety net.
3. **Print from WASM** — Import a `consoleLog(ptr, len)` from JS env for debugging.
4. **Upgrade path** — when you hit performance limits later, the upgrade to strides + `[*]u8` + DType is mechanical: same API surface, different internals.

---

## Future Upgrades (when you're ready)

These aren't needed now, but here's how to evolve the design:

| Upgrade     | When                                       | What changes                                                          |
| ----------- | ------------------------------------------ | --------------------------------------------------------------------- |
| Strides     | Transpose/slice copies become a bottleneck | Replace `[]f64` with `[*]u8` + strides, views instead of copies   |
| Multi-dtype | Need i32/f32/u8 arrays                     | Add `DType` enum, use `[*]u8` with `@ptrCast` for type dispatch |
| WASM SIMD   | Element-wise ops need more speed           | Use `@Vector(4, f64)` in hot loops                                  |
| Views       | Memory usage too high from copies          | Add `owns_data` flag + `base` pointer                             |
