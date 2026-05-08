# Plan: Hermes V1 CDP Adapter

A detailed plan for restoring the JS step-debugger (breakpoints, stepping,
watches, console eval, heap snapshots, sampling profiler) on the
RN 0.79.5 + Hermes V1 stack by writing a small **adapter** that exposes the
old `hermes/inspector/*` API on top of V1's `hermes/cdp/*` API. RN's
inspector-modern code then compiles and works **unchanged**.

## Why an adapter (vs porting)

- **Smaller**: ~300-500 LoC of glue, vs ~370 LoC of substantive rewrites
  spread across ConnectionDemux + Registration + HermesExecutorFactory +
  tests.
- **Localized**: zero changes to RN's `inspector-modern/` source. Future RN
  upgrades that touch that code re-merge cleanly.
- **Reversible**: the adapter is two header files + one cpp file in
  `ReactCommon/hermes/inspector/`. Deleting them and re-disabling
  `HERMES_ENABLE_DEBUGGER` undoes the work.
- **Testable in isolation**: the adapter can be smoke-tested by feeding it
  a CDP `Debugger.enable` JSON and watching for a response.

The cost is one indirection layer at runtime (function call overhead) which
is irrelevant for an interactive debugger.

## File layout

Vendor inside the modified RN tree (so RN's includes resolve):

```
sample79/node_modules/react-native/ReactCommon/hermes/inspector/
├── RuntimeAdapter.h           # NEW (shim)
├── RuntimeAdapter.cpp         # NEW (~20 LoC: dtor + SharedRuntimeAdapter)
└── chrome/
    ├── CDPHandler.h           # NEW (shim)
    └── CDPHandler.cpp         # NEW (~250 LoC: the actual translation)
```

The header paths are exactly what RN's inspector-modern includes today
(`<hermes/inspector/RuntimeAdapter.h>`, `<hermes/inspector/chrome/CDPHandler.h>`),
so consumer code is untouched.

These files should also become a third RN-side patch
(`patches/03-cdp-adapter.patch`) once they stabilize.

## API surface mapping

### Old API surface RN actually uses

From `sdks/hermes/API/hermes/inspector/`:

```cpp
// RuntimeAdapter.h
namespace facebook::hermes::inspector_modern {
  class RuntimeAdapter {
   public:
    virtual ~RuntimeAdapter() = 0;
    virtual HermesRuntime& getRuntime() = 0;
    virtual void tickleJs();   // default no-op
  };
  class SharedRuntimeAdapter : public RuntimeAdapter { ... };
}

// chrome/CDPHandler.h
namespace facebook::hermes::inspector_modern::chrome {
  using CDPMessageCallbackFunction = std::function<void(const std::string&)>;
  using OnUnregisterFunction       = std::function<void()>;

  struct CDPHandlerSessionConfig { bool isRuntimeDomainEnabled{false}; };
  struct CDPHandlerExecutionContextDescription { int32_t id; std::string origin; std::string name; std::optional<std::string> auxData; bool shouldSendNotifications; };

  class CDPHandler {
   public:
    static std::shared_ptr<CDPHandler> create(
        std::unique_ptr<RuntimeAdapter> adapter,
        bool waitForDebugger = false,
        bool processConsoleAPI = true,
        std::shared_ptr<State> state = nullptr,
        const CDPHandlerSessionConfig& sessionConfig = {},
        std::optional<CDPHandlerExecutionContextDescription> ec = std::nullopt);
    // Deprecated overload kept for RN compatibility — same signature + title:
    static std::shared_ptr<CDPHandler> create(
        std::unique_ptr<RuntimeAdapter>, const std::string& title, /* ...same */);
    ~CDPHandler();

    std::string getTitle() const;
    bool registerCallbacks(CDPMessageCallbackFunction, OnUnregisterFunction);
    bool unregisterCallbacks();
    void handle(std::string);
    std::unique_ptr<State> getState();
  };

  struct State {
    struct Private;                      // opaque
    explicit State(std::unique_ptr<Private>);
    ~State();
    Private& get();
  };
}
```

### V1 API we delegate to

From `hermes-android-250829098.0.13-debug.aar` prefab headers:

```cpp
// hermes/cdp/CDPDebugAPI.h
namespace facebook::hermes::cdp {
  class CDPDebugAPI {
   public:
    static std::unique_ptr<CDPDebugAPI> create(
        HermesRuntime& runtime, size_t maxCachedMessages = kMaxCachedConsoleMessages);
    HermesRuntime& runtime();
    debugger::AsyncDebuggerAPI& asyncDebuggerAPI();
    void addConsoleMessage(ConsoleMessage);
    // ...
  };
}

// hermes/cdp/CDPAgent.h
namespace facebook::hermes::cdp {
  using OutboundMessageFunc = std::function<void(const std::string&)>;

  class State { /* opaque, move-only */
   public:
    State();
    explicit State(std::unique_ptr<Private>);
    State(State&&) noexcept;
    State& operator=(State&&) noexcept;
    operator bool() const;
    Private& operator*();
    Private* operator->();
  };

  class CDPAgent {
   public:
    static std::unique_ptr<CDPAgent> create(
        int32_t executionContextID,
        CDPDebugAPI& cdpDebugAPI,
        debugger::EnqueueRuntimeTaskFunc enqueueRuntimeTaskCallback,
        OutboundMessageFunc messageCallback,
        State state = {});
    void handleCommand(std::string json);
    void enableRuntimeDomain();
    void enableDebuggerDomain();
    State getState();
  };
}
```

`debugger::EnqueueRuntimeTaskFunc` lives in `<hermes/AsyncDebuggerAPI.h>` —
need to inspect to confirm its exact signature; expected to be roughly
`std::function<void(std::function<void(HermesRuntime&)>)>` (i.e., "post a
task that will run on the runtime thread").

### Translation table

| Old call | New impl |
|---|---|
| `CDPHandler::create(adapter, ...)` | Stash `adapter`, `title`, `state`, `sessionConfig`, `ecDesc`. Defer real construction until `registerCallbacks` (because we need the message callback to construct CDPAgent). |
| `CDPHandler::create(adapter, title, ...)` (deprecated overload) | Same as above, just stores title. |
| `CDPHandler::registerCallbacks(msg, onUnreg)` | Now we have everything: get/create `CDPDebugAPI` for `adapter.getRuntime()`. Build `EnqueueRuntimeTaskFunc` that calls `adapter.enqueueRuntimeTask(...)` (see "RN-side patches" below). Construct `CDPAgent` with all of it + the converted V1 `State`. If `sessionConfig.isRuntimeDomainEnabled` (or always — see open question), call `agent->enableRuntimeDomain()`. Call `enableDebuggerDomain()` unconditionally to mirror old behavior. Stash `onUnreg`. Return true (no previously registered cb in the lazy-construct path). |
| `CDPHandler::unregisterCallbacks()` | Destroy the agent (`agent_.reset()`). Invoke `onUnreg`. Return true. |
| `CDPHandler::handle(msg)` | `agent_->handleCommand(std::move(msg))`. |
| `CDPHandler::getTitle()` | Return stashed title. |
| `CDPHandler::getState()` | Wrap V1's `State` (move-only) in a `std::unique_ptr<inspector_modern::chrome::State>` whose `Private` holds the V1 `cdp::State` by move. |
| `~CDPHandler` | Destroys `agent_` (releases CDP resources), then `cdpDebugAPI_` reference (refcount-decrement on the per-runtime cache). |
| `RuntimeAdapter::getRuntime()` | Pure virtual, unchanged. |
| `RuntimeAdapter::tickleJs()` | Default no-op, unchanged. (Consumers may still override; we don't call it from the adapter.) |

## Implementation details

### CDPHandler.h (shim)

Should be byte-compatible with consumer expectations. Three things matter:

1. Declare `CDPHandler` with the same `create()` overloads, `registerCallbacks`/`unregisterCallbacks`/`handle`/`getTitle`/`getState`. Hide impl in a `unique_ptr<Impl> impl_`.
2. Declare `State` with the same shape (`struct Private; explicit State(unique_ptr<Private>); ~State(); Private& get();`).
3. Re-export `CDPMessageCallbackFunction`, `OnUnregisterFunction`, `CDPHandlerSessionConfig`, `CDPHandlerExecutionContextDescription`.

Use the same `INSPECTOR_EXPORT` visibility macro (or just `__attribute__((visibility("default")))`).

### CDPHandler.cpp (impl)

Pseudo-code:

```cpp
namespace facebook::hermes::inspector_modern::chrome {

// State::Private wraps a V1 cdp::State (which is move-only).
struct State::Private { hermes::cdp::State v1; };
State::State(std::unique_ptr<Private> p) : privateState_(std::move(p)) {}
State::~State() = default;
Private& State::get() { return *privateState_; }

// ---- One CDPDebugAPI per runtime, refcounted ----
class CDPDebugAPIRegistry {
  struct Entry { std::unique_ptr<hermes::cdp::CDPDebugAPI> api; int refcount; };
  std::mutex mu_;
  std::unordered_map<HermesRuntime*, Entry> map_;
 public:
  hermes::cdp::CDPDebugAPI& acquire(HermesRuntime& rt) {
    std::lock_guard l(mu_);
    auto& e = map_[&rt];
    if (!e.api) e.api = hermes::cdp::CDPDebugAPI::create(rt);
    ++e.refcount;
    return *e.api;
  }
  void release(HermesRuntime& rt) {
    std::lock_guard l(mu_);
    auto it = map_.find(&rt);
    if (it == map_.end()) return;
    if (--it->second.refcount == 0) map_.erase(it);
  }
};
static CDPDebugAPIRegistry& registry() { static CDPDebugAPIRegistry r; return r; }

class CDPHandler::Impl {
 public:
  std::unique_ptr<RuntimeAdapter> adapter;
  std::string title;
  std::shared_ptr<State> initialState;        // old-API state, must be converted
  CDPHandlerSessionConfig sessionConfig;
  std::optional<CDPHandlerExecutionContextDescription> ecDesc;

  // Constructed in registerCallbacks, destroyed in unregisterCallbacks/dtor.
  hermes::cdp::CDPDebugAPI* debugAPI = nullptr;       // borrowed from registry
  std::unique_ptr<hermes::cdp::CDPAgent> agent;
  OnUnregisterFunction onUnregister;

  ~Impl() {
    if (agent) {
      agent.reset();
      registry().release(adapter->getRuntime());
    }
  }
};

std::shared_ptr<CDPHandler> CDPHandler::create(
    std::unique_ptr<RuntimeAdapter> adapter,
    bool /*waitForDebugger*/,            // see open Q1
    bool /*processConsoleAPI*/,          // see open Q2
    std::shared_ptr<State> state,
    const CDPHandlerSessionConfig& sessionConfig,
    std::optional<CDPHandlerExecutionContextDescription> ec) {
  auto h = std::shared_ptr<CDPHandler>(new CDPHandler(...));
  h->impl_->adapter = std::move(adapter);
  h->impl_->initialState = std::move(state);
  h->impl_->sessionConfig = sessionConfig;
  h->impl_->ecDesc = std::move(ec);
  // title stays empty for this overload; the with-title overload sets it.
  return h;
}

bool CDPHandler::registerCallbacks(
    CDPMessageCallbackFunction msgCallback,
    OnUnregisterFunction onUnregister) {
  if (impl_->agent) return false;       // already registered

  HermesRuntime& rt = impl_->adapter->getRuntime();
  impl_->debugAPI = &registry().acquire(rt);

  auto enqueue = [adapterPtr = impl_->adapter.get()](
      std::function<void(HermesRuntime&)> task) {
    adapterPtr->enqueueRuntimeTask(std::move(task));   // see RN-side patch
  };

  hermes::cdp::State v1State;
  if (impl_->initialState && impl_->initialState->get().v1) {
    v1State = std::move(impl_->initialState->get().v1);
  }
  int32_t ecId = impl_->ecDesc ? impl_->ecDesc->id : 1;

  impl_->agent = hermes::cdp::CDPAgent::create(
      ecId, *impl_->debugAPI, std::move(enqueue), std::move(msgCallback),
      std::move(v1State));

  // Old API auto-enabled the Debugger domain on construction; mirror that.
  impl_->agent->enableDebuggerDomain();
  if (impl_->sessionConfig.isRuntimeDomainEnabled) {
    impl_->agent->enableRuntimeDomain();
  }

  impl_->onUnregister = std::move(onUnregister);
  return true;
}

bool CDPHandler::unregisterCallbacks() {
  if (!impl_->agent) return false;
  impl_->agent.reset();
  registry().release(impl_->adapter->getRuntime());
  impl_->debugAPI = nullptr;
  if (impl_->onUnregister) impl_->onUnregister();
  impl_->onUnregister = nullptr;
  return true;
}

void CDPHandler::handle(std::string msg) {
  if (impl_->agent) impl_->agent->handleCommand(std::move(msg));
}

std::string CDPHandler::getTitle() const { return impl_->title; }

std::unique_ptr<State> CDPHandler::getState() {
  if (!impl_->agent) return nullptr;
  auto p = std::make_unique<State::Private>();
  p->v1 = impl_->agent->getState();
  return std::make_unique<State>(std::move(p));
}

} // namespace
```

### RuntimeAdapter.h (shim, with one new virtual)

Same as upstream, **plus** one new virtual to expose runtime-thread task
posting (see "RN-side patches" below):

```cpp
class INSPECTOR_EXPORT RuntimeAdapter {
 public:
  virtual ~RuntimeAdapter() = 0;
  virtual HermesRuntime& getRuntime() = 0;
  virtual void tickleJs();

  /// NEW: post a task that runs on the runtime thread (with exclusive
  /// access to the runtime). The default implementation aborts; concrete
  /// adapters must override. Required by the V1 CDP back-end.
  virtual void enqueueRuntimeTask(std::function<void(HermesRuntime&)> task);
};
```

### RuntimeAdapter.cpp

```cpp
RuntimeAdapter::~RuntimeAdapter() = default;
void RuntimeAdapter::tickleJs() {}
void RuntimeAdapter::enqueueRuntimeTask(std::function<void(HermesRuntime&)>) {
  abort();   // concrete adapters MUST override
}
SharedRuntimeAdapter::SharedRuntimeAdapter(std::shared_ptr<HermesRuntime> r)
  : runtime_(std::move(r)) {}
SharedRuntimeAdapter::~SharedRuntimeAdapter() = default;
HermesRuntime& SharedRuntimeAdapter::getRuntime() { return *runtime_; }
```

## RN-side patches needed

Two small changes outside the adapter:

1. **`HermesExecutorRuntimeAdapter` in `HermesExecutorFactory.cpp`** —
   override the new `enqueueRuntimeTask` virtual. The class already holds
   a `MessageQueueThread` (or `std::shared_ptr<JSQueue>`), and `tickleJs`
   already proves it can post to the runtime thread. The override is ~5
   lines:

   ```cpp
   void HermesExecutorRuntimeAdapter::enqueueRuntimeTask(
       std::function<void(HermesRuntime&)> task) override {
     thread_->runOnQueue([rt = runtime_, t = std::move(task)]() {
       t(*rt);
     });
   }
   ```

2. **`HermesInstanceRuntimeAdapter` in `HermesInstance.cpp`** — same
   treatment if it exists (also gated on `HERMES_ENABLE_DEBUGGER` so check
   the file inside the ifdef).

3. **CMake** — add `RuntimeAdapter.cpp` and `chrome/CDPHandler.cpp` to the
   library that owns the inspector code. Best home: a new sibling
   `ReactCommon/hermes/inspector/CMakeLists.txt` building a
   `hermes_inspector_shim` static-or-object library that
   `hermes_inspector_modern` (and `hermes_executor_common`) link against,
   so the symbols `inspector_modern::chrome::CDPHandler::*` resolve.

4. **Re-enable `HERMES_ENABLE_DEBUGGER`** — undo the deletion from README
   §6e in the eight CMake files. Don't undo §6f's `#ifdef` wrap on
   `HermesExecutorFactory.cpp` — it's harmless and keeps the file
   compilable in either mode.

## Open questions to resolve before coding

1. **`waitForDebugger`** — old API supported pausing on first JS until a
   debugger attaches. V1 has the same concept but the entry point is
   different (`AsyncDebuggerAPI::installPauseTrigger`?). Verify by reading
   `sdks/hermes/API/hermes/AsyncDebuggerAPI.h` and grep the Hermes test
   suite for the pattern. If complex to wire, MVP can ignore the flag and
   document it.

2. **`processConsoleAPI`** — old flag; in V1 console messages route
   through `CDPDebugAPI::addConsoleMessage`. RN already had its own
   console wiring in `HermesExecutorFactory`; verify nothing breaks if
   we ignore this flag in MVP.

3. **`EnqueueRuntimeTaskFunc` signature** — confirm by reading
   `<hermes/AsyncDebuggerAPI.h>` (extract from V1 prefab AAR). Adjust the
   shim's `enqueue` lambda to match exactly.

4. **State persistence** — old `State::Private` and V1 `cdp::State::Private`
   are completely different opaque types. MVP: drop preserved state on
   reload (return `nullptr` from getState the first time, accept any
   incoming state but ignore its contents). Reload-state preservation can
   come later; users will just lose breakpoints across reloads.

5. **Multiple agents per runtime** — per the V1 docstring CDPDebugAPI is
   "independent of any particular CDPAgent" so multiple concurrent
   CDPAgents per CDPDebugAPI should be fine. The registry pattern handles
   this. Verify with a stress test (open two devtools windows on the same
   page).

## Step-by-step implementation order

1. **Inspect remaining headers** — read `AsyncDebuggerAPI.h` and any
   other V1 header the adapter touches to lock down exact signatures.
   Estimated: 30 min.

2. **Write `RuntimeAdapter.h` + `.cpp`** — straightforward port, plus
   the new `enqueueRuntimeTask` virtual. Estimated: 30 min.

3. **Patch `HermesExecutorRuntimeAdapter` (and any sibling adapters in
   RN) to override `enqueueRuntimeTask`**. Estimated: 30 min.

4. **Write `chrome/CDPHandler.h`** — declarations matching old API.
   Estimated: 30 min.

5. **Write `chrome/CDPHandler.cpp`** — the bulk of the work. Implement
   `Impl`, `registry`, all create/registerCallbacks/handle/getState/
   unregisterCallbacks/dtor logic. Estimated: 3 hours.

6. **CMake plumbing** — add the new CMakeLists.txt for the shim,
   relink `hermes_inspector_modern` and `hermes_executor_common` against
   it. Estimated: 30 min.

7. **Re-enable `HERMES_ENABLE_DEBUGGER`** in the 8 CMake spots. Build.
   Fix link errors. Estimated: 30 min.

8. **Smoke test** — install the debug APK, attach RN DevTools (or Chrome
   devtools via the legacy `chrome://inspect` flow if RN DevTools is
   unavailable). Verify:
   - Connection establishes
   - `Debugger.enable` / `Runtime.enable` succeed
   - A breakpoint set in `App.tsx` triggers
   - `console.log` from JS shows up in the devtools console
   - Eval-in-console works
   - Heap snapshot completes
   Estimated: 1-2 hours, plus debugging.

9. **Stretch: state preservation across reloads**, **stretch: console
   API ingestion**, **stretch: waitForDebugger**. Each is its own little
   investigation; defer to a follow-up.

10. **Capture as patch** — add `patches/03-cdp-adapter.patch` and update
    REGENERATE.md / README §6 to reference it.

**Total MVP estimate:** ~6-8 hours of focused work (one solid day).

## Testing

- **Unit-level**: feed the shim CDP JSON from `ConnectionDemuxTests.cpp`
  (already has fixtures). The test was disabled with `HERMES_ENABLE_DEBUGGER`;
  re-enabling it gives a free regression suite.

- **Integration**: stop Metro, install debug APK, run, attach RN DevTools
  (or Chrome devtools). Confirm the welcome-screen renders with debugger
  attached, set a breakpoint in `App.tsx`'s render, hot-reload, breakpoint
  hits.

- **Regression**: re-run the existing app launch test from
  README §4 — adapter should be transparent when no debugger is attached.

## Risks (in descending order of concern)

1. **`EnqueueRuntimeTaskFunc` semantics differ from `tickleJs`'s implicit
   model.** V1 expects tasks to run "with exclusive access to the runtime"
   in FIFO order. RN's `MessageQueueThread::runOnQueue` posts tasks to a
   queue but interleaves with JS execution. If V1 assumes the task runs
   *between* JS evaluations (not during), and RN's queue allows posting
   during, we may see deadlocks or use-after-free in CDP callbacks.
   **Mitigation**: read AsyncDebuggerAPI doc carefully; the runtime task
   may need to be posted via `AsyncDebuggerAPI::triggerInterrupt` style
   API rather than the executor.

2. **Lifetime cycle on rapid reload.** Metro reload destroys the runtime
   and the adapter, then creates new ones. Our `CDPDebugAPIRegistry`
   keys on `&HermesRuntime` (raw pointer). If a freed runtime address is
   reused before the entry is released, we'll hand out a stale
   `CDPDebugAPI`. **Mitigation**: ensure the ConnectionDemux destroys
   handlers eagerly on runtime teardown, or key the registry on
   `weak_ptr<HermesRuntime>` if available.

3. **State-format mismatch losing breakpoints across reloads.** Already
   accepted as MVP scope-cut — see open question 4.

4. **Console message routing.** RN expects console output to flow
   through CDP's `Runtime.consoleAPICalled` events. V1 routes via
   `CDPDebugAPI::addConsoleMessage`. If the existing console wiring in
   `HermesExecutorFactory.cpp` doesn't call into `CDPDebugAPI`, console
   messages won't appear in devtools. **Mitigation**: redirect RN's
   console hook to call `cdpDebugAPI_->addConsoleMessage(...)`. Might
   require exposing the per-runtime CDPDebugAPI via a getter on the
   adapter.

## Success criteria

- App builds with `HERMES_ENABLE_DEBUGGER` re-enabled.
- App launches and renders welcome screen normally.
- RN DevTools connects to the running app.
- A breakpoint set in `App.tsx` is hit.
- `console.log` output appears in the devtools console.
- No regressions in release build (release builds don't compile inspector
  code, but verify nothing leaked into `assembleRelease`).

## Out of scope (for this plan)

- Sampling profiler (`HermesSamplingProfiler.cpp`) — separate, smaller
  task: rewire the three JNI methods against V1's
  `hermes/Public/SamplingProfiler.h`. README §7 status item.
- Sampling profile serializer (`HermesRuntimeSamplingProfileSerializer.cpp`)
  — V1 changed the frame model to `std::variant`; needs a rewrite
  against the new types. Decoupled from CDP.
- Restoring the Hermes fatal handler — README §6g documents this is
  intentionally permanent (one extra logcat line not worth it).
