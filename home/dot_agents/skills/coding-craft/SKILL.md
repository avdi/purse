---
name: coding-craft
description: >
  Avdi's language-agnostic coding preferences: code that explains itself
  through names instead of comments, comments that carry only the why, no dead
  code or debug leftovers, no speculative flexibility, no defense against
  failures nobody has seen, and how to document a data shape or a known defect.
  Use when writing or reviewing code or comments in any language, before adding
  a comment, a parameter, a branch, or a rescue. Ruby specifics live in
  ruby-style.
---

## The stance

Code should explain itself. Prefer more, smaller functions with names that say
the intent over long functions with comments. Prefer the version of the code
that doesn't exist yet over one that handles a case nobody has met. Describe the
design as it is, and leave the past to version control.

## Names over comments

When a comment says *what* a chunk of logic does, first try an extracted,
well-named function or variable.

```ruby
# Bad
# app_alerts is the sole source of this page's notice.
flash_message = current_user.app_alerts(router: self).first

# Good
flash_message = current_user.primary_app_alert(router: self)
```

Keep a comment for the residual *why* no name can hold: a constraint from
outside the code, a surprising choice, a hazard.

A name that is hard to find is a design signal. If the honest description joins
two things ("charge and then release the lock on failure"), the function does
two things. Split them rather than trying synonyms.

### When the why is an ordering constraint

A comment can state "step A must precede step B" but cannot hold the order. The
refactor that breaks it will look like an improvement to whoever reads the code
instead of the comment. Extract a function whose whole reason to exist is the
order, and move **both** steps into it.

```js
// Bad: advisory. The POST's success callback still looks like the natural
// home for the UI update.
// Must run before the POST below.
this.updateUI(messages);
return $.ajax({ type: 'POST', url, data, success, error });

// Good: the order is the function's reason to exist.
updateUIThenSubmitRemoval(messages, data) {
  this.updateUI(messages);
  return this.submitRemovalRequest(data);
}
```

Read the extracted function back: its steps should be at one level of
abstraction. A named call beside a sprawling inline options literal buries the
order, so give the literal its own named function too. State the invariant once,
in the name; don't repeat it in a docstring and an inline "don't move this".

## Comments that earn their place

A comment survives this test: would it still make sense, and still be true, to a
reader six months out who never saw the change?

Cut:

- Narration of a bug, a fix, or how the code used to work.
- Restating what the code makes obvious.
- Prose re-explaining a test's edge case that its name already expresses.
- Review or ticket context ("as discussed", "per review", an issue or PR number,
  an error-tracker ID). The exception is a `TODO` pointing at the ticket for work
  still to be done.
- Justification aimed at an imagined reviewer ("extracted so this is testable",
  "split out per feedback"). Say what the unit is and does; let the code show it
  is decoupled or pure.

### Keep a comment true of the thing it sits on

- **Don't describe an exception the code doesn't make.** If a rule applies
  uniformly, say so, then say what differs about the consequences.
- **Put it on the right declaration.** A function or class comment gives the
  contract callers rely on. A reason for one statement, argument or constant goes
  directly beside it (a retry rationale beside the call that receives the
  retry setting, the sizing reason beside the TTL constant).
- **Don't reach downstream.** "Must be set because the report filters on it"
  implies the report is the only consumer, and goes stale when another appears.

```ruby
# Bad: names one consumer among many
# opt_out must be written even here, because the win-back audience filters on it.
user.update_attribute(:opt_out, true)

# Good: justifies the decision where it's made
# A record that went invalid some other way must still record the suppression.
user.update_attribute(:opt_out, true)
```

### A rejected alternative is not documentation

Document the design that stands. Judge the rhetorical shape, not a word list:
"X, not Y", "actually", and "just" can carry the same review-history argument as
an explicit before/after story. Remove the contrast and check whether the
sentence still explains the current behavior. If a symbol's misleading name
creates the assumption the prose corrects, fix the name.

