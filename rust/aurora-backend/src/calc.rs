use crate::json::JsonOut;

pub struct CalcCard {
    pub title: String,
    pub sub: String,
    pub copy_val: String,
    pub icon: String,
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Num(f64),
    Ident(String),
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Pow,
    Amp,
    Pipe,
    Tilde,
    Shl,
    Shr,
    LParen,
    RParen,
    Comma,
}

fn tokenize(s: &str) -> Result<Vec<Tok>, String> {
    let b = s.as_bytes();
    let mut i = 0usize;
    let mut out = Vec::new();
    while i < b.len() {
        if b[i].is_ascii_whitespace() {
            i += 1;
            continue;
        }
        if b[i].is_ascii_digit() || (b[i] == b'.' && b.get(i + 1).is_some_and(u8::is_ascii_digit)) {
            if b[i] == b'0' && matches!(b.get(i + 1), Some(b'x' | b'X')) {
                i += 2;
                let start = i;
                while i < b.len() && b[i].is_ascii_hexdigit() {
                    i += 1;
                }
                if i == start {
                    return Err("Invalid hex literal".to_string());
                }
                let val = i64::from_str_radix(&s[start..i], 16).map_err(|_| "Hex overflow")?;
                out.push(Tok::Num(val as f64));
                continue;
            }
            if b[i] == b'0' && matches!(b.get(i + 1), Some(b'b' | b'B')) {
                i += 2;
                let start = i;
                while i < b.len() && matches!(b[i], b'0' | b'1') {
                    i += 1;
                }
                if i == start {
                    return Err("Invalid binary literal".to_string());
                }
                let val = i64::from_str_radix(&s[start..i], 2).map_err(|_| "Binary overflow")?;
                out.push(Tok::Num(val as f64));
                continue;
            }
            if b[i] == b'0' && matches!(b.get(i + 1), Some(b'o' | b'O')) {
                i += 2;
                let start = i;
                while i < b.len() && matches!(b[i], b'0'..=b'7') {
                    i += 1;
                }
                if i == start {
                    return Err("Invalid octal literal".to_string());
                }
                let val = i64::from_str_radix(&s[start..i], 8).map_err(|_| "Octal overflow")?;
                out.push(Tok::Num(val as f64));
                continue;
            }
            let start = i;
            let mut saw_dot = false;
            while i < b.len() {
                if b[i].is_ascii_digit() {
                    i += 1;
                } else if b[i] == b'.' && !saw_dot {
                    saw_dot = true;
                    i += 1;
                } else {
                    break;
                }
            }
            let val: f64 = s[start..i].parse().map_err(|_| "Invalid number")?;
            out.push(Tok::Num(val));
            continue;
        }
        if b[i].is_ascii_alphabetic() || b[i] == b'_' {
            let start = i;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                i += 1;
            }
            out.push(Tok::Ident(s[start..i].to_ascii_lowercase()));
            continue;
        }
        match b[i] {
            b'+' => {
                out.push(Tok::Plus);
                i += 1;
            }
            b'-' => {
                out.push(Tok::Minus);
                i += 1;
            }
            b'*' => {
                if b.get(i + 1) == Some(&b'*') {
                    out.push(Tok::Pow);
                    i += 2;
                } else {
                    out.push(Tok::Star);
                    i += 1;
                }
            }
            b'/' => {
                out.push(Tok::Slash);
                i += 1;
            }
            b'%' => {
                out.push(Tok::Percent);
                i += 1;
            }
            b'^' => {
                out.push(Tok::Pow);
                i += 1;
            }
            b'&' => {
                out.push(Tok::Amp);
                i += 1;
            }
            b'|' => {
                out.push(Tok::Pipe);
                i += 1;
            }
            b'~' => {
                out.push(Tok::Tilde);
                i += 1;
            }
            b'<' if b.get(i + 1) == Some(&b'<') => {
                out.push(Tok::Shl);
                i += 2;
            }
            b'>' if b.get(i + 1) == Some(&b'>') => {
                out.push(Tok::Shr);
                i += 2;
            }
            b'(' => {
                out.push(Tok::LParen);
                i += 1;
            }
            b')' => {
                out.push(Tok::RParen);
                i += 1;
            }
            b',' => {
                out.push(Tok::Comma);
                i += 1;
            }
            _ => return Err("Unexpected symbol".to_string()),
        }
    }
    Ok(out)
}

struct ExprParser {
    toks: Vec<Tok>,
    pos: usize,
    depth: usize,
}

