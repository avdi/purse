---
name: ruby-style
description: >
  Avdi's Ruby conventions: endless methods, guard clauses, and-chains,
  unit-bearing constant names, naming by failure contract (maybe_/try_/safe_,
  ensure_/require_), pure predicates, no explicit begin/rescue in methods,
  methods over local lambdas, pattern matching, duck typing with try, blocks for
  log messages, builders for structured output, containing metaprogramming, and
  extracting objects instead of single-includer modules or service objects. Use
  when writing or reviewing any Ruby. Language-agnostic comment and naming
  hygiene is in coding-craft.
---

Comment, dead-code and speculative-flexibility rules live in `coding-craft`.
This skill is Ruby idiom. The object-design rules (modules, service objects,
value objects) are in `references/extracting-objects.md`; read it before
extracting a module, writing a `.call` object, or splitting a large class.

## Syntax and layout

**Endless methods** for one-liners, unless there's a syntax conflict or the
parameters are complex:

```ruby
def refresh_path = @refresh_path || helpers.oauth_refresh_path
```

**Inner classes** go at the top of the enclosing class.

**Hash key punning** when keys match variable or method names: `{ name:, email: }`.

**Break long calls** across lines, one argument per line, when near 80
characters.

**Prefix access modifiers at the definition.** `def` returns the method name, so
`private def`, `protected def` and `private_class_method def` work. Don't gather
helpers into a trailing symbol list; it restates every name and drifts. (A bare
`private` followed by plain `def`s is also fine.)

```ruby
# Bad
def self.image_in(part) = ...
private_class_method :image_in

# Good
private_class_method def self.image_in(part) = ...
```

**Vertically align compact `if`/`case` results** so the values form a column:

```ruby
if complete?     then :complete
elsif timed_out? then :proceed
elsif error?     then :error
else                  :loading
end
```

**Branch on a value's class with `case`/`when`**, not an `is_a?` ternary or
modifier-`if` chain.

**Init-then-append** for a unique collection that may be unset:

```ruby
# Bad
session[:ids] = (session[:ids] || []) | [id]

# Good
session[:ids] ||= []
session[:ids]  |= [id]
```

**Never build JSON, XML or HTML with string interpolation.** Use templates,
helpers, `to_json`/`as_json`, serializers or builders.

**Blank line on stdout:** `puts` with no argument.

**Log messages go in a block**, so they aren't built when the level is off:

```ruby
logger.info { "Account[#{id}] payload: #{object.to_json}" }
```

## Constants

Put the unit in the name of a dimensioned constant, and extract bare magic
numbers into one:

```ruby
OPEN_TIMEOUT_SECONDS = 2
MAX_BODY_BYTES       = 256 * 1024
```

A string constant costs the reader a hop. Pay it when the value is arbitrary, mirrors an
external vocabulary that mustn't drift, or is used from more than one file. Skip
it when the value is its own name in another case, used once, beside a method
that says the same word:

```ruby
# Questionable
STATUS_ACTIVE = "active"
def active? = status == STATUS_ACTIVE

# Fine
def active? = status == "active"
```

## Control flow

**Guard clauses:** write simple opening guards as one-line modifier returns.
Express conditional work with the body's structure.

```ruby
def deliver(message)
  return unless message.deliverable?
  ...
end
```

**And-chains for pure retrieval**, when each step may return falsy and the rest
is meaningless without it:

```ruby
def subscription_active?(record)
  sub_id = record.try(:subscription).presence and
    sub = Billing::Subscription.retrieve(sub_id) and
    ACTIVE_STATUSES.include?(sub.status)
end
```

Use `and`/`or` for control flow, never in boolean conditions.

**XOR for mutually exclusive arguments:**

```ruby
raise ArgumentError, "pass either account or mailer" unless account.nil? ^ mailer.nil?
```

**Pattern matching for small membership sets** (3 to 5 short literals; past that
use `include?`):

```ruby
return false unless status in "open" | "draft"
```

Don't join `case/in` patterns with `|` unless they share an outcome:

```ruby
# Bad: claims both are :new
in [nil, _] | [_, nil] then :new

# Good
in [nil, _] then :new
in [_, nil] then :downgrade
```

**Sibling branches read at the same level.** When the branches of one
conditional do the same kind of thing, give each a named call at the same
altitude:

```ruby
if identity
  send_instructions! identity
else
  send_email_not_found_instructions! email
end
```

**Parallel conditionals on one discriminant become one object.** When several
methods each branch over the same cases to return a different facet, those
ladders must be kept in sync by hand. Make one object per case carrying all
the facets, and resolve the case once:

```ruby
# Bad
def imap_server(domain) = if gmail?(domain) then "imap.gmail.com" elsif ... end
def smtp_server(domain) = if gmail?(domain) then "smtp.gmail.com" elsif ... end

# Good
def mail_server_provider
  @mail_server_provider ||=
    provider_by_domain_match || provider_by_mx_lookup || MailServerProvider.null
end
def imap_server = mail_server_provider.imap_server
def smtp_server = mail_server_provider.smtp_server
```

**Duck typing with `try`.** Prefer `try` to `respond_to? &&`. Use `&.` when the
receiver is expected to be the right type or nil; use `try` to permit any type.

```ruby
return false if obj.try(:closed)
```

## Methods, not local lambdas

A lambda in a local variable, only to get call syntax in the same scope, is a
method that hasn't been written. Reserve lambdas for callables that are passed
somewhere. Write them with the stabby literal (`-> { }`, `-> do ... end`); use
`lambda` only where the literal can't parse, and say why.

