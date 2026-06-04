let wasmReady = false;

async function init() {
  const base = self.location.href.replace(/\/[^/]*$/, '');
  importScripts(base + '/pkg/recovery_wasm.js');
  await wasm_bindgen(base + '/pkg/recovery_wasm_bg.wasm');
  self.__crapto1_script_url = base + '/pkg/recovery_wasm.js';
  await wasm_bindgen.initThreadPool(navigator.hardwareConcurrency || 4);
  wasmReady = true;
  postMessage({ type: 'ready' });
}

self.onmessage = async function(e) {
  const { id, method, args } = e.data;
  if (!wasmReady) {
    postMessage({ id, error: 'WASM not ready' });
    return;
  }
  try {
    let result;
    switch (method) {
      case 'darkside':
        result = wasm_bindgen.darkside(args.uid, new Uint32Array(args.flat));
        result = Array.from(result, v => v.toString());
        break;
      case 'nested':
        result = wasm_bindgen.nested(args.uid, args.dist, args.nt0, args.nt0Enc, args.par0, args.nt1, args.nt1Enc, args.par1);
        result = Array.from(result, v => v.toString());
        break;
      case 'static_nested':
        result = wasm_bindgen.static_nested(args.uid, args.keyType, args.nt0, args.nt0Enc, args.nt1, args.nt1Enc);
        result = Array.from(result, v => v.toString());
        break;
      case 'static_encrypted_nested':
        result = wasm_bindgen.static_encrypted_nested(args.uid, args.nt, args.ntEnc, args.ntParEnc);
        result = Array.from(result, v => v.toString());
        break;
      case 'mfkey32':
        result = wasm_bindgen.mfkey32(args.uid, args.nt0, args.nr0Enc, args.ar0Enc, args.nt1, args.nr1Enc, args.ar1Enc);
        result = result.toString();
        break;
      case 'mfkey64':
        result = wasm_bindgen.mfkey64(args.uid, args.nt, args.nrEnc, args.arEnc, args.atEnc);
        result = result.toString();
        break;
      case 'hardnested':
        result = wasm_bindgen.hardnested(new Uint8Array(args.nonces));
        result = result.toString();
        break;
      default:
        postMessage({ id, error: 'Unknown method: ' + method });
        return;
    }
    postMessage({ id, result });
  } catch (err) {
    postMessage({ id, error: err.toString() });
  }
};

init();