impl ExprParser {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos)
    }

    fn next(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.pos).cloned()?;
        self.pos += 1;
        Some(t)
    }

    fn eval_bit_or(&mut self) -> Result<f64, String> {
        let mut lhs = self.eval_bit_and()?;
        while self.peek() == Some(&Tok::Pipe) {
            self.next();
            let rhs = self.eval_bit_and()?;
            lhs = ((lhs as i64) | (rhs as i64)) as f64;
        }
        Ok(lhs)
    }

    fn eval_bit_and(&mut self) -> Result<f64, String> {
        let mut lhs = self.eval_shift()?;
        while self.peek() == Some(&Tok::Amp) {
            self.next();
            let rhs = self.eval_shift()?;
            lhs = ((lhs as i64) & (rhs as i64)) as f64;
        }
        Ok(lhs)
    }

    fn eval_shift(&mut self) -> Result<f64, String> {
        let mut lhs = self.eval_add()?;
        loop {
            match self.peek() {
                Some(Tok::Shl) => {
                    self.next();
                    let rhs = (self.eval_add()? as i64).clamp(0, 63) as u32;
                    lhs = ((lhs as i64).wrapping_shl(rhs)) as f64;
                }
                Some(Tok::Shr) => {
                    self.next();
                    let rhs = (self.eval_add()? as i64).clamp(0, 63) as u32;
                    lhs = ((lhs as i64).wrapping_shr(rhs)) as f64;
                }
                _ => break,
            }
        }
        Ok(lhs)
    }

    fn eval_add(&mut self) -> Result<f64, String> {
        let mut lhs = self.eval_mul()?;
        loop {
            match self.peek() {
                Some(Tok::Plus) => {
                    self.next();
                    lhs += self.eval_mul()?;
                }
                Some(Tok::Minus) => {
                    self.next();
                    lhs -= self.eval_mul()?;
                }
                _ => break,
            }
        }
        Ok(lhs)
    }

    fn eval_mul(&mut self) -> Result<f64, String> {
        let mut lhs = self.eval_pow()?;
        loop {
            match self.peek() {
                Some(Tok::Star) => {
                    self.next();
                    lhs *= self.eval_pow()?;
                }
                Some(Tok::Slash) => {
                    self.next();
                    let rhs = self.eval_pow()?;
                    lhs /= rhs;
                }
                Some(Tok::Percent) => {
                    self.next();
                    let rhs = self.eval_pow()?;
                    lhs %= rhs;
                }
                _ => break,
            }
        }
        Ok(lhs)
    }

    fn eval_pow(&mut self) -> Result<f64, String> {
        let base = self.eval_unary()?;
        if self.peek() == Some(&Tok::Pow) {
            self.next();
            let exp = self.eval_pow()?;
            Ok(base.powf(exp))
        } else {
            Ok(base)
        }
    }

    fn eval_unary(&mut self) -> Result<f64, String> {
        if self.depth > 64 {
            return Err("Expression too deeply nested".to_string());
        }
        self.depth += 1;
        let res = match self.peek() {
            Some(Tok::Plus) => {
                self.next();
                self.eval_unary()
            }
            Some(Tok::Minus) => {
                self.next();
                self.eval_unary().map(|v| -v)
            }
            Some(Tok::Tilde) => {
                self.next();
                self.eval_unary().map(|v| (!(v as i64)) as f64)
            }
            _ => self.eval_primary(),
        };
        self.depth -= 1;
        res
    }

    fn eval_primary(&mut self) -> Result<f64, String> {
        match self.next() {
            Some(Tok::Num(n)) => Ok(n),
            Some(Tok::LParen) => {
                let v = self.eval_bit_or()?;
                if self.next() != Some(Tok::RParen) {
                    return Err("Missing ')'".to_string());
                }
                Ok(v)
            }
            Some(Tok::Ident(name)) => {
                if self.peek() == Some(&Tok::LParen) {
                    self.next();
                    let mut args = Vec::new();
                    if self.peek() != Some(&Tok::RParen) {
                        loop {
                            args.push(self.eval_bit_or()?);
                            match self.peek() {
                                Some(Tok::Comma) => {
                                    self.next();
                                }
                                Some(Tok::RParen) => break,
                                _ => return Err("Expected ',' or ')'".to_string()),
                            }
                        }
                    }
                    self.next();
                    apply_fn(&name, &args)
                } else {
                    match name.as_str() {
                        "pi" => Ok(std::f64::consts::PI),
                        "e" => Ok(std::f64::consts::E),
                        _ => Err(format!("Unknown identifier '{name}'")),
                    }
                }
            }
            _ => Err("Unexpected token".to_string()),
        }
    }
}

