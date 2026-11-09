# Windows CI restore assertion, head 68293c6

Preserved failing evidence: [run 42619050534, job 129166151962](https://github.com/no-colours-fabric/ncf-image-upscaler/actions/runs/42619050534/job/129166151962).
The installer, isolated imports, no-weights check, backend policy, close/Locate,
84 dialog checks and 18 preference checks passed. Actual maximized bounds matched
the queried work area `0,0,1024,728`; exact restore equality then failed.

The geometry harness requested a 1150-wide normal window with the application's
1056 minimum on a 1024-wide CI display. Windows may reposition such oversized
normal windows on restore. The revised harness places a smaller test window
inside the primary work area in WPF logical units (including DPI scaling) and
overrides only its test minimum dimensions.
Production minimum dimensions are unchanged. Exact maximized/work-area and
original/restored equality assertions remain; new traces record both rectangles.
Synthetic minimum-constraint and negative-coordinate assertions remain separate.
This is not a native mouse or small-display usability certification.
