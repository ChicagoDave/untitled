# Session Plan: Headless Core Library (Build Step 1)

**Created**: 2026-06-05
**Overall scope**: Build the UI-free Swift core library — domain model types, block-lifecycle operations, Fountain-for-prose parse/serialize, and `revealProjection` — fully unit-tested on Linux with zero rendering or AppKit/SwiftUI dependencies. This is §13 build step 1 only; the editor shell and display projection are out of scope.
**Bounded contexts touched**: N/A — this is foundational infrastructure / domain model scaffolding, not a DDD-bounded-context separation. The core is itself the one bounded context for this product.
**Key domain language**: Block, BlockID, ChapterCut, Document (with monotonic nextBlockID), RevealToken, Run, SetPieceKind, PresentationOverride

---

## Phases

### Phase 1: Swift toolchain + SwiftPM package skeleton
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: Infrastructure prerequisite — no domain logic, but nothing else can be built or tested without it.
- **Entry state**: Linux server has no Swift toolchain installed. The repo contains only docs and ADRs; no Swift source files exist.
- **Deliverable**: Swift toolchain installed and on PATH; a SwiftPM library package (`Package.swift` + `Sources/UntitledCore/` + `Tests/UntitledCoreTests/`) that compiles and passes a trivial smoke test (`swift test` exits 0). No AppKit/SwiftUI/Foundation-UI imports — `Foundation` only for `String`/`Data` if needed, or pure Swift. The `.gitignore` excludes `.build/`.
- **Exit state**: `swift build` and `swift test` both succeed. The scaffold is committed. Any future phase can begin by opening a Swift file and writing types.
- **Status**: COMPLETE — Swift 6.2 installed at `~/swift/swift-6.2-RELEASE-ubuntu24.04` (userspace, no sudo; PATH persisted in `~/.bashrc`). `core/` package builds; 1 Swift Testing test green. (session ca5fff, 2026-06-05)

---

### Phase 2: Domain model types
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: The §4 types exactly as specified and refined by ADR-0010 — `Run`, `Block`, `BlockID`, `BlockContent`, `SetPieceKind`, `PresentationOverride`, `TextAlignment`, `ChapterCut`, `Document` (with monotonic `nextBlockID`). Bible and Metadata as minimal stubs sufficient to let `Document` compile.
- **Entry state**: Phase 1 exit state — `swift test` passes on the skeleton.
- **Deliverable**: All §4 types declared in `Sources/UntitledCore/`, compiling with zero warnings. `BlockID` is `Int`; `Block.id` is `let` (immutable); `Document.nextBlockID` is `private(set)` and has a factory method `mutating func mintBlockID() -> BlockID`. Every type and public member has a JSDoc/Swift doc-comment per the documentation standard. A compile-only test confirms all types are visible from the test target. No behavior yet — that is Phase 3.
- **Exit state**: `swift build` succeeds with all §4 types present. `swift test` still passes (compile test). Types committed.
- **Status**: COMPLETE — all §4 types declared across Inline/Block/Structure/Document.swift, 0 build warnings; 2 Swift Testing tests green (assembly + `mintBlockID` mutation). (session ca5fff, 2026-06-05)

---

### Phase 3: Block-lifecycle operations with cut-relocation
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: The four ADR-0010 block-lifecycle rules that keep `ChapterCut` anchors correct during editing: split (Enter mid-block), merge (delete at a boundary), delete (block removed entirely), and same-block-edit (insert/delete before a cut's offset shifts it). These are the highest-risk, most test-worthy operations in the core.
- **Entry state**: Phase 2 exit state — all §4 types compile and are committed.
- **Deliverable**:
  - A `DocumentEditing` module (or extension on `Document`) exposing `splitBlock(id:atOffset:)`, `mergeBlocks(first:second:)`, `deleteBlock(id:)`, and `adjustCutOffset(blockID:delta:pivot:)`.
  - A Behavior Statement produced in the conversation for each operation before tests are written.
  - A behavioral test for every DOES and REJECTS WHEN line in each Behavior Statement — asserting on actual model state after the call, not on return values or mocks.
  - All four ADR-0010 cut-relocation rules exercised: split re-anchors trailing-half cuts to the new block; merge re-anchors retired-block cuts to the survivor at the merge offset; delete relocates anchored cuts to the nearest surviving boundary (or drops if document empties); same-block-edit shifts offsets.
  - Test suite graded GREEN before commit (no RED or YELLOW assertions).
- **Exit state**: `swift test` passes with all lifecycle behavioral tests GREEN. Operations and tests committed. The core correctly maintains cut integrity through any block mutation.
- **Status**: COMPLETE — `splitBlock`/`mergeBlocks`/`deleteBlock`/`adjustCutOffset` in DocumentEditing.swift (+ BlockText.swift helpers); 19 Swift Testing tests GREEN, 0 warnings. mutation-verification run; all 3 flagged gaps (override inheritance, sceneBreak/setPiece last-block branch, rejection state-unmutated) closed. (session ca5fff, 2026-06-05)

---

### Phase 4: Fountain-for-prose parse/serialize and revealProjection
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: The two remaining core capabilities — lossless round-trip between the §4 model and the on-disk plain-text format (prose file + chapter sidecar per ADR-0007), and `revealProjection(_ doc: Document) -> [RevealToken]` as pure plain values (no NSAttributedString, no AppKit).
- **Entry state**: Phase 3 exit state — all lifecycle operations pass tests and are committed.
- **Deliverable**:
  - `parse(proseText: String, sidecar: String?) throws -> Document` and `serialize(_ doc: Document) -> (prose: String, sidecar: String)` in `Sources/UntitledCore/`.
  - Fountain-for-prose syntax handled: paragraphs as plain lines, scene break as `#` or `***` on its own line, set-pieces as fenced blocks (`:::verse … :::`  etc.), italic as `_…_`, block IDs persisted in the sidecar (not the prose), chapter cuts (blockID, offset, title) in the sidecar.
  - Lossless round-trip property: `parse(serialize(doc)) == doc` for any well-formed document — verified by parameterized tests covering each block type and a document with cuts.
  - `revealProjection(_ doc: Document) -> [RevealToken]` — produces the flat sequence of `.text` and `.code` tokens that the reveal pane would render. `RevealToken` is a plain enum with no rendering types.
  - Behavior Statements for `parse`, `serialize`, and `revealProjection` produced in the conversation before tests.
  - Behavioral tests for all DOES and REJECTS WHEN lines: malformed input rejection, lossless round-trip, correct token sequence for each block type (including SetPiece `[line]` codes and `[Chapter]` cut codes), correct REJECTS WHEN for malformed fences or unknown sidecar IDs.
  - Test suite graded GREEN before commit.
- **Exit state**: `swift test` passes with all parse/serialize and revealProjection tests GREEN. The headless core is complete and committed. `displayProjection`, peek/@-bible, chapter-slicing UI, and templates remain unimplemented — this is correct per scope.
- **Status**: COMPLETE — `RevealToken`/`CodeID` (RevealToken.swift), `revealProjection` (Reveal.swift), `serialize`/`parse`/`ParseError` over a JSON sidecar (Storage.swift); 29 Swift Testing tests added (16 storage round-trip/rejection + 13 reveal), 48 total GREEN, 0 warnings. Decision (ADR-0009): explicit inline italic (`Run.italic`) IS a reveal code — `[i]`/`[/i]` chips; a set-piece's *derived* italic produces no chips. (session 54ff60, 2026-06-05)
