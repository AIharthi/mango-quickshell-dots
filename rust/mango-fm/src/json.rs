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

    pub fn get_arr(&self, key: &str) -> Option<&[JsonVal]> {
        match self.get(key) {
            Some(JsonVal::Arr(a)) => Some(a.as_slice()),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            JsonVal::Str(s) => Some(s.as_str()),
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
                        other => return Err(format!("Invalid escape \\{}", other as char)),
                    }
                }
                c if c < 0x20 => return Err("Control char inside JSON string".to_string()),
                first => {
                    self.pos -= 1;
                    let rest = std::str::from_utf8(&self.bytes[self.pos..])
                        .map_err(|_| "Invalid UTF-8 in string")?;
                    let ch = rest.chars().next().ok_or("Unexpected EOF")?;
                    if first == b'\\' || first == b'"' {
                        unreachable!();
                    }
                    out.push(ch);
                    self.pos += ch.len_utf8();
                }
            }
        }
        Err("Unterminated JSON string".to_string())
    }

    fn parse_hex4(&mut self) -> Result<u16, String> {
        if self.pos + 4 > self.bytes.len() {
            return Err("Truncated \\uXXXX escape".to_string());
        }
        let s = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
            .map_err(|_| "Invalid UTF-8 in \\u escape")?;
        let v = u16::from_str_radix(s, 16).map_err(|_| "Invalid hex in \\u escape")?;
        self.pos += 4;
        Ok(v)
    }

    fn parse_number(&mut self) -> Result<JsonVal, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        if self.peek() == Some(b'0') {
            self.pos += 1;
        } else if matches!(self.peek(), Some(b'1'..=b'9')) {
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        } else {
            return Err(format!("Invalid number at {}", start));
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("Invalid fraction at {}", self.pos));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("Invalid exponent at {}", self.pos));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        let slice = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "Invalid number UTF-8")?;
        let n: f64 = slice
            .parse()
            .map_err(|_| format!("Failed to parse number '{}'", slice))?;
        Ok(JsonVal::Num(n))
    }

    fn parse_array(&mut self) -> Result<JsonVal, String> {
        self.pos += 1;
        let mut items = Vec::new();
        self.skip_ws();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JsonVal::Arr(items));
        }
        loop {
            items.push(self.parse_val()?);
            self.skip_ws();
            match self.next() {
                Some(b',') => continue,
                Some(b']') => return Ok(JsonVal::Arr(items)),
                _ => return Err(format!("Expected ',' or ']' at {}", self.pos)),
            }
        }
    }

    fn parse_object(&mut self) -> Result<JsonVal, String> {
        self.pos += 1;
        let mut entries = Vec::new();
        self.skip_ws();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonVal::Obj(entries));
        }
        loop {
            self.skip_ws();
            let key = self.parse_string()?;
            self.skip_ws();
            if self.next() != Some(b':') {
                return Err(format!("Expected ':' after key at {}", self.pos));
            }
            let val = self.parse_val()?;
            entries.push((key, val));
            self.skip_ws();
            match self.next() {
                Some(b',') => continue,
                Some(b'}') => return Ok(JsonVal::Obj(entries)),
                _ => return Err(format!("Expected ',' or '}}' at {}", self.pos)),
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
        self.i64(v);
    }

    pub fn kv_raw(&mut self, k: &str, raw_json: &str) {
        self.key(k);
        self.raw(raw_json);
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

    pub fn i64(&mut self, v: i64) {
        self.comma();
        let _ = write!(self.buf, "{v}");
    }

    pub fn raw(&mut self, raw_json: &str) {
        self.comma();
        self.buf.push_str(raw_json);
    }

    pub fn finish(self) -> String {
        self.buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_roundtrip() {
        let src = r#"{"id":42,"op":"copy","hidden":false,"ratio":0.75,"paths":["a\"b","c\nd","\u0041"]}"#;
        let v = parse(src).expect("parse ok");
        assert_eq!(v.get_u64("id"), Some(42));
        assert_eq!(v.get_str("op"), Some("copy"));
        assert_eq!(v.get_bool("hidden"), Some(false));
        let arr = v.get_arr("paths").expect("arr");
        assert_eq!(arr[0].as_str(), Some("a\"b"));
        assert_eq!(arr[1].as_str(), Some("c\nd"));
        assert_eq!(arr[2].as_str(), Some("A"));
    }

    #[test]
    fn encode_escaped() {
        let mut o = JsonOut::new();
        o.obj_start();
        o.kv_str("msg", "hello\n\"rust\"\t\\end\x07");
        o.kv_u64("count", 3);
        o.kv_bool("ok", true);
        o.obj_end();
        let s = o.finish();
        let parsed = parse(&s).expect("valid encoded json");
        assert_eq!(parsed.get_str("msg"), Some("hello\n\"rust\"\t\\end\x07"));
        assert_eq!(parsed.get_u64("count"), Some(3));
        assert_eq!(parsed.get_bool("ok"), Some(true));
    }
}
