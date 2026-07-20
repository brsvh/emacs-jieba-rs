---
name: rust-coding
description: >-
  Write, review, and refactor idiomatic Rust code following community style
  conventions. Use when working with Rust functions, structs, modules, error
  handling, async code, concurrency, unsafe code, API design, memory
  optimization, performance tuning, numeric safety, conversions, serde,
  pattern matching, macros, closures, observability, testing, or common
  anti-patterns. Contains 265 rules across 26 categories prioritized by
  impact.
---

# Rust Coding

Use this skill to produce maintainable, idiomatic, and highly optimized Rust
code. Current for Rust 1.96 (2024 edition).

## Workflow

1. Identify the code's role first: new function, struct, module, error handling,
   async code, unsafe block, API design, optimization, or refactoring.
1. Inspect neighboring `.rs` files for the crate conventions: edition, module
   structure, error handling style, async runtime, dependency choices, and local
   patterns.
1. Keep changes scoped. Preserve existing public APIs, feature flags, and module
   boundaries unless the user asks for a breaking change.
1. Load the relevant rule files from `references/` by category prefix:
   - `own-*` — Ownership & Borrowing (CRITICAL)
   - `err-*` — Error Handling (CRITICAL)
   - `mem-*` — Memory Optimization (CRITICAL)
   - `unsafe-*` — Unsafe Code (CRITICAL)
   - `api-*` — API Design (HIGH)
   - `async-*` — Async/Await (HIGH)
   - `conc-*` — Concurrency (HIGH)
   - `opt-*` — Compiler Optimization (HIGH)
   - `num-*` — Numeric Safety (HIGH)
   - `type-*`, `trait-*`, `conv-*`, `const-*`, `serde-*`, `pat-*`, `macro-*`,
     `closure-*`, `coll-*`, `name-*`, `test-*`, `doc-*`, `obs-*`, `perf-*` —
     Medium priority categories
   - `proj-*`, `lint-*` — Low priority categories
   - `anti-*` — Anti-patterns reference
1. Apply rules by priority: CRITICAL > HIGH > MEDIUM > LOW.
1. Validate with the narrowest useful command before finishing:
   - `cargo check` for type and borrow checking
   - `cargo fmt --check` for formatting
   - `cargo clippy` for linting
   - `cargo test` for test suites
   - `cargo miri test` for crates containing `unsafe` code

## Rule Categories by Priority

| Priority | Category                    | Impact    | Prefix     | Rules |
| -------- | --------------------------- | --------- | ---------- | ----- |
| 1        | Ownership & Borrowing       | CRITICAL  | `own-`     | 12    |
| 2        | Error Handling              | CRITICAL  | `err-`     | 12    |
| 3        | Memory Optimization         | CRITICAL  | `mem-`     | 17    |
| 4        | Unsafe Code                 | CRITICAL  | `unsafe-`  | 7     |
| 5        | API Design                  | HIGH      | `api-`     | 17    |
| 6        | Async/Await                 | HIGH      | `async-`   | 18    |
| 7        | Concurrency                 | HIGH      | `conc-`    | 4     |
| 8        | Compiler Optimization       | HIGH      | `opt-`     | 12    |
| 9        | Numeric & Arithmetic Safety | HIGH      | `num-`     | 5     |
| 10       | Type Safety                 | MEDIUM    | `type-`    | 13    |
| 11       | Trait & Generics Design     | MEDIUM    | `trait-`   | 6     |
| 12       | Conversions                 | MEDIUM    | `conv-`    | 3     |
| 13       | Const & Compile-Time        | MEDIUM    | `const-`   | 4     |
| 14       | Serde                       | MEDIUM    | `serde-`   | 8     |
| 15       | Pattern Matching            | MEDIUM    | `pat-`     | 5     |
| 16       | Macros                      | MEDIUM    | `macro-`   | 8     |
| 17       | Closures                    | MEDIUM    | `closure-` | 5     |
| 18       | Collections                 | MEDIUM    | `coll-`    | 4     |
| 19       | Naming Conventions          | MEDIUM    | `name-`    | 16    |
| 20       | Testing                     | MEDIUM    | `test-`    | 15    |
| 21       | Documentation               | MEDIUM    | `doc-`     | 12    |
| 22       | Observability               | MEDIUM    | `obs-`     | 7     |
| 23       | Performance Patterns        | MEDIUM    | `perf-`    | 13    |
| 24       | Project Structure           | LOW       | `proj-`    | 14    |
| 25       | Clippy & Linting            | LOW       | `lint-`    | 13    |
| 26       | Anti-patterns               | REFERENCE | `anti-`    | 15    |

______________________________________________________________________

## Quick Reference

### 1. Ownership & Borrowing (CRITICAL)