```ruby
# Bad
copy_into = lambda do |source, dest = source.basename.to_s|
  cp_r source, artifacts_dir / dest if source.exist?
end
copy_into.call Pathname.new("tmp/screenshots")

# Good
def copy_into_artifacts(source, dest = source.basename.to_s)
  return unless source.exist?
  cp_r source, artifacts_dir / dest
end
```

## Naming

**Command-query separation.** A method ending in `?` is pure. A method that
conditionally mutates and returns a boolean is named with a prefix:

```ruby
# Bad
def grant_trial?
  return false unless eligible?
  grant!
  true
end

# Good
def maybe_grant_trial
  return false unless eligible?
  grant!
  true
end
```

**Choose a conditional-action prefix by failure contract, not by the boolean:**

- `maybe_*`: guards eligibility or whether the work is already done. A falsey
  return means the guard declined. Operational failures propagate.
- `try_*`: an attempt that rescues a defined failure and returns falsey. Name or
  document the failures it handles; others propagate.
- `safe_*`: promises protection from a defined failure. Use it only when that
  protection is real and clear to callers.

Don't add a rescue merely to justify a prefix.

**Find-or-make names the object, not its id:**

- `ensure_*` finds or creates.
- `require_*` finds or raises.
- `upsert_*` creates or updates.
- `resolve_*` turns a reference into the object.

A name made awkward by an id suffix (`find_or_open_id`) marks a maker that
returns only an id. Make it return the object; the caller takes `.id`.

**A name containing `_or_` is a red flag** (`emit_or_drop`). It describes the
control flow or a hidden fallback instead of the intent. Name the contract
(`safe_emit`). If no honest contract name exists, the method does two things.

**Separate a domain action from its control-flow wrapper.** When a method's honest
name joins a domain action to a mechanism (cleanup, retry, locking, timing),
extract the mechanism into a block-taking method and leave the action visible at
the call site. Use `do...end` for this wrapper shape, even for one statement,
with the wrapped action on its own line.

```ruby
# Bad
def notify_releasing_claim_on_failure
  user.charge_failed!(charge.failure_message)
rescue StandardError
  release_charge_notice_claim
  raise
end

# Good
releasing_claim_on_failure do
  user.charge_failed!(charge.failure_message)
end

def releasing_claim_on_failure
  yield
rescue StandardError
  release_charge_notice_claim
  raise
end
```

The extraction must keep the failure contract: cleanup must not turn the
original failure into a success.

## No explicit `begin`/`rescue`/`end` in a method

A `begin` in a method body says the method does two things. In order of
preference:

1. Extract the rescued step into its own method and use the method-level
   `rescue`. This also names the step.
2. If it's short and stays inline, drop the `begin`: a `do...end` block takes
   `rescue`/`else`/`ensure` directly. (Not `{ }` blocks.)

```ruby
# Bad
canceled = subscriptions.filter_map {|sub|
  begin
    sub.cancel
  rescue Billing::Error => e
    failures << e
    nil
  end
}

# Good
canceled = subscriptions.filter_map {|sub| try_cancel_subscription(sub, failures:) }

def try_cancel_subscription(sub, failures:)
  sub.cancel
rescue Billing::Error => e
  failures << e
  nil
end

# Good, short and inline
subscriptions.each do |sub|
  sub.cancel
rescue Billing::Error => e
  failures << e
end
```

## Metaprogramming: generate the parameters, not the behavior

A factory returning `Module.new` is worth it when several call sites want the
same wrapper with different arguments. Keep the generated part to those
arguments. Put the behavior in a named module as ordinary methods, and have the
generated module `include` it.

```ruby
module Pausable
  def self.[](paused:, metric:)
    Module.new do
      set_temporary_name "%s[paused: %p, metric: %p]" % [Pausable, paused, metric]

      define_method(:paused?)      { paused.call }
      define_method(:pause_metric) { metric }

      include Pausable
    end
  end

  def perform(...)
    if paused?
      $statsd.increment(pause_metric)
    else
      super
    end
  end
end
```

- Expose the arguments as **public** readers. Prefix the names the mixin injects
  with its own concern (`pause_metric`), since it's mixed into classes it
  doesn't own. The concern's public question stays bare (`paused?`).
- **Label the module** with `set_temporary_name`, so `ancestors` and backtraces
  don't show `#<Module:0x...>`. The name must not look like a constant path.
- **`define_method(:foo, &callable)` re-binds `self`.** Closed-over locals
  survive; implicit-self calls inside the lambda don't. Call the lambda
  instead and it keeps its binding.
- **Forward `...` only to `super`.** A prepended wrapper is generic over the
  wrapped method's signature; its collaborators have their own arity.
- **Decorate a growing protocol with `DelegateClass(SharedBase)`.** A hand-rolled
  forwarder only forwards the methods it was written against, and a verb added
  later silently misses every existing decorator. Declare the protocol once on a
  base class and make each decorator `DelegateClass(Base)`. Ask a layer for a
  capability by name (`store.feature(:erasure)`), never `is_a?`.

```ruby
class Store
  def read(id) = raise(NotImplementedError)
  def feature(name) = nil
end

class Erasing < DelegateClass(Store)
  def feature(name) = name == :erasure ? self : super
end
```

## Rake tasks

A helper shared across tasks goes in a companion module under `lib/tasks/`,
`include`d inside the task namespace, not as lambdas at the top of the `.rake`
file.

## Facts the whole app shares

Derived, app-wide knowledge (the current origin, the default sender, a provider's
issuer list) lives behind one accessor on a config object, not re-derived at each
call site. The second time you write the same derivation, hoist it. An origin
string includes the port whenever it isn't the scheme's default; build it with
`URI(...).to_s` rather than hand-rolling the rule.

## Direction

- Objects over modules with one includer.
- Value objects over parallel `if`/`case` ladders.
- Configuration declared on a config object, not read from `ENV` inline.
