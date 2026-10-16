/// Knowledge base module (MoonBit native).
///
/// A deterministic, zero-dependency retrieval layer:
///   - bilingual tokenization (ASCII words + CJK single chars)
///   - bag-of-words TF vectors over a fixed vocabulary
///   - cosine similarity ranking
///   - `retrieve_context` scaffolding for RAG prompts
///
/// Nothing here is random, so results are reproducible across runs.

/// A retrievable document.
pub struct Doc {
  id : String
  title : String
  body : String
} derive(ToJson, FromJson)

// Explicit ToJson/FromJson extends (silence implicit-promotion deprecation).
pub extend Doc with ToJson::{ to_json }
pub extend Doc with @json.FromJson::{ from_json }

/// Internal (private) scored representation of a document.
struct Entry {
  doc : Doc
  vec : Array[Double]
}

/// Public constructor — record literals are not exported cross-package.
pub fn doc(id : String, title : String, body : String) -> Doc {
  Doc::{ id, title, body }
}

/// A built knowledge base: immutable documents + their vectors.
pub struct KB {
  docs : Array[Doc]
  vocab : Array[String]
  entries : Array[Entry]
}

// --- Tokenization ---------------------------------------------------------

/// True for CJK Unified Ideographs (incl. Extension A).
fn is_cjk(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)
}

/// True for ASCII letters and digits.
fn is_word_char(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 97 && code <= 122) || (code >= 65 && code <= 90) ||
  (code >= 48 && code <= 57)
}

/// Lowercase an ASCII letter in place; leaves other chars untouched.
fn lower_char(c : Char) -> Char {
  let code = c.to_int()
  if code >= 65 && code <= 90 {
    Int::unsafe_to_char(code + 32)
  } else {
    c
  }
}

/// Deterministic bilingual tokenizer.
///   - ASCII letters/digits form lowercase words
///   - each CJK character becomes its own single-character token
///   - all other characters are separators
pub fn tokenize(s : String) -> Array[String] {
  let toks : Array[String] = []
  let mut buf = ""
  for c in s {
    if is_cjk(c) {
      if buf.length() > 0 {
        toks.push(buf)
        buf = ""
      }
      toks.push("\{c}")
    } else if is_word_char(c) {
      buf = buf + "\{lower_char(c)}"
    } else if buf.length() > 0 {
      toks.push(buf)
      buf = ""
    }
  }
  if buf.length() > 0 {
    toks.push(buf)
  }
  toks
}

// --- Vocabulary & vectors -------------------------------------------------

fn contains_str(arr : Array[String], s : String) -> Bool {
  for x in arr {
    if x == s {
      return true
    }
  }
  false
}

fn vocab_index(vocab : Array[String], tok : String) -> Int {
  for i = 0; i < vocab.length(); i = i + 1 {
    if vocab[i] == tok {
      return i
    }
  }
  -1
}

/// Bag-of-words term-frequency vector aligned to `vocab`.
pub fn embed(text : String, vocab : Array[String]) -> Array[Double] {
  let v : Array[Double] = []
  for i = 0; i < vocab.length(); i = i + 1 {
    v.push(0.0)
  }
  for t in tokenize(text) {
    let idx = vocab_index(vocab, t)
    if idx >= 0 {
      v[idx] = v[idx] + 1.0
    }
  }
  v
}

// --- Math helpers (no external deps) --------------------------------------

/// Newton's-method square root (avoids a math-package dependency).
fn sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut g = x
  for i = 0; i < 32; i = i + 1 {
    g = 0.5 * (g + x / g)
  }
  g
}

fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let mut s = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

fn cosine(a : Array[Double], b : Array[Double]) -> Double {
  let na = sqrt(dot(a, a))
  let nb = sqrt(dot(b, b))
  if na == 0.0 || nb == 0.0 {
    return 0.0
  }
  dot(a, b) / (na * nb)
}

// --- Public API -----------------------------------------------------------

