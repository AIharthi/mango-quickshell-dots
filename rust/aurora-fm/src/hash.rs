use std::collections::HashSet;
use std::fmt::Write as _;
use std::fs::{self, File};
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;

use crate::json::JsonOut;
use crate::util::{display_path, expand_path, human_size};

const MAX_HASH_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MAX_DIR_ENTRIES: usize = 50_000;

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

struct Sha256 {
    state: [u32; 8],
    len_bits: u64,
    buf: [u8; 64],
    buf_len: usize,
}

impl Sha256 {
    fn new() -> Self {
        Self {
            state: [
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
                0x5be0cd19,
            ],
            len_bits: 0,
            buf: [0u8; 64],
            buf_len: 0,
        }
    }

    fn compress(state: &mut [u32; 8], block: &[u8; 64]) {
        let mut w = [0u32; 64];
        for (i, slot) in w.iter_mut().enumerate().take(16) {
            let off = i * 4;
            *slot =
                u32::from_be_bytes([block[off], block[off + 1], block[off + 2], block[off + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = *state;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = h
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        state[0] = state[0].wrapping_add(a);
        state[1] = state[1].wrapping_add(b);
        state[2] = state[2].wrapping_add(c);
        state[3] = state[3].wrapping_add(d);
        state[4] = state[4].wrapping_add(e);
        state[5] = state[5].wrapping_add(f);
        state[6] = state[6].wrapping_add(g);
        state[7] = state[7].wrapping_add(h);
    }

    fn update(&mut self, mut data: &[u8]) {
        self.len_bits = self
            .len_bits
            .wrapping_add((data.len() as u64).wrapping_mul(8));
        if self.buf_len > 0 {
            let take = (64 - self.buf_len).min(data.len());
            self.buf[self.buf_len..self.buf_len + take].copy_from_slice(&data[..take]);
            self.buf_len += take;
            data = &data[take..];
            if self.buf_len == 64 {
                let block = self.buf;
                Self::compress(&mut self.state, &block);
                self.buf_len = 0;
            }
        }
        while data.len() >= 64 {
            let mut block = [0u8; 64];
            block.copy_from_slice(&data[..64]);
            Self::compress(&mut self.state, &block);
            data = &data[64..];
        }
        if !data.is_empty() {
            self.buf[..data.len()].copy_from_slice(data);
            self.buf_len = data.len();
        }
    }

    fn finalize_hex(mut self) -> String {
        let bit_len = self.len_bits;
        self.buf[self.buf_len] = 0x80;
        self.buf_len += 1;
        if self.buf_len > 56 {
            self.buf[self.buf_len..64].fill(0);
            let block = self.buf;
            Self::compress(&mut self.state, &block);
            self.buf_len = 0;
        }
        self.buf[self.buf_len..56].fill(0);
        self.buf[56..64].copy_from_slice(&bit_len.to_be_bytes());
        let block = self.buf;
        Self::compress(&mut self.state, &block);

        let mut out = String::with_capacity(64);
        for word in self.state {
            let _ = write!(out, "{word:08x}");
        }
        out
    }
}

pub fn sha256_file(raw_path: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let meta =
        fs::metadata(&target).map_err(|_| format!("File not found: {}", target.display()))?;
    if !meta.is_file() {
        return Err(format!("Not a regular file: {}", target.display()));
    }
    let size = meta.len();
    if size > MAX_HASH_BYTES {
        return Err(format!(
            "File exceeds 2 GiB hash limit ({})",
            human_size(size)
        ));
    }

    let mut file = File::open(&target).map_err(|e| format!("Failed to open file: {e}"))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    let mut hashed = 0u64;
    loop {
        let n = file
            .read(&mut buf)
            .map_err(|e| format!("Read error while hashing: {e}"))?;
        if n == 0 {
            break;
        }
        hashed = hashed.saturating_add(n as u64);
        if hashed > MAX_HASH_BYTES {
            return Err("File grew beyond 2 GiB hash limit during read".to_string());
        }
        hasher.update(&buf[..n]);
    }
    let digest = hasher.finalize_hex();

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_str("path", &display_path(&target));
    o.kv_str("sha256", &digest);
    o.kv_u64("size", hashed);
    o.kv_str("humanSize", &human_size(hashed));
    o.obj_end();
    Ok(o.finish())
}

pub fn dir_size(raw_path: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let canonical = fs::canonicalize(&target).unwrap_or_else(|_| target.clone());
    let root_meta = fs::metadata(&canonical)
        .map_err(|_| format!("Directory not found: {}", canonical.display()))?;
    if !root_meta.is_dir() {
        return Err(format!("Not a directory: {}", canonical.display()));
    }

    let mut seen_dirs: HashSet<(u64, u64)> = HashSet::new();
    seen_dirs.insert((root_meta.dev(), root_meta.ino()));

    let mut stack: Vec<PathBuf> = vec![canonical];
    let mut total_bytes = 0u64;
    let mut file_count = 0u64;
    let mut dir_count = 0u64;
    let mut visited = 0usize;
    let mut capped = false;

    'walk: while let Some(dir) = stack.pop() {
        let Ok(rd) = fs::read_dir(&dir) else {
            continue;
        };
        for item in rd.flatten() {
            visited += 1;
            if visited > MAX_DIR_ENTRIES {
                capped = true;
                break 'walk;
            }
            let full = item.path();
            let Ok(lmeta) = fs::symlink_metadata(&full) else {
                continue;
            };
            if lmeta.file_type().is_symlink() {
                continue;
            }
            if lmeta.is_dir() {
                let key = (lmeta.dev(), lmeta.ino());
                if seen_dirs.insert(key) {
                    dir_count += 1;
                    stack.push(full);
                }
            } else {
                file_count += 1;
                total_bytes = total_bytes.saturating_add(lmeta.len());
            }
        }
    }

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_str("path", &display_path(&target));
    o.kv_u64("bytes", total_bytes);
    o.kv_str("humanSize", &human_size(total_bytes));
    o.kv_u64("files", file_count);
    o.kv_u64("dirs", dir_count);
    o.kv_bool("capped", capped);
    o.obj_end();
    Ok(o.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn hex_digest(data: &[u8]) -> String {
        let mut h = Sha256::new();
        h.update(data);
        h.finalize_hex()
    }

    #[test]
    fn nist_sha256_vectors() {
        assert_eq!(
            hex_digest(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex_digest(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn hash_and_dir_size_with_symlink_loop() {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let base = std::env::temp_dir().join(format!("aurora_hash_test_{ts}"));
        let sub = base.join("sub");
        fs::create_dir_all(&sub).expect("create test dirs");
        let file_a = base.join("hello.bin");
        let file_b = sub.join("nested.bin");
        fs::write(&file_a, b"abc").expect("write a");
        fs::write(&file_b, b"12345").expect("write b");
        symlink(&base, sub.join("loop")).expect("create loop symlink");

        let file_res = sha256_file(&file_a.to_string_lossy()).expect("sha256_file ok");
        let v = crate::json::parse(&file_res).expect("parse sha256 json");
        assert_eq!(
            v.get_str("sha256"),
            Some("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        );
        assert_eq!(v.get_u64("size"), Some(3));
        assert!(sha256_file(&base.to_string_lossy()).is_err());

        let dir_res = dir_size(&base.to_string_lossy()).expect("dir_size ok");
        let dv = crate::json::parse(&dir_res).expect("parse dir_size json");
        assert_eq!(dv.get_u64("bytes"), Some(8));
        assert_eq!(dv.get_u64("files"), Some(2));
        assert_eq!(dv.get_u64("dirs"), Some(1));
        assert_eq!(dv.get_bool("capped"), Some(false));

        let _ = fs::remove_dir_all(&base);
    }
}
