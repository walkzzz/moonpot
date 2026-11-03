/// Native AI module for MoonPot.
///
/// Turns a natural-language prompt into a Penpot-style design tree, lays it
/// out with a deterministic grid packer, and renders it to standalone
/// HTML/CSS. The `AiProvider` interface lets an offline, deterministic
/// `MockProvider` stand in for a real LLM later — zero network, zero deps.

pub struct GenRequest {
  prompt : String
  width : Double
  height : Double
  name : String
} derive(ToJson, FromJson)

pub extend GenRequest with ToJson::{ to_json }
pub extend GenRequest with @json.FromJson::{ from_json }

pub struct GenResult {
  project : @common.Project
  notes : Array[String]
} derive(ToJson, FromJson)

pub extend GenResult with ToJson::{ to_json }
pub extend GenResult with @json.FromJson::{ from_json }

/// The LLM client interface. `MockProvider` implements it today; any
/// external package may add its own provider (OpenAiProvider/etc.) since
/// the trait is open.
pub(open) trait AiProvider {
  gen(Self, req : GenRequest) -> GenResult
}

/// Generic entry point: any provider turns a request into a design.
pub fn[T: AiProvider] generate(provider : T, req : GenRequest) -> GenResult {
  provider.gen(req)
}

/// Factory so other packages can build a request without a struct literal
/// (MoonBit does not export struct constructors across packages).
pub fn gen_request(
  prompt : String,
  width : Double,
  height : Double,
  name : String,
) -> GenRequest {
  GenRequest::{ prompt, width, height, name }
}

/// Factory so other packages can build a GenResult (struct literals are
/// not constructible across packages).
pub fn gen_result(
  project : @common.Project,
  notes : Array[String],
) -> GenResult {
  GenResult::{ project, notes }
}

/// Run a shared contract suite against ANY `AiProvider` implementation.
/// Returns a list of human-readable failure messages; empty means pass.
/// This is the v0.2 gate: a real provider and `MockProvider` must satisfy
/// the exact same assertions (determinism, JSON round-trip, shape bounds,
/// non-empty notes).
pub fn[T: AiProvider] provider_contract(p : T, name : String) -> Array[String] raise {
  let fails : Array[String] = []
  let req = gen_request(
    "landing page with 3 cards and a button", 800.0, 600.0, "Contract",
  )
  // 1. determinism: same request -> identical design JSON
  let a = p.gen(req).project.to_json().stringify()
  let b = p.gen(req).project.to_json().stringify()
  if a != b {
    fails.push(name + ": gen() is non-deterministic")
  }
  // 2. JSON round-trip: the result serializes to a parseable JSON object
  let res = p.gen(req)
  let json_str = res.to_json().stringify()
  match @json.parse(json_str) {
    Json::Object(_) => ()
    _ => fails.push(name + ": GenResult JSON is not an object")
  }
  // 3. empty prompt still yields a renderable design (>=1 shape, <=24)
  let eres = p.gen(gen_request("", 400.0, 300.0, ""))
  if eres.project.files.length() == 0 {
    fails.push(name + ": empty prompt produced no files")
  } else {
    let ef = eres.project.files[0]
    if ef.pages.length() == 0 {
      fails.push(name + ": empty prompt produced no pages")
    } else {
      let n = @common.count_shapes(ef)
      if n < 1 {
        fails.push(name + ": empty prompt produced <1 shape")
      }
      if n > 24 {
        fails.push(name + ": empty prompt produced >24 shapes (unbounded?)")
      }
    }
  }
  // 4. notes are populated
  if res.notes.length() == 0 {
    fails.push(name + ": empty notes")
  }
  fails
}

/// Validate a generated design tree is well-formed enough to render.
/// Used by `generate_safe` to detect malformed output (e.g. a real LLM
/// that emits broken JSON): files/pages/shapes non-empty, geometry and
/// alpha in range.
pub fn validate_design(proj : @common.Project) -> Bool {
  if proj.files.length() == 0 {
    return false
  }
  for f in proj.files {
    if f.pages.length() == 0 {
      return false
    }
    for pg in f.pages {
      if pg.shapes.length() == 0 {
        return false
      }
      for s in pg.shapes {
        if s.width < 0.0 || s.height < 0.0 {
          return false
        }
        if s.fill.a < 0.0 || s.fill.a > 1.0 {
          return false
        }
      }
    }
  }
  true
}

/// Generate with a self-healing fallback: if the provider returns an
/// invalid design, fall back to the deterministic `MockProvider` so the
/// pipeline never breaks (v0.2 structured-output contract).
pub fn[T: AiProvider] generate_safe(provider : T, req : GenRequest) -> GenResult {
  let res = provider.gen(req)
  if validate_design(res.project) {
    res
  } else {
    MockProvider::new().gen(req)
  }
}

test "MockProvider satisfies the provider contract" {
  let fails = try {
    provider_contract(MockProvider::new(), "MockProvider")
  } catch {
    _ => [""]
  }
  assert_true(fails.is_empty())
}

test "generate dispatches to the provider" {
  let prov = MockProvider::new()
  let req = GenRequest::{
    prompt: "dashboard", width: 400.0, height: 300.0, name: "Dash",
  }
  let res = generate(prov, req)
  assert_true(res.project.files.length() > 0)
}
