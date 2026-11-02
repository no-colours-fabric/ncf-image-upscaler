# Preserved independent CI failure

Source head: `d0a8fab2b48a6597dd466c0dc629a9a8d2d715a5`.
[Windows job](https://github.com/no-colours-fabric/ncf-image-upscaler/actions/runs/41345623758/job/124964685004).

Coordinator observed: setup/build/runtime isolation/no-weights passed, then
`save: FAIL Did not close exactly once`. Six other close cases passed;
Locate checks did not execute after the suite failure. This independent failure
is retained, not replaced by the earlier local seven-pass report.

The original harness assumed asynchronous saving and deferred closing completed
within a fixed 80 ms Dispatcher interval. The targeted revision holds saving on
an explicit gate, asserts the window stays open while saving is incomplete, then
releases saving and waits for the actual Closed event with a five-second deadline.
Exactly one close, completed export before close, unchanged input and absence of
Dispatcher exceptions remain required. No product lifecycle behavior is weakened.
Independent CI must confirm the revised harness; a local pass alone does not
prove the cause of the earlier CI timing/failure.
