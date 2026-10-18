# Document rendering

`ds720d decode CAPTURE.jsonl` produces a document-oriented rendering from the
native RGB stream. This stage runs after duplex separation and rear mirroring;
it does not issue USB commands or change the acquisition file.

The original C implementation is in `src/document.c` under the MIT license.
It has no external library dependency. The image exporter uses Apple's ImageIO.

## Cropping

The scanner backing is close to black while the observed paper is much brighter.
The renderer finds rows occupied by paper, estimates left/right edges across
those rows, then estimates top/bottom edges across the retained columns. Robust
edge percentiles reject isolated reflections and dust. It inscribes a rectangle
inside these estimates, with a two-pixel inset on detected edges to remove dark
edge remnants. It does not crop to text, rescale, sharpen or straighten the page.
Ambiguous geometry falls back to the entire image.

## Paper white

Each face receives an independent estimate. A histogram of sufficiently bright,
near-neutral pixels identifies the dominant paper tone. A lower percentile of
that paper cluster estimates the per-channel white level. The same estimate is
computed in 128-pixel tiles; tiles without enough paper use the global estimate.
Bilinear interpolation of the tile estimates forms a smooth white field.

Each RGB component is scaled against its local white estimate and clipped at
255. There is no black-and-white threshold or spatial filter. Printed colors
remain RGB, with the channel gains also compensating for the paper's mild cast.
When no sufficiently large neutral paper cluster exists, tone adjustment is
skipped. This is document enhancement, not sensor calibration or a color profile.

## Raw option and limits

`ds720d decode CAPTURE.jsonl --raw` exports the unadjusted RGB values, at their
original dimensions, as `-raw-front.png` and `-raw-back.png`. Rear orientation is
corrected in both modes. The capture and original input pixels are never changed.

Document rendering favors neutral paper with text. Pale shading, colored paper,
photographs and artwork should use the raw option when fidelity matters. A
rectangular crop can remove a narrow strip of paper around a skewed sheet; it
does not rectify perspective or rotation. Physical folds and marks remain.
Parameters have been evaluated against one real double-sided sheet, not a broad
document collection.

On that capture, raw images were 2592 by 3760 pixels. The cleaned front was
2462 by 3481 pixels and the back 2461 by 3480, retaining 300 dpi. Both were
examined visually: the dark exterior was removed, the paper became white, and
the small text, printed lines and color mark remained legible. Captures and
personal document contents are excluded from Git.

Software tests use synthetic documents to check uneven lighting, different
sensor brightness, thin dark and faint gray marks, colored print, blank and dark
inputs, crop geometry, invalid dimensions and unchanged source data. The decoder
also tests raw RGB pixel equality and output DPI through ImageIO. These tests
run with address and undefined-behavior sanitizers.
