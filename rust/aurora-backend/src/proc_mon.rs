use std::cmp::Ordering;
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::thread;
use std::time::Duration;

use crate::json::JsonOut;
use crate::util::{read_i64, read_trimmed};

pub fn cmd_hwmon() {
    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.key("sensors");
    o.arr_start();

    if let Ok(rd) = fs::read_dir("/sys/class/hwmon") {
        let mut hwmons: Vec<_> = rd.flatten().map(|e| e.path()).collect();
        hwmons.sort();
        for hw in hwmons {
            let chip = read_trimmed(&hw.join("name"))
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| {
                    hw.file_name()
                        .map(|n| n.to_string_lossy().into_owned())
                        .unwrap_or_default()
                });
            let Ok(files) = fs::read_dir(&hw) else {
                continue;
            };
            let mut inputs: Vec<_> = files
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.starts_with("temp") && n.ends_with("_input"))
                        .unwrap_or(false)
                })
                .collect();
            inputs.sort();

            for inp in inputs {
                let Some(raw) = read_i64(&inp) else {
                    continue;
                };
                let temp_c = (raw as f64) / 1000.0;
                if !(-20.0..=180.0).contains(&temp_c) {
                    continue;
                }
                let inp_s = inp.to_string_lossy();
                let base = inp_s.strip_suffix("_input").unwrap_or(&inp_s);
                let label = read_trimmed(Path::new(&format!("{base}_label")))
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| {
                        Path::new(base)
                            .file_name()
                            .map(|n| n.to_string_lossy().into_owned())
                            .unwrap_or_default()
                    });
                let crit_c = read_i64(Path::new(&format!("{base}_crit")))
                    .map(|v| (v as f64) / 1000.0)
                    .filter(|c| (30.0..=150.0).contains(c))
                    .unwrap_or(100.0);

                o.obj_start();
                o.kv_str("chip", &chip);
                o.kv_str("label", &label);
                o.kv_f64("tempC", temp_c, 1);
                o.kv_f64("critC", crit_c, 1);
                o.obj_end();
            }
        }
    }

    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
}

fn read_total_jiffies_and_cores() -> (u64, usize) {
    let Ok(txt) = fs::read_to_string("/proc/stat") else {
        return (0, 1);
    };
    let mut total = 0u64;
    let mut cores = 0usize;
    for line in txt.lines() {
        if let Some(rest) = line.strip_prefix("cpu ") {
            total = rest
                .split_whitespace()
                .filter_map(|s| s.parse::<u64>().ok())
                .sum();
        } else if let Some(rest) = line.strip_prefix("cpu") {
            let head = rest.split_whitespace().next().unwrap_or("");
            if !head.is_empty() && head.bytes().all(|b| b.is_ascii_digit()) {
                cores += 1;
            }
        } else {
            break;
        }
    }
    (total, cores.max(1))
}

fn parse_proc_stat(line: &str) -> Option<(String, u64)> {
    let lparen = line.find('(')?;
    let rparen = line.rfind(')')?;
    if rparen <= lparen {
        return None;
    }
    let name = line[lparen + 1..rparen].to_string();
    let tail = line.get(rparen + 2..)?;
    let fields: Vec<&str> = tail.split_whitespace().collect();
    if fields.len() < 13 {
        return None;
    }
    let utime = fields[11].parse::<u64>().ok()?;
    let stime = fields[12].parse::<u64>().ok()?;
    Some((name, utime.saturating_add(stime)))
}

fn read_vm_rss_mb(pid: u64) -> f64 {
    let Ok(txt) = fs::read_to_string(format!("/proc/{pid}/status")) else {
        return 0.0;
    };
    for line in txt.lines() {
        if let Some(rest) = line.strip_prefix("VmRSS:") {
            let kb = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(0);
            return (kb as f64) / 1024.0;
        }
    }
    0.0
}

fn read_proc_jiffies() -> HashMap<u64, (String, u64)> {
    let mut map = HashMap::new();
    let Ok(rd) = fs::read_dir("/proc") else {
        return map;
    };
    for ent in rd.flatten() {
        let fname = ent.file_name();
        let s = fname.to_string_lossy();
        let Ok(pid) = s.parse::<u64>() else {
            continue;
        };
        if pid <= 1 {
            continue;
        }
        let Ok(stat) = fs::read_to_string(ent.path().join("stat")) else {
            continue;
        };
        if let Some((comm, ticks)) = parse_proc_stat(&stat) {
            map.insert(pid, (comm, ticks));
        }
    }
    map
}

struct ProcRow {
    pid: u64,
    cpu_pct: f64,
    mem_mb: f64,
    name: String,
}

pub fn cmd_processes(args: &[String]) {
    let sort_mode = args
        .first()
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| matches!(s.as_str(), "cpu" | "mem" | "pid"))
        .unwrap_or_else(|| "cpu".to_string());
    let limit = args
        .get(1)
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(25)
        .clamp(1, 100);

    let (tot_a, cores) = read_total_jiffies_and_cores();
    let snap_a = read_proc_jiffies();
    thread::sleep(Duration::from_millis(100));
    let (tot_b, _) = read_total_jiffies_and_cores();
    let snap_b = read_proc_jiffies();

    let total_delta = tot_b.saturating_sub(tot_a).max(1) as f64;
    let mut rows: Vec<ProcRow> = Vec::with_capacity(snap_b.len());
    for (pid, (name, ticks_b)) in snap_b {
        let prev_ticks = snap_a.get(&pid).map(|(_, t)| *t).unwrap_or(ticks_b);
        let p_delta = ticks_b.saturating_sub(prev_ticks) as f64;
        // Scale by core count so CPU% matches per-core top/ps convention
        let cpu_pct = (p_delta / total_delta) * (cores as f64) * 100.0;
        let mem_mb = read_vm_rss_mb(pid);
        rows.push(ProcRow {
            pid,
            cpu_pct: cpu_pct.clamp(0.0, (cores as f64) * 100.0),
            mem_mb,
            name,
        });
    }

    match sort_mode.as_str() {
        "mem" => rows.sort_by(|a, b| {
            b.mem_mb
                .partial_cmp(&a.mem_mb)
                .unwrap_or(Ordering::Equal)
                .then_with(|| a.pid.cmp(&b.pid))
        }),
        "pid" => rows.sort_by_key(|a| a.pid),
        _ => rows.sort_by(|a, b| {
            b.cpu_pct
                .partial_cmp(&a.cpu_pct)
                .unwrap_or(Ordering::Equal)
                .then_with(|| b.mem_mb.partial_cmp(&a.mem_mb).unwrap_or(Ordering::Equal))
        }),
    }
    rows.truncate(limit);

    let mut o = JsonOut::with_capacity(rows.len() * 64 + 64);
    o.obj_start();
    o.kv_str("sort", &sort_mode);
    o.key("processes");
    o.arr_start();
    for r in rows {
        o.obj_start();
        o.kv_u64("pid", r.pid);
        o.kv_f64("cpuPct", r.cpu_pct, 1);
        o.kv_f64("memMb", r.mem_mb, 1);
        o.kv_str("name", &r.name);
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
    fn parses_comm_with_spaces_and_parens() {
        let sample = "4210 (Web (Content) Helper) S 1200 4210 4210 0 -1 4194560 12 0 1 0 350 45 0 0 20 0 4 0 1000 100 50 184467";
        let (name, ticks) = parse_proc_stat(sample).expect("parse stat");
        assert_eq!(name, "Web (Content) Helper");
        assert_eq!(ticks, 395);
    }
}
