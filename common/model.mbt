/// Penpot-inspired domain model (MoonBit native re-platform).
/// Project > File > Page > Shape(tree). All types are JSON-serializable so
/// the same structs flow between the REST API, the MCP server and the CLI.

pub struct Color {
  r : Int
  g : Int
  b : Int
  a : Double
} derive(ToJson, FromJson, Debug, Eq)

pub extend Color with Eq::{ equal, not_equal }
pub extend Color with @moonbitlang/core/debug.Debug::{ to_repr }

pub enum ShapeKind {
  Rect
  Text
  Frame
  Group
} derive(ToJson, FromJson, Debug, Eq)

pub extend ShapeKind with Eq::{ equal, not_equal }
pub extend ShapeKind with @moonbitlang/core/debug.Debug::{ to_repr }

/// A shape in the design tree. Groups/Frames carry `children`; leaf shapes
/// keep `children` empty.
pub struct Shape {
  id : String
  name : String
  kind : ShapeKind
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
  opacity : Double
  fill : Color
  text : String
  font_size : Double
  children : Array[Shape]
} derive(ToJson, FromJson)

pub struct ShapePatch {
  x : Option[Double]
  y : Option[Double]
  width : Option[Double]
  height : Option[Double]
  rotation : Option[Double]
  opacity : Option[Double]
  fill : Option[Color]
  text : Option[String]
} derive(ToJson, FromJson)

/// A collaborative edit operation broadcast over WebSocket.
pub enum ChangeOp {
  AddShape(String, Shape)
  UpdateShape(String, ShapePatch)
  RemoveShape(String)
  RenameShape(String, String)
} derive(ToJson, FromJson)

pub struct Page {
  id : String
  name : String
  shapes : Array[Shape]
} derive(ToJson, FromJson)

pub struct File {
  id : String
  name : String
  pages : Array[Page]
} derive(ToJson, FromJson)

pub struct Project {
  id : String
  name : String
  files : Array[File]
} derive(ToJson, FromJson)

// Explicit ToJson/FromJson extends to silence implicit-promotion deprecation.
pub extend Color with ToJson::{ to_json }
pub extend Color with @json.FromJson::{ from_json }
pub extend ShapeKind with ToJson::{ to_json }
pub extend ShapeKind with @json.FromJson::{ from_json }
pub extend Shape with ToJson::{ to_json }
pub extend Shape with @json.FromJson::{ from_json }
pub extend ShapePatch with ToJson::{ to_json }
pub extend ShapePatch with @json.FromJson::{ from_json }
pub extend ChangeOp with ToJson::{ to_json }
pub extend ChangeOp with @json.FromJson::{ from_json }
pub extend Page with ToJson::{ to_json }
pub extend Page with @json.FromJson::{ from_json }
pub extend File with ToJson::{ to_json }
pub extend File with @json.FromJson::{ from_json }
pub extend Project with ToJson::{ to_json }
pub extend Project with @json.FromJson::{ from_json }

///|
pub fn color(r : Int, g : Int, b : Int, a : Double) -> Color {
  Color::{ r, g, b, a }
}

///|
pub fn shape(
  id : String,
  name : String,
  kind : ShapeKind,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  fill~ : Color = Color::{ r: 0, g: 0, b: 0, a: 1.0 },
  text~ : String = "",
  font_size~ : Double = 16.0,
  children~ : Array[Shape] = [],
) -> Shape {
  Shape::{
    id, name, kind, x, y, width, height, rotation: 0.0, opacity: 1.0, fill,
    text, font_size, children,
  }
}

///|
pub fn page(id : String, name : String, shapes~ : Array[Shape] = []) -> Page {
  Page::{ id, name, shapes }
}

///|
pub fn file(id : String, name : String, pages~ : Array[Page] = []) -> File {
  File::{ id, name, pages }
}

///|
pub fn project(id : String, name : String, files~ : Array[File] = []) -> Project {
  Project::{ id, name, files }
}

// --- Cross-package record-update helpers --------------------------------
// Struct constructors are not exported across packages in MoonBit, so other
// packages (skill, mcp, cli, server) use these `pub fn` copy-with helpers
// instead of record literals like `Shape::{ ..s, name }`.

pub fn shape_set_name(s : Shape, name : String) -> Shape {
  Shape::{ ..s, name }
}

pub fn shape_set_fill(s : Shape, fill : Color) -> Shape {
  Shape::{ ..s, fill }
}

