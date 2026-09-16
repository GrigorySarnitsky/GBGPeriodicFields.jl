# Frame: the decision points a multi-GPU + spill design must answer (fact-independent)

Two features, deliberately kept apart because they are different kinds of thing:
  (A) SPILL — one device using host memory when HBM is exhausted. Capacity, one process, no communication.
  (B) FOUR GPUS PER NODE — using more than one device for one run. Capacity AND speed, requires a decomposed base.

D1  Is (B) domain decomposition, or something cheaper? (ensemble/task parallelism; fiber/component parallelism;
    peer-GPU memory pooling). Name what each buys and what it costs; reject with reasons, not by omission.
D2  One process with N devices, or N processes with one device each (MPI)? Which preserves the package as it is?
D3  Where does the decomposition live — on the BASE (Grid3D), on the storage (array type), or in a new field type?
D4  Which operation families are unchanged by construction, which communicate, which need a design decision?
    (the §2 vertical / horizontal / measure split is the tool for this)
D5  Who owns the distributed transform: a dependency (PencilFFTs), a vendor library (cuFFTMp), or our own transpose?
D6  Reductions become collectives — what is the user-visible contract, and what is the deadlock story?
D7  The reality condition pairs j with mod(-(j-1),n)+1 on the folded axis — what constraint does that put on the
    decomposition, and is it a constraint or a communication?
D8  The point/transfer layer: halo width per scheme, point migration, and whether it can be staged later.
D9  Invariants: which of the fourteen survive per-rank unchanged, which need an explicit amendment
    (9 ownership vs halo padding; 13 allocation-free vs MPI buffers; 14 storage family vs a distributed family;
    4 zero-mode scaling vs the global size; the bitwise thread-invariance guarantee vs rank-count invariance).
D10 (A)'s API: is spill transparent (just pass a different array type) or does it need a package verb?
    What breaks in similar_field / the family-taking constructors / _same_backend / plans?
D11 (A)'s policy: what SHOULD be spilled? (the transform's working set is the worst candidate; cold fields the best)
D12 Testing: what can be tested on a one-GPU workstation, what needs the cluster; what is the oracle
    (decision 55 forbids leaning only on a 1-rank-vs-4-rank comparison).
D13 Dependencies: MPI + a distributed FFT as hard deps, weak deps (extension), or vendored?
D14 Scope: §1 and PERFORMANCE §1 say single-node/single-GPU is deliberate, and decision 37 rests on it.
    What exactly is overturned, and what replaces the reasoning?
D15 Staging: what ships first, what is independently useful, what can be deferred without stranding the rest?
D16 Consumer (IT) impact and the coordination path.
D17 Effort, risk, and the honest "do nothing / do less" alternative.
