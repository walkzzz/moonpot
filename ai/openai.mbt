/// OpenAI-compatible chat-completions provider (offline-capable, network-ready).
///
/// `OpenAiCompatProvider` builds a standards-compliant
/// `/v1/chat/completions` request and — when API credentials are present —
/// performs a live call. The live HTTP transport lives in the `server`
/// package (which owns `@crescent.fetch`); this module stays dependency-free
/// and fully testable offline.
///
/// When credentials are absent the provider degrades gracefully to a
/// deterministic offline design so the generation pipeline never breaks —
/// consistent with the v0.2 self-heal contract.

pub struct OpenAiCompatProvider {
  base_url : String
  api_key : String
  model : String
  enabled : Bool
}

/// Build a provider from explicit config. `enabled` is true iff `api_key` is
/// non-empty. `base_url` defaults to the OpenAI endpoint; `model` defaults to
/// `gpt-4o-mini`.
pub fn OpenAiCompatProvider::make(
  base_url : String,
  api_key : String,
  model : String,
) -> OpenAiCompatProvider {
  let base = if base_url.length() == 0 {
    "https://api.openai.com/v1"
  } else {
    base_url
  }
  let mdl = if model.length() == 0 { "gpt-4o-mini" } else { model }
  OpenAiCompatProvider::{
    base_url: base,
    api_key: api_key,
    model: mdl,
    enabled: api_key.length() > 0,
  }
}

/// The transport request the server sends over HTTP.
pub struct OpenAiRequest {
  url : String
  headers : Map[String, String]
  body : Json
}

fn openai_system_prompt() -> String {
  "You are MoonPot, a UI design generator. Given a natural-language UI " +
  "description, reply ONLY with a JSON object of the form " +
  "{\"files\":[{\"name\":string,\"pages\":[{\"name\":string,\"shapes\":[" +
  "{\"type\":\"rect\"|\"text\",\"x\":num,\"y\":num,\"w\":num,\"h\":num," +
  "\"fill\":{\"r\":0,\"g\":0,\"b\":0,\"a\":1},\"text\":string?}]}]}]}. " +
  "Emit between 1 and 24 shapes. No prose, no markdown fences."
}

/// Build the chat-completions request for a generation request.
/// Fully testable offline — no network, no env access.
pub fn OpenAiCompatProvider::build_request(
  self : OpenAiCompatProvider,
  req : GenRequest,
) -> OpenAiRequest {
  let sep = if self.base_url.has_suffix("/") { "" } else { "/" }
  let url = self.base_url + sep + "chat/completions"
  let headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + self.api_key,
  }
  let messages = Json::array([
    Json::object({
      "role": Json("system"),
      "content": Json(openai_system_prompt()),
    }),
    Json::object({ "role": Json("user"), "content": Json(req.prompt) }),
  ])
  let body = Json::object({
    "model": Json(self.model),
    "messages": messages,
    "temperature": Json::number(0.7),
    "response_format": Json::object({ "type": Json("json_object") }),
  })
  OpenAiRequest::{ url, headers, body }
}

/// Synchronous trait impl returns a deterministic OFFLINE design so the
/// `AiProvider` contract stays satisfiable without network. The live,
/// LLM-backed path is invoked from the server's async REST route.
pub impl AiProvider for OpenAiCompatProvider with gen(
  self : OpenAiCompatProvider,
  req : GenRequest,
) -> GenResult {
  let res = MockProvider::new().gen(req)
  let notes = res.notes
  if self.enabled {
    notes.push(
      "provider: openai-compat (offline placeholder; use async REST route for live LLM)",
    )
  } else {
    notes.push("provider: openai-compat (offline; set MOONPOT_AI_KEY to enable)")
  }
  GenResult::{ project: res.project, notes }
}

pub extend OpenAiCompatProvider with AiProvider::{ gen }

test "OpenAiCompatProvider::make with no key is disabled" {
  let p = OpenAiCompatProvider::make("", "", "")
  assert_false(p.enabled)
}

test "OpenAiCompatProvider::make fills defaults" {
  let p = OpenAiCompatProvider::make("", "sk-x", "")
  assert_true(p.enabled)
  assert_eq(p.model, "gpt-4o-mini")
  assert_eq(p.base_url, "https://api.openai.com/v1")
}

test "OpenAiCompatProvider offline gen yields a valid design" {
  let p = OpenAiCompatProvider::make("", "", "")
  let r = p.gen(gen_request("landing", 800.0, 600.0, "O"))
  assert_true(validate_design(r.project))
  assert_true(r.notes[0].contains("offline"))
}

test "OpenAiCompatProvider build_request shape" {
  let p = OpenAiCompatProvider::make("http://x/v1", "k", "m")
  let r = p.build_request(gen_request("hi", 1.0, 1.0, "N"))
  assert_true(r.url.has_suffix("/chat/completions"))
  assert_eq(r.headers.get("Authorization"), Some("Bearer k"))
  assert_eq(r.headers.get("Content-Type"), Some("application/json"))
  match r.body {
    Json::Object(m) => {
      assert_eq(m.get("model"), Some(Json("m")))
      match m.get("messages") {
        Some(Json::Array(msgs)) => assert_eq(msgs.length(), 2)
        _ => fail("messages should be an array")
      }
    }
    _ => fail("body should be an object")
  }
}
