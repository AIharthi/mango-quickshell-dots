use std::fs;
use std::io::{self, BufWriter, Write};
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use crate::json::JsonOut;
use crate::util::{battery_snapshot, format_rate, format_uptime, read_trimmed, read_u64};

#[derive(Clone, Copy, Default)]
struct CpuTimes {
    total: u64,
    idle: u64,
}

#[derive(Clone)]
struct NetTotals {
    rx: u64,
    tx: u64,
    primary_iface: String,
}

struct Sample {
    at: Instant,
    agg_cpu: CpuTimes,
    cores: Vec<CpuTimes>,
    net: NetTotals,
}

#[derive(Default)]
struct CachedDisk {
    percent: u64,
    label: String,
    free_label: String,
    ticks_left: u8,
}

fn parse_cpu_line(parts: &[&str]) -> Option<CpuTimes> {
    if parts.len() < 5 {
        return None;
    }
    let mut vals = [0u64; 10];
    let mut count = 0usize;
    for s in &parts[1..] {
        if count >= vals.len() {
            break;
        }
        vals[count] = s.parse::<u64>().unwrap_or(0);
        count += 1;
    }
    let idle = vals[3].saturating_add(vals[4]);
    let total: u64 = vals[..count].iter().sum();
    Some(CpuTimes { total, idle })
}

fn read_cpu_sample() -> (CpuTimes, Vec<CpuTimes>) {
    let mut agg = CpuTimes::default();
    let mut cores = Vec::new();
    let Ok(txt) = fs::read_to_string("/proc/stat") else {
        return (agg, cores);
    };
    for line in txt.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.is_empty() {
            continue;
        }
        if parts[0] == "cpu" {
            if let Some(c) = parse_cpu_line(&parts) {
                agg = c;
            }
        } else if let Some(suffix) = parts[0].strip_prefix("cpu") {
            if !suffix.is_empty() && suffix.bytes().all(|b| b.is_ascii_digit()) {
                if let Some(c) = parse_cpu_line(&parts) {
                    cores.push(c);
                }
            }
        } else if parts[0] != "cpu" && !parts[0].starts_with("cpu") {
            break;
        }
    }
    (agg, cores)
}

fn read_net_sample() -> NetTotals {
    let mut totals = NetTotals {
        rx: 0,
        tx: 0,
        primary_iface: String::new(),
    };
    let Ok(txt) = fs::read_to_string("/proc/net/dev") else {
        return totals;
    };
    let mut best_score = 0u64;
    for line in txt.lines().skip(2) {
        let Some((raw_if, rest)) = line.split_once(':') else {
            continue;
        };
        let iface = raw_if.trim();
        if iface.is_empty() || iface == "lo" {
            continue;
        }
        let cols: Vec<&str> = rest.split_whitespace().collect();
        if cols.len() < 10 {
            continue;
        }
        let rx = cols[0].parse::<u64>().unwrap_or(0);
        let tx = cols[8].parse::<u64>().unwrap_or(0);
        totals.rx = totals.rx.saturating_add(rx);
        totals.tx = totals.tx.saturating_add(tx);

        let is_up = read_trimmed(&Path::new("/sys/class/net").join(iface).join("operstate"))
            .as_deref()
            == Some("up");
        let traffic = rx.saturating_add(tx);
        let score = if is_up {
            u64::MAX / 2 + traffic
        } else {
            traffic
        };
        if totals.primary_iface.is_empty() || score > best_score {
            best_score = score;
            totals.primary_iface = iface.to_string();
        }
    }
    totals
}

fn take_sample() -> Sample {
    let (agg_cpu, cores) = read_cpu_sample();
    let net = read_net_sample();
    Sample {
        at: Instant::now(),
        agg_cpu,
        cores,
        net,
    }
}

