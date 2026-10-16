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

test "generate dispatches to the provider" {
  let prov = MockProvider::new()
  let req = GenRequest::{
    prompt: "dashboard", width: 400.0, height: 300.0, name: "Dash",
  }
  let res = generate(prov, req)
  assert_true(res.project.files.length() > 0)
}
