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
///   WS   /ws/gen                               streaming generate (start/progress/done frames)
///
/// NOTE: `/api/generate` is provider-aware — when `MOONPOT_AI_KEY` is set it
/// calls an OpenAI-compatible endpoint live (with self-heal fallback);
/// otherwise it uses the deterministic Mock provider. True Server-Sent Events
/// are not supported by this crescent build (responses are fully buffered),
/// so progressive generation is delivered over `/ws/gen` instead.
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

/// ---- provider + streaming helpers ----

/// Read the AI provider configuration from the environment.
/// `MOONPOT_AI_KEY` enables the OpenAI-compatible live provider;
/// `MOONPOT_AI_BASE_URL` and `MOONPOT_AI_MODEL` are optional.
fn read_ai_config() -> @ai.OpenAiCompatProvider {
  match @env.get_env_var("MOONPOT_AI_KEY") {
    Some(k) => {
      let base = match @env.get_env_var("MOONPOT_AI_BASE_URL") {
        Some(b) => b
        None => ""
      }
      let model = match @env.get_env_var("MOONPOT_AI_MODEL") {
        Some(m) => m
        None => ""
      }
      @ai.OpenAiCompatProvider::make(base, k, model)
    }
    None => @ai.OpenAiCompatProvider::make("", "", "")
  }
}

/// Map a live OpenAI-compatible HTTP response to a `GenResult`.
/// Any network/parse/mapping failure self-heals to the deterministic Mock
/// provider so the pipeline never breaks.
fn openai_to_result(
  resp : @crescent.HttpResponse,
  req : @ai.GenRequest,
) -> @ai.GenResult {
  let fallback = @ai.generate_safe(@ai.MockProvider::new(), req)
  let notes = fallback.notes
  notes.push("openai: live call failed/unparsable; fell back to mock")
  let fallback_res = @ai.gen_result(fallback.project, notes)
  try {
    let text : String = resp.read_body()
    match @json.parse(text) {
      Json::Object(m) => {
        match m.get("choices") {
          Some(Json::Array(choices)) => {
            if choices.length() == 0 {
              return fallback_res
            }
            match choices[0] {
              Json::Object(c) => {
                match c.get("message") {
                  Some(Json::Object(msg)) => {
                    match msg.get("content") {
                      Some(Json::String(content)) => {
                        let parsed : Json = @json.parse(content)
                        match parsed {
                          Json::Object(m) => {
                            match m.get("files") {
                              Some(_) => {
                                let proj : @common.Project =
                                  @json.from_json(parsed)
                                if @ai.validate_design(proj) {
                                  return @ai.gen_result(
                                    proj,
                                    [
                                      "provider: openai-compat (live)",
                                      "model: " + req.name,
                                    ],
                                  )
                                }
                                return fallback_res
                              }
                              None => return fallback_res
                            }
                          }
                          _ => return fallback_res
                        }
                      }
                      _ => return fallback_res
                    }
                  }
                  _ => return fallback_res
                }
              }
              _ => return fallback_res
            }
          }
          _ => return fallback_res
        }
      }
      _ => return fallback_res
    }
  } catch {
    _ => return fallback_res
  }
}

/// WebSocket /ws/gen request payload (best-effort parsed from JSON).
struct WSGenReq {
  prompt : String
  width : Double?
  height : Double?
  name : String?
} derive(FromJson)

/// Parse a /ws/gen text frame into a GenRequest, defaulting on any error.
fn parse_ws_gen(text : String) -> @ai.GenRequest {
  try {
    let j = @json.parse(text)
    let w : WSGenReq = @json.from_json(j)
    @ai.gen_request(
      w.prompt,
      match w.width {
        Some(x) => x
        None => 800.0
      },
      match w.height {
        Some(y) => y
        None => 600.0
      },
      match w.name {
        Some(n) => n
        None => "WSGen"
      },
    )
  } catch {
    _ => @ai.gen_request("landing page", 800.0, 600.0, "WSGen")
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
          version: "0.2.0",
          description: "Penpot ported to MoonBit with AI / Skill / MCP / CLI / KB",
          endpoints: [
            "GET /health",
            "GET /api/projects",
            "GET /api/projects/:pid/files/:fid",
            "GET /api/skills",
            "POST /api/generate (provider-aware: OpenAI if MOONPOT_AI_KEY set)",
            "POST /api/projects/:pid/files/:fid/skills/:name",
            "POST /api/kb/query",
            "POST /api/rpc",
            "WS /ws",
            "WS /ws/gen (streaming generate)",
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
  // AI generate (provider-aware: OpenAI-compatible if MOONPOT_AI_KEY set)
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
        let cfg = read_ai_config()
        let res = if cfg.enabled {
          let r = cfg.build_request(req)
          let body_str = r.body.stringify()
          let resp = @fetch.post(r.url, data=body_str, headers=r.headers)
          openai_to_result(resp, req)
        } else {
          @ai.generate_safe(@ai.MockProvider::new(), req)
        }
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
  // Streaming generate: client sends a JSON generate request, server pushes
  // progressive frames (start -> progress -> done). Delivered over WS because
  // this crescent build buffers full HTTP responses (no SSE/chunked push).
  app.ws(
    "/ws/gen",
    @ws.WebSocketHandler(fn(ev) {
      match ev {
        @ws.Open(peer) =>
          peer.text("{\"type\":\"ready\",\"endpoint\":\"/ws/gen\"}")
        @ws.Message(peer, msg) =>
          match msg {
            @ws.Text(text) => {
              let req = parse_ws_gen(text)
              peer.text("{\"type\":\"start\"}")
              let res = @ai.generate_safe(@ai.MockProvider::new(), req)
              let n = @common.count_shapes(res.project.files[0])
              let progress = "{\"type\":\"progress\",\"stage\":\"layout\",\"shapes\":" +
                n.to_string() +
                "}"
              peer.text(progress)
              let done = "{\"type\":\"done\",\"project\":" +
                Json(res.project).stringify() +
                ",\"notes\":" +
                Json(res.notes).stringify() +
                "}"
              peer.text(done)
            }
            @ws.Binary(_) =>
              peer.text("binary frames unsupported; send JSON text")
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
