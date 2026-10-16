/// Offline, deterministic mock LLM provider.

pub struct MockProvider {
  model : String
}

pub fn MockProvider::new() -> MockProvider {
  MockProvider::{ model: "moonpot-mock-1" }
}

pub fn MockProvider::model_name(self : MockProvider) -> String {
  self.model
}

impl AiProvider for MockProvider with gen(
  self : MockProvider,
  req : GenRequest,
) -> GenResult {
  let (shapes, base_notes) = build_design(req)
  let notes = base_notes
  notes.push("provider: " + self.model)
  let name = if req.name.length() > 0 { req.name } else { "Design" }
  let f = @common.file("f1", name, pages=[ @common.page("p1", "Page 1", shapes=shapes) ])
  let proj = @common.project("proj1", name, files=[f])
  GenResult::{ project: proj, notes }
}

pub extend MockProvider with AiProvider::{ gen }
