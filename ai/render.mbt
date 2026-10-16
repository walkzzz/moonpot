/// Render a generated project to a standalone static HTML/CSS document.

pub fn render_html(proj : @common.Project) -> String {
  let mut body = ""
  for f in proj.files {
    for pg in f.pages {
      for s in pg.shapes {
        body = body + render_shape(s)
      }
    }
  }
  let css =
    "body{margin:0;font-family:system-ui,Segoe UI,Arial,sans-serif;background:#f8fafc;}" +
    ".shape{position:absolute;box-sizing:border-box;display:flex;align-items:center;" +
    "justify-content:center;border-radius:8px;overflow:hidden;padding:6px;}"
  "<!doctype html>\n" +
    "<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>MoonPot Design</title>\n" +
    "<style>" + css + "</style>\n</head>\n<body>\n" + body + "</body>\n</html>\n"
}

fn render_shape(s : @common.Shape) -> String {
  let left = s.x.to_string()
  let top = s.y.to_string()
  let w = s.width.to_string()
  let h = s.height.to_string()
  let bg = css_color(s.fill)
  let fs = s.font_size.to_string()
  let fg = text_color_for(s.fill)
  let content = escape_html(s.text)
  let div =
    "<div class=\"shape\" style=\"left:" + left + "px;top:" + top + "px;width:" + w +
      "px;height:" + h + "px;background:" + bg + ";color:" + fg + ";font-size:" + fs +
      "px;\">" + content + "</div>\n"
  div + render_children(s.children)
}

fn render_children(children : Array[@common.Shape]) -> String {
  let mut acc = ""
  for c in children {
    acc = acc + render_shape(c)
  }
  acc
}

fn css_color(c : @common.Color) -> String {
  "rgba(" + c.r.to_string() + "," + c.g.to_string() + "," + c.b.to_string() + "," +
    c.a.to_string() + ")"
}

/// Choose a readable text color based on background luminance.
fn text_color_for(c : @common.Color) -> String {
  let lum = 0.299 * c.r.to_double() + 0.587 * c.g.to_double() + 0.114 * c.b.to_double()
  if lum > 140.0 { "#111111" } else { "#ffffff" }
}

fn escape_html(s : String) -> String {
  s.replace(old="&", new="&amp;").replace(old="<", new="&lt;").replace(
    old=">",
    new="&gt;",
  )
}

test "render_html wraps shapes in divs" {
  let prov = MockProvider::new()
  let req = GenRequest::{
    prompt: "dashboard", width: 400.0, height: 300.0, name: "Dash",
  }
  let res = prov.gen(req)
  let html = render_html(res.project)
  assert_true(html.contains("<!doctype html>"))
  assert_true(html.contains("class=\"shape\""))
  assert_true(html.contains("Dash"))
}
