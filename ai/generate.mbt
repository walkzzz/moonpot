/// Prompt -> design tree. Keyword-driven, deterministic, offline.

priv struct DesignItem {
  kind : @common.ShapeKind
  label : String
  fill : @common.Color
  is_text : Bool
  text : String
  font : Double
}

/// Build the shapes + human-readable notes from a generation request.
fn build_design(req : GenRequest) -> (Array[@common.Shape], Array[String]) {
  let p = req.prompt.to_lower()
  let items : Array[DesignItem] = []
  let notes : Array[String] = []
  let mut has_title = false

  if p.contains("landing") || p.contains("dashboard") || p.contains("title") || p.contains("page") {
    has_title = true
    notes.push("added a title block")
  }
  if p.contains("button") || p.contains("cta") {
    items.push(
      DesignItem::{
        kind: @common.rect, label: "Button", fill: pick_color("button"),
        is_text: true, text: "Click me", font: 16.0,
      },
    )
    notes.push("added a button")
  }
  if p.contains("card") {
    for i = 0; i < 3; i = i + 1 {
      items.push(
        DesignItem::{
          kind: @common.frame,
          label: "Card " + (i + 1).to_string(),
          fill: pick_color("card" + i.to_string()),
          is_text: false, text: "", font: 14.0,
        },
      )
    }
    notes.push("added 3 cards")
  }
  if p.contains("list") {
    for i = 0; i < 4; i = i + 1 {
      items.push(
        DesignItem::{
          kind: @common.rect,
          label: "Item " + (i + 1).to_string(),
          fill: pick_color("item" + i.to_string()),
          is_text: true, text: "List item " + (i + 1).to_string(), font: 14.0,
        },
      )
    }
    notes.push("added a 4-item list")
  }
  if p.contains("image") || p.contains("photo") {
    items.push(
      DesignItem::{
        kind: @common.rect, label: "Image", fill: pick_color("image"),
        is_text: true, text: "[ image ]", font: 14.0,
      },
    )
    notes.push("added an image placeholder")
  }
  if items.length() == 0 && !has_title {
    for i = 0; i < 3; i = i + 1 {
      items.push(
        DesignItem::{
          kind: @common.rect,
          label: "Block " + (i + 1).to_string(),
          fill: pick_color("block" + i.to_string()),
          is_text: false, text: "", font: 14.0,
        },
      )
    }
    notes.push("no keywords matched; generated 3 placeholder blocks")
  }

  let pad = 24.0
  let gap = 16.0
  let shapes : Array[@common.Shape] = []
  let mut cursor_y = pad
  let title_h = 48.0

  if has_title {
    let title_text = if req.name.length() > 0 { req.name } else { "Generated Design" }
    shapes.push(
      text_block("title", title_text, pad, cursor_y, req.width - 2.0 * pad, title_h, 28.0),
    )
    cursor_y = cursor_y + title_h + gap
  }

  // Clamp the content area so tiny/odd canvases cannot produce an empty
  // grid (which would make `cells[i]` index out of bounds below).
  let area_h0 = req.height - cursor_y - pad
  let area_h = if area_h0 < 64.0 { 64.0 } else { area_h0 }
  let area_w0 = req.width - 2.0 * pad
  let area_w = if area_w0 < 64.0 { 64.0 } else { area_w0 }
  let cells = grid_cells(items.length(), area_w, area_h, gap)
  for i = 0; i < items.length(); i = i + 1 {
    let it = items[i]
    let cell = cells[i]
    shapes.push(make_shape(it, i, pad + cell.x, cursor_y + cell.y, cell.w, cell.h))
  }
  (shapes, notes)
}

fn text_block(
  id : String,
  t : String,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  font : Double,
) -> @common.Shape {
  @common.shape(
    id, t, @common.text, x, y, w, h,
    fill=@common.color(241, 245, 249, 1.0), text=t, font_size=font,
  )
}

fn make_shape(
  it : DesignItem,
  i : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> @common.Shape {
  let id = "s" + i.to_string()
  if it.is_text {
    @common.shape(
      id, it.label, it.kind, x, y, w, h,
      fill=it.fill, text=it.text, font_size=it.font,
    )
  } else {
    @common.shape(id, it.label, it.kind, x, y, w, h, fill=it.fill)
  }
}

test "build_design: landing + cards + button = 5 shapes" {
  let req = GenRequest::{
    prompt: "landing page with 3 cards and a button",
    width: 800.0, height: 600.0, name: "Landing",
  }
  let (shapes, notes) = build_design(req)
  assert_eq(shapes.length(), 5)
  assert_true(notes.length() > 0)
}

test "build_design: fallback when no keywords match" {
  let req = GenRequest::{
    prompt: "asdkjfh", width: 400.0, height: 300.0, name: "",
  }
  let (shapes, _) = build_design(req)
  assert_eq(shapes.length(), 3)
}
