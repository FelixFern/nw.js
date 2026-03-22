import fs from "fs";
import path from "path";

const WASM_PATH = path.join(__dirname, "../zig-out/bin/num-wasm.wasm");
const USIZE = 4;
const F64 = 8;

interface NdArray {
  data: number[];
  shape: number[];
}

interface NumWasmExports {
  memory: WebAssembly.Memory;
  wasm_alloc(len: number): number;
  wasm_free(ptr: number, len: number): void;
  add(a: number, b: number): number;
  sum_f64(ptr: number, len: number): number;
  wasm_zeros(shapePtr: number, shapeLen: number, outPtr: number): number;
  wasm_ones(shapePtr: number, shapeLen: number, outPtr: number): number;
  wasm_full(shapePtr: number, shapeLen: number, value: number, outPtr: number): number;
  wasm_arange(start: number, stop: number, step: number, outPtr: number): number;
  wasm_linspace(start: number, stop: number, count: number, outPtr: number): number;
}

export class NumWasm {
  private _exports: NumWasmExports;
  private _memory: WebAssembly.Memory;

  private constructor(instance: WebAssembly.Instance) {
    this._exports = instance.exports as unknown as NumWasmExports;
    this._memory = (instance.exports as unknown as NumWasmExports).memory;
  }

  static async init(): Promise<NumWasm> {
    const wasmBuffer = fs.readFileSync(WASM_PATH);
    const { instance } = await WebAssembly.instantiate(wasmBuffer);
    return new NumWasm(instance);
  }

  private _writeShape(shape: number[]): { ptr: number; byteLen: number } {
    const byteLen = shape.length * USIZE;
    const ptr = this._exports.wasm_alloc(byteLen);
    if (ptr === 0) throw new Error("alloc failed for shape");
    new Uint32Array(this._memory.buffer, ptr, shape.length).set(shape);
    return { ptr, byteLen };
  }

  private _allocOut(): number {
    const ptr = this._exports.wasm_alloc(2 * USIZE);
    if (ptr === 0) throw new Error("alloc failed for out buffer");
    return ptr;
  }

  private _readResult(outPtr: number): number[] {
    const out = new Uint32Array(this._memory.buffer, outPtr, 2);
    const dataPtr = out[0];
    const dataLen = out[1];
    this._exports.wasm_free(outPtr, 2 * USIZE);

    const data = Array.from(
      new Float64Array(this._memory.buffer, dataPtr, dataLen),
    );
    this._exports.wasm_free(dataPtr, dataLen * F64);
    return data;
  }

  private _callWithShape(
    wasmFn: (...args: number[]) => number,
    shape: number[],
    ...extraArgs: number[]
  ): NdArray {
    const s = this._writeShape(shape);
    const outPtr = this._allocOut();
    const rc = wasmFn(s.ptr, shape.length, ...extraArgs, outPtr);
    this._exports.wasm_free(s.ptr, s.byteLen);
    if (rc !== 0) throw new Error(`WASM call failed (rc=${rc})`);
    return { data: this._readResult(outPtr), shape: [...shape] };
  }

  zeros(shape: number[]): NdArray {
    return this._callWithShape(this._exports.wasm_zeros, shape);
  }

  ones(shape: number[]): NdArray {
    return this._callWithShape(this._exports.wasm_ones, shape);
  }

  full(shape: number[], value: number): NdArray {
    return this._callWithShape(this._exports.wasm_full, shape, value);
  }

  arange(start: number, stop: number, step: number): NdArray {
    const outPtr = this._allocOut();
    const rc = this._exports.wasm_arange(start, stop, step, outPtr);
    if (rc !== 0) throw new Error(`arange failed (rc=${rc})`);
    const data = this._readResult(outPtr);
    return { data, shape: [data.length] };
  }

  linspace(start: number, stop: number, count: number): NdArray {
    const outPtr = this._allocOut();
    const rc = this._exports.wasm_linspace(start, stop, count, outPtr);
    if (rc !== 0) throw new Error(`linspace failed (rc=${rc})`);
    const data = this._readResult(outPtr);
    return { data, shape: [data.length] };
  }
}
