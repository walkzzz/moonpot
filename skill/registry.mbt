/// Skill registry: a small, deterministic set of design-tree transformers.

pub fn list_skills() -> Array[String] {
  ["flatten", "auto-color", "tag-all", "normalize-names"]
}

/// Run a named skill on a design file. Returns the transformed file, or an
/// error for an unknown skill name.
pub fn run_skill(name : String, file : @common.File) -> Result[@common.File, String] {
  match name {
    "flatten" => Ok(flatten(file))
    "auto-color" => Ok(auto_color(file))
    "tag-all" => Ok(tag_all(file, "tagged"))
    "normalize-names" => Ok(normalize_names(file))
    _ => Err("unknown skill: " + name)
  }
}

test "list_skills returns the four transformers" {
  assert_eq(list_skills().length(), 4)
}

test "run_skill rejects unknown name" {
  let f = @common.file("f", "F")
  assert_true(run_skill("nope", f) is Err(_))
}
