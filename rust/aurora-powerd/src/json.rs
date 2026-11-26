use std::fmt::Write as _;

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
        self.comma();
        self.buf.push_str(if v { "true" } else { "false" });
    }

    pub fn kv_u64(&mut self, k: &str, v: u64) {
        self.key(k);
        self.comma();
        let _ = write!(self.buf, "{v}");
    }

    pub fn str(&mut self, v: &str) {
        self.comma();
        escape_into(&mut self.buf, v);
    }

    pub fn finish(self) -> String {
        self.buf
    }
}
