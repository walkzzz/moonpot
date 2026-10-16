/// MCP (Model Context Protocol) layer for MoonPot.
///
/// A minimal but real JSON-RPC 2.0 dispatcher: it parses incoming requests,
/// routes by `mthd`, calls into the store / ai / skill / kb modules, and
/// emits JSON-RPC responses. Transport is line-delimited JSON (one request
/// per line); the `mcpserver` executable reads requests from a file so it
/// stays runnable under `moonrun` where stdin is unavailable.
///
/// Supported methods:
///   moonpot/list_projects
///   moonpot/read_file        { project_id, file_id }
///   moonpot/generate_design  { prompt, width, height, name }
///   moonpot/run_skill        { project_id, file_id, skill }
///   moonpot/query_kb         { docs, query, top_k }

// --- JSON-RPC envelope structs ------------------------------------------

struct RpcOk {
  jsonrpc : String
  id : Json
  result : Json
} derive(ToJson)

struct RpcErrBody {
  code : Int
  message : String
} derive(ToJson)

struct RpcErr {
  jsonrpc : String
  id : Json
  error : Json
} derive(ToJson)

pub extend RpcOk with ToJson::{ to_json }
pub extend RpcErrBody with ToJson::{ to_json }
pub extend RpcErr with ToJson::{ to_json }

// --- Json field extraction -----------------------------------------------

fn str_field(params : Json, key : String) -> String {
  match params {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

fn num_field(params : Json, key : String) -> Double {
  match params {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
}

fn int_field(params : Json, key : String) -> Int {
  match params {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
    _ => 3
  }
}

fn json_field(params : Json, key : String) -> Json {
  match params {
    Json::Object(m) =>
      match m.get(key) {
        Some(v) => v
        _ => Json::null()
      }
    _ => Json::null()
  }
}

fn parse_docs(arr : Json) -> Array[@kb.Doc] {
  match arr {
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

// --- JSON-RPC envelope builders ------------------------------------------

fn ok_response(id : Json, result : Json) -> String {
  RpcOk::{ jsonrpc: "2.0", id, result }.to_json().stringify()
}

fn error_response(id : Json, code : Int, message : String) -> String {
  let body = RpcErrBody::{ code, message }.to_json()
  RpcErr::{ jsonrpc: "2.0", id, error: body }.to_json().stringify()
}

// --- Dispatch -------------------------------------------------------------

pub fn handle(store : @store.Store, req_text : String) -> String {
  let parsed : Json = try {
    @json.parse(req_text)
  } catch {
    _ => return error_response(Json::null(), -32700, "parse error")
  }
  let (mthd, id, params) = match parsed {
    Json::Object(m) => (
      match m.get("method") {
        Some(Json::String(s)) => s
        _ => ""
      },
      match m.get("id") {
        Some(v) => v
        _ => Json::null()
      },
      match m.get("params") {
        Some(v) => v
        _ => Json::null()
      },
    )
    _ => ("", Json::null(), Json::null())
  }
  if mthd.length() == 0 {
    return error_response(id, -32600, "missing method")
  }
  dispatch(store, mthd, id, params)
}

fn dispatch(
  store : @store.Store,
  mthd : String,
  id : Json,
  params : Json,
) -> String {
  if mthd == "moonpot/list_projects" {
    return ok_response(id, store.list_projects().to_json())
  } else if mthd == "moonpot/read_file" {
    let pid = str_field(params, "project_id")
    let fid = str_field(params, "file_id")
    match store.get_file(pid, fid) {
      Some(f) => return ok_response(id, f.to_json())
      None => return error_response(id, -32001, "file not found: " + pid + "/" + fid)
    }
  } else if mthd == "moonpot/generate_design" {
    let prompt = str_field(params, "prompt")
    let width = num_field(params, "width")
    let height = num_field(params, "height")
    let name = str_field(params, "name")
    let req = @ai.gen_request(prompt, width, height, name)
    let res = @ai.MockProvider::new().gen(req)
    return ok_response(id, res.project.to_json())
  } else if mthd == "moonpot/run_skill" {
    let pid = str_field(params, "project_id")
    let fid = str_field(params, "file_id")
    let skill = str_field(params, "skill")
    match store.get_file(pid, fid) {
      Some(f) =>
        match @skill.run_skill(skill, f) {
          Ok(out) => {
            ignore(store.put_file(pid, out))
            return ok_response(id, out.to_json())
          }
          Err(msg) => return error_response(id, -32002, msg)
        }
      None => return error_response(id, -32001, "file not found: " + pid + "/" + fid)
    }
  } else if mthd == "moonpot/query_kb" {
    let docs = parse_docs(json_field(params, "docs"))
    let query = str_field(params, "query")
    let top_k = int_field(params, "top_k")
    let kb = @kb.build(docs)
    let ctx = @kb.retrieve_context(kb, query, top_k)
    return ok_response(id, Json::string(ctx))
  } else {
    return error_response(id, -32601, "method not found: " + mthd)
  }
}

// --- Tests ----------------------------------------------------------------

test "handle list_projects returns json-rpc result" {
  let s = @store.Store::new()
  s.create_project(@common.project("p1", "Demo"))
  let resp = handle(
    s,
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"moonpot/list_projects\"}",
  )
  assert_true(resp.contains("\"jsonrpc\":\"2.0\""))
  assert_true(resp.contains("\"p1\""))
  assert_true(resp.contains("\"result\""))
}

test "handle read_file returns the file json" {
  let s = @store.Store::new()
  s.create_project(@common.project("p1", "P"))
  s.put_file("p1", @common.file("f1", "F")).unwrap()
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"moonpot/read_file\",\"params\":{\"project_id\":\"p1\",\"file_id\":\"f1\"}}"
  let resp = handle(s, req)
  assert_true(resp.contains("\"F\""))
}

test "handle generate_design returns a project" {
  let s = @store.Store::new()
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"moonpot/generate_design\",\"params\":{\"prompt\":\"landing page\",\"width\":800,\"height\":600,\"name\":\"L\"}}"
  let resp = handle(s, req)
  assert_true(resp.contains("\"result\""))
  assert_true(resp.contains("\"files\""))
}

test "handle query_kb returns retrieved context" {
  let s = @store.Store::new()
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"moonpot/query_kb\",\"params\":{\"docs\":[{\"id\":\"d1\",\"title\":\"MoonBit FFI\",\"body\":\"MoonBit calls C and JS.\"},{\"id\":\"d2\",\"title\":\"Cooking\",\"body\":\"boil pasta\"}],\"query\":\"MoonBit C\",\"top_k\":1}}"
  let resp = handle(s, req)
  assert_true(resp.contains("MoonBit FFI"))
}

test "handle unknown method returns error" {
  let s = @store.Store::new()
  let resp = handle(s, "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"nope\"}")
  assert_true(resp.contains("\"error\""))
  assert_true(resp.contains("-32601"))
}
