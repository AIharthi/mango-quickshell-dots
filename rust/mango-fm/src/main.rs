#![forbid(unsafe_code)]

mod json;
mod list;
mod ops;
mod places;
mod preview;
mod search;
mod trash;
mod util;

use std::env;
use std::io::{self, BufRead, BufWriter, Stdout, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

use crate::json::{JsonOut, JsonVal};

fn print_err_exit(msg: &str) -> ! {
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", false);
    o.kv_str("error", msg);
    o.obj_end();
    println!("{}", o.finish());
    std::process::exit(1);
}

fn write_line(writer: &Arc<Mutex<BufWriter<Stdout>>>, line: &str) {
    if let Ok(mut w) = writer.lock() {
        let _ = w.write_all(line.as_bytes());
        let _ = w.write_all(b"\n");
        let _ = w.flush();
    }
}

fn send_reply(writer: &Arc<Mutex<BufWriter<Stdout>>>, id: u64, res: Result<String, String>) {
    let mut o = JsonOut::with_capacity(256);
    o.obj_start();
    o.kv_u64("id", id);
    match res {
        Ok(data_json) => {
            o.kv_bool("ok", true);
            o.kv_raw("data", &data_json);
        }
        Err(err) => {
            o.kv_bool("ok", false);
            o.kv_str("error", &err);
        }
    }
    o.obj_end();
    write_line(writer, &o.finish());
}

fn send_progress(
    writer: &Arc<Mutex<BufWriter<Stdout>>>,
    id: u64,
    label: &str,
    done: usize,
    total: usize,
    current: &str,
) {
    let pct = if total == 0 {
        100u64
    } else {
        ((done as u64) * 100) / (total as u64)
    };
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_str("event", "progress");
    o.kv_u64("id", id);
    o.kv_str("label", label);
    o.kv_u64("done", done as u64);
    o.kv_u64("total", total as u64);
    o.kv_u64("pct", pct.min(100));
    o.kv_str("current", current);
    o.obj_end();
    write_line(writer, &o.finish());
}

fn collect_paths(req: &JsonVal) -> Vec<String> {
    if let Some(arr) = req.get_arr("paths") {
        arr.iter()
            .filter_map(|v| v.as_str().map(str::to_string))
            .collect()
    } else if let Some(p) = req.get_str("path") {
        vec![p.to_string()]
    } else {
        Vec::new()
    }
}

fn serve_loop() {
    let stdin = io::stdin();
    let writer = Arc::new(Mutex::new(BufWriter::new(io::stdout())));
    let search_token = Arc::new(AtomicU64::new(0));

    // Signal readiness to Quickshell SplitParser immediately
    let mut ready = JsonOut::new();
    ready.obj_start();
    ready.kv_str("event", "ready");
    ready.kv_str("version", env!("CARGO_PKG_VERSION"));
    ready.obj_end();
    write_line(&writer, &ready.finish());

    for line_res in stdin.lock().lines() {
        let Ok(line) = line_res else { break };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let req = match json::parse(trimmed) {
            Ok(v) => v,
            Err(e) => {
                send_reply(&writer, 0, Err(format!("Invalid JSON request: {e}")));
                continue;
            }
        };
        let id = req.get_u64("id").unwrap_or(0);
        let Some(op) = req.get_str("op") else {
            send_reply(&writer, id, Err("Missing 'op'".to_string()));
            continue;
        };

        match op {
            "ping" => send_reply(&writer, id, Ok("{\"pong\":true}".to_string())),
            "list" => {
                let path = req.get_str("path").unwrap_or("~");
                let hidden = req.get_bool("hidden").unwrap_or(false);
                let sort = req.get_str("sort").unwrap_or("name");
                let desc = req.get_bool("desc").unwrap_or(false);
                let dirs_first = req.get_bool("dirsFirst").unwrap_or(true);
                send_reply(&writer, id, list::list_dir(path, hidden, sort, desc, dirs_first));
            }
            "dir_stamp" => {
                let path = req.get_str("path").unwrap_or("~");
                send_reply(&writer, id, list::dir_stamp(path));
            }
            "places" => send_reply(&writer, id, places::get_places()),
            "bookmark_add" => {
                let path = req.get_str("path").unwrap_or("");
                let name = req.get_str("name");
                send_reply(&writer, id, places::bookmark_add(path, name));
            }
            "bookmark_remove" => {
                let path = req.get_str("path").unwrap_or("");
                send_reply(&writer, id, places::bookmark_remove(path));
            }
            "preview" => {
                let path = req.get_str("path").unwrap_or("");
                send_reply(&writer, id, preview::preview_path(path));
            }
            "search" => {
                let path = req.get_str("path").unwrap_or("~").to_string();
                let query = req.get_str("query").unwrap_or("").to_string();
                let hidden = req.get_bool("hidden").unwrap_or(false);
                let max_res = req.get_u64("max").unwrap_or(120) as usize;
                let my_tok = search_token.fetch_add(1, Ordering::Relaxed) + 1;
                let tok = Arc::clone(&search_token);
                let w = Arc::clone(&writer);
                thread::spawn(move || {
                    let res = search::search_dir(&path, &query, hidden, max_res, &tok, my_tok);
                    send_reply(&w, id, res);
                });
            }
            "mkdir" => {
                let path = req.get_str("path").unwrap_or("");
                let name = req.get_str("name");
                send_reply(&writer, id, ops::mkdir(path, name));
            }
            "touch" => {
                let path = req.get_str("path").unwrap_or("");
                let name = req.get_str("name");
                send_reply(&writer, id, ops::touch(path, name));
            }
            "rename" => {
                let path = req.get_str("path").unwrap_or("");
                let new_name = req.get_str("newName").unwrap_or("");
                send_reply(&writer, id, ops::rename_item(path, new_name));
            }
            "copy" | "move" => {
                let is_move = op == "move";
                let sources = collect_paths(&req);
                let dest = req.get_str("dest").unwrap_or("").to_string();
                let overwrite = req.get_bool("overwrite").unwrap_or(false);
                let w = Arc::clone(&writer);
                let label = if is_move { "Moving" } else { "Copying" };
                thread::spawn(move || {
                    let w_prog = Arc::clone(&w);
                    let res = ops::copy_or_move(&sources, &dest, is_move, overwrite, |d, t, c| {
                        send_progress(&w_prog, id, label, d, t, c);
                    });
                    send_reply(&w, id, res);
                });
            }
            "trash" => {
                let paths = collect_paths(&req);
                send_reply(&writer, id, trash::trash_paths(&paths));
            }
            "trash_list" => send_reply(&writer, id, trash::trash_list()),
            "trash_restore" => {
                let name = req.get_str("trashName").unwrap_or("");
                send_reply(&writer, id, trash::trash_restore(name));
            }
            "trash_empty" => send_reply(&writer, id, trash::trash_empty()),
            "delete" => {
                let paths = collect_paths(&req);
                let w = Arc::clone(&writer);
                thread::spawn(move || {
                    let res = ops::delete_paths(&paths);
                    send_reply(&w, id, res);
                });
            }
            "chmod" => {
                let path = req.get_str("path").unwrap_or("");
                let mode = req.get_str("mode").unwrap_or("");
                send_reply(&writer, id, ops::chmod_path(path, mode));
            }
            "compress" => {
                let sources = collect_paths(&req);
                let dest = req.get_str("destDir").unwrap_or("").to_string();
                let name = req.get_str("name").unwrap_or("archive").to_string();
                let fmt = req.get_str("format").unwrap_or("tar.gz").to_string();
                let w = Arc::clone(&writer);
                thread::spawn(move || {
                    send_progress(&w, id, "Compressing", 0, 1, &name);
                    let res = ops::compress_paths(&sources, &dest, &name, &fmt);
                    send_progress(&w, id, "Compressing", 1, 1, "");
                    send_reply(&w, id, res);
                });
            }
            "extract" => {
                let path = req.get_str("path").unwrap_or("").to_string();
                let dest = req.get_str("destDir").map(str::to_string);
                let w = Arc::clone(&writer);
                thread::spawn(move || {
                    send_progress(&w, id, "Extracting", 0, 1, &path);
                    let res = ops::extract_archive(&path, dest.as_deref());
                    send_progress(&w, id, "Extracting", 1, 1, "");
                    send_reply(&w, id, res);
                });
            }
            "copy_uri" => {
                let paths = collect_paths(&req);
                send_reply(&writer, id, ops::copy_uri(&paths));
            }
            "copy_text" => {
                let text = req.get_str("text").unwrap_or("");
                send_reply(&writer, id, ops::copy_text(text));
            }
            "open" => {
                let path = req.get_str("path").unwrap_or("");
                send_reply(&writer, id, ops::open_path(path));
            }
            "open_with" => {
                let path = req.get_str("path").unwrap_or("");
                let app = req.get_str("app").unwrap_or("");
                send_reply(&writer, id, ops::open_with(path, app));
            }
            "terminal" => {
                let path = req.get_str("path").unwrap_or("~");
                let term = req.get_str("terminal");
                send_reply(&writer, id, ops::open_terminal(path, term));
            }
            "quit" => {
                send_reply(&writer, id, Ok("{\"bye\":true}".to_string()));
                break;
            }
            other => send_reply(&writer, id, Err(format!("Unknown op '{other}'"))),
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args[0] == "serve" {
        serve_loop();
        return;
    }

    match args[0].as_str() {
        "version" => {
            println!("{{\"name\":\"mango-fm\",\"version\":\"{}\"}}", env!("CARGO_PKG_VERSION"));
        }
        "list" => {
            let mut path = "~";
            let mut hidden = false;
            let mut sort = "name";
            let mut desc = false;
            let mut dirs_first = true;
            let mut i = 1usize;
            while i < args.len() {
                match args[i].as_str() {
                    "--hidden" => hidden = true,
                    "--desc" => desc = true,
                    "--no-dirs-first" => dirs_first = false,
                    "--sort" if i + 1 < args.len() => {
                        sort = args[i + 1].as_str();
                        i += 1;
                    }
                    s if !s.starts_with('-') => path = s,
                    _ => {}
                }
                i += 1;
            }
            match list::list_dir(path, hidden, sort, desc, dirs_first) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        "places" => match places::get_places() {
            Ok(out) => println!("{out}"),
            Err(e) => print_err_exit(&e),
        },
        "preview" => {
            let path = args.get(1).map(String::as_str).unwrap_or("~");
            match preview::preview_path(path) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        "search" => {
            let path = args.get(1).map(String::as_str).unwrap_or("~");
            let query = args.get(2).map(String::as_str).unwrap_or("");
            let mut hidden = false;
            let mut max_res = 120usize;
            let mut i = 3usize;
            while i < args.len() {
                match args[i].as_str() {
                    "--hidden" => hidden = true,
                    "--max" if i + 1 < args.len() => {
                        max_res = args[i + 1].parse().unwrap_or(120);
                        i += 1;
                    }
                    _ => {}
                }
                i += 1;
            }
            let tok = AtomicU64::new(1);
            match search::search_dir(path, query, hidden, max_res, &tok, 1) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        "trash" => match trash::trash_paths(&args[1..]) {
            Ok(out) => println!("{out}"),
            Err(e) => print_err_exit(&e),
        },
        "trash-list" => match trash::trash_list() {
            Ok(out) => println!("{out}"),
            Err(e) => print_err_exit(&e),
        },
        "trash-restore" => {
            let name = args.get(1).map(String::as_str).unwrap_or("");
            match trash::trash_restore(name) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        "trash-empty" => match trash::trash_empty() {
            Ok(out) => println!("{out}"),
            Err(e) => print_err_exit(&e),
        },
        "open" => {
            let path = args.get(1).map(String::as_str).unwrap_or("~");
            match ops::open_path(path) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        "terminal" => {
            let path = args.get(1).map(String::as_str).unwrap_or("~");
            let term = args.get(2).map(String::as_str);
            match ops::open_terminal(path, term) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        "copy-text" => {
            let txt = args[1..].join(" ");
            match ops::copy_text(&txt) {
                Ok(out) => println!("{out}"),
                Err(e) => print_err_exit(&e),
            }
        }
        other => print_err_exit(&format!("Unknown subcommand '{other}'")),
    }
}
