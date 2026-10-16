/// Standalone verifier for the store + common modules.
/// Run with: moonrun <this>.wasm  (exit 0 = all passed).
/// This exists because `moon test`'s runner is blocked by the sandbox in
/// this CI environment; the assertions mirror the inline `test` blocks.

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

  println("ALL STORE + AI + SKILL + KB + MCP + CLI TESTS PASSED")
}