- [`own-borrow-over-clone`](references/own-borrow-over-clone.md) — Prefer `&T`
  borrowing over `.clone()`
- [`own-slice-over-vec`](references/own-slice-over-vec.md) — Accept `&[T]` not
  `&Vec<T>`, `&str` not `&String`
- [`own-cow-conditional`](references/own-cow-conditional.md) — Use `Cow<'a, T>`
  for conditional ownership
- [`own-arc-shared`](references/own-arc-shared.md) — Use `Arc<T>` for
  thread-safe shared ownership
- [`own-rc-single-thread`](references/own-rc-single-thread.md) — Use `Rc<T>` for
  shared ownership in single-threaded contexts
- [`own-refcell-interior`](references/own-refcell-interior.md) — Use
  `RefCell<T>` for interior mutability in single-threaded code
- [`own-mutex-interior`](references/own-mutex-interior.md) — Use `Mutex<T>` for
  interior mutability across threads
- [`own-rwlock-readers`](references/own-rwlock-readers.md) — Use `RwLock<T>`
  when reads significantly outnumber writes
- [`own-copy-small`](references/own-copy-small.md) — Implement `Copy` for small,
  simple types
- [`own-clone-explicit`](references/own-clone-explicit.md) — Use explicit
  `Clone` for types where copying has meaningful cost
- [`own-move-large`](references/own-move-large.md) — Move large types instead of
  copying; use `Box` if moves are expensive
- [`own-lifetime-elision`](references/own-lifetime-elision.md) — Rely on
  lifetime elision rules; add explicit lifetimes only when required

### 2. Error Handling (CRITICAL)

- [`err-thiserror-lib`](references/err-thiserror-lib.md) — Use `thiserror` for
  library error types
- [`err-anyhow-app`](references/err-anyhow-app.md) — Use `anyhow` for
  application error handling
- [`err-result-over-panic`](references/err-result-over-panic.md) — Return
  `Result<T, E>` instead of panicking for recoverable errors
- [`err-context-chain`](references/err-context-chain.md) — Add context with
  `.context()` or `.with_context()`
- [`err-no-unwrap-prod`](references/err-no-unwrap-prod.md) — Avoid `unwrap()` in
  production code; use `?`, `expect()`, or handle errors
- [`err-expect-bugs-only`](references/err-expect-bugs-only.md) — Use `expect()`
  only for invariants that indicate bugs, not user errors
- [`err-question-mark`](references/err-question-mark.md) — Use `?` operator for
  clean propagation
- [`err-from-impl`](references/err-from-impl.md) — Implement `From<E>` for error
  conversions to enable `?` operator
- [`err-source-chain`](references/err-source-chain.md) — Preserve error chains
  with `#[source]` or `source()` method
- [`err-lowercase-msg`](references/err-lowercase-msg.md) — Start error messages
  lowercase, no trailing punctuation
- [`err-doc-errors`](references/err-doc-errors.md) — Document error conditions
  with `# Errors` section in doc comments
- [`err-custom-type`](references/err-custom-type.md) — Define custom error types
  for domain-specific failures

### 3. Memory Optimization (CRITICAL)

- [`mem-with-capacity`](references/mem-with-capacity.md) — Use `with_capacity()`
  when size is known
- [`mem-smallvec`](references/mem-smallvec.md) — Use `SmallVec` for
  usually-small collections
- [`mem-arrayvec`](references/mem-arrayvec.md) — Use `ArrayVec<T, N>` for
  fixed-capacity collections that never heap-allocate
- [`mem-box-large-variant`](references/mem-box-large-variant.md) — Box large
  enum variants to reduce overall enum size
- [`mem-boxed-slice`](references/mem-boxed-slice.md) — Use `Box<[T]>` instead of
  `Vec<T>` for fixed-size heap data
- [`mem-thinvec`](references/mem-thinvec.md) — Use `ThinVec<T>` for nullable
  collections with minimal overhead
- [`mem-clone-from`](references/mem-clone-from.md) — Use `clone_from()` to reuse
  allocations when repeatedly cloning
- [`mem-reuse-collections`](references/mem-reuse-collections.md) — Clear and
  reuse collections instead of creating new ones in loops
- [`mem-avoid-format`](references/mem-avoid-format.md) — Avoid `format!()` when
  string literals work
- [`mem-write-over-format`](references/mem-write-over-format.md) — Use
  `write!()` into existing buffers instead of `format!()` allocations
- [`mem-arena-allocator`](references/mem-arena-allocator.md) — Use arena
  allocators for batch allocations
- [`mem-zero-copy`](references/mem-zero-copy.md) — Use zero-copy patterns with
  slices and `Bytes`
