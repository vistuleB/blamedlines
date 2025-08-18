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

pub fn comments_digest(
  blame: Blame,
) -> String {
  list.index_fold(
    blame.comments,
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

fn truncate_with_suffix_or_pad(
  content: String,
  desired_length: Int,
  truncation_suffix: String,
) -> String {
  let l = string.length(content)
  case l > desired_length {
    True -> string.drop_end(content, l - {desired_length - string.length(truncation_suffix)}) <> truncation_suffix
    False -> content <> spaces(desired_length - l)
  }
}

fn glue_columns_3(
  table_lines: List(#(String, String, String)),
  min_max_col1: #(Int, Int),
  min_max_col2: #(Int, Int),
  truncation_suffix_col1: String,
  truncation_suffix_col2: String,
) -> #(#(Int, Int), List(String)) {
  let #(col1_max, col2_max) = list.fold(
    table_lines,
    #(0, 0),
    fn (acc, tuple) {
      #(
        int.max(acc.0, tuple.0 |> string.length),
        int.max(acc.1, tuple.1 |> string.length),
      )
    }
  )

  let col1_size = int.max(int.min(col1_max, min_max_col1.1), min_max_col1.0)
  let col2_size = int.max(int.min(col2_max, min_max_col2.1), min_max_col2.0)

  let table_lines =
    list.map(
      table_lines,
      fn (tuple) {
        truncate_with_suffix_or_pad(tuple.0, col1_size, truncation_suffix_col1)
        <> truncate_with_suffix_or_pad(tuple.1, col2_size, truncation_suffix_col2)
        <> tuple.2
      }
    )

  #(#(col1_max, col2_max), table_lines)
}

fn pretty_printer_no1_header_lines(
  margin_total_width: Int,
  extra_dashes_for_content: Int,
) -> List(String) {
  [
    string.repeat("-", margin_total_width + extra_dashes_for_content),
    "| Blame" <> string.repeat(" ", margin_total_width - {"| Blame###" |> string.length}) <> "###Content",
    string.repeat("-", margin_total_width + extra_dashes_for_content),
  ]
}

fn pretty_printer_no1_body_lines(
  contents: List(OutputLine),
  banner: String,
) -> #(#(Int, Int), List(String)) {
  let banner = case banner == "" {
    True -> ""
    False -> "(" <> banner <> ")"
  }

  let #(#(cols1, cols2), table_lines) =
    list.map(
      contents,
      fn(c) {#(
        "| " <> banner <> blame_digest(c.blame),
        comments_digest(c.blame),
        "###" <> c.content,
      )},
    )
    |> glue_columns_3(#(43, 43), #(35, 35), "...", "...]")

  #(#(cols1, cols2), table_lines)
}

fn pretty_printer_no1_footer_lines(
  margin_total_width: Int,
  extra_dashes_for_content: Int,
) -> List(String) {
  [
    string.repeat("-", margin_total_width + extra_dashes_for_content),
  ]
}

pub fn output_lines_pretty_printer_no1(
  content: List(OutputLine),
  banner: String,
) -> String {
  let #(#(cols1, cols2), body_lines) =
    pretty_printer_no1_body_lines(content, banner)

  [
    pretty_printer_no1_header_lines(cols1 + cols2, 35),
    body_lines,
    pretty_printer_no1_footer_lines(cols1 + cols2, 35),
  ]
  |> list.flatten
  |> string.join("\n")
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
