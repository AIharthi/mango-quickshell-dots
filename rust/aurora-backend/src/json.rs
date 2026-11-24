use std::fmt::Write as _;

#[derive(Debug, Clone, PartialEq)]
pub enum JsonVal {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<JsonVal>),
    Obj(Vec<(String, JsonVal)>),
}

impl JsonVal {
    pub fn get(&self, key: &str) -> Option<&JsonVal> {
        match self {
            JsonVal::Obj(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn get_str(&self, key: &str) -> Option<&str> {
        match self.get(key) {
            Some(JsonVal::Str(s)) => Some(s.as_str()),
            _ => None,
        }
    }

    pub fn get_bool(&self, key: &str) -> Option<bool> {
        match self.get(key) {
            Some(JsonVal::Bool(b)) => Some(*b),
            _ => None,
        }
    }

    pub fn get_u64(&self, key: &str) -> Option<u64> {
        match self.get(key) {
            Some(JsonVal::Num(n)) if n.is_finite() && *n >= 0.0 => Some(*n as u64),
            _ => None,
        }
    }

    pub fn get_i64(&self, key: &str) -> Option<i64> {
        match self.get(key) {
            Some(JsonVal::Num(n)) if n.is_finite() => Some(*n as i64),
            _ => None,
        }
    }

    pub fn get_f64(&self, key: &str) -> Option<f64> {
        match self.get(key) {
            Some(JsonVal::Num(n)) if n.is_finite() => Some(*n),
            _ => None,
        }
    }

    pub fn as_u64(&self) -> Option<u64> {
        match self {
            JsonVal::Num(n) if n.is_finite() && *n >= 0.0 => Some(*n as u64),
            _ => None,
        }
    }

    pub fn as_arr(&self) -> Option<&[JsonVal]> {
        match self {
            JsonVal::Arr(a) => Some(a.as_slice()),
            _ => None,
        }
    }
}

pub fn parse(input: &str) -> Result<JsonVal, String> {
    let mut p = Parser {
        bytes: input.as_bytes(),
        pos: 0,
    };
    p.skip_ws();
    let val = p.parse_val()?;
    p.skip_ws();
    if p.pos != p.bytes.len() {
        return Err(format!("Trailing characters at byte {}", p.pos));
    }
    Ok(val)
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() {
            match self.bytes[self.pos] {
                b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1,
                _ => break,
            }
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<u8> {
        let b = self.bytes.get(self.pos).copied()?;
        self.pos += 1;
        Some(b)
    }

    fn parse_val(&mut self) -> Result<JsonVal, String> {
        self.skip_ws();
        match self.peek() {
            Some(b'n') => self.parse_lit(b"null", JsonVal::Null),
            Some(b't') => self.parse_lit(b"true", JsonVal::Bool(true)),
            Some(b'f') => self.parse_lit(b"false", JsonVal::Bool(false)),
            Some(b'"') => self.parse_string().map(JsonVal::Str),
            Some(b'[') => self.parse_array(),
            Some(b'{') => self.parse_object(),
            Some(b'-' | b'0'..=b'9') => self.parse_number(),
            Some(b) => Err(format!("Unexpected byte '{}' at {}", b as char, self.pos)),
            None => Err("Unexpected end of JSON".to_string()),
        }
    }

    fn parse_lit(&mut self, lit: &[u8], val: JsonVal) -> Result<JsonVal, String> {
        if self.bytes[self.pos..].starts_with(lit) {
            self.pos += lit.len();
            Ok(val)
        } else {
            Err(format!("Invalid literal at {}", self.pos))
        }
    }

    fn parse_string(&mut self) -> Result<String, String> {
        if self.next() != Some(b'"') {
            return Err("Expected opening quote".to_string());
        }
        let mut out = String::new();
        while let Some(b) = self.next() {
            match b {
                b'"' => return Ok(out),
                b'\\' => {
                    let esc = self.next().ok_or("Unterminated escape")?;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let code = self.parse_hex4()?;
                            if (0xD800..=0xDBFF).contains(&code) {
                                if self.peek() == Some(b'\\')
                                    && self.bytes.get(self.pos + 1) == Some(&b'u')
                                {
                                    self.pos += 2;
                                    let low = self.parse_hex4()?;
                                    if (0xDC00..=0xDFFF).contains(&low) {
                                        let combined = 0x10000
                                            + (((code as u32 - 0xD800) << 10)
                                                | (low as u32 - 0xDC00));
                                        let ch = char::from_u32(combined)
                                            .ok_or("Invalid surrogate pair")?;
                                        out.push(ch);
                                        continue;
                                    }
                                }
                                return Err("Lone UTF-16 high surrogate".to_string());
                            }
                            let ch = char::from_u32(code as u32).ok_or("Invalid unicode escape")?;
                            out.push(ch);
                        }
                        _ => return Err(format!("Unknown escape '\\{}'", esc as char)),
                    }
                }
                _ => {
                    let start = self.pos - 1;
                    if b < 0x80 {
                        out.push(b as char);
                    } else {
                        let width = if b & 0xE0 == 0xC0 {
                            2
                        } else if b & 0xF0 == 0xE0 {
                            3
                        } else if b & 0xF8 == 0xF0 {
                            4
                        } else {
                            return Err("Invalid UTF-8 byte in JSON string".to_string());
                        };
                        let end = start + width;
                        if end > self.bytes.len() {
                            return Err("Truncated UTF-8 sequence".to_string());
                        }
                        let s = std::str::from_utf8(&self.bytes[start..end])
                            .map_err(|_| "Invalid UTF-8 in JSON string".to_string())?;
                        out.push_str(s);
                        self.pos = end;
                    }
                }
            }
        }
        Err("Unterminated string literal".to_string())
    }

    fn parse_hex4(&mut self) -> Result<u16, String> {
        let mut val = 0u16;
        for _ in 0..4 {
            let b = self.next().ok_or("Truncated \\u escape")?;
            let nib = match b {
                b'0'..=b'9' => (b - b'0') as u16,
                b'a'..=b'f' => (b - b'a' + 10) as u16,
                b'A'..=b'F' => (b - b'A' + 10) as u16,
                _ => return Err("Invalid hex digit in \\u escape".to_string()),
            };
            val = (val << 4) | nib;
        }
        Ok(val)
    }

    fn parse_number(&mut self) -> Result<JsonVal, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.pos += 1;
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        let s = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "Invalid number".to_string())?;
        let n: f64 = s.parse().map_err(|_| format!("Invalid number '{s}'"))?;
        Ok(JsonVal::Num(n))
    }

