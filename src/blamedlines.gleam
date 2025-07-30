import gleam/io
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile.{type FileError}

// this module contains the two must 'upstream' types,
// that are dissociated from any particular format
//
// - Blame
// - BlamedLine
//
// note that List(BlamedLine) is used as the primary
// intermediary data format when either serializing or 
// deserializing Writerly or VXML, but does not concern
// the average user

const ins = string.inspect
const len = string.length

pub type Blame {
  Blame(
    filename: String,
    line_no: Int,
    char_no: Int,
    comments: List(String),
  )
}

pub type BlamedLine {
  BlamedLine(
    blame: Blame,
    indent: Int,      // does not necessarily coincide with blame.char_no as individual files find themselves embedded with an added indentation inside the final source -- this value here is the "final indentation" of the embedded content, whereas blame.char_no will refer to the original column number of the content as it found in the original source file containing that content 
    suffix: String,
  )
}

// ***************************
// Blame utilities
// ***************************

pub fn clear_comments(blame: Blame) -> Blame {
  Blame(..blame, comments: [])
}

pub fn prepend_comment(blame: Blame, comment: String) -> Blame {
  Blame(..blame, comments: [comment, ..blame.comments])
}

pub fn append_comment(blame: Blame, comment: String) -> Blame {
  Blame(..blame, comments: list.append(blame.comments, [comment]))
}

pub fn no_blame() -> Blame {
  Blame("", 0, 0, [])
}

// ***************************
// BlamedLine utilities
// ***************************

pub fn filename_of_first_blame(
  blamed_lines: List(BlamedLine)
) -> Result(String, Nil) {
  case blamed_lines {
    [first, ..] -> Ok(first.blame.filename)
    _ -> Error(Nil)
  }
}

// **************************************************
// creating List(BlamedLine) from file contents or filenames
// **************************************************

pub fn string_to_blamed_lines(
  source: String,
  file: String,
  added_indentation: Int,
) -> List(BlamedLine) {
  string.split(source, "\n")
  |> list.index_map(
    fn (s, i) {
      let suffix = string.trim_start(s)
      let indent = len(s) - len(suffix)
      BlamedLine(
        blame: Blame(
          filename: file,
          line_no: i + 1,
          char_no: indent,
          comments: [],
        ),
        indent: indent + added_indentation,
        suffix: suffix,
      )
    }
  )
}

pub fn path_to_blamed_lines(
  file: String,
  added_indentation: Int,
) -> Result(List(BlamedLine), FileError) {
  simplifile.read(file)
  |> result.map(string_to_blamed_lines(_, file, added_indentation))
}

// **************************************************
// BlamedLine -> String & List(BlamedLine) -> String
// **************************************************

pub fn blamed_line_to_string(bic: BlamedLine) -> String {
  spaces(bic.indent) <> bic.suffix
}

pub fn blamed_lines_to_string(lines: List(BlamedLine)) -> String {
  lines
  |> list.map(blamed_line_to_string)
  |> string.join("\n")
}

// **************************************************
// List(BlamedLine) pretty-printer (no1)
// **************************************************

fn spaces(i: Int) -> String {
  string.repeat(" ", i)
}

fn pad_to(
  thing: String,
  length: Int,
) -> String {
  thing
  <> spaces(length - string.length(thing))
}

fn all_but_comments_info(
  bic: BlamedLine,
) -> String {
  bic.blame.filename
  <> ":"
  <> ins(bic.blame.line_no)
  <> ":"
  <> ins(bic.blame.char_no)
  <> " :i"
  <> ins(bic.indent)
}

fn comments_info(
  bic: BlamedLine,
  truncate_at: Int,
) -> String {
  let comments = ins(bic.blame.comments)
  let comments = case string.length(comments) > truncate_at {
    False -> comments
    True ->
      string.drop_end(comments, string.length(comments) - truncate_at + 4) <> "...]"
  }
  comments
}

fn pad_to_max_length_and_add(
  things: List(String),
  prefix: String,
  suffix: String,
) -> List(String) {
  let max_length =
    things
    |> list.map(string.length)
    |> list.max(int.compare)
    |> result.unwrap(0)

  things
  |> list.map(fn(s) {
    prefix <> pad_to(s, max_length) <> suffix
  })
}

fn concatenate_columns(col1: List(String), col2: List(String)) -> List(String) {
  let assert True = list.length(col1) == list.length(col2)
  list.map2(col1, col2, fn(c1, c2) { c1 <> c2 })
}

fn blamed_lines_pretty_printer_no1_header(
  margin_total_width: Int,
  margin_suffix: String,
  margin_prefix: String,
  extra_dashes_for_content: Int,
) -> String {
  string.repeat("-", margin_total_width + extra_dashes_for_content)
  <> "\n"
  <> margin_prefix
  <> "Blame"
  <> string.repeat(" ", margin_total_width - string.length(margin_prefix <> "Blame" <> margin_suffix))
  <> margin_suffix
  <> "###Content\n"
  <> string.repeat("-", margin_total_width + extra_dashes_for_content)
}

fn blamed_lines_pretty_printer_no1_body(
  blamed_lines: List(BlamedLine),
  margin_part1_annotator: fn(BlamedLine) -> String,
  margin_part2_annotator: fn(BlamedLine) -> String,
  margin_prefix: String,
  margin_mid: String,
  margin_suffix: String,
) -> #(String, Int) {
  let margin_pt1_column =
    blamed_lines
    |> list.map(margin_part1_annotator)
    |> pad_to_max_length_and_add(margin_prefix, margin_mid)

  let margin_pt2_column =
    blamed_lines
    |> list.map(margin_part2_annotator)
    |> pad_to_max_length_and_add("", margin_suffix)

  let margin_column =
    concatenate_columns(margin_pt1_column, margin_pt2_column)

  let contents_column =
    blamed_lines
    |> list.map(blamed_line_to_string)

  let final_content =
    concatenate_columns(margin_column, contents_column)
    |> string.join("\n")

  let margin_total_width =
    margin_column
    |> list.map(string.length)
    |> list.max(int.compare)
    |> result.unwrap(0)
  
  #(final_content, margin_total_width)
}

fn blamed_lines_pretty_printer_no1_footer(
  margin_total_width: Int,
  extra_dashes_for_content: Int,
) -> String {
  string.repeat("-", margin_total_width + extra_dashes_for_content)
}

pub fn blamed_lines_pretty_printer_no1(
  lines: List(BlamedLine),
  banner: String,
) -> String {
  let prefix = "| "
  let suffix = "###"

  let #(body, margin_total_width) =
    blamed_lines_pretty_printer_no1_body(
      lines,
      all_but_comments_info,
      comments_info(_, 35),
      prefix <> "(" <> banner <> ")",
      " ",
      " " <> suffix,
    )

  let header = 
    blamed_lines_pretty_printer_no1_header(margin_total_width, prefix, suffix, 20)

  let footer =
    blamed_lines_pretty_printer_no1_footer(margin_total_width, 20)
  
  {
    header
    <> "\n"
    <> body
    <> "\n"
    <> footer
  }
}

pub fn main() {
  io.println("Hello from blamedlines!")
}