```ruby
# Bad: most of the sentence is about the alternative
# Half-closes rather than closing outright: a plain close would have discarded
# the bytes already written.
def drop!

# Good
# Half-closes, so bytes already written arrive before the connection ends.
def drop!
```

Keep the contrast only when the alternative is the one a reader will reach for
and the reason it fails is invisible, and then state it as a property of the
current design.

### Name a known defect you are shipping past

Those rules cover prose that narrates. They are not a reason to stay quiet about
behavior that is wrong and out of scope to fix. Say so where the broken branch
is: a `NOTE:` for what it does now, a `TODO:` for what should happen.

```ruby
# NOTE: This emails the identity's address, not the one that was submitted, so
# the requester may still be unable to sign in.
#
# TODO: send to the submitted address, or name the identity address in the mail.
send_instructions! identity
```

State the severity plainly, and pick the structure that makes the defect more
visible, not less.

### Mark a deliberate stopgap

When you write the interim shape of something being migrated away from, add a
`TODO` naming the destination and the issue tracking it. Without it the stopgap
reads as the design and the next reader extends it.

### A data shape worth documenting

If the why is "this value has this shape" (an external API response, a
serialized payload, a heterogeneous column):

- Show a real example, confirmed against the source, scrubbed of secrets and
  personal data, elided to the load-bearing parts.
- Then ask whether the shape wants its own home. A paragraph explaining a hinky
  structure means a small named unit should own the shape, with its examples and
  tests beside it. New knowledge of an external payload goes in the class that
  parses it, not at each call site.

## No dead code, no debug leftovers

Delete commented-out code, unreachable branches, unused helpers and "keep in
case" blocks. History remembers. Before writing "nothing calls this", look past
the obvious call sites: serializers, dashboards, rake tasks, SQL, templates, and
code in other languages reach things in ways a narrow search misses.

Remove debugger calls, focused tests, stray prints and commented-out assertions
before merging.

## Question code that need not exist

A knob with one setting, a parameter every caller passes the same value for, an
adapter with one implementation, a module with one includer, a `case` with one
live branch: each is code someone must read, test and keep true.

```ruby
# Bad: flexible in name only; every caller passes :stripe
def subscription_for(account_holder, payment_processor: :stripe)

# Good: until a second processor is real, the parameter is fiction
def subscription_for(account_holder)
```

The counter-case is a seam the codebase already uses, such as an injected
collaborator with a default, which exists so tests and callers can substitute.
That seam has two real users. A parameter with one doesn't.

A change that is a prerequisite for a *named* follow-up is the exception: design
for the follow-up's stated shape, but don't invent hypothetical ones.

## Let the failure arrive before paying to prevent it

Defensive code for a failure nobody has seen costs as much as defensive code for
one that happens weekly, and buys less: a rescue for an error the call can't
raise, a retry around an operation never seen to fail, a nil guard for a value a
validation already forbids. Each adds a branch nothing exercises.

Where the failure is real, and not handling it costs a user's data, money or
trust, handle it.

When error handling grows to a handful of lines inside an important branch,
extract it into a named helper so the main path stays readable.

## Fewer parameters, more objects

New variation resolves through a value object or collaborator, not another
keyword argument threaded down the stack.

## Words to avoid in your own prose

Describe the actual mechanism instead of reaching for a stand-in. "Gate", for
instance, hides what is blocking what and why; say "the lint step blocks the
commit until it passes". Skip breathless words in comments and copy ("blazingly
fast", "seamlessly", exclamation marks).

## Reviewing a change

Questions to ask of a diff, roughly in order:

1. Could a name replace this comment?
2. Does this comment narrate history, a review, or a rejected alternative?
3. Is anything here dead, or never called?
4. Is any parameter, branch or abstraction serving only one case?
5. Is any rescue or guard defending against something nobody has seen?
6. Did this follow the shape the codebase already uses for this kind of
   variation, or bolt on beside it? A fourth `if provider ==` on a method that
   was clean three branches ago wants an object.