fn read_cpu_freq_ghz() -> f64 {
    let Ok(rd) = fs::read_dir("/sys/devices/system/cpu") else {
        return 0.0;
    };
    let mut sum_khz = 0u64;
    let mut count = 0u64;
    for ent in rd.flatten() {
        let name = ent.file_name();
        let s = name.to_string_lossy();
        if let Some(rest) = s.strip_prefix("cpu") {
            if !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit()) {
                if let Some(khz) = read_u64(&ent.path().join("cpufreq/scaling_cur_freq")) {
                    if khz > 0 {
                        sum_khz = sum_khz.saturating_add(khz);
                        count += 1;
                    }
                }
            }
        }
    }
    if count == 0 {
        return 0.0;
    }
    ((sum_khz as f64) / (count as f64)) / 1_000_000.0
}

fn read_mem_metrics() -> (f64, f64, u64, u64) {
    let Ok(txt) = fs::read_to_string("/proc/meminfo") else {
        return (0.0, 0.0, 0, 0);
    };
    let mut total_kb = 0u64;
    let mut avail_kb = 0u64;
    let mut free_kb = 0u64;
    let mut buffers_kb = 0u64;
    let mut cached_kb = 0u64;
    let mut swap_total_kb = 0u64;
    let mut swap_free_kb = 0u64;

    for line in txt.lines() {
        let mut it = line.split_whitespace();
        let Some(k) = it.next() else { continue };
        let Some(v_s) = it.next() else { continue };
        let Ok(v) = v_s.parse::<u64>() else {
            continue;
        };
        match k {
            "MemTotal:" => total_kb = v,
            "MemAvailable:" => avail_kb = v,
            "MemFree:" => free_kb = v,
            "Buffers:" => buffers_kb = v,
            "Cached:" => cached_kb = v,
            "SwapTotal:" => swap_total_kb = v,
            "SwapFree:" => swap_free_kb = v,
            _ => {}
        }
    }
    if avail_kb == 0 {
        avail_kb = free_kb.saturating_add(buffers_kb).saturating_add(cached_kb);
    }
    let used_kb = total_kb.saturating_sub(avail_kb);
    let mem_pct = if total_kb > 0 {
        (((used_kb as f64) * 100.0) / (total_kb as f64))
            .round()
            .clamp(0.0, 100.0) as u64
    } else {
        0
    };
    let swap_pct = if swap_total_kb > 0 {
        let su = swap_total_kb.saturating_sub(swap_free_kb);
        (((su as f64) * 100.0) / (swap_total_kb as f64))
            .round()
            .clamp(0.0, 100.0) as u64
    } else {
        0
    };
    let used_gb = (used_kb as f64) / (1024.0 * 1024.0);
    let total_gb = (total_kb as f64) / (1024.0 * 1024.0);
    (used_gb, total_gb, mem_pct, swap_pct)
}

fn read_temps() -> (u64, u64) {
    let mut cpu_temp = 0u64;
    let mut gpu_temp = 0u64;
    let mut any_temp = 0u64;

    if let Ok(rd) = fs::read_dir("/sys/class/hwmon") {
        let mut entries: Vec<_> = rd.flatten().map(|e| e.path()).collect();
        entries.sort();
        for hw in entries {
            let chip = read_trimmed(&hw.join("name"))
                .unwrap_or_default()
                .to_ascii_lowercase();
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
                let Some(raw) = read_u64(&inp) else {
                    continue;
                };
                let deg = if raw > 1000 { raw / 1000 } else { raw };
                if !(10..150).contains(&deg) {
                    continue;
                }
                if any_temp == 0 {
                    any_temp = deg;
                }
                if cpu_temp == 0
                    && matches!(
                        chip.as_str(),
                        "k10temp" | "coretemp" | "zenpower" | "acpitz" | "thinkpad" | "dell_smm"
                    )
                {
                    cpu_temp = deg;
                }
                if gpu_temp == 0
                    && matches!(
                        chip.as_str(),
                        "amdgpu" | "nvidia" | "radeon" | "i915" | "xe"
                    )
                {
                    gpu_temp = deg;
                }
            }
        }
    }

    if cpu_temp == 0 {
        if let Ok(rd) = fs::read_dir("/sys/class/thermal") {
            let mut zones: Vec<_> = rd
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.starts_with("thermal_zone"))
                        .unwrap_or(false)
                })
                .collect();
            zones.sort();
            for z in zones {
                if let Some(raw) = read_u64(&z.join("temp")) {
                    let deg = if raw > 1000 { raw / 1000 } else { raw };
                    if (10..150).contains(&deg) {
                        cpu_temp = deg;
                        break;
                    }
                }
            }
        }
    }

    if cpu_temp == 0 {
        cpu_temp = any_temp;
    }
    (cpu_temp, gpu_temp)
}