fn apply_fn(name: &str, args: &[f64]) -> Result<f64, String> {
    match (name, args) {
        ("sqrt", [a]) => Ok(a.sqrt()),
        ("cbrt", [a]) => Ok(a.cbrt()),
        ("sin", [a]) => Ok(a.sin()),
        ("cos", [a]) => Ok(a.cos()),
        ("tan", [a]) => Ok(a.tan()),
        ("abs", [a]) => Ok(a.abs()),
        ("round", [a]) => Ok(a.round()),
        ("floor", [a]) => Ok(a.floor()),
        ("ceil", [a]) => Ok(a.ceil()),
        ("log", [a]) => Ok(a.ln()),
        ("log10", [a]) => Ok(a.log10()),
        ("exp", [a]) => Ok(a.exp()),
        ("pow", [a, b]) => Ok(a.powf(*b)),
        ("min", xs) if !xs.is_empty() => Ok(xs.iter().copied().fold(f64::INFINITY, f64::min)),
        ("max", xs) if !xs.is_empty() => Ok(xs.iter().copied().fold(f64::NEG_INFINITY, f64::max)),
        _ => Err(format!("Unknown function '{name}'")),
    }
}

fn eval_math(raw: &str) -> Option<f64> {
    let toks = tokenize(raw).ok()?;
    if toks.is_empty() {
        return None;
    }
    let mut p = ExprParser {
        toks,
        pos: 0,
        depth: 0,
    };
    let val = p.eval_bit_or().ok()?;
    if p.pos != p.toks.len() || !val.is_finite() {
        return None;
    }
    Some(val)
}

fn format_num(val: f64) -> String {
    if (val - val.round()).abs() < 1e-11 && val.abs() < 1e15 {
        return format!("{}", val.round() as i64);
    }
    let s = format!("{val:.6}");
    let trimmed = s.trim_end_matches('0').trim_end_matches('.');
    trimmed.to_string()
}

fn distance_factor(u: &str) -> Option<(f64, &'static str)> {
    match u {
        "mm" => Some((0.001, "mm")),
        "cm" => Some((0.01, "cm")),
        "m" | "meter" | "meters" => Some((1.0, "m")),
        "km" => Some((1000.0, "km")),
        "in" | "inch" | "inches" => Some((0.0254, "in")),
        "ft" | "foot" | "feet" => Some((0.3048, "ft")),
        "yd" | "yard" | "yards" => Some((0.9144, "yd")),
        "mi" | "mile" | "miles" => Some((1609.344, "mi")),
        _ => None,
    }
}

fn mass_factor(u: &str) -> Option<(f64, &'static str)> {
    match u {
        "mg" => Some((0.001, "mg")),
        "g" => Some((1.0, "g")),
        "kg" => Some((1000.0, "kg")),
        "oz" => Some((28.349523125, "oz")),
        "lb" | "lbs" => Some((453.59237, "lb")),
        _ => None,
    }
}

fn data_factor(u: &str) -> Option<(f64, &'static str)> {
    match u {
        "b" | "byte" | "bytes" => Some((1.0, "B")),
        "kb" => Some((1_000.0, "KB")),
        "mb" => Some((1_000_000.0, "MB")),
        "gb" => Some((1_000_000_000.0, "GB")),
        "tb" => Some((1_000_000_000_000.0, "TB")),
        "kib" => Some((1024.0, "KiB")),
        "mib" => Some((1024.0 * 1024.0, "MiB")),
        "gib" => Some((1024.0 * 1024.0 * 1024.0, "GiB")),
        "tib" => Some((1024.0 * 1024.0 * 1024.0 * 1024.0, "TiB")),
        _ => None,
    }
}

fn time_factor(u: &str) -> Option<(f64, &'static str)> {
    match u {
        "ms" => Some((0.001, "ms")),
        "s" | "sec" | "secs" => Some((1.0, "s")),
        "min" | "mins" => Some((60.0, "min")),
        "h" | "hr" | "hrs" | "hour" | "hours" => Some((3600.0, "h")),
        "d" | "day" | "days" => Some((86400.0, "d")),
        _ => None,
    }
}

