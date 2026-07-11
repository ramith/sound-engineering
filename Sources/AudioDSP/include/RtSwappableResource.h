#pragma once

#include <atomic>
#include <memory>

namespace AdaptiveSound
{

    // RtSwappableResource<T> — lock-free, single-producer/single-consumer handoff of an
    // owned, off-RT-allocated resource T to the real-time thread without ever allocating,
    // freeing, or locking on the RT path.
    //
    // Extracted from EQModule's open-coded activeSetup_/pendingSetup_/toReleaseSetup_
    // triple-atomic vDSP_biquad_Setup swap (S6 Tier-3 §3, the authority for this type).
    //
    // OWNERSHIP MODEL
    //   The three atomic slots hold RAW std::atomic<T*>. We do NOT use std::atomic<unique_ptr>
    //   (which is not lock-free). RAII (std::unique_ptr<T>) appears ONLY at the API edges:
    //   the publish() parameter, and inside reclaim()/the destructor where a retired raw
    //   pointer is rebound into a unique_ptr<T> so T's destructor frees the resource.
    //   T must own its underlying resource and free it in its own destructor (e.g. a RAII
    //   wrapper around an opaque handle).
    //
    // THREADING CONTRACT
    //   - publish() / reclaim() / ~RtSwappableResource(): off-RT (the single producer).
    //   - adopt() / active(): RT (the single consumer). No alloc/free/lock on these paths.
    //   - The destructor's precondition is that the RT consumer is QUIESCED (no concurrent
    //     adopt()/active()); it then frees whatever lives in all three slots.
    //
    // SINGLE-PENDING CONTRACT (§3.2)
    //   The producer MUST NOT outrun the RT adopt: at most one resource may sit in pending_
    //   awaiting adoption. If publish() is called again while a previously published resource
    //   has not yet been adopted, the displaced (un-adopted) resource is freed immediately by
    //   publish() — see below — so there is no leak in publish()'s own path. The leak window
    //   the design calls out is the RT-side orphan: if the RT thread adopts a *second* pending
    //   before reclaim() drains the *first* retired active, adopt() can only deposit one old
    //   resource into toRelease_ and intentionally leaks the displaced one (it cannot free on
    //   the RT thread). This is acceptable for EQ (small vDSP setups); revisit for BRIR (large
    //   kernels). The Realizer's coalescing (S6 Tier-3 sub-step 2 / §3a) guarantees a burst of
    //   intents collapses to a single publish(), so the producer never outruns the RT adopt in
    //   practice. Cross-reference: 3c's single-pending safety depends on 3a's coalescing.
    //
    // NO ABA HAZARD
    //   Every slot transition is a plain exchange/store/load — we NEVER CAS-compare a pointer
    //   value, so a recycled address can never be mistaken for an unchanged slot. Do NOT "fix"
    //   this with tagged pointers; there is nothing to fix.
    template <typename T> class RtSwappableResource
    {
        // Pointer-width atomics must be lock-free for the RT swap to be wait-free.
        static_assert(std::atomic<T*>::is_always_lock_free,
                      "RtSwappableResource requires lock-free pointer atomics for RT-safe swaps");

      public:
        RtSwappableResource() = default;

        // Off-RT. Precondition: the RT consumer is quiesced. Frees whatever lives in every
        // slot by rebinding each raw pointer into a unique_ptr<T> (T's dtor frees).
        ~RtSwappableResource()
        {
            freeSlot(active_);
            freeSlot(pending_);
            freeSlot(toRelease_);
        }

        RtSwappableResource(const RtSwappableResource&) = delete;
        RtSwappableResource& operator=(const RtSwappableResource&) = delete;
        RtSwappableResource(RtSwappableResource&&) = delete;
        RtSwappableResource& operator=(RtSwappableResource&&) = delete;

        // Off-RT: hand a freshly built resource to the RT thread.
        //  1. Reclaim first — free anything the RT thread retired into toRelease_, so the
        //     producer's own path bounds the number of live resources.
        //  2. Release ownership of `resource` into pending_ with a RELEASE store: this pairs
        //     with adopt()'s acquire so the RT thread sees the fully-constructed contents of T.
        //  3. If a previously published resource was never adopted, free that displaced one
        //     here (off-RT) — single-pending: pending_ never accumulates more than one.
        void publish(std::unique_ptr<T> resource) noexcept
        {
            reclaim();
            // release: publishing the pointer must "happen-before" the RT acquire that
            // adopts it, so all stores that built *resource are visible to the RT thread.
            T* displaced = pending_.exchange(resource.release(), std::memory_order_release);
            // displaced is a prior pending that the RT thread never adopted. Single-pending
            // contract: free it here, off-RT, rather than letting pending_ accumulate.
            std::unique_ptr<T>{displaced}; // dtor frees if non-null
        }

        // RT: adopt any pending resource into active_, retiring the old active_ for off-RT
        // reclaim. No alloc/free/lock. Returns the resource the RT thread should run.
        T* adopt() noexcept
        {
            // acquire: matches publish()'s release so we observe the new resource fully built.
            T* incoming = pending_.exchange(nullptr, std::memory_order_acquire);
            if (incoming != nullptr)
            {
                // Swap the incoming resource in as active. release: a subsequent active()
                // (or another adopt()) on the RT thread, and any off-RT reader, must see the
                // fully-published pointer.
                T* old = active_.exchange(incoming, std::memory_order_release);
                // Deposit the retired active into toRelease_ for the off-RT producer to free.
                // release: we hand off only the pointer value; the producer reclaim()s with
                // acquire. If toRelease_ already held an un-reclaimed resource, the displaced
                // orphan is intentionally leaked — we cannot free on the RT thread. See the
                // single-pending contract above; the Realizer's coalescing prevents this.
                T* orphan = toRelease_.exchange(old, std::memory_order_release);
                (void)orphan;
            }
            // acquire: see active() — load-bearing pairing with publish()'s release.
            return active_.load(std::memory_order_acquire);
        }

        // RT: return the current active resource without swapping anything.
        // The acquire is LOAD-BEARING: it pairs with publish()'s release store so the RT
        // thread sees the fully-constructed contents of T behind the pointer (not just a
        // visible pointer value). Do NOT relax this to memory_order_relaxed.
        T* active() const noexcept
        {
            return active_.load(std::memory_order_acquire);
        }

        // Off-RT: free whatever the RT thread retired into toRelease_.
        // acquire: pairs with adopt()'s release deposit so this thread observes a complete
        // hand-off before freeing.
        void reclaim() noexcept
        {
            freeSlot(toRelease_);
        }

      private:
        // Off-RT only. Atomically take the slot's pointer and free it via unique_ptr<T>.
        // acquire: observe the producing thread's stores to *ptr before the destructor runs.
        static void freeSlot(std::atomic<T*>& slot) noexcept
        {
            std::unique_ptr<T>{slot.exchange(nullptr, std::memory_order_acquire)};
        }

        std::atomic<T*> active_{nullptr};    // RT runs this
        std::atomic<T*> pending_{nullptr};   // off-RT publishes, RT adopts
        std::atomic<T*> toRelease_{nullptr}; // RT deposits old, off-RT reclaims
    };

} // namespace AdaptiveSound