fn read_uptime_and_load() -> (u64, String, String) {
    let uptime_sec = read_trimmed(Path::new("/proc/uptime"))
        .and_then(|s| s.split_whitespace().next().map(str::to_string))
        .and_then(|f| f.parse::<f64>().ok())
        .map(|f| f.max(0.0) as u64)
        .unwrap_or(0);
    let uptime_label = format_uptime(uptime_sec);
    let load_label = read_trimmed(Path::new("/proc/loadavg"))
        .and_then(|s| s.split_whitespace().next().map(str::to_string))
        .unwrap_or_else(|| "0.00".to_string());
    (uptime_sec, uptime_label, load_label)
}

fn format_compact_bytes(bytes: u64) -> String {
    let gib = (bytes as f64) / (1024.0 * 1024.0 * 1024.0);
    if gib >= 100.0 {
        format!("{gib:.0}G")
    } else if gib >= 1.0 {
        format!("{gib:.1}G")
    } else {
        let mib = (bytes as f64) / (1024.0 * 1024.0);
        format!("{mib:.0}M")
    }
}

fn refresh_disk(cache: &mut CachedDisk) {
    if cache.ticks_left > 0 {
        cache.ticks_left -= 1;
        return;
    }
    cache.ticks_left = 15;
    let Ok(out) = Command::new("df").args(["-P", "/"]).output() else {
        return;
    };
    if !out.status.success() {
        return;
    }
    let txt = String::from_utf8_lossy(&out.stdout);
    let Some(row) = txt.lines().nth(1) else {
        return;
    };
    let cols: Vec<&str> = row.split_whitespace().collect();
    if cols.len() >= 5 {
        let pct_str = cols[4].trim_end_matches('%');
        if let Ok(p) = pct_str.parse::<u64>() {
            cache.percent = p.min(100);
            cache.label = format!("{}%", cache.percent);
        }
        if let Ok(avail_kb) = cols[3].parse::<u64>() {
            cache.free_label = format_compact_bytes(avail_kb.saturating_mul(1024));
        }
    }
}

fn cpu_pct(prev: CpuTimes, cur: CpuTimes) -> u64 {
    let dt = cur.total.saturating_sub(prev.total);
    if dt == 0 {
        return 0;
    }
    let di = cur.idle.saturating_sub(prev.idle);
    let busy = dt.saturating_sub(di);
    (((busy as f64) * 100.0) / (dt as f64))
        .round()
        .clamp(0.0, 100.0) as u64
}