    fn parse_array(&mut self) -> Result<JsonVal, String> {
        self.next();
        let mut arr = Vec::new();
        loop {
            self.skip_ws();
            if self.peek() == Some(b']') {
                self.next();
                return Ok(JsonVal::Arr(arr));
            }
            arr.push(self.parse_val()?);
            self.skip_ws();
            match self.peek() {
                Some(b',') => {
                    self.next();
                }
                Some(b']') => {
                    self.next();
                    return Ok(JsonVal::Arr(arr));
                }
                _ => return Err("Expected ',' or ']' in array".to_string()),
            }
        }
    }

    fn parse_object(&mut self) -> Result<JsonVal, String> {
        self.next();
        let mut entries = Vec::new();
        loop {
            self.skip_ws();
            if self.peek() == Some(b'}') {
                self.next();
                return Ok(JsonVal::Obj(entries));
            }
            let k = self.parse_string()?;
            self.skip_ws();
            if self.next() != Some(b':') {
                return Err("Expected ':' after object key".to_string());
            }
            let v = self.parse_val()?;
            entries.push((k, v));
            self.skip_ws();
            match self.peek() {
                Some(b',') => {
                    self.next();
                }
                Some(b'}') => {
                    self.next();
                    return Ok(JsonVal::Obj(entries));
                }
                _ => return Err("Expected ',' or '}' in object".to_string()),
            }
        }
    }
}

