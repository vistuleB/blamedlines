import gleam/io
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile.{type FileError}

// this module is in the process of being refactored;
// it contains the type
//
// - Blame
//
// that is the most upstream type of all, and
//
// - InputLine
// - OutputLine
//
// that are separated only for the purpose of user
// semantics & readability (they are the same type); as
// it so happens that conversion from one to the other
// never takes place in the course of a normal
// computation (the possible exception being the serialization
// of a List(InputLine) for the purpose of debugging)

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

pub type InputLine {
  InputLine(
    blame: Blame,
    indent: Int,
    content: String,
  )
}

pub type OutputLine {
  OutputLine(
    blame: Blame,
    indent: Int,
    content: String,
  )
}

// ***************************
// Blame utilities
// ***************************

pub const no_blame = Blame("", 0, 0, [])

pub fn clear_comments(blame: Blame) -> Blame {
  Blame(..blame, comments: [])
}

pub fn prepend_comment(blame: Blame, comment: String) -> Blame {
  Blame(..blame, comments: [comment, ..blame.comments])
}

pub fn append_comment(blame: Blame, comment: String) -> Blame {
  Blame(..blame, comments: list.append(blame.comments, [comment]))
}

pub fn advance(blame: Blame, by: Int) -> Blame {
  Blame(..blame, char_no: blame.char_no + by)
}

pub fn blame_digest(blame: Blame) -> String {
  blame.filename
  <> ":"
  <> ins(blame.line_no)
  <> ":"
  <> ins(blame.char_no)
}

// **************************************************
// String -> List(InputLine) & path -> String -> List(InputLine)
// **************************************************

pub fn string_to_input_lines(
  source: String,
  path: String,
  added_indentation: Int,
) -> List(InputLine) {
  string.split(source, "\n")
  |> list.index_map(
    fn (s, i) {
      let content = string.trim_start(s)
      let indent = len(s) - len(content)
      InputLine(
        blame: Blame(
          filename: path,
          line_no: i + 1,
          char_no: indent,
          comments: [],
        ),
        indent: indent + added_indentation,
        content: content,
      )
    }
  )
}

pub fn read(
  path: String,
  added_indentation: Int,
) -> Result(List(InputLine), FileError) {
  simplifile.read(path)
  |> result.map(string_to_input_lines(_, path, added_indentation))
}

// **************************************************
// OutputLine -> String & List(OutputLine) -> String
// **************************************************

pub fn output_line_to_string(line: OutputLine) -> String {
  spaces(line.indent) <> line.content
}

pub fn output_lines_to_string(lines: List(OutputLine)) -> String {
  lines
  |> list.map(output_line_to_string)
  |> string.join("\n")
}

// **************************************************
// List(OutputLine) pretty-printer (no1)
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
  line: OutputLine,
) -> String {
  blame_digest(line.blame)
}

fn comments_info(
  line: OutputLine,
  truncate_at: Int,
) -> String {
  let comments = list.index_fold(
    line.blame.comments,
    "[",
    fn(acc, comment, i) {
      acc <> case i > 0 {
        True -> ", "
        False -> ""
      }
      <> comment
    }
  )
  <> "]"
  
  let comments = case string.length(comments) > truncate_at {
    False -> comments
    True ->
      string.drop_end(comments, string.length(comments) - truncate_at + 4) <> "...]"
  }
  comments
}

fn max_list_string_length(
  things: List(String),
) -> Int {
  things
  |> list.map(string.length)
  |> list.max(int.compare)
  |> result.unwrap(0)
}

fn pad_to_at_least_and_add(
  things: List(String),
  at_least: Int,
  prefix: String,
  suffix: String,
) -> List(String) {
  let max_length = int.max(at_least, max_list_string_length(things))
  things
  |> list.map(fn(s) {prefix <> pad_to(s, max_length) <> suffix})
}

fn concatenate_columns(col1: List(String), col2: List(String)) -> List(String) {
  let assert True = list.length(col1) == list.length(col2)
  list.map2(col1, col2, fn(c1, c2) { c1 <> c2 })
}

fn output_lines_pretty_printer_no1_header(
  margin_total_width: Int,
  margin_prefix: String,
  margin_suffix: String,
  extra_dashes_for_content: Int,
) -> String {
  string.repeat("-", margin_total_width + extra_dashes_for_content)
  <> "\n"
  <> margin_prefix
  <> "Blame"
  <> string.repeat(" ", margin_total_width - string.length(margin_prefix <> "Blame" <> margin_suffix))
  <> margin_suffix
  <> "Content\n"
  <> string.repeat("-", margin_total_width + extra_dashes_for_content)
}

fn output_lines_pretty_printer_no1_body(
  lines: List(OutputLine),
  margin_part1_annotator: fn(OutputLine) -> String,
  margin_part2_annotator: fn(OutputLine) -> String,
  margin_prefix: String,
  margin_mid: String,
  margin_suffix: String,
) -> #(String, Int) {
  let margin_pt1_column =
    lines
    |> list.map(margin_part1_annotator)
    |> pad_to_at_least_and_add(43, margin_prefix, margin_mid)

  let col1_size = case list.first(margin_pt1_column) {
    Ok(s) -> string.length(s)
    _ -> 0
  }

  let left_for_col2 = 78 - col1_size

  let margin_pt2_column =
    lines
    |> list.map(margin_part2_annotator)
    |> pad_to_at_least_and_add(left_for_col2, "", margin_suffix)

  let margin_column =
    concatenate_columns(margin_pt1_column, margin_pt2_column)

  let contents_column =
    lines
    |> list.map(output_line_to_string)

  let final_content =
    concatenate_columns(margin_column, contents_column)
    |> string.join("\n")

  let margin_total_width =
    margin_column
    |> max_list_string_length
  
  #(final_content, margin_total_width)
}

fn output_lines_pretty_printer_no1_footer(
  margin_total_width: Int,
  extra_dashes_for_content: Int,
) -> String {
  string.repeat("-", margin_total_width + extra_dashes_for_content)
}

pub fn output_lines_pretty_printer_no1(
  lines: List(OutputLine),
  banner: String,
) -> String {
  let prefix = "| "
  let suffix = "###"

  let #(body, margin_total_width) =
    output_lines_pretty_printer_no1_body(
      lines,
      all_but_comments_info,
      comments_info(_, 35),
      case banner == "" {
        True -> prefix
        False -> prefix <> "(" <> banner <> ")"
      },
      " ",
      " " <> suffix,
    )

  let header = 
    output_lines_pretty_printer_no1_header(margin_total_width, prefix, suffix, 20)

  let footer =
    output_lines_pretty_printer_no1_footer(margin_total_width, 20)
  
  {
    header
    <> "\n"
    <> body
    <> "\n"
    <> footer
  }
}

pub fn echo_output_lines(
  lines: List(OutputLine),
  banner: String,
) -> List(OutputLine) {
  lines
  |> output_lines_pretty_printer_no1(banner)
  |> io.println
  lines
}

pub fn input_lines_to_output_lines(
  lines: List(InputLine)
) -> List(OutputLine) {
  lines
  |> list.map(fn(l){OutputLine(l.blame, l.indent, l.content)})
}

pub fn echo_input_lines(
  lines: List(InputLine),
  banner: String,
) -> List(InputLine) {
  lines
  |> input_lines_to_output_lines
  |> output_lines_pretty_printer_no1(banner)
  |> io.println
  lines
}

pub fn main() {
  io.println("Hello from blamedlines!")
}
