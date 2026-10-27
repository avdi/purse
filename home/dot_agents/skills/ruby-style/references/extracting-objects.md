# Extracting objects instead of modules and service objects

Read this before extracting a module, writing an object with only `.call`, or
splitting a class that hit a size limit.

## A module with one includer is a class in disguise

Moving methods into a module that one class includes leaves the class exactly as
large: the same behavior, the same state it reaches into, spread over two files.
It hides the class's size from the linter and the reader. Never use it to get a
class under a size or complexity limit.

Find the abstraction and give it an object the class uses.

```ruby
# Bad: one includer. VisionPass is as big as before, and the module reads
# @page and whatever else VisionPass holds.
module ReaderNameReading
  def reader_name = normalize(name_candidates.first)
  def name_candidates = @page.header_lines.select { |line| name_like?(line) }
end

class VisionPass
  include ReaderNameReading
end

# Good: the abstraction is named, owns its state, and can be tested alone.
class ReaderName
  def initialize(page) = @page = page
  def value = normalize(candidates.first)

  private

  def candidates = @page.header_lines.select { |line| name_like?(line) }
end

class VisionPass
  def reader_name = ReaderName.new(@page).value
end
```

If the abstraction isn't obvious, don't settle for the nearest seam; a module
cut along whatever line was convenient is how these get made. Ask an **oracle**:
someone with more to give the question than you have right now. That's the
human who owns the code, or a more capable agent whose whole job is this one
question. Hand over the class, the limit it hit, and what you tried, and ask what
the class is really made of.

### Archetypes to try the abstraction against

Each comes with the tell that a module's methods are really one of them.

| Archetype | Tell |
|---|---|
| **Algorithm object.** Attributes are the inputs; `call` returns the result. No I/O, no mutating inputs; a table of cases tests it. | Methods all compute from the same few ivars toward one answer. |
| **Value object.** Immutable, equal by attributes, owns the operations on that data. | The same group of arguments or ivars travels through several methods. |
| **Strategy or policy.** One question, several interchangeable answers, chosen by case and injected. | A `case`/`if` ladder on one discriminant repeated through the module. |
| **Parser or reader.** Turns raw input into a validated value and owns every way that can fail. | Methods named `extract_`, `normalize_`, `candidates_`, all on one blob. |
| **Query object.** Composes a query and returns a relation or list; owns the filters and order. | Scope-building helpers chained inside the class. |
| **Presenter or view model.** Shapes one thing for one audience; no business rules. | Formatting and label helpers. |
| **Builder or assembler.** Gathers parts into a composite so the caller never sees the order. | A long method setting up many collaborators before the real work. |
| **Null object.** The nothing case behaving like the something case. | `nil` checks on one collaborator scattered through the module. |
| **Process object.** One run of a multi-step, non-transactional task that remembers how far it got, records effects it has handed over so a retry can't repeat them, and separates a recoverable snag from a terminal failure. | A status column several classes write; "already did this" flags guarding a double charge; retry logic guessing which errors are permanent; methods that must be called in a fixed order. |

This list is for asking "what is this class made of?". It isn't a menu; an
abstraction that fits none of these can still be right.

## A module earns its place by a shared role

A module is for behavior that belongs to no one class: several classes include
it and it adds a role they each play (`Comparable`, a `Trackable` concern), or
it's a published extension point. Count the includers (`include`, `prepend` and
`extend` of the name). One includer: extract an object. Two includers sharing a
few helpers and no role: that's a shared object with two callers.

### A mixin standing in for constructor arguments

Use a mixin only when the behavior needs the including class's identity: its
other methods or instance state. If all it needs is a few values the caller
already has, those are constructor arguments and this is a collaborator object.
The class builds one and delegates, with `Forwardable`.

```ruby
# Bad: a mixin standing in for arguments
module BacklogReport
  def waiting = ... # calls `title`, `base_scope`, `refinements`, which the
                    # including class is expected to define
end

# Good
class BacklogReport
  def initialize(title:, base_scope:, refinements:) = ...
end

class LifecycleEmailBacklog
  extend Forwardable
  def_delegators :backlog_report, :waiting, :report_lines

  def backlog_report
    @backlog_report ||= BacklogReport.new(title:, base_scope: User.all, refinements:)
  end
end
```

A standalone object is also testable on its own; a mixin's behavior is usually
reachable, and so tested, only through whatever includes it.

## A module that namespaces one function is the same smell, milder

A module of `def self.` methods, private helpers and constants around one public
function is more honest than a single-includer mixin, but it's still a function
object nobody built. With no instance, the helpers pass the same value to each
other as arguments, and `private_class_method` plus a comment stand in for
encapsulation.

```ruby
# Bad: a namespace; `parsed` is threaded by hand
module AnswerReading
  def self.canonical_items(text)
    consumed_keys_only(JSON.parse(text.strip.gsub(FENCE, "")))
  end

  def self.consumed_keys_only(parsed)
    return parsed unless parsed.is_a?(Array)
    parsed.map { |item| item.is_a?(Hash) ? item.slice(*CANONICAL_KEYS) : item }
  end
  private_class_method :consumed_keys_only
end

# Good: the input is an attribute; the helpers read it
class AnswerReading
  def initialize(text) = @text = text

  def canonical_items
    return parsed unless parsed.is_a?(Array)
    parsed.map { |item| consumed_keys_only(item) }
  end

  private

  def parsed = @parsed ||= JSON.parse(@text.strip.gsub(FENCE, ""))

  def consumed_keys_only(item)
    item.is_a?(Hash) ? item.slice(*CANONICAL_KEYS) : item
  end
end
```

A module of independent stateless utilities that share no input and no
vocabulary is not this smell. Declare those with `module_function` (callable as
`MimeParts.images(mail)` or by `include` and bare call), not `def self.`.

## No service objects

A module or class whose only public method is `.call`, `.execute`, `.perform` or
`.run`, or restates the module's own name (`ThingDoer.do_thing`), is a service
object. Don't write one. Build the object that owns the input (above), put the
behavior on the model that owns the data, or make it a process object if it's a
process. Name functions for what they answer (`MimeParts.images`,
`MimeParts.calendars`), not for "doing" the module.

## Extract emergent concepts into value objects

Before writing a helper function or a verb-shaped object, ask what the result is
a ___ of. If the result has a name you'd say aloud ("a privacy digest"), make
that the class and build it from its input: the instance is the concept
(`PrivacyDigest.new(value)` with `to_s`, `==`, `absent?`), not
`PrivacyDigest.new(value).digest`, and not a function. The names of variables
that hold a helper's result are the clue; they are concepts waiting for a class.

```ruby
# Bad: concepts without classes
late_arrivals = rows.references(in_flight)
salvaged      = TruncatedArraySalvage.new(text).json

# Good
salvaged = SalvagedArray.new(text)   # to_s, empty?; the scanning loop is internal
```

### A value constructs itself

A class method on the value is its named constructor. A second class that exists
only to compute the value is a service object; move its body onto the value.
`Data.define` is open to methods for this reason.

```ruby
# Bad
FeedbackStats.new(window:).call   # returns a FeedbackStats::Result

# Good
FeedbackStats = Data.define(:count, :mean) do
  def self.over(window) = ...
end
FeedbackStats.over(window)
```

### Name a class `...Scanner` only when something steps it

`next`, `each`, `scan_until`, as `StringScanner` does. A calculation that walks
text is a function of its input: model the result (`SalvagedArray`) and keep the
loop as its internals.
