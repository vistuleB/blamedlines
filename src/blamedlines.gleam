import gleam/int
import gleam/io
import gleam/list
import gleam/pair
import gleam/result
import gleam/string

const ins = string.inspect

pub type Blame {
  Blame(filename: String, line_no: Int, comments: List(String))
}

pub type BlamedLine {
  BlamedLine(blame: Blame, indent: Int, suffix: String)
}

type MarginAssembler =
  fn(BlamedLine) -> String

type LineNumberAndFilename =
  #(Int, String)

type IndentAndContent =
  #(Int, String)

pub fn clear_comments(blame: Blame) -> Blame {
  Blame(blame.filename, blame.line_no, [])
}

pub fn prepend_comment(blame: Blame, comment: String) -> Blame {
  Blame(blame.filename, blame.line_no, [comment, ..blame.comments])
}

pub fn append_comment(blame: Blame, comment: String) -> Blame {
  Blame(blame.filename, blame.line_no, list.append(blame.comments, [comment]))
}

fn add_consecutive_blames_map_fold(
  state: LineNumberAndFilename,
  line: IndentAndContent,
) -> #(LineNumberAndFilename, BlamedLine) {
  let #(line_number, filename) = state
  let #(indent, content) = line
  #(
    #(line_number + 1, filename),
    BlamedLine(Blame(filename, line_number, []), indent, content),
  )
}

fn add_consecutive_blames(
  pairs: List(IndentAndContent),
  first_line_number_and_filename: LineNumberAndFilename,
) -> List(BlamedLine) {
  list.map_fold(
    pairs,
    first_line_number_and_filename,
    add_consecutive_blames_map_fold,
  )
  |> pair.second
}

pub fn get_indent_and_content(
  line: String,
  extra_indent: Int,
) -> IndentAndContent {
  let content = string.trim_start(line)
  #(string.length(line) - string.length(content) + extra_indent, content)
}

pub fn get_indents_and_contents(
  lines: List(String),
  extra_indent: Int,
) -> List(IndentAndContent) {
  list.map(lines, get_indent_and_content(_, extra_indent))
}

pub fn string_to_blamed_lines_hard_mode(
  source: String,
  filename: String,
  starting_line_number: Int,
  starting_indent: Int,
) -> List(BlamedLine) {
  string.split(source, "\n")
  |> get_indents_and_contents(starting_indent)
  |> add_consecutive_blames(#(starting_line_number, filename))
}

pub fn string_to_blamed_lines_easy_mode(
  source: String,
  filename: String,
) -> List(BlamedLine) {
  string_to_blamed_lines_hard_mode(source, filename, 1, 0)
}

pub const string_to_blamed_lines = string_to_blamed_lines_easy_mode

pub fn blamed_line_to_string(line: BlamedLine) -> String {
  let BlamedLine(_, indent, content) = line
  string.repeat(" ", indent) <> content
}

pub fn blamed_lines_to_string(lines: List(BlamedLine)) -> String {
  lines
  |> list.map(blamed_line_to_string)
  |> string.join("\n")
}

fn max_length(margins: List(String)) -> Int {
  case margins {
    [] -> 0
    [first, ..rest] -> int.max(string.length(first), max_length(rest))
  }
}

fn vanilla_bob_margin_assembler(line: BlamedLine) -> String {
  line.blame.filename <> ":" <> ins(line.blame.line_no)
}

fn jane_sue_margin_assember(line: BlamedLine) -> String {
  let comments = ins(line.blame.comments)
  let comments = case string.length(comments) > 35 {
    False -> comments
    True ->
      string.drop_end(comments, string.length(comments) - 35 + 4) <> "...]"
  }
  comments
}

fn pad_to_and_add(
  thing: String,
  to: Int,
  prefix: String,
  suffix: String,
) -> String {
  prefix <> thing <> { string.repeat(" ", to - string.length(thing)) } <> suffix
}

fn pad_to_max_length_and_add(
  things: List(String),
  prefix: String,
  suffix: String,
) -> List(String) {
  let desired_length = max_length(things)
  things
  |> list.map(pad_to_and_add(_, desired_length, prefix, suffix))
}

fn column_add(col1: List(String), col2: List(String)) -> List(String) {
  let assert True = list.length(col1) == list.length(col2)
  list.map2(col1, col2, fn(c1, c2) { c1 <> c2 })
}

fn left_margins_and_blamed_lines_add(
  margins: List(String),
  lines: List(BlamedLine),
) -> List(String) {
  lines
  |> list.map(blamed_line_to_string)
  |> column_add(margins, _)
}

fn padded_margins2(
  lines: List(BlamedLine),
  margin_prefix: String,
  margin_assembler1: MarginAssembler,
  margin_mid: String,
  margin_assembler2: MarginAssembler,
  margin_suffix: String,
) -> List(String) {
  let margins1 =
    lines
    |> list.map(margin_assembler1)
    |> pad_to_max_length_and_add(margin_prefix, margin_mid)
  let margins2 =
    lines
    |> list.map(margin_assembler2)
    |> pad_to_max_length_and_add("", margin_suffix)
  column_add(margins1, margins2)
}

fn blamed_lines_to_string_left_informed_margin2(
  lines: List(BlamedLine),
  margin_prefix: String,
  margin_assembler1: MarginAssembler,
  margin_mid: String,
  margin_assembler2: MarginAssembler,
  margin_suffix: String,
) -> #(String, Int) {
  let margins =
    padded_margins2(
      lines,
      margin_prefix,
      margin_assembler1,
      margin_mid,
      margin_assembler2,
      margin_suffix,
    )
  #(
    left_margins_and_blamed_lines_add(margins, lines) |> string.join("\n"),
    margins
      |> list.map(string.length)
      |> list.max(int.compare)
      |> result.unwrap(0),
  )
}

fn table_header(pretty_printer_margin: Int) -> String {
  string.repeat("-", pretty_printer_margin + 20)
  <> "\n"
  <> "| Blame"
  <> string.repeat(" ", pretty_printer_margin - string.length("| Blame###"))
  <> "###Content\n"
  <> string.repeat("-", pretty_printer_margin + 20)
  <> "\n"
}

fn table_footer(longest_blame_length: Int) -> String {
  string.repeat("-", longest_blame_length + 20) <> "\n"
}

pub fn blamed_lines_to_table_vanilla_bob_and_jane_sue(
  banner: String,
  lines: List(BlamedLine),
) -> String {
  let #(doc, margin_length) =
    blamed_lines_to_string_left_informed_margin2(
      lines,
      "| " <> banner,
      vanilla_bob_margin_assembler,
      " ",
      jane_sue_margin_assember,
      " ###",
    )
  table_header(margin_length) <> doc <> "\n" <> table_footer(margin_length)
}

pub fn main() {
  io.println("Hello from blamedlines!")
}
