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
  const { add, wasm_alloc, wasm_free, sum_f64, memory } = instance.exports;

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

  // ----- summary -----
  console.log(`\n${"─".repeat(40)}`);
  console.log(`${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