- [`mem-compact-string`](references/mem-compact-string.md) — Use compact string
  types for memory-constrained string storage
- [`mem-smaller-integers`](references/mem-smaller-integers.md) — Use
  appropriately-sized integers to reduce memory footprint
- [`mem-assert-type-size`](references/mem-assert-type-size.md) — Use static
  assertions to guard against accidental type size growth
- [`mem-take-replace`](references/mem-take-replace.md) — Use `mem::take` /
  `mem::replace` to move a value out of a `&mut` without cloning
- [`mem-drop-order`](references/mem-drop-order.md) — Know and control drop
  order: struct fields drop top-to-bottom, locals in reverse

### 4. Unsafe Code (CRITICAL)

- [`unsafe-safety-comment`](references/unsafe-safety-comment.md) — Write a
  `// SAFETY:` comment above every `unsafe` block and a `# Safety` section in
  every `unsafe fn`
- [`unsafe-minimize-scope`](references/unsafe-minimize-scope.md) — Keep `unsafe`
  blocks as small as possible
- [`unsafe-miri-ci`](references/unsafe-miri-ci.md) — Run `cargo miri test` in CI
  for every crate that contains `unsafe` code
- [`unsafe-maybeuninit`](references/unsafe-maybeuninit.md) — Use
  `MaybeUninit<T>` for uninitialized memory; never use `mem::uninitialized()` or
  `mem::zeroed()`
- [`unsafe-extern-block`](references/unsafe-extern-block.md) — In Rust 2024,
  wrap `extern` blocks in `unsafe extern { }`
- [`unsafe-send-sync-manual`](references/unsafe-send-sync-manual.md) — Document
  invariants when manually implementing `Send` or `Sync`
- [`unsafe-no-mangle-unsafe`](references/unsafe-no-mangle-unsafe.md) — Use
  `#[unsafe(no_mangle)]` in Rust 2024

### 5. API Design (HIGH)

- [`api-builder-pattern`](references/api-builder-pattern.md) — Use Builder
  pattern for complex construction
- [`api-builder-must-use`](references/api-builder-must-use.md) — Mark builder
  methods with `#[must_use]`
- [`api-newtype-safety`](references/api-newtype-safety.md) — Use newtypes to
  prevent mixing semantically different values
- [`api-typestate`](references/api-typestate.md) — Use typestate pattern to
  encode state machine invariants in the type system
- [`api-sealed-trait`](references/api-sealed-trait.md) — Use sealed traits to
  prevent external implementations while allowing use
- [`api-extension-trait`](references/api-extension-trait.md) — Use extension
  traits to add methods to external types
- [`api-parse-dont-validate`](references/api-parse-dont-validate.md) — Parse
  into validated types at boundaries
- [`api-impl-into`](references/api-impl-into.md) — Accept `impl Into<T>` for
  flexible APIs, implement `From<T>` for conversions
- [`api-impl-asref`](references/api-impl-asref.md) — Use `AsRef<T>` when you
  only need to borrow the inner data
- [`api-must-use`](references/api-must-use.md) — Mark types and functions with
  `#[must_use]` when ignoring results is likely a bug
- [`api-non-exhaustive`](references/api-non-exhaustive.md) — Use
  `#[non_exhaustive]` on public enums and structs
- [`api-from-not-into`](references/api-from-not-into.md) — Implement `From<T>`,
  not `Into<U>`
- [`api-default-impl`](references/api-default-impl.md) — Implement `Default` for
  types with sensible default values
- [`api-common-traits`](references/api-common-traits.md) — Implement standard
  traits (Debug, Clone, PartialEq, etc.) for public types
- [`api-serde-optional`](references/api-serde-optional.md) — Make serde a
  feature flag, not a hard dependency
- [`api-impl-fromiterator`](references/api-impl-fromiterator.md) — Implement
  `FromIterator`, `Extend`, and `IntoIterator`
- [`api-operator-overload`](references/api-operator-overload.md) — Overload
  operators only when semantics are natural

### 6. Async/Await (HIGH)

- [`async-tokio-runtime`](references/async-tokio-runtime.md) — Configure Tokio
  runtime appropriately
- [`async-no-lock-await`](references/async-no-lock-await.md) — Never hold
  `Mutex`/`RwLock` across `.await`
- [`async-spawn-blocking`](references/async-spawn-blocking.md) — Use
  `spawn_blocking` for CPU-intensive work
- [`async-tokio-fs`](references/async-tokio-fs.md) — Use `tokio::fs` instead of
  `std::fs` in async code
- [`async-cancellation-token`](references/async-cancellation-token.md) — Use
  `CancellationToken` for graceful shutdown
- [`async-join-parallel`](references/async-join-parallel.md) — Use `join!` or
  `try_join!` for concurrent independent futures
