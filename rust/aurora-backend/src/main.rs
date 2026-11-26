#![forbid(unsafe_code)]

mod calc;
mod captures;
mod clipboard;
mod distro;
mod doctor;
mod json;
mod pip;
mod probe;
mod proc_mon;
mod services;
mod snippets;
mod store;
mod telemetry;
mod updater;
mod util;
mod workspaces;

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
        print_err_exit("Usage: aurora-backend <version|probe|battery|telemetry|hwmon|processes|clipboard|calc|doctor|captures|distro|store|services|service-action|kill-proc|power|snippets|pip|workspaces|config-update>");
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
        "captures" => {
            if let Err(e) = captures::cmd_captures(rest) {
                print_err_exit(&e);
            }
        }
        "distro" => {
            if let Err(e) = distro::cmd_distro(rest) {
                print_err_exit(&e);
            }
        }
        "store" => {
            if let Err(e) = store::cmd_store(rest) {
                print_err_exit(&e);
            }
        }
        "services" => services::cmd_services(),
        "service-action" => {
            if let Err(e) = services::cmd_service_action(rest) {
                print_err_exit(&e);
            }
        }
        "kill-proc" => {
            if let Err(e) = services::cmd_kill_proc(rest) {
                print_err_exit(&e);
            }
        }
        "power" => {
            if let Err(e) = services::cmd_power(rest) {
                print_err_exit(&e);
            }
        }
        "snippets" => {
            if let Err(e) = snippets::cmd_snippets(rest) {
                print_err_exit(&e);
            }
        }
        "pip" => {
            if let Err(e) = pip::cmd_pip(rest) {
                print_err_exit(&e);
            }
        }
        "workspaces" => {
            if let Err(e) = workspaces::cmd_workspaces(rest) {
                print_err_exit(&e);
            }
        }
        "config-update" => {
            if let Err(e) = updater::cmd_config_update(rest) {
                print_err_exit(&e);
            }
        }
        other => print_err_exit(&format!("Unknown subcommand '{other}'")),
    }
}