pub fn shape_set_children(s : Shape, children : Array[Shape]) -> Shape {
  Shape::{ ..s, children }
}

pub fn shape_set_xy(s : Shape, x : Double, y : Double) -> Shape {
  Shape::{ ..s, x, y }
}

pub fn file_set_pages(f : File, pages : Array[Page]) -> File {
  File::{ ..f, pages }
}

pub fn page_set_shapes(pg : Page, shapes : Array[Shape]) -> Page {
  Page::{ ..pg, shapes }
}

fn[T] coalesce(opt : Option[T], cur : T) -> T {
  match opt {
    Some(v) => v
    None => cur
  }
}

/// Depth-first lookup of a shape by id across the whole file.
pub fn find_shape(file : File, id : String) -> Shape? {
  for p in file.pages {
    for s in p.shapes {
      match find_in_shape(s, id) {
        Some(found) => return Some(found)
        None => ()
      }
    }
  }
  None
}

fn find_in_shape(s : Shape, id : String) -> Shape? {
  if s.id == id {
    return Some(s)
  }
  for c in s.children {
    match find_in_shape(c, id) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

fn update_tree(
  shapes : Array[Shape],
  id : String,
  f : (Shape) -> Shape,
) -> Array[Shape] {
  shapes.map(fn(s) {
    if s.id == id {
      f(s)
    } else if s.children.length() == 0 {
      s
    } else {
      Shape::{ ..s, children: update_tree(s.children, id, f) }
    }
  })
}

fn filter_tree(shapes : Array[Shape], id : String) -> Array[Shape] {
  let kept = shapes.filter(fn(s) { s.id != id })
  kept.map(fn(s) {
    if s.children.length() == 0 {
      s
    } else {
      Shape::{ ..s, children: filter_tree(s.children, id) }
    }
  })
}

/// Apply a single collaborative operation, returning a new immutable File.
pub fn apply_change(file : File, op : ChangeOp) -> Result[File, String] {
  match op {
    AddShape(page_id, sh) => add_shape(file, page_id, sh)
    UpdateShape(shape_id, patch) => update_shape(file, shape_id, patch)
    RemoveShape(shape_id) => Ok(remove_shape(file, shape_id))
    RenameShape(shape_id, name) => rename_shape(file, shape_id, name)
  }
}

fn add_shape(file : File, page_id : String, sh : Shape) -> Result[File, String] {
  let mut found = false
  let new_pages = file.pages.map(fn(p) {
    if p.id == page_id {
      found = true
      Page::{ ..p, shapes: [..p.shapes, sh] }
    } else {
      p
    }
  })
  if !found {
    Err("page not found: " + page_id)
  } else {
    Ok(File::{ ..file, pages: new_pages })
  }
}

fn update_shape(
  file : File,
  shape_id : String,
  patch : ShapePatch,
) -> Result[File, String] {
  let mut found = false
  let new_pages = file.pages.map(fn(p) {
    Page::{
      ..p,
      shapes: update_tree(p.shapes, shape_id, fn(s) {
        found = true
        Shape::{
          ..s,
          x: coalesce(patch.x, s.x),
          y: coalesce(patch.y, s.y),
          width: coalesce(patch.width, s.width),
          height: coalesce(patch.height, s.height),
          rotation: coalesce(patch.rotation, s.rotation),
          opacity: coalesce(patch.opacity, s.opacity),
          fill: coalesce(patch.fill, s.fill),
          text: coalesce(patch.text, s.text),
        }
      }),
    }
  })
  if !found {
    Err("shape not found: " + shape_id)
  } else {
    Ok(File::{ ..file, pages: new_pages })
  }
}

fn remove_shape(file : File, shape_id : String) -> File {
  let new_pages = file.pages.map(fn(p) {
    Page::{ ..p, shapes: filter_tree(p.shapes, shape_id) }
  })
  File::{ ..file, pages: new_pages }
}

fn rename_shape(file : File, shape_id : String, name : String) -> Result[File, String] {
  let mut found = false
  let new_pages = file.pages.map(fn(p) {
    Page::{
      ..p,
      shapes: update_tree(p.shapes, shape_id, fn(s) {
        found = true
        Shape::{ ..s, name }
      }),
    }
  })
  if !found {
    Err("shape not found: " + shape_id)
  } else {
    Ok(File::{ ..file, pages: new_pages })
  }
}

/// All shapes in the file (depth-first, flat list).
pub fn all_shapes(file : File) -> Array[Shape] {
  let acc : Array[Shape] = []
  for p in file.pages {
    for s in p.shapes {
      collect(s, acc)
    }
  }
  acc
}

fn collect(s : Shape, acc : Array[Shape]) -> Unit {
  acc.push(s)
  for c in s.children {
    collect(c, acc)
  }
}

/// Text content of the file, used by the knowledge-base indexer.
pub fn collect_text(file : File) -> Array[String] {
  all_shapes(file).map(fn(s) {
    if s.text.length() > 0 {
      s.name + ": " + s.text
    } else {
      s.name
    }
  })
}

///|
pub fn count_shapes(file : File) -> Int {
  all_shapes(file).length()
}

// --- Cross-package enum constructors ---------------------------------------
// MoonBit 0.1.x does not export enum constructors across packages (and
// per-variant `pub` is rejected), so we re-expose `ShapeKind` and `ChangeOp`
// constructors as public values / functions. Within `common` the bare
// constructors (`Rect`, `AddShape`, ...) are still usable directly.

pub let rect : ShapeKind = Rect
pub let text : ShapeKind = Text
pub let frame : ShapeKind = Frame
pub let group : ShapeKind = Group

pub fn add_shape_op(page_id : String, s : Shape) -> ChangeOp {
  AddShape(page_id, s)
}

pub fn update_shape_op(shape_id : String, patch : ShapePatch) -> ChangeOp {
  UpdateShape(shape_id, patch)
}

pub fn remove_shape_op(shape_id : String) -> ChangeOp {
  RemoveShape(shape_id)
}

pub fn rename_shape_op(shape_id : String, name : String) -> ChangeOp {
  RenameShape(shape_id, name)
}

test "find_shape finds nested child" {
  let f = file(
    "f1",
    "F",
    pages=[
      page(
        "p1",
        "P",
        shapes=[
          shape(
            "a",
            "A",
            Frame,
            0.0,
            0.0,
            10.0,
            10.0,
            children=[shape("b", "B", Rect, 1.0, 1.0, 2.0, 2.0)],
          ),
        ],
      ),
    ],
  )
  assert_true(find_shape(f, "b") is Some(_))
  assert_true(find_shape(f, "missing") is None)
}

test "count_shapes counts whole tree" {
  let f = file(
    "f1",
    "F",
    pages=[
      page(
        "p1",
        "P",
        shapes=[
          shape(
            "a",
            "A",
            Frame,
            0.0,
            0.0,
            1.0,
            1.0,
            children=[shape("b", "B", Rect, 0.0, 0.0, 1.0, 1.0)],
          ),
        ],
      ),
    ],
  )
  assert_eq(count_shapes(f), 2)
}

test "apply_change add then rename" {
  let f0 = file("f1", "F", pages=[page("p1", "P", shapes=[])])
  let f1 = apply_change(
    f0,
    AddShape("p1", shape("s1", "S", Rect, 0.0, 0.0, 5.0, 5.0)),
  ).unwrap()
  assert_eq(count_shapes(f1), 1)
  let f2 = apply_change(f1, RenameShape("s1", "Renamed")).unwrap()
  let sh = find_shape(f2, "s1").unwrap()
  assert_eq(sh.name, "Renamed")
}

test "apply_change update patch merges fields" {
  let f0 = file(
    "f1",
    "F",
    pages=[
      page("p1", "P", shapes=[shape("s1", "S", Rect, 0.0, 0.0, 5.0, 5.0)]),
    ],
  )
  let patch = ShapePatch::{
    x: Some(42.0),
    y: None,
    width: None,
    height: None,
    rotation: None,
    opacity: None,
    fill: None,
    text: Some("hi"),
  }
  let f1 = apply_change(f0, UpdateShape("s1", patch)).unwrap()
  let sh = find_shape(f1, "s1").unwrap()
  assert_eq(sh.x, 42.0)
  assert_eq(sh.width, 5.0)
  assert_eq(sh.text, "hi")
}

test "to_json emits shape id" {
  let f = file(
    "f1",
    "F",
    pages=[
      page("p1", "P", shapes=[shape("a", "A", Rect, 0.0, 0.0, 1.0, 1.0)]),
    ],
  )
  let s = f.to_json().stringify()
  assert_true(s.contains("\"id\""))
  assert_true(s.contains("\"a\""))
}