- [`async-try-join`](references/async-try-join.md) — Use `try_join!` for
  concurrent fallible operations
- [`async-select-racing`](references/async-select-racing.md) — Use `select!` to
  race futures
- [`async-bounded-channel`](references/async-bounded-channel.md) — Use bounded
  channels for backpressure
- [`async-mpsc-queue`](references/async-mpsc-queue.md) — Use `mpsc` channels for
  async message queues
- [`async-broadcast-pubsub`](references/async-broadcast-pubsub.md) — Use
  `broadcast` channel for pub/sub
- [`async-watch-latest`](references/async-watch-latest.md) — Use `watch` channel
  for sharing the latest value
- [`async-oneshot-response`](references/async-oneshot-response.md) — Use
  `oneshot` channel for request-response
- [`async-joinset-structured`](references/async-joinset-structured.md) — Use
  `JoinSet` for dynamic task collections
- [`async-clone-before-await`](references/async-clone-before-await.md) — Clone
  Arc/Rc before await points
- [`async-fn-in-trait`](references/async-fn-in-trait.md) — Use native `async fn`
  in traits (stable 1.75)
- [`async-async-fn-bounds`](references/async-async-fn-bounds.md) — Use
  `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce` bounds
- [`async-cancel-safety`](references/async-cancel-safety.md) — Ensure
  `tokio::select!` branches are cancellation-safe

### 7. Concurrency (HIGH)

- [`conc-rayon-par-iter`](references/conc-rayon-par-iter.md) — Use rayon's
  `par_iter()` for CPU-bound data parallelism
- [`conc-scoped-threads`](references/conc-scoped-threads.md) — Use
  `std::thread::scope` to borrow stack data across threads
- [`conc-atomic-ordering`](references/conc-atomic-ordering.md) — Use the weakest
  correct memory `Ordering`
- [`conc-thread-local`](references/conc-thread-local.md) — Prefer
  `thread_local!` with `Cell`/`RefCell` over `static mut`

### 8. Compiler Optimization (HIGH)

- [`opt-inline-small`](references/opt-inline-small.md) — Use `#[inline]` for
  small hot functions
- [`opt-inline-always-rare`](references/opt-inline-always-rare.md) — Use
  `#[inline(always)]` sparingly
- [`opt-inline-never-cold`](references/opt-inline-never-cold.md) — Use
  `#[inline(never)]` and `#[cold]` for error paths
- [`opt-cold-unlikely`](references/opt-cold-unlikely.md) — Mark unlikely code
  paths with `#[cold]`
- [`opt-likely-hint`](references/opt-likely-hint.md) — Use code structure to
  hint at likely branches
- [`opt-lto-release`](references/opt-lto-release.md) — Enable LTO in release
  builds
- [`opt-codegen-units`](references/opt-codegen-units.md) — Set
  `codegen-units = 1` in release builds
- [`opt-pgo-profile`](references/opt-pgo-profile.md) — Use Profile-Guided
  Optimization
- [`opt-target-cpu`](references/opt-target-cpu.md) — Use `target-cpu=native` on
  known deployment targets
- [`opt-bounds-check`](references/opt-bounds-check.md) — Eliminate bounds checks
  in hot paths
- [`opt-simd-portable`](references/opt-simd-portable.md) — Use portable SIMD
- [`opt-cache-friendly`](references/opt-cache-friendly.md) — Organize data for
  cache-efficient access

### 9. Numeric & Arithmetic Safety (HIGH)

- [`num-overflow-explicit`](references/num-overflow-explicit.md) — Handle
  integer overflow explicitly
- [`num-cast-try-from`](references/num-cast-try-from.md) — Avoid `as` for
  narrowing casts; use `From`/`TryFrom`
- [`num-float-compare`](references/num-float-compare.md) — Don't compare floats
  with `==`; use a tolerance
- [`num-saturating-clamp`](references/num-saturating-clamp.md) — Bound values
  with `clamp` and saturating arithmetic
- [`num-nonzero`](references/num-nonzero.md) — Use `NonZero*` types to forbid
  zero

### 10. Type Safety (MEDIUM)

- [`type-newtype-ids`](references/type-newtype-ids.md) — Wrap IDs in newtypes
- [`type-newtype-validated`](references/type-newtype-validated.md) — Use
  newtypes to enforce validation
- [`type-enum-states`](references/type-enum-states.md) — Use enums for mutually
  exclusive states
- [`type-option-nullable`](references/type-option-nullable.md) — Use `Option<T>`
  for optional values
- [`type-result-fallible`](references/type-result-fallible.md) — Use
  `Result<T, E>` for fallible operations
- [`type-phantom-marker`](references/type-phantom-marker.md) — Use `PhantomData`
  for type relationships
