#![forbid(unsafe_code)]

mod calc;
mod clipboard;
mod doctor;
mod json;
mod probe;
mod proc_mon;
mod telemetry;
mod util;

use std::env;

use crate::json::JsonOut;

fn print_err_exit(msg: &str) -> ! {
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", false);
    o.kv_str("error", msg);
    o.obj_end();
    println!("{}", o.finish());
    std::process::exit(1);
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let Some(cmd) = args.first().map(String::as_str) else {
        print_err_exit("Usage: aurora-backend <version|probe|battery|telemetry|hwmon|processes|clipboard|calc|doctor>");
    };
    let rest = &args[1..];

    match cmd {
        "version" => {
            println!(
                "{{\"name\":\"aurora-backend\",\"version\":\"{}\"}}",
                env!("CARGO_PKG_VERSION")
            );
        }
        "probe" => probe::cmd_probe(),
        "battery" => probe::cmd_battery(),
        "telemetry" => {
            if let Err(e) = telemetry::cmd_telemetry(rest) {
                print_err_exit(&e);
            }
        }
        "hwmon" => proc_mon::cmd_hwmon(),
        "processes" => proc_mon::cmd_processes(rest),
        "clipboard" => {
            if let Err(e) = clipboard::cmd_clipboard(rest) {
                print_err_exit(&e);
            }
        }
        "calc" => calc::cmd_calc(rest),
        "doctor" => doctor::cmd_doctor(),
        other => print_err_exit(&format!("Unknown subcommand '{other}'")),
    }
}
