/*
 * Copyright (c) 2026 FFmpeg
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include "libavutil/aarch64/asm.S"

// FAST_DIV255(x) = (x + 128 + ((x + 128) >> 8)) >> 8
// Implemented with NEON: ursra + urshr pattern

// int ff_overlay_row_44_neon(uint8_t *d, uint8_t *da, uint8_t *s,
//                            uint8_t *a, int w, ptrdiff_t alinesize)
// No alpha subsampling (YUV444 / GBRP): process 16 pixels at a time
// x0=dst, x1=da(unused), x2=src, x3=alpha, w4=width, x5=alinesize(unused)
// Returns number of pixels processed in w0
function ff_overlay_row_44_neon, export=1
        mov         w9, w4              // save original width
        cmp         w4, #16
        b.lt        2f

        movi        v31.16b, #255       // constant 255

1:      ld1         {v0.16b}, [x0]      // load dst
        ld1         {v1.16b}, [x2], #16 // load src
        ld1         {v2.16b}, [x3], #16 // load alpha

        // inv_alpha = 255 - alpha
        sub         v3.16b, v31.16b, v2.16b

        // dst * inv_alpha -> 16-bit
        umull       v4.8h, v0.8b, v3.8b
        umull2      v5.8h, v0.16b, v3.16b

        // + src * alpha -> 16-bit accumulate
        umlal       v4.8h, v1.8b, v2.8b
        umlal2      v5.8h, v1.16b, v2.16b

        // FAST_DIV255: (v + 128 + ((v + 128) >> 8)) >> 8
        // Equivalent: ursra(v, 8) then urshr(8)
        ursra       v4.8h, v4.8h, #8
        ursra       v5.8h, v5.8h, #8
        rshrn      v0.8b, v4.8h, #8
        rshrn2     v0.16b, v5.8h, #8

        st1         {v0.16b}, [x0], #16

        sub         w4, w4, #16
        cmp         w4, #16
        b.ge        1b

2:      sub         w0, w9, w4          // return pixels processed
        ret
endfunc

// int ff_overlay_row_20_neon(uint8_t *d, uint8_t *da, uint8_t *s,
//                            uint8_t *a, int w, ptrdiff_t alinesize)
// YUV420 chroma: 2x2 alpha subsampling, process 8 chroma pixels at a time
// x0=dst, x1=da(unused), x2=src, x3=alpha, w4=width, x5=alinesize
function ff_overlay_row_20_neon, export=1
        mov         w9, w4
        cmp         w4, #8
        b.lt        2f

        add         x6, x3, x5         // alpha + alinesize (next line)
        movi        v31.16b, #255

1:      ld1         {v0.8b}, [x0]       // load 8 dst chroma pixels
        ld1         {v1.8b}, [x2], #8   // load 8 src chroma pixels
        ld1         {v2.16b}, [x3], #16 // load 16 alpha from line 0
        ld1         {v3.16b}, [x6], #16 // load 16 alpha from line 1

        // Average 2x2: pairwise add both lines, then average
        uaddlp      v4.8h, v2.16b      // pairwise add line 0 -> 8 x u16
        uadalp      v4.8h, v3.16b      // pairwise accumulate line 1
        rshrn      v2.8b, v4.8h, #2   // (sum + 2) >> 2 -> 8 x u8

        sub         v3.8b, v31.8b, v2.8b // inv_alpha

        umull       v4.8h, v0.8b, v3.8b
        umlal       v4.8h, v1.8b, v2.8b

        ursra       v4.8h, v4.8h, #8
        rshrn      v0.8b, v4.8h, #8

        st1         {v0.8b}, [x0], #8

        sub         w4, w4, #8
        cmp         w4, #8
        b.ge        1b

2:      sub         w0, w9, w4
        ret
endfunc

// int ff_overlay_row_22_neon(uint8_t *d, uint8_t *da, uint8_t *s,
//                            uint8_t *a, int w, ptrdiff_t alinesize)
// YUV422 chroma: horizontal 2x subsampling, process 8 chroma pixels at a time
// x0=dst, x1=da(unused), x2=src, x3=alpha, w4=width, x5=alinesize(unused)
function ff_overlay_row_22_neon, export=1
        mov         w9, w4
        cmp         w4, #8
        b.lt        2f

        movi        v31.16b, #255

1:      ld1         {v0.8b}, [x0]       // load 8 dst chroma pixels
        ld1         {v1.8b}, [x2], #8   // load 8 src chroma pixels
        ld1         {v2.16b}, [x3], #16 // load 16 alpha values

        // Horizontal pairwise average
        uaddlp      v4.8h, v2.16b      // pairwise add -> 8 x u16
        rshrn      v2.8b, v4.8h, #1   // (sum + 1) >> 1 -> 8 x u8

        sub         v3.8b, v31.8b, v2.8b

        umull       v4.8h, v0.8b, v3.8b
        umlal       v4.8h, v1.8b, v2.8b

        ursra       v4.8h, v4.8h, #8
        rshrn      v0.8b, v4.8h, #8

        st1         {v0.8b}, [x0], #8

        sub         w4, w4, #8
        cmp         w4, #8
        b.ge        1b

2:      sub         w0, w9, w4
        ret
endfunc