- [`type-never-diverge`](references/type-never-diverge.md) — Use `!` (never
  type) for non-returning functions
- [`type-generic-bounds`](references/type-generic-bounds.md) — Add trait bounds
  only where needed
- [`type-no-stringly`](references/type-no-stringly.md) — Avoid stringly-typed
  APIs
- [`type-repr-transparent`](references/type-repr-transparent.md) — Use
  `#[repr(transparent)]` for newtypes in FFI
- [`type-deref-coercion`](references/type-deref-coercion.md) — Implement
  `Deref`/`DerefMut` only for smart pointers
- [`type-display-vs-debug`](references/type-display-vs-debug.md) — Use `Display`
  for user-facing output, `Debug` for diagnostics
- [`type-numeric-fmt`](references/type-numeric-fmt.md) — Implement numeric
  formatting traits for newtypes

### 11. Trait & Generics Design (MEDIUM)

- [`trait-associated-type-vs-generic`](references/trait-associated-type-vs-generic.md)
  — Associated type vs generic parameter
- [`trait-blanket-impl`](references/trait-blanket-impl.md) — Use blanket impls
- [`trait-coherence-newtype`](references/trait-coherence-newtype.md) — Respect
  the orphan rule with newtypes
- [`trait-default-methods`](references/trait-default-methods.md) — Define traits
  with required methods and defaulted ones
- [`trait-dyn-vs-generic`](references/trait-dyn-vs-generic.md) — Static vs
  dynamic dispatch
- [`trait-object-safety`](references/trait-object-safety.md) — Keep traits
  dyn-compatible when needed

### 12. Conversions (MEDIUM)

- [`conv-tryfrom-fallible`](references/conv-tryfrom-fallible.md) — Implement
  `TryFrom` for fallible conversions
- [`conv-fromstr-parsing`](references/conv-fromstr-parsing.md) — Implement
  `FromStr` for string parsing
- [`conv-asmut-mutable`](references/conv-asmut-mutable.md) — Accept
  `impl AsMut<T>` for mutable borrowed inputs

### 13. Const & Compile-Time (MEDIUM)

- [`const-block`](references/const-block.md) — Use inline `const { }` blocks
- [`const-fn`](references/const-fn.md) — Make functions `const fn`
- [`const-generics`](references/const-generics.md) — Use const generics
- [`const-vs-static`](references/const-vs-static.md) — `const` vs `static`

### 14. Serde (MEDIUM)

- [`serde-rename-all`](references/serde-rename-all.md) — Match naming
  conventions with `#[serde(rename_all = ...)]`
- [`serde-default-compat`](references/serde-default-compat.md) — Use
  `#[serde(default)]` for optional fields
- [`serde-skip-empty`](references/serde-skip-empty.md) — Omit empty fields with
  `skip_serializing_if`
- [`serde-flatten`](references/serde-flatten.md) — Inline nested structs with
  `#[serde(flatten)]`
- [`serde-enum-representation`](references/serde-enum-representation.md) —
  Choose enum tagging deliberately
- [`serde-deny-unknown-fields`](references/serde-deny-unknown-fields.md) —
  Reject unexpected keys
- [`serde-custom-with`](references/serde-custom-with.md) — Customize
  (de)serialization
- [`serde-try-from-validate`](references/serde-try-from-validate.md) — Validate
  while deserializing

### 15. Pattern Matching (MEDIUM)

- [`pat-let-else`](references/pat-let-else.md) — Use `let ... else`
- [`pat-matches-macro`](references/pat-matches-macro.md) — Use `matches!()`
- [`pat-if-let-chains`](references/pat-if-let-chains.md) — Use `if let` chains
- [`pat-exhaustive-enum`](references/pat-exhaustive-enum.md) — Match
  exhaustively
- [`pat-at-bindings`](references/pat-at-bindings.md) — Use `@` bindings

### 16. Macros (MEDIUM)

- [`macro-prefer-functions`](references/macro-prefer-functions.md) — Reach for
  macros only when functions/generics can't express it
- [`macro-rules-hygiene`](references/macro-rules-hygiene.md) — Rely on
  `macro_rules!` hygiene
- [`macro-fragment-specifiers`](references/macro-fragment-specifiers.md) —
  Capture with precise fragment specifiers
- [`macro-export-crate-path`](references/macro-export-crate-path.md) — Export
  with `#[macro_export]`
- [`macro-private-helpers`](references/macro-private-helpers.md) — Hide
  macro-generated helpers
- [`macro-proc-two-crate`](references/macro-proc-two-crate.md) — Use dedicated
  proc-macro crate
- [`macro-proc-syn-quote`](references/macro-proc-syn-quote.md) — Build proc
  macros with `syn`/`quote`
