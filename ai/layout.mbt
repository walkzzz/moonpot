/// Deterministic grid-packing auto-layout (zero external deps).

pub struct Cell {
  x : Double
  y : Double
  w : Double
  h : Double
}

/// Pack `n` cells into an `area_w` x `area_h` box with `gap` spacing.
/// Cells are positioned relative to (0,0); add an offset when placing.
pub fn grid_cells(
  n : Int,
  area_w : Double,
  area_h : Double,
  gap : Double,
) -> Array[Cell] {
  if n <= 0 || area_w <= 0.0 || area_h <= 0.0 {
    return []
  }
  let cols = pick_cols(n)
  let rows = (n + cols - 1) / cols
  let cell_w = (area_w - (cols - 1).to_double() * gap) / cols.to_double()
  let cell_h = (area_h - (rows - 1).to_double() * gap) / rows.to_double()
  let cells : Array[Cell] = []
  for i = 0; i < n; i = i + 1 {
    let c = i % cols
    let r = i / cols
    cells.push(
      Cell::{
        x: c.to_double() * (cell_w + gap),
        y: r.to_double() * (cell_h + gap),
        w: cell_w,
        h: cell_h,
      },
    )
  }
  cells
}

fn pick_cols(n : Int) -> Int {
  if n <= 1 { 1 }
  else if n <= 2 { 2 }
  else if n <= 4 { 2 }
  else if n <= 6 { 3 }
  else if n <= 9 { 3 }
  else { 4 }
}

/// Cheap, bounded string hash for deterministic color selection.
fn hash_seed(s : String) -> Int {
  let mut h = 7
  for c in s {
    h = (h * 31 + c.to_int()) % 1000003
  }
  h
}

/// A small, pleasant fixed palette (no randomness needed).
fn palette() -> Array[@common.Color] {
  [
    @common.color(99, 102, 241, 1.0),
    @common.color(16, 185, 129, 1.0),
    @common.color(244, 63, 94, 1.0),
    @common.color(245, 158, 11, 1.0),
    @common.color(59, 130, 246, 1.0),
    @common.color(168, 85, 247, 1.0),
  ]
}

/// Deterministic color from a seed string.
pub fn pick_color(seed : String) -> @common.Color {
  let p = palette()
  let idx = hash_seed(seed) % p.length()
  p[idx]
}

test "grid_cells returns n cells" {
  assert_eq(grid_cells(4, 800.0, 600.0, 16.0).length(), 4)
  assert_eq(grid_cells(0, 800.0, 600.0, 16.0).length(), 0)
}

test "pick_color is deterministic" {
  assert_eq(pick_color("card0"), pick_color("card0"))
}
