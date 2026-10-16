/// Standalone verifier for the store + common modules.
/// Run with: moonrun <this>.wasm  (exit 0 = all passed).
/// This exists because `moon test`'s runner is blocked by the sandbox in
/// this CI environment; the assertions mirror the inline `test` blocks.

/// A local fake provider proving the AiProvider trait is swappable: it
/// ignores the prompt and always emits a single fixed-shape design.
struct FakeProvider {
  tag : String
}

fn FakeProvider::new(tag : String) -> FakeProvider {
  FakeProvider::{ tag }
}

impl @ai.AiProvider for FakeProvider with gen(
  self : FakeProvider,
  req : @ai.GenRequest,
) -> @ai.GenResult {
  let f = @common.file("fake1", "Fake", pages=[
    @common.page("fp", "P", shapes=[
      @common.shape("fs0", "fake", @common.rect, 0.0, 0.0, 100.0, 50.0),
    ]),
  ])
  @ai.gen_result(@common.project("fake_proj", req.name, files=[f]),
    ["fake:" + self.tag, "prompt:" + req.prompt])
}

fn main raise {
  // 1. create / get / list projects
  let s = @store.Store::new()
  assert_eq(s.list_projects().length(), 0)
  s.create_project(@common.project("p1", "My Project"))
  assert_eq(s.list_projects().length(), 1)
  assert_true(s.get_project("p1") is Some(_))
  assert_true(s.get_project("missing") is None)
  println("[1] create/get/list projects ... ok")

  // 2. put / get / delete file
  s.create_project(@common.project("p2", "P2"))
  s.put_file("p2", @common.file("f1", "F1")).unwrap()
  assert_true(s.get_file("p2", "f1") is Some(_))
  assert_true(s.put_file("ghost", @common.file("x", "X")) is Err(_))
  s.delete_file("p2", "f1")
  assert_true(s.get_file("p2", "f1") is None)
  println("[2] put/get/delete file ... ok")

  // 3. update / delete project
  s.update_project(@common.project("p1", "new"))
  assert_eq(s.get_project("p1").unwrap().name, "new")
  s.delete_project("p1")
  assert_true(s.get_project("p1") is None)
  println("[3] update/delete project ... ok")

  // 4. JSON round-trip (in memory)
  let s2 = @store.Store::new()
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
  s2.create_project(@common.project("p1", "P", files=[f]))
  let json = s2.to_json_string()
  assert_true(json.contains("\"p1\""))
  let s3 = @store.Store::from_json_string(json)
  assert_eq(s3.get_file("p1", "f1").unwrap().name, "F")
  println("[4] json round-trip ... ok")

  // 5. persistence round-trip (file snapshot)
  let path = "./store_selftest_tmp.json"
  try {
    @fs.remove_file(path)
  } catch {
    _ => ()
  }
  let s4 = @store.Store::new()
  s4.create_project(@common.project("p1", "Persisted"))
  s4.save_as(path).unwrap()
  let s5 = @store.Store::load_from(path).unwrap()
  assert_eq(s5.get_project("p1").unwrap().name, "Persisted")
  try {
    @fs.remove_file(path)
  } catch {
    _ => ()
  }
  println("[5] persistence round-trip ... ok")

  // 6. AI: mock provider generates a design tree from a prompt
  let req = @ai.gen_request(
    "landing page with 3 cards and a button", 800.0, 600.0, "Landing",
  )
  let mres = @ai.MockProvider::new().gen(req)
  assert_eq(mres.project.files[0].pages[0].shapes.length(), 5)
  println("[6] ai mock generate ... ok")

  // 7. AI: render the design to standalone HTML/CSS
  let html = @ai.render_html(mres.project)
  assert_true(html.contains("<!doctype html>"))
  assert_true(html.contains("class=\"shape\""))
  assert_true(html.contains("Landing"))
  println("[7] ai render html ... ok")

  // 8. Skill: flatten + auto-color
  let sk = @common.file(
    "f", "F",
    pages=[ @common.page("p", "P", shapes=[
      @common.shape(
        "o", "O", @common.frame, 100.0, 50.0, 30.0, 30.0,
        children=[ @common.shape("c", "C", @common.rect, 10.0, 10.0, 5.0, 5.0) ],
      ),
    ]) ],
  )
  let flat = @skill.run_skill("flatten", sk).unwrap()
  assert_eq(flat.pages[0].shapes.length(), 2)
  let colored = @skill.run_skill("auto-color", sk).unwrap()
  // first shape is the frame -> emerald
  assert_eq(colored.pages[0].shapes[0].fill, @common.color(16, 185, 129, 1.0))
  println("[8] skill flatten + auto-color ... ok")

  // 9. Skill: tag-all + normalize-names
  let tagged = @skill.tag_all(sk, "v1")
  assert_eq(tagged.pages[0].shapes[0].name, "O #v1")
  let norm = @skill.normalize_names(sk)
  assert_eq(norm.pages[0].shapes[0].name, "shape_0")
  println("[9] skill tag-all + normalize ... ok")

  // 10. KB: build, query and retrieve RAG context
  let docs = [
    @kb.doc("d1", "MoonBit FFI", "MoonBit calls C and JavaScript through extern functions."),
    @kb.doc("d2", "Recipes", "Boil water and cook pasta with salt for ten minutes."),
  ]
  let kb = @kb.build(docs)
  let hits = @kb.query(kb, "MoonBit extern C", 1)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].0.id, "d1")
  let ctx = @kb.retrieve_context(kb, "MoonBit extern C", 1)
  assert_true(ctx.contains("[MoonBit FFI]"))
  println("[10] kb build + query + retrieve ... ok")

  // 11. MCP: JSON-RPC dispatch
  let mstore = @store.Store::new()
  mstore.create_project(@common.project("mp1", "MCP Demo"))
  mstore.put_file("mp1", @common.file("mf1", "MFile")).unwrap()
  let list_req =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"moonpot/list_projects\"}"
  let list_resp = @mcp.handle(mstore, list_req)
  assert_true(list_resp.contains("\"mp1\""))
  let gen_req =
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"moonpot/generate_design\",\"params\":{\"prompt\":\"landing\",\"width\":800,\"height\":600,\"name\":\"L\"}}"
  let gen_resp = @mcp.handle(mstore, gen_req)
  assert_true(gen_resp.contains("\"result\""))
  let bad_req = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"nope\"}"
  let bad_resp = @mcp.handle(mstore, bad_req)
  assert_true(bad_resp.contains("\"error\""))
  println("[11] mcp json-rpc dispatch ... ok")

  // 12. CLI: end-to-end subcommands (isolated temp store + docs file)
  let cpath = "./cli_selftest_tmp.json"
  let dpath = "./cli_docs_tmp.json"
  try {
    @fs.write_string_to_file(
      dpath, "[{\"id\":\"d1\",\"title\":\"MoonBit\",\"body\":\"MoonBit is fast.\"}]",
    )
  } catch {
    _ => ()
  }
  ignore(@cli.run_cli(["moonpot", "init", "--store", cpath]))
  ignore(@cli.run_cli(["moonpot", "new-project", "Demo", "--store", cpath]))
  ignore(
    @cli.run_cli([
      "moonpot", "generate", "landing page", "--name", "L", "--store", cpath,
    ]),
  )
  ignore(
    @cli.run_cli([
      "moonpot", "run-skill", "proj_gen_L", "f1", "flatten", "--store", cpath,
    ]),
  )
  ignore(
    @cli.run_cli([
      "moonpot", "ask", "MoonBit", "--docs-file", dpath, "--topk", "1",
    ]),
  )
  assert_eq(@cli.run_cli(["moonpot", "help"]), 0)
  assert_eq(@cli.run_cli(["moonpot", "bogus"]), 1)
  try {
    @fs.remove_file(cpath)
  } catch {
    _ => ()
  }
  try {
    @fs.remove_file(dpath)
  } catch {
    _ => ()
  }
  println("[12] cli subcommands ... ok")

  // 13. AI boundaries: empty prompt, all-keyword prompt, determinism, tiny canvas
  let empty_res = @ai.MockProvider::new().gen(@ai.gen_request("", 400.0, 300.0, ""))
  assert_eq(empty_res.project.files[0].pages[0].shapes.length(), 3)
  assert_true(empty_res.notes[0].contains("no keywords matched"))
  let all_res = @ai.MockProvider::new().gen(
    @ai.gen_request("landing page button card list image", 1000.0, 800.0, "All"),
  )
  // title + button + 3 cards + 4 list items + image = 10 shapes
  assert_eq(all_res.project.files[0].pages[0].shapes.length(), 10)
  let det1 = @ai.MockProvider::new().gen(@ai.gen_request("landing", 800.0, 600.0, "D"))
  let det2 = @ai.MockProvider::new().gen(@ai.gen_request("landing", 800.0, 600.0, "D"))
  assert_eq(det1.project.to_json().stringify(), det2.project.to_json().stringify())
  assert_eq(det1.notes.length(), det2.notes.length())
  // tiny canvas must not panic (regression: grid_cells used to index out of bounds)
  let tiny = @ai.MockProvider::new().gen(@ai.gen_request("button", 10.0, 20.0, "Tiny"))
  assert_eq(tiny.project.files[0].pages[0].shapes.length(), 1)
  println("[13] ai boundaries + determinism ... ok")

  // 14. MOCK swap: a local FakeProvider implements the same AiProvider trait
  let fake = @ai.generate(FakeProvider::new("t1"), @ai.gen_request("hello", 1.0, 1.0, "FakeN"))
  assert_eq(fake.project.name, "FakeN")
  assert_eq(fake.project.files[0].pages[0].shapes.length(), 1)
  assert_eq(fake.notes[0], "fake:t1")
  assert_true(fake.notes[1].contains("hello"))
  println("[14] fake provider swap ... ok")

  // 15. FAKE data: corrupted snapshots must fail gracefully, CLI must recover
  let bad1 = "./selftest_bad1.json"
  let bad2 = "./selftest_bad2.json"
  try {
    @fs.write_string_to_file(bad1, "not json {{{")
  } catch {
    _ => ()
  }
  try {
    @fs.write_string_to_file(bad2, "[1,2,3]")
  } catch {
    _ => ()
  }
  assert_true(@store.Store::load_from(bad1) is Err(_))
  assert_true(@store.Store::load_from(bad2) is Err(_))
  // CLI recovers from a corrupted snapshot by starting a fresh store
  assert_eq(@cli.run_cli(["moonpot", "new-project", "AfterCrash", "--store", bad1]), 0)
  assert_true(@store.Store::load_from(bad1) is Ok(_))
  try {
    @fs.remove_file(bad1)
  } catch {
    _ => ()
  }
  try {
    @fs.remove_file(bad2)
  } catch {
    _ => ()
  }
  println("[15] fake data resilience ... ok")

  // 16. MCP full method matrix + error codes
  let mst = @store.Store::new()
  mst.create_project(@common.project("mp", "MP"))
  let nested = @common.shape(
    "o", "O", @common.frame, 100.0, 50.0, 30.0, 30.0,
    children=[ @common.shape("c", "C", @common.rect, 10.0, 10.0, 5.0, 5.0) ],
  )
  mst.put_file("mp", @common.file("nf", "Nested", pages=[
    @common.page("p", "P", shapes=[nested]),
  ])).unwrap()
  let miss = @mcp.handle(
    mst,
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"moonpot/read_file\",\"params\":{\"project_id\":\"ghost\",\"file_id\":\"x\"}}",
  )
  assert_true(miss.contains("-32001"))
  let bad_skill = @mcp.handle(
    mst,
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"moonpot/run_skill\",\"params\":{\"project_id\":\"mp\",\"file_id\":\"nf\",\"skill\":\"nope\"}}",
  )
  assert_true(bad_skill.contains("-32002"))
  let parse_err = @mcp.handle(mst, "not json at all")
  assert_true(parse_err.contains("-32700"))
  let no_method = @mcp.handle(mst, "{\"jsonrpc\":\"2.0\",\"id\":3}")
  assert_true(no_method.contains("-32600"))
  let kb_empty = @mcp.handle(
    mst,
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"moonpot/query_kb\",\"params\":{\"docs\":[],\"query\":\"x\",\"top_k\":0}}",
  )
  assert_true(kb_empty.contains("\"result\":\"\""))
  // run_skill via MCP flattens and persists the change
  let flat_req = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"moonpot/run_skill\",\"params\":{\"project_id\":\"mp\",\"file_id\":\"nf\",\"skill\":\"flatten\"}}"
  let flat_resp = @mcp.handle(mst, flat_req)
  assert_true(flat_resp.contains("\"result\""))
  assert_eq(mst.get_file("mp", "nf").unwrap().pages[0].shapes.length(), 2)
  println("[16] mcp method matrix + error codes ... ok")

  // 17. KB edges: empty index, topk 0 / overflow, CJK query, add(), score order
  let kb_empty2 = @kb.build([])
  assert_eq(@kb.query(kb_empty2, "anything", 3).length(), 0)
  assert_eq(@kb.retrieve_context(kb_empty2, "anything", 3), "")
  let kdocs = [
    @kb.doc("d1", "月亮", "月亮在夜空中发光"),
    @kb.doc("d2", "太阳", "太阳在白天照耀大地"),
    @kb.doc("d3", "Recipe", "boil water and add pasta"),
  ]
  let kkb = @kb.build(kdocs)
  assert_eq(@kb.query(kkb, "月亮 发光", 0).length(), 0)
  assert_eq(@kb.query(kkb, "月亮 发光", 100).length(), 3)
  let khits = @kb.query(kkb, "月亮 发光", 2)
  assert_eq(khits[0].0.id, "d1")
  assert_true(khits[0].1 >= khits[1].1)
  let kkb2 = @kb.add(kkb, @kb.doc("d4", "Pasta", "pasta with tomato sauce"))
  assert_eq(@kb.query(kkb2, "pasta sauce", 1)[0].0.id, "d4")
  println("[17] kb edges + cjk ... ok")

  // 18. CLI error paths + help variants
  assert_eq(@cli.run_cli(["moonpot"]), 1)
  assert_eq(@cli.run_cli(["moonpot", "new-project"]), 1)
  assert_eq(@cli.run_cli(["moonpot", "generate"]), 1)
  assert_eq(@cli.run_cli(["moonpot", "run-skill", "p", "f"]), 1)
  assert_eq(@cli.run_cli(["moonpot", "ask"]), 1)
  assert_eq(@cli.run_cli(["moonpot", "-h"]), 0)
  assert_eq(@cli.run_cli(["moonpot", "--help"]), 0)
  println("[18] cli error paths ... ok")

  // 19. Store scale + unicode + deep nesting round-trip
  let big_shapes : Array[@common.Shape] = []
  for i = 0; i < 500; i = i + 1 {
    big_shapes.push(
      @common.shape(
        "s" + i.to_string(), "N" + i.to_string(), @common.rect,
        i.to_double(), 0.0, 10.0, 10.0,
      ),
    )
  }
  let big_store = @store.Store::new()
  big_store.create_project(
    @common.project("big", "设计项目甲", files=[
      @common.file("bf", "画布一", pages=[
        @common.page("bp", "页面一", shapes=big_shapes),
      ]),
    ]),
  )
  let big_path = "./selftest_big.json"
  try {
    @fs.remove_file(big_path)
  } catch {
    _ => ()
  }
  big_store.save_as(big_path).unwrap()
  let big_loaded = @store.Store::load_from(big_path).unwrap()
  let bf = big_loaded.get_file("big", "bf").unwrap()
  assert_eq(bf.pages[0].shapes.length(), 500)
  assert_eq(bf.pages[0].shapes[499].name, "N499")
  assert_eq(big_loaded.get_project("big").unwrap().name, "设计项目甲")
  try {
    @fs.remove_file(big_path)
  } catch {
    _ => ()
  }
  // deep nesting flattens to 3 top-level shapes with accumulated offsets
  let deep = @common.shape(
    "o", "O", @common.frame, 100.0, 50.0, 30.0, 30.0,
    children=[
      @common.shape("m", "M", @common.frame, 10.0, 10.0, 20.0, 20.0,
        children=[ @common.shape("i", "I", @common.rect, 1.0, 1.0, 5.0, 5.0) ]),
    ],
  )
  let flat3 = @skill.run_skill("flatten", @common.file("df", "DF", pages=[
    @common.page("dp", "P", shapes=[deep]),
  ])).unwrap()
  assert_eq(flat3.pages[0].shapes.length(), 3)
  assert_eq(flat3.pages[0].shapes[2].x, 111.0)
  assert_eq(flat3.pages[0].shapes[2].y, 61.0)
  println("[19] store scale + unicode + deep flatten ... ok")

  // 20. Render escaping + full skill chain on a generated design
  let esc_file = @common.file("ef", "EF", pages=[
    @common.page("ep", "P", shapes=[
      @common.shape("es", "a<b>&c", @common.text, 0.0, 0.0, 10.0, 10.0,
        text="a<b>&c"),
    ]),
  ])
  let esc_proj = @common.project("eproj", "EProj", files=[esc_file])
  let esc_html = @ai.render_html(esc_proj)
  assert_true(esc_html.contains("a&lt;b&gt;&amp;c"))
  let chain = @ai.MockProvider::new().gen(
    @ai.gen_request("landing page with 3 cards and a button", 800.0, 600.0, "Chain"),
  )
  let html2 = @ai.render_html(chain.project)
  assert_true(html2.contains("position:absolute"))
  assert_true(html2.contains("rgba("))
  // skill pipeline: auto-color -> flatten -> tag-all -> normalize-names
  let c1 = @skill.run_skill("auto-color", chain.project.files[0]).unwrap()
  let c2 = @skill.run_skill("flatten", c1).unwrap()
  let c3 = @skill.run_skill("tag-all", c2).unwrap()
  let c4 = @skill.run_skill("normalize-names", c3).unwrap()
  assert_eq(c4.pages[0].shapes.length(), 5)
  assert_eq(c4.pages[0].shapes[0].name, "shape_0")
  assert_eq(c4.pages[0].shapes[4].name, "shape_4")
  // shape order: title(text) -> button(rect) -> 3 card frames
  assert_eq(c4.pages[0].shapes[0].fill, @common.color(15, 23, 42, 1.0))
  assert_eq(c4.pages[0].shapes[1].fill, @common.color(99, 102, 241, 1.0))
  assert_eq(c4.pages[0].shapes[2].fill, @common.color(16, 185, 129, 1.0))
  println("[20] render + skill chain ... ok")

  println("ALL STORE + AI + SKILL + KB + MCP + CLI TESTS PASSED")
}
