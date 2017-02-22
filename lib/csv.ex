defmodule CSV do
  alias CSV.Decoding.Preprocessing
  alias CSV.Decoding.Decoder
  alias CSV.Encoding.Encoder
  alias CSV.EscapeSequenceError
  alias CSV.RowLengthError

  @moduledoc ~S"""
  RFC 4180 compliant CSV parsing and encoding for Elixir. Allows to specify other separators,
  so it could also be named: TSV, but it isn't.
  """

  @doc """
  Decode a stream of comma-separated lines into a table.

  ## Options

  These are the options:

    * `:separator`   – The separator token to use, defaults to `?,`. Must be a codepoint (syntax: ? + (your separator)).
    * `:strip_fields` – When set to true, will strip whitespace from cells. Defaults to false.
    * `:escape_max_lines` – How many lines to maximally aggregate for multiline escapes. Defaults to a 1000.
    * `:num_workers` – The number of parallel operations to run when producing the stream.
    * `:worker_work_ratio` – The available work per worker, defaults to 5. Higher rates will mean more work sharing, but might also lead to work fragmentation slowing down the queues.
    * `:headers`     – When set to `true`, will take the first row of the csv and use it as
      header values.
      When set to a list, will use the given list as header values.
      When set to `false` (default), will use no header values.
      When set to anything but `false`, the resulting rows in the matrix will
      be maps instead of lists.

  ## Examples

  Convert a filestream into a stream of rows:

      iex> \"../test/fixtures/docs.csv\"
      iex> |> Path.expand(__DIR__)
      iex> |> File.stream!
      iex> |> CSV.decode!
      iex> |> Enum.take(2)
      [[\"a\",\"b\",\"c\"], [\"d\",\"e\",\"f\"]]

  Convert a filestream into a stream of rows in order of the given stream:

      iex> \"../test/fixtures/docs.csv\"
      iex> |> Path.expand(__DIR__)
      iex> |> File.stream!
      iex> |> CSV.decode!(num_workers: 1)
      iex> |> Enum.take(2)
      [[\"a\",\"b\",\"c\"], [\"d\",\"e\",\"f\"]]

  Map an existing stream of lines separated by a token to a stream of rows with a header row:

      iex> [\"a;b\",\"c;d\", \"e;f\"]
      iex> |> Stream.map(&(&1))
      iex> |> CSV.decode!(separator: ?;, headers: true)
      iex> |> Enum.take(2)
      [%{\"a\" => \"c\", \"b\" => \"d\"}, %{\"a\" => \"e\", \"b\" => \"f\"}]

  Map an existing stream of lines separated by a token to a stream of rows with a given header row:

      iex> [\"a;b\",\"c;d\", \"e;f\"]
      iex> |> Stream.map(&(&1))
      iex> |> CSV.decode!(separator: ?;, headers: [:x, :y])
      iex> |> Enum.take(2)
      [%{:x => \"a\", :y => \"b\"}, %{:x => \"c\", :y => \"d\"}]

  """

  def decode(stream, options \\ []) do
    stream |> preprocess(options) |> Decoder.decode(options) |> inline_errors!
  end

  def decode!(stream, options \\ []) do
    stream |> preprocess(options) |> Decoder.decode(options) |> raise_errors!
  end

  defp preprocess(stream, options) do
    case options |> Keyword.get(:mode) do
      :codepoints ->
          stream |> Preprocessing.Codepoints.process(options)
      _ ->
          stream |> Preprocessing.Lines.process(options)
    end
  end

  defp raise_errors!(stream) do
    stream |> Stream.map(&yield_or_raise!/1)
  end

  defp yield_or_raise!({ :error, EscapeSequenceError, escape_sequence, index }) do
    raise EscapeSequenceError, escape_sequence: escape_sequence, line: index + 1, escape_max_lines: -1
  end
  defp yield_or_raise!({ :error, mod, message, index }) do
    raise mod, message: message, line: index + 1
  end
  defp yield_or_raise!({ :ok, row }), do: row

  defp inline_errors!(stream) do
    stream |> Stream.map(&yield_or_inline!/1)
  end

  defp yield_or_inline!({ :error, EscapeSequenceError, escape_sequence, index }) do
    { :error, EscapeSequenceError.exception(escape_sequence: escape_sequence, line: index + 1, escape_max_lines: -1).message }
  end
  defp yield_or_inline!({ :error, RowLengthError, actual_length, expected_length, message, index, row}) do
    { :error, RowLengthError.exception(message: message, line: index + 1).message,
      %{
        error_type: RowLengthError,
        actual_length: actual_length,
        expected_length: expected_length,
        line: index,
        row: row
      }
    }
  end
  defp yield_or_inline!({ :error, errormod, message, index}) do
    { :error, errormod.exception(message: message, line: index + 1).message }
  end
  defp yield_or_inline!(value), do: value

  @doc """
  Encode a table stream into a stream of RFC 4180 compliant CSV lines for writing to a file
  or other IO.

  ## Options

  These are the options:

    * `:separator`   – The separator token to use, defaults to `?,`. Must be a codepoint (syntax: ? + (your separator)).
    * `:delimiter`   – The delimiter token to use, defaults to `\\r\\n`. Must be a string.

  ## Examples

  Convert a stream of rows with cells into a stream of lines:

      iex> [~w(a b), ~w(c d)]
      iex> |> CSV.encode
      iex> |> Enum.take(2)
      [\"a,b\\r\\n\", \"c,d\\r\\n\"]

  Convert a stream of rows with cells with escape sequences into a stream of lines:

      iex> [[\"a\\nb\", \"\\tc\"], [\"de\", \"\\tf\\\"\"]]
      iex> |> CSV.encode(separator: ?\\t, delimiter: \"\\n\")
      iex> |> Enum.take(2)
      [\"\\\"a\\\\nb\\\"\\t\\\"\\\\tc\\\"\\n\", \"de\\t\\\"\\\\tf\\\"\\\"\\\"\\n\"]
  """

  def encode(stream, options \\ []) do
    Encoder.encode(stream, options)
  end

end
