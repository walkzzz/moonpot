/// Runnable MCP server (JSON-RPC over line-delimited JSON).
///
/// In a real deployment this loop reads requests from stdin and writes
/// responses to stdout. Because `moonrun` here has no stdin, the loop reads
/// requests from `./mcp_in.jsonl` when present, and otherwise runs a small
/// built-in demo so the server is always runnable and verifiable.

fn demo_requests() -> Array[String] {
  [
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"moonpot/list_projects\"}",
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"moonpot/read_file\",\"params\":{\"project_id\":\"demo\",\"file_id\":\"home\"}}",
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"moonpot/generate_design\",\"params\":{\"prompt\":\"landing page\",\"width\":800,\"height\":600,\"name\":\"L\"}}",
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"moonpot/query_kb\",\"params\":{\"docs\":[{\"id\":\"d1\",\"title\":\"MoonBit FFI\",\"body\":\"MoonBit calls C and JS.\"}],\"query\":\"MoonBit\",\"top_k\":1}}",
  ]
}

fn main {
  let store = @store.Store::new()
  store.create_project(@common.project("demo", "Demo Project"))
  store.put_file("demo", @common.file("home", "Home Page")).unwrap()

  let requests : Array[String] = try {
    let text = @fs.read_file_to_string("./mcp_in.jsonl")
    text.split("\n")
      .map(fn(l) { l.to_owned() })
      .filter(fn(l) { l.trim().length() > 0 })
      .collect()
  } catch {
    _ => demo_requests()
  }

  println("--- MoonPot MCP server (JSON-RPC 2.0) ---")
  for r in requests {
    let resp = @mcp.handle(store, r)
    println(resp)
  }
  println("--- end ---")
}
