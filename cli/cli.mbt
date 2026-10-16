/// Native command-line interface for MoonPot.
///
/// `run_cli(args)` dispatches subcommands that build on the store / ai /
/// skill / kb / mcp modules. A `--store <path>` global flag selects the
/// snapshot file (default `./moonpot.json`) so the subcommands share state.
///
/// Subcommands:
///   init                         create an empty snapshot file
///   new-project <name>           create a project
///   generate <prompt> [--width W --height H --name N]
///                                generate a design and save it as a project
///   run-skill <project> <file> <skill>
///                                apply a skill to a stored file
///   ask <query> [--docs-file F] [--topk N]
///                                RAG retrieve context over docs
///   mcp [--in file.jsonl]        run the MCP JSON-RPC loop (file transport)
///   help                         print usage

/// Read a `--name value` style flag; returns None if absent.
fn get_flag(args : Array[String], name : String) -> String? {
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == name && i + 1 < args.length() {
      return Some(args[i + 1])
    }
  }
  None
}

/// Parse a JSON number literal (e.g. "800") into a Double.
fn parse_double(s : String) -> Double {
  try {
    match @json.parse(s) {
      Json::Number(n, ..) => n
      _ => 0.0
    }
  } catch {
    _ => 0.0
  }
}

/// Parse a JSON array of {id,title,body} into KB documents.
fn parse_docs_json(text : String) -> Array[@kb.Doc] raise {
  match @json.parse(text) {
    Json::Array(items) =>
      items.map(fn(it) {
        match it {
          Json::Object(m) =>
            @kb.doc(
              match m.get("id") {
                Some(Json::String(s)) => s
                _ => ""
              },
              match m.get("title") {
                Some(Json::String(s)) => s
                _ => ""
              },
              match m.get("body") {
                Some(Json::String(s)) => s
                _ => ""
              },
            )
          _ => @kb.doc("", "", "")
        }
      })
    _ => []
  }
}

/// Load the snapshot if it exists, else return a fresh store.
fn load_or_new(path : String) -> @store.Store {
  match @store.Store::load_from(path) {
    Ok(s) => s
    Err(_) => @store.Store::new()
  }
}

fn print_help() -> Unit {
  println("MoonPot CLI")
  println("  moonpot init")
  println("  moonpot new-project <name>")
  println("  moonpot generate <prompt> [--width W --height H --name N]")
  println("  moonpot run-skill <project> <file> <skill>")
  println("  moonpot ask <query> [--docs-file F] [--topk N]")
  println("  moonpot mcp [--in file.jsonl]")
  println("  moonpot help")
  println("Global: --store <path>  (default ./moonpot.json)")
}

/// Dispatch a CLI invocation. Returns a process exit code (0 = ok).
pub fn run_cli(args : Array[String]) -> Int {
  let store_path = match get_flag(args, "--store") {
    Some(p) => p
    None => "./moonpot.json"
  }
  if args.length() < 2 {
    print_help()
    return 1
  }
  let sub = args[1]
  if sub == "help" || sub == "-h" || sub == "--help" {
    print_help()
    return 0
  } else if sub == "init" {
    let s = @store.Store::new()
    match s.save_as(store_path) {
      Ok(_) => {
        println("initialized " + store_path)
        return 0
      }
      Err(e) => {
        println("error: " + e)
        return 1
      }
    }
  } else if sub == "new-project" {
    if args.length() < 3 {
      println("error: new-project requires <name>")
      return 1
    }
    let name = args[2]
    let id = "proj_" + name
    let s = load_or_new(store_path)
    s.create_project(@common.project(id, name))
    match s.save_as(store_path) {
      Ok(_) => {
        println("created project " + id + " (" + name + ")")
        return 0
      }
      Err(e) => {
        println("error: " + e)
        return 1
      }
    }
  } else if sub == "generate" {
    if args.length() < 3 {
      println("error: generate requires <prompt>")
      return 1
    }
    let prompt = args[2]
    let width = match get_flag(args, "--width") {
      Some(w) => parse_double(w)
      None => 800.0
    }
    let height = match get_flag(args, "--height") {
      Some(h) => parse_double(h)
      None => 600.0
    }
    let name = match get_flag(args, "--name") {
      Some(n) => n
      None => "Generated"
    }
    let req = @ai.gen_request(prompt, width, height, name)
    let res = @ai.MockProvider::new().gen(req)
    let s = load_or_new(store_path)
    let pid = "proj_gen_" + name
    s.create_project(@common.project(pid, name))
    s.put_file(pid, res.project.files[0]).unwrap()
    match s.save_as(store_path) {
      Ok(_) => {
        println(
          "generated project " + pid + " with " +
          res.project.files[0].pages[0].shapes.length().to_string() +
          " top-level shapes",
        )
        return 0
      }
      Err(e) => {
        println("error: " + e)
        return 1
      }
    }
  } else if sub == "run-skill" {
    if args.length() < 5 {
      println("error: run-skill requires <project> <file> <skill>")
      return 1
    }
    let pid = args[2]
    let fid = args[3]
    let skill = args[4]
    let s = load_or_new(store_path)
    match s.get_file(pid, fid) {
      Some(f) =>
        match @skill.run_skill(skill, f) {
          Ok(out) => {
            ignore(s.put_file(pid, out))
            match s.save_as(store_path) {
              Ok(_) => {
                println("applied skill '" + skill + "' to " + pid + "/" + fid)
                return 0
              }
              Err(e) => {
                println("error: " + e)
                return 1
              }
            }
          }
          Err(msg) => {
            println("error: " + msg)
            return 1
          }
        }
      None => {
        println("error: file not found " + pid + "/" + fid)
        return 1
      }
    }
  } else if sub == "ask" {
    if args.length() < 3 {
      println("error: ask requires <query>")
      return 1
    }
    let query = args[2]
    let top_k = match get_flag(args, "--topk") {
      Some(k) => parse_double(k).to_int()
      None => 3
    }
    let docs : Array[@kb.Doc] = match get_flag(args, "--docs-file") {
      Some(p) => {
        let text = try { @fs.read_file_to_string(p) } catch { _ => "" }
        try { parse_docs_json(text) } catch { _ => [] }
      }
      None => []
    }
    let kb = @kb.build(docs)
    let ctx = @kb.retrieve_context(kb, query, top_k)
    println(ctx)
    return 0
  } else if sub == "mcp" {
    let in_path = match get_flag(args, "--in") {
      Some(p) => p
      None => "./mcp_in.jsonl"
    }
    let lines : Array[String] = try {
      @fs.read_file_to_string(in_path)
        .split("\n")
        .map(fn(l) { l.to_owned() })
        .filter(fn(l) { l.trim().length() > 0 })
        .collect()
    } catch {
      _ => []
    }
    let s = load_or_new(store_path)
    for line in lines {
      println(@mcp.handle(s, line))
    }
    return 0
  } else {
    println("unknown subcommand: " + sub)
    print_help()
    return 1
  }
}