pub fn escape_into(buf: &mut String, s: &str) {
    buf.push('"');
    for ch in s.chars() {
        match ch {
            '"' => buf.push_str("\\\""),
            '\\' => buf.push_str("\\\\"),
            '\u{0008}' => buf.push_str("\\b"),
            '\u{000c}' => buf.push_str("\\f"),
            '\n' => buf.push_str("\\n"),
            '\r' => buf.push_str("\\r"),
            '\t' => buf.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(buf, "\\u{:04x}", c as u32);
            }
            c => buf.push(c),
        }
    }
    buf.push('"');
}

pub struct JsonOut {
    pub buf: String,
    need_comma: Vec<bool>,
}

impl JsonOut {
    pub fn new() -> Self {
        Self {
            buf: String::with_capacity(512),
            need_comma: Vec::new(),
        }
    }

    pub fn with_capacity(cap: usize) -> Self {
        Self {
            buf: String::with_capacity(cap),
            need_comma: Vec::new(),
        }
    }

    fn comma(&mut self) {
        if let Some(last) = self.need_comma.last_mut() {
            if *last {
                self.buf.push(',');
            }
            *last = true;
        }
    }

    pub fn obj_start(&mut self) {
        self.comma();
        self.buf.push('{');
        self.need_comma.push(false);
    }

    pub fn obj_end(&mut self) {
        self.need_comma.pop();
        self.buf.push('}');
    }

    pub fn arr_start(&mut self) {
        self.comma();
        self.buf.push('[');
        self.need_comma.push(false);
    }

    pub fn arr_end(&mut self) {
        self.need_comma.pop();
        self.buf.push(']');
    }

    pub fn key(&mut self, k: &str) {
        self.comma();
        escape_into(&mut self.buf, k);
        self.buf.push(':');
        if let Some(last) = self.need_comma.last_mut() {
            *last = false;
        }
    }

    pub fn kv_str(&mut self, k: &str, v: &str) {
        self.key(k);
        self.str(v);
    }

    pub fn kv_bool(&mut self, k: &str, v: bool) {
        self.key(k);
        self.bool(v);
    }

    pub fn kv_u64(&mut self, k: &str, v: u64) {
        self.key(k);
        self.u64(v);
    }

    pub fn kv_i64(&mut self, k: &str, v: i64) {
        self.key(k);
        self.comma();
        let _ = write!(self.buf, "{v}");
    }

    pub fn kv_f64(&mut self, k: &str, v: f64, decimals: usize) {
        self.key(k);
        self.comma();
        if v.is_finite() {
            let _ = write!(self.buf, "{v:.decimals$}");
        } else {
            self.buf.push('0');
        }
    }

    pub fn str(&mut self, v: &str) {
        self.comma();
        escape_into(&mut self.buf, v);
    }

    pub fn bool(&mut self, v: bool) {
        self.comma();
        self.buf.push_str(if v { "true" } else { "false" });
    }

    pub fn u64(&mut self, v: u64) {
        self.comma();
        let _ = write!(self.buf, "{v}");
    }

    pub fn finish(self) -> String {
        self.buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_roundtrip_and_out() {
        let mut o = JsonOut::new();
        o.obj_start();
        o.kv_str("hello", "a\"b\n");
        o.kv_bool("ok", true);
        o.kv_u64("n", 42);
        o.kv_f64("r", 3.25, 2);
        o.key("arr");
        o.arr_start();
        o.u64(1);
        o.str("x");
        o.bool(false);
        o.arr_end();
        o.obj_end();
        let raw = o.finish();
        let val = parse(&raw).expect("parse ok");
        assert_eq!(val.get_str("hello"), Some("a\"b\n"));
        assert_eq!(val.get_bool("ok"), Some(true));
        assert_eq!(val.get_u64("n"), Some(42));
        assert_eq!(
            val.get("arr").and_then(|v| v.as_arr()).map(|a| a.len()),
            Some(3)
        );
    }
}
