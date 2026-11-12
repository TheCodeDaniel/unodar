# Phase 3 pending doc examples

`docs_test` compiles three examples in `docs/` and requires the output shown. Their Phase 3 versions describe
compiler behaviour that does not exist yet, so they wait here and replace the Phase 2 text in the commit whose code
makes them true (`docs/DECISIONS.md`, 2026-11-12). Delete this file when all three have moved.

## `docs/DIAGNOSTICS.md`, E003 example output

Lands with the new E003 wording, in the `cpp()` commit (plan step 5, last construct), since its help points to
`cpp()`. Until then the E003 message keeps listing the API functions.

```text
input.dart:8:3: error[E003]: unknown function 'tone': it is neither declared in this file nor part of the unodar API.
  = help: Declare the function in this file, or call the Arduino function through the escape hatch, e.g. `cpp('tone(8, 440);');`. See docs/SUBSET.md for the unodar API.
```