- [`macro-proc-error-spans`](references/macro-proc-error-spans.md) — Report
  errors as spanned compile errors

### 17. Closures (MEDIUM)

- [`closure-fn-trait-bounds`](references/closure-fn-trait-bounds.md) — Require
  the least restrictive `Fn` trait
- [`closure-impl-fn-return`](references/closure-impl-fn-return.md) — Return
  closures as `impl Fn`, not `Box<dyn Fn>`
- [`closure-move-capture`](references/closure-move-capture.md) — Use `move` for
  escaping closures
- [`closure-static-vs-dyn`](references/closure-static-vs-dyn.md) — `impl Fn` vs
  `dyn Fn`
- [`closure-disjoint-capture`](references/closure-disjoint-capture.md) — Capture
  only what you use

### 18. Collections (MEDIUM)

- [`coll-binaryheap`](references/coll-binaryheap.md) — Use `BinaryHeap` for
  priority queues
- [`coll-map-choice`](references/coll-map-choice.md) — Pick the right map
  (HashMap/BTreeMap/IndexMap)
- [`coll-seq-choice`](references/coll-seq-choice.md) — Default to `Vec`; use
  `VecDeque` for queue/deque
- [`coll-set-membership`](references/coll-set-membership.md) — Use
  `HashSet`/`BTreeSet` for membership tests

### 19. Naming Conventions (MEDIUM)

- [`name-types-camel`](references/name-types-camel.md) — `UpperCamelCase` for
  types and traits
- [`name-variants-camel`](references/name-variants-camel.md) — `UpperCamelCase`
  for enum variants
- [`name-funcs-snake`](references/name-funcs-snake.md) — `snake_case` for
  functions and variables
- [`name-consts-screaming`](references/name-consts-screaming.md) —
  `SCREAMING_SNAKE_CASE` for constants
- [`name-lifetime-short`](references/name-lifetime-short.md) — Short lifetime
  names: `'a`, `'b`
- [`name-type-param-single`](references/name-type-param-single.md) — Single
  letters for type parameters
- [`name-as-free`](references/name-as-free.md) — `as_` prefix for reference
  conversions
- [`name-to-expensive`](references/name-to-expensive.md) — `to_` prefix for
  expensive conversions
- [`name-into-ownership`](references/name-into-ownership.md) — `into_` prefix
  for ownership-consuming conversions
- [`name-no-get-prefix`](references/name-no-get-prefix.md) — Omit `get_` prefix
  for simple getters
- [`name-is-has-bool`](references/name-is-has-bool.md) — `is_`/`has_` for
  boolean methods
- [`name-iter-convention`](references/name-iter-convention.md) —
  `iter`/`iter_mut`/`into_iter`
- [`name-iter-method`](references/name-iter-method.md) — Name iterator methods
  consistently
- [`name-iter-type-match`](references/name-iter-type-match.md) — Name iterator
  types after source method
- [`name-acronym-word`](references/name-acronym-word.md) — Treat acronyms as
  words: `HttpServer`
- [`name-crate-no-rs`](references/name-crate-no-rs.md) — Don't suffix crate
  names with `-rs`

### 20. Testing (MEDIUM)

- [`test-cfg-test-module`](references/test-cfg-test-module.md) — Put unit tests
  in `#[cfg(test)] mod tests { }`
- [`test-use-super`](references/test-use-super.md) — Use `use super::*;` in test
  modules
- [`test-integration-dir`](references/test-integration-dir.md) — Put integration
  tests in `tests/`
- [`test-descriptive-names`](references/test-descriptive-names.md) — Use
  descriptive test names
- [`test-arrange-act-assert`](references/test-arrange-act-assert.md) —
  Arrange-Act-Assert structure
- [`test-proptest-properties`](references/test-proptest-properties.md) — Use
  proptest for property-based testing
- [`test-mockall-mocking`](references/test-mockall-mocking.md) — Use mockall for
  trait mocking
- [`test-mock-traits`](references/test-mock-traits.md) — Use traits for
  dependencies
- [`test-fixture-raii`](references/test-fixture-raii.md) — Use RAII for
  automatic cleanup
- [`test-tokio-async`](references/test-tokio-async.md) — Use `#[tokio::test]`
  for async tests
- [`test-should-panic`](references/test-should-panic.md) — Use `#[should_panic]`
- [`test-criterion-bench`](references/test-criterion-bench.md) — Use `criterion`
  for benchmarking
- [`test-doctest-examples`](references/test-doctest-examples.md) — Keep doc
  examples as executable doctests
- [`test-loom-concurrency`](references/test-loom-concurrency.md) — Use `loom`
  for concurrent code