/// Build a KB from a set of documents (deterministic vocabulary order).
pub fn build(docs : Array[Doc]) -> KB {
  let vocab : Array[String] = []
  for d in docs {
    let text = d.title + " " + d.body
    for t in tokenize(text) {
      if !contains_str(vocab, t) {
        vocab.push(t)
      }
    }
  }
  let entries : Array[Entry] = []
  for d in docs {
    let text = d.title + " " + d.body
    entries.push({ doc: d, vec: embed(text, vocab) })
  }
  { docs, vocab, entries }
}

/// Add a document and return a fresh KB (vocabulary may grow).
pub fn add(kb : KB, doc : Doc) -> KB {
  let all : Array[Doc] = []
  for d in kb.docs {
    all.push(d)
  }
  all.push(doc)
  build(all)
}

/// Rank documents by cosine similarity to the query, returning top `top_k`.
pub fn query(kb : KB, q : String, top_k : Int) -> Array[(Doc, Double)] {
  let qvec = embed(q, kb.vocab)
  let scored : Array[(Doc, Double)] = []
  for e in kb.entries {
    scored.push((e.doc, cosine(qvec, e.vec)))
  }
  // descending sort by score (manual, dependency-free)
  for i = 0; i < scored.length(); i = i + 1 {
    for j = i + 1; j < scored.length(); j = j + 1 {
      if scored[j].1 > scored[i].1 {
        let tmp = scored[i]
        scored[i] = scored[j]
        scored[j] = tmp
      }
    }
  }
  let k = if top_k < scored.length() { top_k } else { scored.length() }
  let out : Array[(Doc, Double)] = []
  for i = 0; i < k; i = i + 1 {
    out.push(scored[i])
  }
  out
}

fn join_parts(parts : Array[String], sep : String) -> String {
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + sep
    }
    out = out + parts[i]
  }
  out
}

/// Concatenate the top-k documents into a single RAG context block.
pub fn retrieve_context(kb : KB, q : String, top_k : Int) -> String {
  let hits = query(kb, q, top_k)
  let parts : Array[String] = []
  for h in hits {
    parts.push("[" + h.0.title + "]\n" + h.0.body)
  }
  join_parts(parts, "\n\n")
}

// --- Tests ----------------------------------------------------------------

test "tokenize splits ascii words and cjk chars" {
  let t = tokenize("Hello 世界 ABC")
  // hello, 世, 界, abc
  assert_true(contains_str(t, "hello"))
  assert_true(contains_str(t, "世"))
  assert_true(contains_str(t, "界"))
  assert_true(contains_str(t, "abc"))
  assert_eq(t.length(), 4)
}

test "build + query returns the most relevant doc first" {
  let docs = [
    { id: "1", title: "MoonBit basics", body: "MoonBit is a fast programming language for cloud and edge." },
    { id: "2", title: "Cooking pasta", body: "Boil water then add pasta and salt for ten minutes." },
    { id: "3", title: "MoonBit FFI", body: "MoonBit can call C and JavaScript through extern functions." },
  ]
  let kb = build(docs)
  let hits = query(kb, "MoonBit language programming", 2)
  assert_eq(hits.length(), 2)
  // doc 1 should outrank doc 3 because it shares more query terms
  assert_eq(hits[0].0.id, "1")
}

test "retrieve_context joins titles and bodies" {
  let docs = [
    { id: "1", title: "A", body: "alpha content about design systems" },
    { id: "2", title: "B", body: "unrelated text about cooking" },
  ]
  let kb = build(docs)
  let ctx = retrieve_context(kb, "design systems", 1)
  assert_true(ctx.contains("[A]"))
  assert_true(ctx.contains("alpha content"))
  assert_false(ctx.contains("[B]"))
}

test "add grows the knowledge base" {
  let kb0 = build([ { id: "1", title: "x", body: "moonbit" } ])
  let kb1 = add(kb0, { id: "2", title: "y", body: "rust language" })
  assert_eq(kb1.docs.length(), 2)
}
