/// MoonPot HTTP server (crescent): REST API + MCP-over-HTTP + WebSocket bridge.
///
/// Routes:
///   GET  /                                     service info
///   GET  /health                               liveness probe
///   GET  /api/projects                         list projects
///   GET  /api/projects/:pid/files/:fid         read a design file
///   GET  /api/skills                           list available skills
///   POST /api/generate                         prompt -> design (stored)
///   POST /api/projects/:pid/files/:fid/skills/:name
///                                              apply a skill to a stored file
///   POST /api/kb/query                         RAG retrieve over KB docs
///   POST /api/rpc                              JSON-RPC 2.0 passthrough (MCP)
///   WS   /ws                                   WebSocket bridge to the MCP dispatcher
///
/// NOTE: the builtin `Json` enum is read-only (constructors unusable), so all
/// JSON responses go through `derive(ToJson)` payload structs + `.json_value`.

/// ---- response payload structs ----

struct InfoBody {
  name : String
  version : String
  description : String
  endpoints : Array[String]
} derive(ToJson)

struct HealthBody {
  status : String
} derive(ToJson)

struct ErrorBody {
  error : String
} derive(ToJson)

struct ProjectsBody {
  projects : Array[@common.Project]
} derive(ToJson)

struct FileBody {
  file : @common.File
} derive(ToJson)

struct SkillsBody {
  skills : Array[String]
} derive(ToJson)

struct GenerateResultBody {
  project : @common.Project
  notes : Array[String]
} derive(ToJson)

struct RunSkillResultBody {
  applied : String
  file : @common.File
} derive(ToJson)

struct KBHitBody {
  id : String
  title : String
  score : Double
} derive(ToJson)

struct KBResultBody {
  context : String
  hits : Array[KBHitBody]
} derive(ToJson)

/// ---- request body structs ----

struct GenerateRequestBody {
  prompt : String
  width : Double?
  height : Double?
  name : String?
} derive(FromJson)

struct KBQueryBody {
  query : String
  topk : Int?
  docs : Array[@kb.Doc]?
} derive(FromJson)

/// ---- helpers ----

fn json_ok(body : &ToJson) -> @crescent.HttpResponse {
  @crescent.HttpResponse::ok().json_value(body)
}

fn json_bad_request(msg : String) -> @crescent.HttpResponse {
  @crescent.HttpResponse::bad_request().json_value(ErrorBody::{ error: msg })
}

fn json_not_found(msg : String) -> @crescent.HttpResponse {
  @crescent.HttpResponse::not_found().json_value(ErrorBody::{ error: msg })
}

/// Extract a route parameter as an owned String.
fn route_param(event : @crescent.Event, key : String) -> String? {
  match event.params.get(key) {
    Some(v) => Some(v.to_owned())
    None => None
  }
}

/// Parse the request body as JSON into T (mirrors HttpRequest::try_json,
/// which is not visible cross-package in this crescent build).
fn[T : @json.FromJson] parse_body(event : @crescent.Event) -> Result[T, String] {
  try {
    let text = @utf8.decode(event.req.raw_body)
    let json = @json.parse(text)
    Ok(@json.from_json(json))
  } catch {
    err => Err(err.to_string())
  }
}

/// ---- app builder ----

