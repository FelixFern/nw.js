const fs = require("fs");
const path = require("path");
const { strict: assert } = require("assert");

const WASM_PATH = path.join(__dirname, "num-wasm.wasm");

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (err) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${err.message}`);
    failed++;
  }
}

async function main() {
  const wasmBuffer = fs.readFileSync(WASM_PATH);
  const { instance } = await WebAssembly.instantiate(wasmBuffer);
  const exports = instance.exports;
  const {
    add,
    wasm_alloc,
    wasm_free,
    sum_f64,
    wasm_zeros,
    wasm_ones,
    wasm_full,
    wasm_arange,
    wasm_linspace,
    wasm_fromSlice,
    memory,
  } = exports;

  // -------------------------------------------------------
  // Helpers: write shape / read result from WASM memory
  // -------------------------------------------------------

  // On wasm32, usize = u32 (4 bytes)
  const USIZE = 4;
  const F64 = 8;

  /**
   * Write a JS shape array into WASM memory.
   * Returns { ptr, byteLen } — caller must wasm_free(ptr, byteLen) when done.
   */
  function writeShape(shape) {
    const byteLen = shape.length * USIZE;
    const ptr = wasm_alloc(byteLen);
    if (ptr === 0) throw new Error("wasm_alloc failed for shape");
    const view = new Uint32Array(memory.buffer, ptr, shape.length);
    view.set(shape);
    return { ptr, byteLen };
  }

  /**
   * Write a JS f64 array into WASM memory.
   * Returns { ptr, byteLen } — caller must wasm_free(ptr, byteLen) when done.
   */
  function writeF64Array(data) {
    const byteLen = data.length * F64;
    const ptr = wasm_alloc(byteLen);
    if (ptr === 0) throw new Error("wasm_alloc failed for f64 data");
    const view = new Float64Array(memory.buffer, ptr, data.length);
    view.set(data);
    return { ptr, byteLen };
  }

  /**
   * Allocate a 2-element usize buffer for out_ptr.
   * Returns ptr — caller reads out[0]=dataPtr, out[1]=dataLen, then frees.
   */
  function allocOut() {
    const ptr = wasm_alloc(2 * USIZE);
    if (ptr === 0) throw new Error("wasm_alloc failed for out buffer");
    return ptr;
  }

  /**
   * Read result from out_ptr, copy f64 data to JS, free WASM memory.
   * Returns a plain JS number array.
   */
  function readResult(outPtr) {
    const out = new Uint32Array(memory.buffer, outPtr, 2);
    const dataPtr = out[0];
    const dataLen = out[1];
    wasm_free(outPtr, 2 * USIZE);

    const data = new Float64Array(memory.buffer, dataPtr, dataLen);
    const jsArray = Array.from(data);

    // Free the WASM data buffer (dataLen elements × 8 bytes each)
    wasm_free(dataPtr, dataLen * F64);
    return jsArray;
  }

  // -------------------------------------------------------
  // Phase 1 — Toolchain
  // -------------------------------------------------------

  console.log("\nnum-wasm · Phase 1\n");

  // ----- add -----
  console.log("add(a, b):");
  test("add(3, 7) === 10", () => assert.equal(add(3, 7), 10));
  test("add(-1, 1) === 0", () => assert.equal(add(-1, 1), 0));
  test("add(0, 0) === 0", () => assert.equal(add(0, 0), 0));

  // ----- wasm_alloc / wasm_free -----
  console.log("\nwasm_alloc / wasm_free:");
  test("alloc 64 bytes returns non-zero pointer", () => {
    const ptr = wasm_alloc(64);
    assert.notEqual(ptr, 0);
    wasm_free(ptr, 64);
  });

  test("alloc multiple times returns different pointers", () => {
    const a = wasm_alloc(32);
    const b = wasm_alloc(32);
    assert.notEqual(a, 0);
    assert.notEqual(b, 0);
    assert.notEqual(a, b);
    wasm_free(a, 32);
    wasm_free(b, 32);
  });

  // ----- sum_f64 -----
  console.log("\nsum_f64(ptr, len):");

  function sumTest(name, jsArray, expected) {
    test(name, () => {
      const count = jsArray.length;
      const bytes = count * 8;
      const ptr = wasm_alloc(bytes);
      assert.notEqual(ptr, 0, "alloc failed");

      const view = new Float64Array(memory.buffer, ptr, count);
      view.set(jsArray);

      const result = sum_f64(ptr, count);
      wasm_free(ptr, bytes);

      assert.ok(
        Math.abs(result - expected) < 1e-10,
        `got ${result}, expected ${expected}`
      );
    });
  }

  sumTest("sum([1.5, 2.5, 3, 4, 5]) === 16", [1.5, 2.5, 3, 4, 5], 16);
  sumTest("sum([0]) === 0", [0], 0);
  sumTest("sum([-1, 1]) === 0", [-1, 1], 0);
  sumTest("sum([1e10, 1e-10]) === 1e10 + 1e-10", [1e10, 1e-10], 1e10 + 1e-10);
  sumTest(
    "sum 1000 elements",
    Array.from({ length: 1000 }, (_, i) => i + 1),
    (1000 * 1001) / 2
  );

  // -------------------------------------------------------
  // Phase 3 — Array Creation Functions
  // -------------------------------------------------------

  console.log("\n\nnum-wasm · Phase 3\n");

  // ----- zeros -----
  console.log("wasm_zeros:");
  test("zeros([2, 3]) → 6 elements, all 0", () => {
    const shape = writeShape([2, 3]);
    const outPtr = allocOut();
    const rc = wasm_zeros(shape.ptr, 2, outPtr);
    wasm_free(shape.ptr, shape.byteLen);
    assert.equal(rc, 0, "wasm_zeros failed");

    const data = readResult(outPtr);
    assert.equal(data.length, 6);
    data.forEach((v) => assert.equal(v, 0.0));
  });

  test("zeros([5]) → 5 elements, all 0", () => {
    const shape = writeShape([5]);
    const outPtr = allocOut();
    const rc = wasm_zeros(shape.ptr, 1, outPtr);
    wasm_free(shape.ptr, shape.byteLen);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.equal(data.length, 5);
    data.forEach((v) => assert.equal(v, 0.0));
  });

  // ----- ones -----
  console.log("\nwasm_ones:");
  test("ones([2, 3]) → 6 elements, all 1", () => {
    const shape = writeShape([2, 3]);
    const outPtr = allocOut();
    const rc = wasm_ones(shape.ptr, 2, outPtr);
    wasm_free(shape.ptr, shape.byteLen);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.equal(data.length, 6);
    data.forEach((v) => assert.equal(v, 1.0));
  });

  // ----- full -----
  console.log("\nwasm_full:");
  test("full([2, 2], 7.5) → 4 elements, all 7.5", () => {
    const shape = writeShape([2, 2]);
    const outPtr = allocOut();
    const rc = wasm_full(shape.ptr, 2, 7.5, outPtr);
    wasm_free(shape.ptr, shape.byteLen);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.equal(data.length, 4);
    data.forEach((v) => assert.equal(v, 7.5));
  });

  // ----- arange -----
  console.log("\nwasm_arange:");
  test("arange(0, 5, 1) → [0, 1, 2, 3, 4]", () => {
    const outPtr = allocOut();
    const rc = wasm_arange(0, 5, 1, outPtr);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.deepEqual(data, [0, 1, 2, 3, 4]);
  });

  test("arange(1, 10, 3) → [1, 4, 7]", () => {
    const outPtr = allocOut();
    const rc = wasm_arange(1, 10, 3, outPtr);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.deepEqual(data, [1, 4, 7]);
  });

  // ----- linspace -----
  console.log("\nwasm_linspace:");
  test("linspace(0, 1, 5) → [0, 0.25, 0.5, 0.75, 1]", () => {
    const outPtr = allocOut();
    const rc = wasm_linspace(0, 1, 5, outPtr);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.equal(data.length, 5);
    const expected = [0, 0.25, 0.5, 0.75, 1.0];
    data.forEach((v, i) =>
      assert.ok(Math.abs(v - expected[i]) < 1e-10, `data[${i}]: got ${v}`)
    );
  });

  test("linspace(5, 5, 1) → [5]", () => {
    const outPtr = allocOut();
    const rc = wasm_linspace(5, 5, 1, outPtr);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.deepEqual(data, [5]);
  });

  // ----- fromSlice -----
  console.log("\nwasm_fromSlice:");
  test("fromSlice([1,2,3,4,5,6], [2,3]) → copies data correctly", () => {
    const inputData = writeF64Array([1, 2, 3, 4, 5, 6]);
    const shape = writeShape([2, 3]);
    const outPtr = allocOut();

    const rc = wasm_fromSlice(inputData.ptr, 6, shape.ptr, 2, outPtr);
    wasm_free(inputData.ptr, inputData.byteLen);
    wasm_free(shape.ptr, shape.byteLen);
    assert.equal(rc, 0);

    const data = readResult(outPtr);
    assert.deepEqual(data, [1, 2, 3, 4, 5, 6]);
  });

  test("fromSlice with shape mismatch → returns -1", () => {
    const inputData = writeF64Array([1, 2, 3, 4, 5]);
    const shape = writeShape([2, 3]); // needs 6 elements, got 5
    const outPtr = allocOut();

    const rc = wasm_fromSlice(inputData.ptr, 5, shape.ptr, 2, outPtr);
    wasm_free(inputData.ptr, inputData.byteLen);
    wasm_free(shape.ptr, shape.byteLen);
    wasm_free(outPtr, 2 * USIZE);
    assert.equal(rc, -1);
  });

  // ----- summary -----
  console.log(`\n${"─".repeat(40)}`);
  console.log(`${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