fn temp_unit(u: &str) -> Option<&'static str> {
    match u {
        "c" | "celsius" => Some("C"),
        "f" | "fahrenheit" => Some("F"),
        "k" | "kelvin" => Some("K"),
        _ => None,
    }
}

fn try_unit_conversion(s: &str) -> Option<Vec<CalcCard>> {
    let low = s.trim().to_ascii_lowercase();
    let (lhs_raw, to_unit_raw) = if let Some((a, b)) = low.rsplit_once(" to ") {
        (a.trim(), b.trim())
    } else if let Some((a, b)) = low.rsplit_once(" in ") {
        (a.trim(), b.trim())
    } else {
        return None;
    };
    if to_unit_raw.is_empty() || !to_unit_raw.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }

    let mut split_idx = lhs_raw.len();
    for (idx, ch) in lhs_raw.char_indices().rev() {
        if !ch.is_ascii_alphabetic() {
            split_idx = idx + ch.len_utf8();
            break;
        }
        if idx == 0 {
            return None;
        }
    }
    let val_expr = lhs_raw[..split_idx].trim();
    let from_unit_raw = lhs_raw[split_idx..].trim();
    if from_unit_raw.is_empty() {
        return None;
    }
    let val = eval_math(val_expr)?;

    if let (Some(f), Some(t)) = (temp_unit(from_unit_raw), temp_unit(to_unit_raw)) {
        let c = match f {
            "C" => val,
            "F" => (val - 32.0) * 5.0 / 9.0,
            "K" => val - 273.15,
            _ => return None,
        };
        let res = match t {
            "C" => c,
            "F" => c * 9.0 / 5.0 + 32.0,
            "K" => c + 273.15,
            _ => return None,
        };
        let label = format!("{} °{t}", format_num(res));
        return Some(vec![CalcCard {
            title: label.clone(),
            sub: format!("{} °{f} -> °{t} · Enter to copy", format_num(val)),
            copy_val: label,
            icon: "󰔏".to_string(),
        }]);
    }

    let pairs = [
        distance_factor(from_unit_raw).zip(distance_factor(to_unit_raw)),
        mass_factor(from_unit_raw).zip(mass_factor(to_unit_raw)),
        data_factor(from_unit_raw).zip(data_factor(to_unit_raw)),
        time_factor(from_unit_raw).zip(time_factor(to_unit_raw)),
    ];
    if let Some(((fk, fnm), (tk, tnm))) = pairs.into_iter().flatten().next() {
        let out_val = val * fk / tk;
        let label = format!("{} {tnm}", format_num(out_val));
        return Some(vec![CalcCard {
            title: label.clone(),
            sub: format!("{} {fnm} -> {tnm} · Enter to copy", format_num(val)),
            copy_val: label,
            icon: "󰪚".to_string(),
        }]);
    }

    None
}