- [`test-snapshot-testing`](references/test-snapshot-testing.md) — Use snapshot
  testing (insta)

### 21. Documentation (MEDIUM)

- [`doc-all-public`](references/doc-all-public.md) — Document all public items
- [`doc-module-inner`](references/doc-module-inner.md) — Use `//!` for module
  docs
- [`doc-examples-section`](references/doc-examples-section.md) — Include
  `# Examples`
- [`doc-errors-section`](references/doc-errors-section.md) — Include `# Errors`
- [`doc-panics-section`](references/doc-panics-section.md) — Include `# Panics`
- [`doc-safety-section`](references/doc-safety-section.md) — Include `# Safety`
- [`doc-question-mark`](references/doc-question-mark.md) — Use `?` in examples
- [`doc-hidden-setup`](references/doc-hidden-setup.md) — Use `# ` to hide setup
- [`doc-intra-links`](references/doc-intra-links.md) — Use intra-doc links
- [`doc-link-types`](references/doc-link-types.md) — Connect related types and
  functions
- [`doc-cargo-metadata`](references/doc-cargo-metadata.md) — Fill `Cargo.toml`
  metadata
- [`doc-crate-readme`](references/doc-crate-readme.md) — Unify README and crate
  docs

### 22. Observability (MEDIUM)

- [`obs-tracing-over-log`](references/obs-tracing-over-log.md) — Use `tracing`
  instead of `println!`/`log`
- [`obs-library-facade`](references/obs-library-facade.md) — Libraries emit
  through facades, never install subscribers
- [`obs-structured-fields`](references/obs-structured-fields.md) — Record
  structured key-value fields
- [`obs-instrument-spans`](references/obs-instrument-spans.md) — Use
  `#[tracing::instrument]`
- [`obs-levels-filter`](references/obs-levels-filter.md) — Use log levels
  meaningfully
- [`obs-error-chain`](references/obs-error-chain.md) — Log errors with full
  source chain
- [`obs-no-sensitive-data`](references/obs-no-sensitive-data.md) — Never log
  secrets or PII

### 23. Performance Patterns (MEDIUM)

- [`perf-iter-over-index`](references/perf-iter-over-index.md) — Prefer
  iterators over manual indexing
- [`perf-iter-lazy`](references/perf-iter-lazy.md) — Keep iterators lazy
- [`perf-collect-once`](references/perf-collect-once.md) — Don't collect
  intermediate iterators
- [`perf-entry-api`](references/perf-entry-api.md) — Use entry API for
  insert-or-update
- [`perf-drain-reuse`](references/perf-drain-reuse.md) — Use drain to reuse
  allocations
- [`perf-extend-batch`](references/perf-extend-batch.md) — Use extend for batch
  insertions
- [`perf-chain-avoid`](references/perf-chain-avoid.md) — Avoid chain in hot
  loops
- [`perf-collect-into`](references/perf-collect-into.md) — Use collect_into for
  reusing containers
- [`perf-black-box-bench`](references/perf-black-box-bench.md) — Use black_box
  in benchmarks
- [`perf-release-profile`](references/perf-release-profile.md) — Optimize
  release profile
- [`perf-profile-first`](references/perf-profile-first.md) — Profile before
  optimizing
- [`perf-ahash`](references/perf-ahash.md) — Use faster hashers when DoS
  resistance not needed
- [`perf-io-buffering`](references/perf-io-buffering.md) — Wrap `Read`/`Write`
  in `BufReader`/`BufWriter`

### 24. Project Structure (LOW)

- [`proj-lib-main-split`](references/proj-lib-main-split.md) — Keep `main.rs`
  minimal, logic in `lib.rs`
- [`proj-mod-by-feature`](references/proj-mod-by-feature.md) — Organize by
  feature, not type
- [`proj-flat-small`](references/proj-flat-small.md) — Keep small projects flat
- [`proj-mod-rs-dir`](references/proj-mod-rs-dir.md) — Use mod.rs for multi-file
  modules
- [`proj-pub-crate-internal`](references/proj-pub-crate-internal.md) — Use
  `pub(crate)` for internal APIs
- [`proj-pub-super-parent`](references/proj-pub-super-parent.md) — Use
  `pub(super)` for parent-only visibility
- [`proj-pub-use-reexport`](references/proj-pub-use-reexport.md) — Use `pub use`
  for clean public API
- [`proj-prelude-module`](references/proj-prelude-module.md) — Create prelude
  module
- [`proj-bin-dir`](references/proj-bin-dir.md) — Put multiple binaries in
  `src/bin/`
- [`proj-workspace-large`](references/proj-workspace-large.md) — Use workspaces
  for large projects
- [`proj-workspace-deps`](references/proj-workspace-deps.md) — Use workspace
  dependency inheritance
