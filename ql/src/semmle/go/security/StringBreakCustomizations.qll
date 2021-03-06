/**
 * Provides default sources, sinks and sanitizers for reasoning about unsafe-quoting
 * vulnerabilities, as well as extension points for adding your own.
 */

import go

module StringBreak {
  /** A (single or double) quote. */
  class Quote extends string {
    Quote() { this = "'" or this = "\"" }

    /** Gets the type of this quote, either single or double. */
    string getType() { if this = "'" then result = "single" else result = "double" }
  }

  /**
   * A data flow source for unsafe-quoting vulnerabilities.
   */
  abstract class Source extends DataFlow::Node { }

  /**
   * A data flow sink for unsafe-quoting vulnerabilities.
   */
  abstract class Sink extends DataFlow::Node {
    /** Gets the quote character for which this is a sink. */
    abstract Quote getQuote();
  }

  /**
   * A sanitizer for unsafe-quoting vulnerabilities.
   */
  abstract class Sanitizer extends DataFlow::Node {
    /** Gets the quote character for which this is a sanitizer. */
    Quote getQuote() { any() }
  }

  /**
   * A sanitizer guard for unsafe-quoting vulnerabilities.
   */
  abstract class SanitizerGuard extends DataFlow::BarrierGuard { }

  /** Holds if `l` contains a `quote` (either single or double). */
  private predicate containsQuote(StringOps::ConcatenationLeaf l, Quote quote) {
    quote = l.getStringValue().regexpFind("['\"]", _, _)
  }

  /** A call to `json.Marshal`, considered as a taint source for unsafe quoting. */
  class JsonMarshalAsSource extends Source {
    JsonMarshalAsSource() {
      exists(Function jsonMarshal | jsonMarshal.hasQualifiedName("encoding/json", "Marshal") |
        // we are only interested in the first result (the second result is an error)
        this = DataFlow::extractTupleElement(jsonMarshal.getACall(), 0)
      )
    }
  }

  /** A string concatenation with quotes, considered as a taint sink for unsafe quoting. */
  class StringConcatenationAsSink extends Sink {
    Quote quote;

    StringConcatenationAsSink() {
      exists(StringOps::ConcatenationLeaf lf | lf.asNode() = this |
        containsQuote(lf.getPreviousLeaf(), quote) and
        containsQuote(lf.getNextLeaf(), quote)
      )
    }

    override Quote getQuote() { result = quote }
  }

  /** A call to `json.Unmarshal`, considered as a sanitizer for unsafe quoting. */
  class UnmarshalSanitizer extends Sanitizer {
    UnmarshalSanitizer() {
      exists(Function jsonUnmarshal | jsonUnmarshal.hasQualifiedName("encoding/json", "Unmarshal") |
        this = jsonUnmarshal.getACall()
      )
    }
  }

  /**
   * A call to `strings.Replace` or `strings.ReplaceAll`, considered as a sanitizer
   * for unsafe quoting.
   */
  class ReplaceSanitizer extends Sanitizer {
    Quote quote;

    ReplaceSanitizer() {
      exists(string name, DataFlow::CallNode call |
        this = call and
        call.getTarget().hasQualifiedName("strings", name) and
        call.getArgument(2).getStringValue().matches("%" + quote + "%")
      |
        name = "Replace" and
        call.getArgument(3).getNumericValue() < 0
        or
        name = "ReplaceAll"
      )
    }

    override Quote getQuote() { result = quote }
  }
}
