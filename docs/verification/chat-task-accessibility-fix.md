# Chat task native accessibility correction

## Observed failure, not a data-loss assumption

Native run 43831489212 on iPhone 16 Plus / iOS 26.1 simulator ran 180 tests:
173 passed, 7 failed, 0 skipped. All three ChatLocalTaskUITests failed before
opening a saved task. The cross-chat test failed finding the Inspect button;
the other two failed finding the records scroll view.

Retained artifact 14210225499, hierarchy attachment
70416D5E-ACC3-45BC-A507-865A90D12FC0.txt, shows both real synthetic records
present after disclosure expansion. The records ScrollView has identifier
`chat.task.list`, not `chat.task.records`; each Inspect/Resume button has the
ancestor `chat.task.card.<id>`, not its own `chat.task.inspect.<id>`.
D130AE38-588D-45F8-817D-2CF30A215512.txt shows the same second-test failure.
Thus the first observed failure is ancestor accessibility identifiers masking
child identifiers, not missing records or failed restoration.

## Change

Move disclosure identifiers to their header Text labels and remove the record
VStack identifier. Keep the actual scroll, evidence, and action identifiers.
Do not change reducer/store, owner guards, task state, test fixtures, or any
original answer/draft/resume/cross-chat assertions. Add an always-retained
expanded hierarchy and a strict records-scroll existence assertion to expose
any remaining native selector problem earlier.

## Evidence and limits

One new Python source-contract test failed before this correction and passes
afterward. Swift frontend syntax parsing and git diff checks pass. This is not
SwiftUI typechecking or proof of native rendering. All three original native
tests must pass in the next parent-owned gate; no CI was dispatched here.
The four other failures in run 43831489212 are outside this scoped correction.
The no-model Resume test still proves rejection and state preservation only,
not successful inference or tool execution.
