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

// void ff_line_noise_neon(uint8_t *dst, const uint8_t *src,
//                         const int8_t *noise, int len, int shift)
// x0 = dst, x1 = src, x2 = noise, w3 = len, w4 = shift
function ff_line_noise_neon, export=1
        add         x2, x2, w4, sxtw       // noise += shift
        cmp         w3, #16
        b.lt        2f

        // Main loop: process 16 pixels per iteration
1:      ld1         {v0.16b}, [x1], #16     // load 16 src pixels
        ld1         {v1.16b}, [x2], #16     // load 16 noise values (int8)
        usqadd      v0.16b, v1.16b          // unsigned saturating accumulate of signed
        st1         {v0.16b}, [x0], #16     // store result
        sub         w3, w3, #16
        cmp         w3, #16
        b.ge        1b

        // Scalar remainder: 0..15 pixels, clamp to [0, 255]
2:      cbz         w3, 4f
        mov         w7, #255
3:      ldrb        w5, [x1], #1
        ldrsb       w6, [x2], #1
        add         w5, w5, w6
        cmp         w5, #0
        csel        w5, wzr, w5, lt
        cmp         w5, #255
        csel        w5, w7, w5, gt
        strb        w5, [x0], #1
        sub         w3, w3, #1
        cbnz        w3, 3b
4:
        ret
endfunc