fn try_color_inspect(s: &str) -> Option<Vec<CalcCard>> {
    let trimmed = s.trim();
    let (r, g, b) = if let Some(hex) = trimmed.strip_prefix('#') {
        if hex.len() == 6 && hex.bytes().all(|c| c.is_ascii_hexdigit()) {
            let rv = u8::from_str_radix(&hex[0..2], 16).ok()?;
            let gv = u8::from_str_radix(&hex[2..4], 16).ok()?;
            let bv = u8::from_str_radix(&hex[4..6], 16).ok()?;
            (rv, gv, bv)
        } else if hex.len() == 3 && hex.bytes().all(|c| c.is_ascii_hexdigit()) {
            let rv = u8::from_str_radix(&hex[0..1], 16).ok()? * 17;
            let gv = u8::from_str_radix(&hex[1..2], 16).ok()? * 17;
            let bv = u8::from_str_radix(&hex[2..3], 16).ok()? * 17;
            (rv, gv, bv)
        } else {
            return None;
        }
    } else {
        let inner = trimmed
            .to_ascii_lowercase()
            .strip_prefix("rgb(")
            .and_then(|x| x.strip_suffix(')'))?
            .to_string();
        let parts: Vec<&str> = inner.split(',').map(str::trim).collect();
        if parts.len() != 3 {
            return None;
        }
        (
            parts[0].parse::<u8>().ok()?,
            parts[1].parse::<u8>().ok()?,
            parts[2].parse::<u8>().ok()?,
        )
    };

    let hex_str = format!("#{r:02x}{g:02x}{b:02x}");
    let rgb_str = format!("rgb({r}, {g}, {b})");
    let rf = (r as f64) / 255.0;
    let gf = (g as f64) / 255.0;
    let bf = (b as f64) / 255.0;
    let max = rf.max(gf).max(bf);
    let min = rf.min(gf).min(bf);
    let l = (max + min) / 2.0;
    let d = max - min;
    let (h, sat) = if d == 0.0 {
        (0.0, 0.0)
    } else {
        let sat = if l > 0.5 {
            d / (2.0 - max - min)
        } else {
            d / (max + min)
        };
        let mut hue = if max == rf {
            (gf - bf) / d + if gf < bf { 6.0 } else { 0.0 }
        } else if max == gf {
            (bf - rf) / d + 2.0
        } else {
            (rf - gf) / d + 4.0
        };
        hue /= 6.0;
        (hue * 360.0, sat * 100.0)
    };
    let hsl_str = format!(
        "hsl({}, {}%, {}%)",
        h.round() as u32,
        sat.round() as u32,
        (l * 100.0).round() as u32
    );
    let rel_lum = 0.2126 * rf + 0.7152 * gf + 0.0722 * bf;

    Some(vec![
        CalcCard {
            title: hex_str.clone(),
            sub: format!("Color Hex (Lum {:.0}%) · Enter to copy", rel_lum * 100.0),
            copy_val: hex_str,
            icon: "󰏘".to_string(),
        },
        CalcCard {
            title: rgb_str.clone(),
            sub: "RGB · Enter to copy".to_string(),
            copy_val: rgb_str,
            icon: "󰏘".to_string(),
        },
        CalcCard {
            title: hsl_str.clone(),
            sub: "HSL · Enter to copy".to_string(),
            copy_val: hsl_str,
            icon: "󰏘".to_string(),
        },
    ])
}

pub fn evaluate(raw: &str) -> Vec<CalcCard> {
    let s = raw.trim();
    if s.is_empty() || s.len() > 160 {
        return Vec::new();
    }
    if let Some(cards) = try_color_inspect(s) {
        return cards;
    }
    if let Some(cards) = try_unit_conversion(s) {
        return cards;
    }
    let Some(val) = eval_math(s) else {
        return Vec::new();
    };
    let rounded = format_num(val);
    let mut cards = vec![CalcCard {
        title: rounded.clone(),
        sub: "Result · Enter to copy".to_string(),
        copy_val: rounded,
        icon: "󰪚".to_string(),
    }];
    if (val - val.round()).abs() < 1e-9 && val.abs() <= (i32::MAX as f64) {
        let iv = val.round() as i64;
        let hex_str = if iv < 0 {
            format!("-0x{:X}", -iv)
        } else {
            format!("0x{:X}", iv)
        };
        cards.push(CalcCard {
            title: hex_str.clone(),
            sub: "Hexadecimal".to_string(),
            copy_val: hex_str,
            icon: "󰅪".to_string(),
        });
        let bin_str = format!("0b{:b}", (iv as i32) as u32);
        cards.push(CalcCard {
            title: bin_str.clone(),
            sub: "Binary (32-bit)".to_string(),
            copy_val: bin_str,
            icon: "󰌋".to_string(),
        });
    }
    cards
}

pub fn cmd_calc(args: &[String]) {
    let query = args.join(" ");
    let cards = evaluate(&query);
    let mut o = JsonOut::with_capacity(256);
    o.obj_start();
    o.kv_bool("ok", !cards.is_empty());
    o.key("cards");
    o.arr_start();
    for c in cards {
        o.obj_start();
        o.kv_str("title", &c.title);
        o.kv_str("sub", &c.sub);
        o.kv_str("copyVal", &c.copy_val);
        o.kv_str("icon", &c.icon);
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn math_bitwise_units_and_colors() {
        assert_eq!(evaluate("2 + 3 * 4")[0].title, "14");
        assert_eq!(evaluate("sqrt(144) + 2^8")[0].title, "268");
        assert_eq!(evaluate("0xff & 0x0f")[0].title, "15");

        assert_eq!(evaluate("100 km to mi")[0].title, "62.137119 mi");
        assert_eq!(evaluate("212 f to c")[0].title, "100 °C");
        assert_eq!(evaluate("2048 mib to gib")[0].title, "2 GiB");

        let color_cards = evaluate("#cba6f7");
        assert_eq!(color_cards.len(), 3);
        assert_eq!(color_cards[1].title, "rgb(203, 166, 247)");
    }
}
