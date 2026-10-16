/// Deterministic design-tree transformers operating on `@common.File`.

fn map_tree(
  shapes : Array[@common.Shape],
  f : (@common.Shape) -> @common.Shape,
) -> Array[@common.Shape] {
  shapes.map(fn(s) {
    let s2 = f(s)
    @common.shape_set_children(s2, map_tree(s2.children, f))
  })
}

fn map_file(
  file : @common.File,
  f : (@common.Shape) -> @common.Shape,
) -> @common.File {
  @common.file_set_pages(
    file,
    file.pages.map(fn(pg) {
      @common.page_set_shapes(pg, map_tree(pg.shapes, f))
    }),
  )
}

/// Collapse all nesting: every shape becomes a top-level shape with its
/// absolute (parent-offset) coordinates; the tree is flattened away.
pub fn flatten(file : @common.File) -> @common.File {
  let new_pages = file.pages.map(fn(pg) {
    let flat : Array[@common.Shape] = []
    for s in pg.shapes {
      flatten_shape(s, 0.0, 0.0, flat)
    }
    @common.page_set_shapes(pg, flat)
  })
  @common.file_set_pages(file, new_pages)
}

fn flatten_shape(
  s : @common.Shape,
  ox : Double,
  oy : Double,
  acc : Array[@common.Shape],
) -> Unit {
  let abs_x = ox + s.x
  let abs_y = oy + s.y
  let base = @common.shape_set_xy(s, abs_x, abs_y)
  acc.push(@common.shape_set_children(base, []))
  for c in s.children {
    flatten_shape(c, abs_x, abs_y, acc)
  }
}

/// Recolor every shape by its kind (deterministic, no randomness).
pub fn auto_color(file : @common.File) -> @common.File {
  map_file(file, fn(s) { @common.shape_set_fill(s, color_for_kind(s.kind)) })
}

fn color_for_kind(k : @common.ShapeKind) -> @common.Color {
  if k == @common.rect {
    @common.color(99, 102, 241, 1.0)
  } else if k == @common.text {
    @common.color(15, 23, 42, 1.0)
  } else if k == @common.frame {
    @common.color(16, 185, 129, 1.0)
  } else {
    @common.color(245, 158, 11, 1.0)
  }
}

/// Append ` #<tag>` to every shape's name.
pub fn tag_all(file : @common.File, tag : String) -> @common.File {
  map_file(file, fn(s) { @common.shape_set_name(s, s.name + " #" + tag) })
}

/// Rename every shape to `shape_<n>` in document order.
pub fn normalize_names(file : @common.File) -> @common.File {
  @common.file_set_pages(
    file,
    file.pages.map(fn(pg) {
      let (shapes, _) = norm_tree(pg.shapes, 0)
      @common.page_set_shapes(pg, shapes)
    }),
  )
}

fn norm_tree(
  shapes : Array[@common.Shape],
  start : Int,
) -> (Array[@common.Shape], Int) {
  let out : Array[@common.Shape] = []
  let mut idx = start
  for s in shapes {
    let renamed = @common.shape_set_name(s, "shape_" + idx.to_string())
    let (children2, idx2) = norm_tree(s.children, idx + 1)
    out.push(@common.shape_set_children(renamed, children2))
    idx = idx2
  }
  (out, idx)
}

test "flatten promotes nested children to top level" {
  let inner = @common.shape("c", "C", @common.rect, 10.0, 10.0, 5.0, 5.0)
  let outer = @common.shape(
    "o", "O", @common.frame, 100.0, 50.0, 30.0, 30.0, children=[inner],
  )
  let f = @common.file("f", "F", pages=[ @common.page("p", "P", shapes=[outer]) ])
  let ff = flatten(f)
  let all = ff.pages[0].shapes
  assert_eq(all.length(), 2)
  let inner2 = all[1]
  assert_eq(inner2.x, 110.0)
  assert_eq(inner2.y, 60.0)
}

test "auto_color paints rects indigo" {
  let f = @common.file(
    "f", "F",
    pages=[ @common.page("p", "P", shapes=[
      @common.shape("a", "A", @common.rect, 0.0, 0.0, 5.0, 5.0),
    ]) ],
  )
  let fc = auto_color(f)
  let sh = fc.pages[0].shapes[0]
  assert_eq(sh.fill, @common.color(99, 102, 241, 1.0))
}

test "tag_all appends the tag" {
  let f = @common.file(
    "f", "F",
    pages=[ @common.page("p", "P", shapes=[
      @common.shape("a", "A", @common.rect, 0.0, 0.0, 5.0, 5.0),
    ]) ],
  )
  let ft = tag_all(f, "v1")
  assert_eq(ft.pages[0].shapes[0].name, "A #v1")
}

test "normalize_names renames in order" {
  let f = @common.file(
    "f", "F",
    pages=[ @common.page("p", "P", shapes=[
      @common.shape("a", "A", @common.rect, 0.0, 0.0, 5.0, 5.0),
      @common.shape("b", "B", @common.text, 1.0, 1.0, 2.0, 2.0),
    ]) ],
  )
  let fn2 = normalize_names(f)
  assert_eq(fn2.pages[0].shapes[0].name, "shape_0")
  assert_eq(fn2.pages[0].shapes[1].name, "shape_1")
}
