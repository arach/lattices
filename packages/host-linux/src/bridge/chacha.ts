// ChaCha20-Poly1305 AEAD (RFC 8439), because Bun's node:crypto (BoringSSL)
// has no "chacha20-poly1305" cipher. Matches CryptoKit's ChaChaPoly: 32-byte
// key, 12-byte nonce, 16-byte tag. Payloads here are small (JSON, preview
// JPEGs), so clarity wins over speed.

function rotl(v: number, n: number) {
  return ((v << n) | (v >>> (32 - n))) >>> 0;
}

function quarter(s: Uint32Array, a: number, b: number, c: number, d: number) {
  s[a] = (s[a] + s[b]) >>> 0; s[d] = rotl(s[d] ^ s[a], 16);
  s[c] = (s[c] + s[d]) >>> 0; s[b] = rotl(s[b] ^ s[c], 12);
  s[a] = (s[a] + s[b]) >>> 0; s[d] = rotl(s[d] ^ s[a], 8);
  s[c] = (s[c] + s[d]) >>> 0; s[b] = rotl(s[b] ^ s[c], 7);
}

/** One 64-byte ChaCha20 block. */
export function chachaBlock(key: Uint8Array, counter: number, nonce: Uint8Array): Uint8Array {
  const kv = new DataView(key.buffer, key.byteOffset, 32);
  const nv = new DataView(nonce.buffer, nonce.byteOffset, 12);
  const init = new Uint32Array(16);
  init[0] = 0x61707865; init[1] = 0x3320646e; init[2] = 0x79622d32; init[3] = 0x6b206574;
  for (let i = 0; i < 8; i++) init[4 + i] = kv.getUint32(i * 4, true);
  init[12] = counter >>> 0;
  for (let i = 0; i < 3; i++) init[13 + i] = nv.getUint32(i * 4, true);
  const s = init.slice();
  for (let i = 0; i < 10; i++) {
    quarter(s, 0, 4, 8, 12); quarter(s, 1, 5, 9, 13); quarter(s, 2, 6, 10, 14); quarter(s, 3, 7, 11, 15);
    quarter(s, 0, 5, 10, 15); quarter(s, 1, 6, 11, 12); quarter(s, 2, 7, 8, 13); quarter(s, 3, 4, 9, 14);
  }
  const out = new Uint8Array(64);
  const ov = new DataView(out.buffer);
  for (let i = 0; i < 16; i++) ov.setUint32(i * 4, (s[i] + init[i]) >>> 0, true);
  return out;
}

export function chacha20(key: Uint8Array, nonce: Uint8Array, counter: number, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  for (let offset = 0, block = counter; offset < data.length; offset += 64, block++) {
    const ks = chachaBlock(key, block, nonce);
    const n = Math.min(64, data.length - offset);
    for (let i = 0; i < n; i++) out[offset + i] = data[offset + i] ^ ks[i];
  }
  return out;
}

const P1305 = (1n << 130n) - 5n;
const leBig = (b: Uint8Array) => {
  let v = 0n;
  for (let i = b.length - 1; i >= 0; i--) v = (v << 8n) | BigInt(b[i]);
  return v;
};

export function poly1305(key: Uint8Array, msg: Uint8Array): Uint8Array {
  const r = leBig(key.subarray(0, 16)) & 0x0ffffffc0ffffffc0ffffffc0fffffffn;
  const s = leBig(key.subarray(16, 32));
  let acc = 0n;
  for (let i = 0; i < msg.length; i += 16) {
    const chunk = msg.subarray(i, Math.min(i + 16, msg.length));
    const n = leBig(chunk) | (1n << BigInt(8 * chunk.length));
    acc = ((acc + n) * r) % P1305;
  }
  acc = (acc + s) & ((1n << 128n) - 1n);
  const tag = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    tag[i] = Number(acc & 0xffn);
    acc >>= 8n;
  }
  return tag;
}

function macData(aad: Uint8Array, ciphertext: Uint8Array): Uint8Array {
  const pad = (n: number) => (16 - (n % 16)) % 16;
  const out = new Uint8Array(aad.length + pad(aad.length) + ciphertext.length + pad(ciphertext.length) + 16);
  out.set(aad, 0);
  out.set(ciphertext, aad.length + pad(aad.length));
  const lens = new DataView(out.buffer, out.length - 16);
  lens.setBigUint64(0, BigInt(aad.length), true);
  lens.setBigUint64(8, BigInt(ciphertext.length), true);
  return out;
}

export function seal(key: Uint8Array, nonce: Uint8Array, plaintext: Uint8Array, aad: Uint8Array): { ciphertext: Uint8Array; tag: Uint8Array } {
  const polyKey = chachaBlock(key, 0, nonce).subarray(0, 32);
  const ciphertext = chacha20(key, nonce, 1, plaintext);
  return { ciphertext, tag: poly1305(polyKey, macData(aad, ciphertext)) };
}

export function open(key: Uint8Array, nonce: Uint8Array, ciphertext: Uint8Array, tag: Uint8Array, aad: Uint8Array): Uint8Array | null {
  const polyKey = chachaBlock(key, 0, nonce).subarray(0, 32);
  const expected = poly1305(polyKey, macData(aad, ciphertext));
  let diff = expected.length ^ tag.length;
  for (let i = 0; i < Math.min(expected.length, tag.length); i++) diff |= expected[i] ^ tag[i];
  return diff === 0 ? chacha20(key, nonce, 1, ciphertext) : null;
}