fn build_telemetry_json(prev: &Sample, cur: &Sample, disk: &mut CachedDisk) -> String {
    refresh_disk(disk);
    let dt = cur.at.duration_since(prev.at).as_secs_f64().max(0.05);
    let cpu_percent = cpu_pct(prev.agg_cpu, cur.agg_cpu);
    let core_pcts: Vec<u64> = prev
        .cores
        .iter()
        .zip(cur.cores.iter())
        .map(|(a, b)| cpu_pct(*a, *b))
        .collect();

    let rx_bps = ((cur.net.rx.saturating_sub(prev.net.rx)) as f64 / dt).round() as u64;
    let tx_bps = ((cur.net.tx.saturating_sub(prev.net.tx)) as f64 / dt).round() as u64;
    let net_down = format_rate(rx_bps);
    let net_up = format_rate(tx_bps);

    let freq_ghz = read_cpu_freq_ghz();
    let (mem_used_gb, mem_total_gb, mem_pct, swap_pct) = read_mem_metrics();
    let (cpu_temp_c, gpu_temp_c) = read_temps();
    let (uptime_sec, uptime_label, load_label) = read_uptime_and_load();
    let bat = battery_snapshot();

    let mut o = JsonOut::with_capacity(512);
    o.obj_start();
    o.kv_u64("cpuPercent", cpu_percent);
    o.key("cores");
    o.arr_start();
    for c in core_pcts {
        o.u64(c);
    }
    o.arr_end();
    o.kv_f64("freqGhz", freq_ghz, 2);
    o.kv_f64("memUsedGb", mem_used_gb, 1);
    o.kv_f64("memTotalGb", mem_total_gb, 1);
    o.kv_u64("memPercent", mem_pct);
    o.kv_u64("swapPercent", swap_pct);
    o.kv_u64("netRxBps", rx_bps);
    o.kv_u64("netTxBps", tx_bps);
    o.kv_str("netDown", &net_down);
    o.kv_str("netUp", &net_up);
    o.kv_str("netIface", &cur.net.primary_iface);
    o.kv_u64("diskPercent", disk.percent);
    o.kv_str("diskLabel", &disk.label);
    o.kv_str("diskFreeLabel", &disk.free_label);
    o.kv_u64("cpuTempC", cpu_temp_c);
    o.kv_u64("gpuTempC", gpu_temp_c);
    o.kv_u64("uptimeSec", uptime_sec);
    o.kv_str("uptimeLabel", &uptime_label);
    o.kv_str("loadLabel", &load_label);

    o.key("battery");
    o.obj_start();
    o.kv_bool("hasBattery", bat.has_battery);
    o.kv_u64("percent", bat.percent);
    o.kv_str("status", &bat.status);
    o.kv_bool("charging", bat.charging);
    o.kv_f64("powerWatts", bat.power_watts, 1);
    o.kv_str("etaLabel", &bat.eta_label);
    o.kv_u64("healthPercent", bat.health_percent);
    o.obj_end();

    o.obj_end();
    o.finish()
}

pub fn cmd_telemetry(args: &[String]) -> Result<(), String> {
    let mut watch_ms: Option<u64> = None;
    let mut i = 0usize;
    while i < args.len() {
        if args[i] == "--watch" {
            let ms = args
                .get(i + 1)
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(2000)
                .clamp(500, 10_000);
            watch_ms = Some(ms);
            i += 2;
            continue;
        }
        i += 1;
    }

    let mut disk = CachedDisk::default();
    let mut prev = take_sample();

    let Some(interval) = watch_ms else {
        thread::sleep(Duration::from_millis(80));
        let cur = take_sample();
        println!("{}", build_telemetry_json(&prev, &cur, &mut disk));
        return Ok(());
    };

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    // Emit initial sample after a short 120ms delta window so the UI populates immediately
    thread::sleep(Duration::from_millis(120));
    let mut cur = take_sample();
    let first = build_telemetry_json(&prev, &cur, &mut disk);
    if out.write_all(first.as_bytes()).is_err()
        || out.write_all(b"\n").is_err()
        || out.flush().is_err()
    {
        return Ok(());
    }
    prev = cur;

    loop {
        thread::sleep(Duration::from_millis(interval));
        cur = take_sample();
        let line = build_telemetry_json(&prev, &cur, &mut disk);
        if out.write_all(line.as_bytes()).is_err()
            || out.write_all(b"\n").is_err()
            || out.flush().is_err()
        {
            break;
        }
        prev = cur;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cpu_pct_computes_delta() {
        let a = CpuTimes {
            total: 1000,
            idle: 800,
        };
        let b = CpuTimes {
            total: 1100,
            idle: 825,
        };
        assert_eq!(cpu_pct(a, b), 75);
    }
}