- [`proj-feature-additive`](references/proj-feature-additive.md) — Design
  features to be additive
- [`proj-msrv-declare`](references/proj-msrv-declare.md) — Declare MSRV in
  `Cargo.toml`
- [`proj-build-rs-minimal`](references/proj-build-rs-minimal.md) — Keep
  `build.rs` minimal

### 25. Clippy & Linting (LOW)

- [`lint-deny-correctness`](references/lint-deny-correctness.md) —
  `#![deny(clippy::correctness)]`
- [`lint-warn-suspicious`](references/lint-warn-suspicious.md) — Enable
  `clippy::suspicious`
- [`lint-warn-style`](references/lint-warn-style.md) — Enable `clippy::style`
- [`lint-warn-complexity`](references/lint-warn-complexity.md) — Enable
  `clippy::complexity`
- [`lint-warn-perf`](references/lint-warn-perf.md) — Enable `clippy::perf`
- [`lint-pedantic-selective`](references/lint-pedantic-selective.md) — Enable
  `clippy::pedantic` selectively
- [`lint-missing-docs`](references/lint-missing-docs.md) — Warn on missing docs
- [`lint-unsafe-doc`](references/lint-unsafe-doc.md) — Require docs for unsafe
  blocks
- [`lint-cargo-metadata`](references/lint-cargo-metadata.md) — Enable
  `clippy::cargo`
- [`lint-rustfmt-check`](references/lint-rustfmt-check.md) — Run
  `cargo fmt --check` in CI
- [`lint-workspace-lints`](references/lint-workspace-lints.md) — Configure lints
  at workspace level
- [`lint-cfg-check`](references/lint-cfg-check.md) — Enable `unexpected_cfgs`
- [`lint-clippy-nursery-selected`](references/lint-clippy-nursery-selected.md) —
  Enable high-value nursery lints selectively

### 26. Anti-patterns (REFERENCE)

- [`anti-unwrap-abuse`](references/anti-unwrap-abuse.md) — Don't `.unwrap()` in
  production
- [`anti-expect-lazy`](references/anti-expect-lazy.md) — Don't use expect for
  recoverable errors
- [`anti-clone-excessive`](references/anti-clone-excessive.md) — Don't clone
  when borrowing works
- [`anti-lock-across-await`](references/anti-lock-across-await.md) — Don't hold
  locks across await points
- [`anti-string-for-str`](references/anti-string-for-str.md) — Don't accept
  &String when &str works
- [`anti-vec-for-slice`](references/anti-vec-for-slice.md) — Don't accept
  &Vec\<T> when &[T] works
- [`anti-index-over-iter`](references/anti-index-over-iter.md) — Don't use
  indexing when iterators work
- [`anti-panic-expected`](references/anti-panic-expected.md) — Don't panic on
  recoverable errors
- [`anti-empty-catch`](references/anti-empty-catch.md) — Don't silently ignore
  errors
- [`anti-over-abstraction`](references/anti-over-abstraction.md) — Don't
  over-abstract
- [`anti-premature-optimize`](references/anti-premature-optimize.md) — Don't
  optimize before profiling
- [`anti-type-erasure`](references/anti-type-erasure.md) — Don't use Box\<dyn
  Trait> when impl Trait works
- [`anti-format-hot-path`](references/anti-format-hot-path.md) — Don't use
  format! in hot paths
- [`anti-collect-intermediate`](references/anti-collect-intermediate.md) — Don't
  collect intermediate iterators
- [`anti-stringly-typed`](references/anti-stringly-typed.md) — Don't use strings
  where enums/newtypes provide type safety

______________________________________________________________________

## Rule Application by Task

| Task                      | Primary Categories               |
| ------------------------- | -------------------------------- |
| New function              | `own-`, `err-`, `name-`, `pat-`  |
| New struct/API            | `api-`, `type-`, `conv-`, `doc-` |
| Async code                | `async-`, `own-`                 |
| Concurrency / parallelism | `conc-`, `async-`, `own-`        |
| Unsafe code               | `unsafe-`, `type-`, `test-`      |
| Error handling            | `err-`, `api-`, `pat-`           |
| Type conversions          | `conv-`, `api-`                  |
| Serialization (serde)     | `serde-`, `type-`, `api-`        |
| Numeric / arithmetic      | `num-`, `type-`                  |
| Macros / code generation  | `macro-`, `anti-`                |
| Closures / callbacks      | `closure-`, `type-`              |
| Logging / observability   | `obs-`, `err-`                   |
| Memory optimization       | `mem-`, `own-`, `perf-`          |
| Performance tuning        | `opt-`, `mem-`, `perf-`          |
| Code review               | `anti-`, `lint-`                 |