/// Build the MoonPot REST + WebSocket app over the given store.
pub fn build_app(store : @store.Store) -> @crescent.App {
  let app = @crescent.App()
  // Service info + liveness
  app.get(
    "/",
    _ =>
      json_ok(
        InfoBody::{
          name: "moonpot",
          version: "0.1.0",
          description: "Penpot ported to MoonBit with AI / Skill / MCP / CLI / KB",
          endpoints: [
            "GET /health",
            "GET /api/projects",
            "GET /api/projects/:pid/files/:fid",
            "GET /api/skills",
            "POST /api/generate",
            "POST /api/projects/:pid/files/:fid/skills/:name",
            "POST /api/kb/query",
            "POST /api/rpc",
            "WS /ws",
          ],
        },
      ),
  )
  app.get("/health", _ => json_ok(HealthBody::{ status: "up" }))
  // Projects
  app.get(
    "/api/projects",
    _ => json_ok(ProjectsBody::{ projects: store.list_projects() }),
  )
  app.get("/api/projects/:pid/files/:fid", event => {
    match (route_param(event, "pid"), route_param(event, "fid")) {
      (Some(pid), Some(fid)) =>
        match store.get_file(pid, fid) {
          Some(f) => json_ok(FileBody::{ file: f })
          None => json_not_found("file not found: " + pid + "/" + fid)
        }
      _ => json_bad_request("missing :pid or :fid")
    }
  })
  // Skills
  app.get(
    "/api/skills",
    _ => json_ok(SkillsBody::{ skills: @skill.list_skills() }),
  )
  // AI generate (deterministic mock provider)
  app.post("/api/generate", event => {
    let parsed : Result[GenerateRequestBody, String] = parse_body(event)
    match parsed {
      Ok(body) => {
        let name = match body.name {
          Some(n) => n
          None => "Generated"
        }
        let req = @ai.gen_request(
          body.prompt,
          match body.width {
            Some(w) => w
            None => 800.0
          },
          match body.height {
            Some(h) => h
            None => 600.0
          },
          name,
        )
        let res = @ai.MockProvider::new().gen(req)
        let pid = "proj_gen_" + name
        store.create_project(@common.project(pid, name))
        ignore(store.put_file(pid, res.project.files[0]))
        json_ok(GenerateResultBody::{ project: res.project, notes: res.notes })
      }
      Err(msg) => json_bad_request("invalid json body: " + msg)
    }
  })
  // Apply a skill to a stored file
  app.post(
    "/api/projects/:pid/files/:fid/skills/:name",
    event => {
      match (
        route_param(event, "pid"),
        route_param(event, "fid"),
        route_param(event, "name"),
      ) {
        (Some(pid), Some(fid), Some(sname)) =>
          match store.get_file(pid, fid) {
            Some(f) =>
              match @skill.run_skill(sname, f) {
                Ok(out) => {
                  ignore(store.put_file(pid, out))
                  json_ok(RunSkillResultBody::{ applied: sname, file: out })
                }
                Err(msg) => json_bad_request(msg)
              }
            None => json_not_found("file not found: " + pid + "/" + fid)
          }
        _ => json_bad_request("missing :pid, :fid or :name")
      }
    },
  )
  // KB query (RAG retrieve)
  app.post("/api/kb/query", event => {
    let parsed : Result[KBQueryBody, String] = parse_body(event)
    match parsed {
      Ok(q) => {
        let docs : Array[@kb.Doc] = match q.docs {
          Some(d) => d
          None => []
        }
        let knowledge = @kb.build(docs)
        let topk = match q.topk {
          Some(k) => k
          None => 3
        }
        let hits = @kb.query(knowledge, q.query, topk)
        let ctx = @kb.retrieve_context(knowledge, q.query, topk)
        let hit_bodies : Array[KBHitBody] = []
        for pair in hits {
          let (doc, score) = pair
          hit_bodies.push(KBHitBody::{ id: doc.id, title: doc.title, score })
        }
        json_ok(KBResultBody::{ context: ctx, hits: hit_bodies })
      }
      Err(msg) => json_bad_request("invalid json body: " + msg)
    }
  })
  // JSON-RPC 2.0 passthrough to the MCP dispatcher (MCP-over-HTTP)
  app.post("/api/rpc", event => {
    let text = @utf8.decode(event.req.raw_body)
    let response = @mcp.handle(store, text)
    @crescent
    .HttpResponse::ok()
    .body(response)
    .header("Content-Type", "application/json; charset=utf-8")
  })
  // WebSocket bridge: text frames are JSON-RPC requests answered by the
  // same MCP dispatcher, so MCP clients can connect over /ws directly.
  app.ws(
    "/ws",
    @ws.WebSocketHandler(fn(ev) {
      match ev {
        @ws.Open(peer) =>
          peer.text("moonpot ws ready: send JSON-RPC 2.0 requests as text frames")
        @ws.Message(peer, msg) =>
          match msg {
            @ws.Text(text) => peer.text(@mcp.handle(store, text))
            @ws.Binary(_) => peer.text("binary frames unsupported; send JSON text")
          }
        @ws.Close(_) => ()
      }
    }),
  )
  app
}

/// ---- entry point ----

async fn main raise {
  let store = @store.Store::new()
  store.create_project(@common.project("demo", "Demo Project"))
  ignore(store.put_file("demo", @common.file("f1", "Demo File")))
  let app = build_app(store)
  println("moonpot server listening on http://0.0.0.0:4000")
  app.serve(port=4000)
}
