use wasm_bindgen::prelude::*;
pub use crapto1::wasm_rayon::init_thread_pool;

#[wasm_bindgen(start)]
pub fn init_panic_hook() {
    console_error_panic_hook::set_once();
}

#[wasm_bindgen]
pub fn darkside(uid: u32, items_flat: &[u32]) -> js_sys::BigUint64Array {
    let mut items = Vec::new();
    let mut i = 0;
    while i + 7 <= items_flat.len() {
        items.push(crapto1::DarksideItem {
            nt: items_flat[i],
            ks: items_flat[i + 1] as u64 | ((items_flat[i + 2] as u64) << 32),
            par: items_flat[i + 3] as u64 | ((items_flat[i + 4] as u64) << 32),
            nr: items_flat[i + 5],
            ar: items_flat[i + 6],
        });
        i += 7;
    }
    let keys = crapto1::darkside(uid, &items);
    let arr = js_sys::BigUint64Array::new_with_length(keys.len() as u32);
    for (i, &k) in keys.iter().enumerate() {
        arr.set_index(i as u32, k);
    }
    arr
}

#[wasm_bindgen]
pub fn nested(
    uid: u32, dist: u32,
    nt0: u32, nt0_enc: u32, par0: u32,
    nt1: u32, nt1_enc: u32, par1: u32,
) -> js_sys::BigUint64Array {
    let data = crapto1::NestedData {
        uid, dist, nt0, nt0_enc, par0: par0 as u8, nt1, nt1_enc, par1: par1 as u8,
    };
    let keys = crapto1::nested(&data);
    let arr = js_sys::BigUint64Array::new_with_length(keys.len() as u32);
    for (i, &k) in keys.iter().enumerate() {
        arr.set_index(i as u32, k);
    }
    arr
}

#[wasm_bindgen]
pub fn static_nested(
    uid: u32, key_type: u32,
    nt0: u32, nt0_enc: u32,
    nt1: u32, nt1_enc: u32,
) -> js_sys::BigUint64Array {
    let data = crapto1::StaticNestedData {
        uid, key_type: key_type as u8, nt0, nt0_enc, nt1, nt1_enc,
    };
    let keys = crapto1::static_nested(&data).unwrap_or_default();
    let arr = js_sys::BigUint64Array::new_with_length(keys.len() as u32);
    for (i, &k) in keys.iter().enumerate() {
        arr.set_index(i as u32, k);
    }
    arr
}

#[wasm_bindgen]
pub fn static_encrypted_nested(
    uid: u32, nt: u32, nt_enc: u32, nt_par_enc: u32,
) -> js_sys::BigUint64Array {
    let data = crapto1::StaticEncryptedNestedData {
        uid, nt, nt_enc, nt_par_enc,
    };
    let keys = crapto1::static_encrypted_nested(&data);
    let arr = js_sys::BigUint64Array::new_with_length(keys.len() as u32);
    for (i, &k) in keys.iter().enumerate() {
        arr.set_index(i as u32, k);
    }
    arr
}

#[wasm_bindgen]
pub fn mfkey32(
    uid: u32, nt0: u32, nr0_enc: u32, ar0_enc: u32,
    nt1: u32, nr1_enc: u32, ar1_enc: u32,
) -> js_sys::BigInt {
    js_sys::BigInt::from(crapto1::recovery32(uid, nt0, nr0_enc, ar0_enc, nt1, nr1_enc, ar1_enc).unwrap_or(0))
}

#[wasm_bindgen]
pub fn mfkey64(uid: u32, nt: u32, nr_enc: u32, ar_enc: u32, at_enc: u32) -> js_sys::BigInt {
    let key = crapto1::recovery64(uid, nt, nr_enc, ar_enc, at_enc);
    js_sys::BigInt::from(key)
}

#[wasm_bindgen]
pub fn hardnested(nonces: &[u8]) -> js_sys::BigInt {
    match crapto1::hardnested(nonces) {
        Some(key) => js_sys::BigInt::from(key),
        None => js_sys::BigInt::from(0),
    }
}
