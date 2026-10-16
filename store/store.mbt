/// In-memory document store with optional JSON-file snapshot.
/// Zero external services: seed it from memory, persist to a `.json` file.
/// (PostgreSQL/Redis can later replace the backing map behind this API.)

pub struct StoreData {
  projects : Array[@common.Project]
} derive(ToJson, FromJson)

pub extend StoreData with ToJson::{ to_json }
pub extend StoreData with @json.FromJson::{ from_json }

pub struct Store {
  mut projects : Array[@common.Project]
  mut path : String?
}

/// Create an empty store (no snapshot file).
pub fn Store::new() -> Store {
  Store::{ projects: [], path: None }
}

/// Open a store bound to `path`; loads existing data if the file exists.
pub fn Store::open(path : String) -> Store {
  match Store::load_from(path) {
    Ok(s) => s
    Err(_) => Store::{ projects: [], path: Some(path) }
  }
}

/// Create a store from a JSON snapshot string.
pub fn Store::from_json_string(s : String) -> Store {
  match load_from_str(s) {
    Ok(st) => st
    Err(_) => Store::new()
  }
}

pub fn Store::list_projects(self : Store) -> Array[@common.Project] {
  self.projects
}

pub fn Store::get_project(self : Store, id : String) -> @common.Project? {
  for p in self.projects {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

pub fn Store::create_project(self : Store, p : @common.Project) -> Unit {
  self.projects.push(p)
  self.save_snapshot()
}

pub fn Store::update_project(self : Store, p : @common.Project) -> Unit {
  for i = 0; i < self.projects.length(); i = i + 1 {
    if self.projects[i].id == p.id {
      self.projects[i] = p
      break
    }
  }
  self.save_snapshot()
}

pub fn Store::delete_project(self : Store, id : String) -> Unit {
  let kept : Array[@common.Project] = []
  for p in self.projects {
    if p.id != id {
      kept.push(p)
    }
  }
  self.projects = kept
  self.save_snapshot()
}

pub fn Store::get_file(
  self : Store,
  project_id : String,
  file_id : String,
) -> @common.File? {
  match self.get_project(project_id) {
    Some(p) => {
      for f in p.files {
        if f.id == file_id {
          return Some(f)
        }
      }
      None
    }
    None => None
  }
}

/// Insert or replace a file inside a project.
pub fn Store::put_file(
  self : Store,
  project_id : String,
  f : @common.File,
) -> Result[Unit, String] {
  match self.get_project(project_id) {
    Some(p) => {
      let mut replaced = false
      for i = 0; i < p.files.length(); i = i + 1 {
        if p.files[i].id == f.id {
          p.files[i] = f
          replaced = true
          break
        }
      }
      if !replaced {
        p.files.push(f)
      }
      self.update_project(p)
      Ok(())
    }
    None => Err("project not found: " + project_id)
  }
}

pub fn Store::delete_file(self : Store, project_id : String, file_id : String) -> Unit {
  match self.get_project(project_id) {
    Some(p) => {
      let kept : Array[@common.File] = []
      for f in p.files {
        if f.id != file_id {
          kept.push(f)
        }
      }
      p.files.clear()
      for f in kept {
        p.files.push(f)
      }
      self.update_project(p)
    }
    None => ()
  }
}

/// Serialize the whole store to a pretty JSON string (the snapshot format).
pub fn Store::to_json_string(self : Store) -> String {
  let data = StoreData::{ projects: self.projects }
  data.to_json().stringify(indent=2)
}

fn Store::save_snapshot(self : Store) -> Unit {
  match self.path {
    Some(p) => {
      try {
        @fs.write_string_to_file(p, self.to_json_string())
      } catch {
        _ => ()
      }
    }
    None => ()
  }
}

/// Persist the store to `path` and remember it for future auto-saves.
pub fn Store::save_as(self : Store, path : String) -> Result[Unit, String] {
  self.path = Some(path)
  try {
    @fs.write_string_to_file(path, self.to_json_string())
    Ok(())
  } catch {
    _ => Err("failed to write snapshot")
  }
}

/// Load a store from a JSON snapshot file.
pub fn Store::load_from(path : String) -> Result[Store, String] {
  try {
    let content = @fs.read_file_to_string(path)
    load_from_str(content)
  } catch {
    _ => Err("failed to read snapshot")
  }
}

fn load_from_str(s : String) -> Result[Store, String] {
  try {
    let json = @json.parse(s)
    let data : StoreData = @json.from_json(json)
    Ok(Store::{ projects: data.projects, path: None })
  } catch {
    _ => Err("failed to parse snapshot")
  }
}

// ---- tests ----

test "store create / get / list projects" {
  let s = Store::new()
  assert_eq(s.list_projects().length(), 0)
  s.create_project(@common.project("p1", "My Project"))
  assert_eq(s.list_projects().length(), 1)
  assert_true(s.get_project("p1") is Some(_))
  assert_true(s.get_project("missing") is None)
}

test "store put / get / delete file" {
  let s = Store::new()
  s.create_project(@common.project("p1", "P"))
  let f = @common.file("f1", "F")
  s.put_file("p1", f).unwrap()
  assert_true(s.get_file("p1", "f1") is Some(_))
  // writing into a missing project must surface an error
  let bad = s.put_file("ghost", @common.file("x", "X"))
  assert_true(bad is Err(_))
  s.delete_file("p1", "f1")
  assert_true(s.get_file("p1", "f1") is None)
}

test "store update / delete project" {
  let s = Store::new()
  s.create_project(@common.project("p1", "old"))
  s.update_project(@common.project("p1", "new"))
  assert_eq(s.get_project("p1").unwrap().name, "new")
  s.delete_project("p1")
  assert_true(s.get_project("p1") is None)
}

test "store json round-trip (in memory)" {
  let s = Store::new()
  let f = @common.file(
    "f1",
    "F",
    pages=[
      @common.page(
        "pg1",
        "Page",
        shapes=[ @common.shape("s1", "S", @common.rect, 0.0, 0.0, 5.0, 5.0) ],
      ),
    ],
  )
  s.create_project(@common.project("p1", "P", files=[f]))
  let json = s.to_json_string()
  assert_true(json.contains("\"p1\""))
  let s2 = Store::from_json_string(json)
  let got = s2.get_file("p1", "f1")
  assert_true(got is Some(_))
  assert_eq(got.unwrap().name, "F")
}

test "store persistence round-trip (file snapshot)" {
  let path = "./store_persist_tmp.json"
  try {
    @fs.remove_file(path)
  } catch {
    _ => ()
  }
  let s = Store::new()
  s.create_project(@common.project("p1", "Persisted"))
  s.save_as(path).unwrap()
  let s2 = Store::load_from(path).unwrap()
  assert_eq(s2.get_project("p1").unwrap().name, "Persisted")
  try {
    @fs.remove_file(path)
  } catch {
    _ => ()
  }
}
